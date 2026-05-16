import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';

/// Bound UDP sender for the binary HID protocol.
///
/// Every command call is fire-and-forget — no waiting on a reply. Only
/// [ping] expects a `PONG` back; the rest of the API just enqueues a send.
class HidClient {
  HidClient();

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  int? _port;
  String? _resolvedHost;
  int _pingSeq = 0;
  final Map<int, Completer<Duration>> _pendingPings = {};
  final Map<int, Stopwatch> _pingStopwatches = {};

  bool get isConfigured => _socket != null;

  /// Tear down and rebind the underlying UDP socket against the same target.
  /// Used by callers that have detected the socket has gone stale (e.g. the
  /// phone went through Wi-Fi sleep and the kernel still accepts sends but
  /// silently drops them).
  Future<void> rebind() async {
    final host = _resolvedHost;
    final port = _port;
    if (host == null || port == null) {
      return;
    }
    await close();
    await configure(host: host, port: port);
  }

  Future<void> configure({required String host, required int port}) async {
    if (_resolvedHost == host && _port == port && _socket != null) {
      return;
    }

    await close();

    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw SocketException('Could not resolve host "$host"');
    }
    // Prefer IPv4 since the firmware binds 0.0.0.0; fall back to whatever
    // the OS resolver gave us if IPv4 is missing entirely.
    final address = addresses.firstWhere(
      (a) => a.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        _handleReply(Uint8List.fromList(datagram.data));
      },
      cancelOnError: false,
    );

    _socket = socket;
    _address = address;
    _port = port;
    _resolvedHost = host;
  }

  void send(Uint8List bytes) {
    final socket = _socket;
    final address = _address;
    final port = _port;
    if (socket == null || address == null || port == null) {
      throw StateError('HidClient is not configured');
    }
    socket.send(bytes, address, port);
  }

  /// Sends a `PING` and resolves with the round-trip time when the matching
  /// `PONG` arrives, or `null` on timeout.
  Future<Duration?> ping({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final seq = ++_pingSeq & 0xffffffff;
    final completer = Completer<Duration>();
    _pendingPings[seq] = completer;
    final stopwatch = Stopwatch()..start();
    _pingStopwatches[seq] = stopwatch;

    try {
      send(HidProtocol.ping(seq));
    } catch (error) {
      _pendingPings.remove(seq);
      _pingStopwatches.remove(seq);
      rethrow;
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pendingPings.remove(seq);
      _pingStopwatches.remove(seq);
      return null;
    }
  }

  Future<void> close() async {
    _socket?.close();
    _socket = null;
    _address = null;
    _port = null;
    _resolvedHost = null;
    for (final completer in _pendingPings.values) {
      if (!completer.isCompleted) {
        completer.completeError(const SocketException('UDP socket closed'));
      }
    }
    _pendingPings.clear();
    _pingStopwatches.clear();
  }

  void _handleReply(Uint8List bytes) {
    final seq = HidProtocol.parsePong(bytes);
    if (seq == null) return;
    final completer = _pendingPings.remove(seq);
    final stopwatch = _pingStopwatches.remove(seq);
    if (completer != null && !completer.isCompleted) {
      completer.complete(stopwatch?.elapsed ?? Duration.zero);
    }
  }
}
