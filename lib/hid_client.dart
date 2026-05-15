import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// One-shot UDP sender for the text-line HID protocol exposed by
/// esp32-rust-c-hid-example.
///
/// The firmware accepts each datagram as one command line (`k a`, `m 10 -5`,
/// `c left`, `md volup`, ...) and replies with a single `ok ...` / `err ...`
/// datagram. We treat replies as best-effort; mouse moves in particular are
/// fire-and-forget.
class HidClient {
  HidClient();

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  int? _port;
  String? _resolvedHost;
  final List<Completer<String>> _waiters = <Completer<String>>[];

  Future<void> configure({required String host, required int port}) async {
    final unchanged =
        _resolvedHost == host && _port == port && _socket != null;
    if (unchanged) {
      return;
    }

    await close();

    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw SocketException('Could not resolve host "$host"');
    }
    final address = addresses.first;

    final socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }
        final text = String.fromCharCodes(datagram.data).trim();
        _completeNextWaiter(text);
      },
      onError: (Object error) => _failAllWaiters(error),
      cancelOnError: false,
    );

    _socket = socket;
    _address = address;
    _port = port;
    _resolvedHost = host;
  }

  /// Sends a raw command line (without trailing newline). Returns the next
  /// reply text the socket receives within [replyTimeout]; null if no reply
  /// arrived in time.
  Future<String?> sendLine(
    String line, {
    Duration replyTimeout = const Duration(milliseconds: 400),
    bool awaitReply = true,
  }) async {
    final socket = _socket;
    final address = _address;
    final port = _port;
    if (socket == null || address == null || port == null) {
      throw StateError('HidClient is not configured');
    }

    final bytes = Uint8List.fromList('$line\n'.codeUnits);
    final sent = socket.send(bytes, address, port);
    if (sent == 0) {
      throw const SocketException('UDP send returned 0 bytes');
    }

    if (!awaitReply) {
      return null;
    }
    final completer = Completer<String>();
    _waiters.add(completer);
    try {
      return await completer.future.timeout(replyTimeout);
    } on TimeoutException {
      _waiters.remove(completer);
      return null;
    }
  }

  Future<void> close() async {
    _socket?.close();
    _socket = null;
    _address = null;
    _port = null;
    _resolvedHost = null;
    _failAllWaiters(const SocketException('UDP socket closed'));
  }

  bool get isConfigured => _socket != null;

  void _completeNextWaiter(String text) {
    if (_waiters.isEmpty) {
      return;
    }
    final next = _waiters.removeAt(0);
    if (!next.isCompleted) {
      next.complete(text);
    }
  }

  void _failAllWaiters(Object error) {
    if (_waiters.isEmpty) {
      return;
    }
    final pending = List<Completer<String>>.from(_waiters);
    _waiters.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }
}
