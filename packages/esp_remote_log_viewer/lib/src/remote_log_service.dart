import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_line.dart';

/// Connection state of [RemoteLogService].
enum RemoteLogState {
  /// No target configured yet.
  idle,

  /// TCP connection attempt in progress.
  connecting,

  /// Connected; receiving lines.
  connected,

  /// Disconnected. If [RemoteLogService.autoReconnect] is true, another
  /// attempt is scheduled.
  disconnected,
}

/// Subscribes to ESP-IDF log lines streamed over TCP by the `esp-remote-log`
/// Rust crate.
///
/// Architecture (mirrors the firmware-side TCP log server):
///   * `connect(host, port)` opens a TCP connection.
///   * The firmware first sends the current ring buffer (replay of recent
///     history) and then live lines as they happen.
///   * We split on `\n`, parse each line, push into a broadcast stream, and
///     keep the last [maxBuffer] in [recent] for late subscribers.
///   * On disconnect, if [autoReconnect] is set, we wait
///     [reconnectDelay] and try again.
class RemoteLogService {
  RemoteLogService({
    this.maxBuffer = 2000,
    this.reconnectDelay = const Duration(seconds: 2),
    this.autoReconnect = true,
  });

  /// In-memory line ring for fresh subscribers.
  final int maxBuffer;
  final Duration reconnectDelay;
  final bool autoReconnect;

  final _lines = StreamController<LogLine>.broadcast();
  final _states = StreamController<RemoteLogState>.broadcast();
  final List<LogLine> _ring = [];

  String? _host;
  int? _port;
  Socket? _socket;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  RemoteLogState _state = RemoteLogState.idle;
  String? _lastError;
  String _stitch = ''; // partial line carried over between chunks

  Stream<LogLine> get stream => _lines.stream;
  Stream<RemoteLogState> get states => _states.stream;
  List<LogLine> get recent => List.unmodifiable(_ring);
  RemoteLogState get state => _state;
  String? get lastError => _lastError;

  /// Connect to a TCP log server (re-points if already connected to a
  /// different target).
  Future<void> connect({required String host, int port = 9001}) async {
    if (_host == host && _port == port && _state == RemoteLogState.connected) {
      return;
    }
    await disconnect();
    _host = host;
    _port = port;
    unawaited(_open());
  }

  Future<void> disconnect() async {
    _retry?.cancel();
    _retry = null;
    await _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    _stitch = '';
    _setState(RemoteLogState.idle);
  }

  Future<void> dispose() async {
    await disconnect();
    await _lines.close();
    await _states.close();
  }

  Future<void> _open() async {
    final host = _host;
    final port = _port;
    if (host == null || port == null) return;
    _setState(RemoteLogState.connecting);

    Socket socket;
    try {
      socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 3));
    } catch (error) {
      _lastError = error.toString();
      _setState(RemoteLogState.disconnected);
      _scheduleReconnect();
      return;
    }

    _socket = socket;
    _lastError = null;
    _setState(RemoteLogState.connected);

    _sub = utf8.decoder.bind(socket).listen(
      _onChunk,
      onError: (Object error) {
        _lastError = error.toString();
        _onDisconnect();
      },
      onDone: _onDisconnect,
      cancelOnError: true,
    );
  }

  void _onChunk(String chunk) {
    final combined = _stitch + chunk;
    final parts = combined.split('\n');
    // The last element is the partial line (or empty if chunk ended on \n).
    _stitch = parts.removeLast();
    for (final raw in parts) {
      if (raw.isEmpty) continue;
      final line = LogLine.parse(raw);
      _ring.add(line);
      if (_ring.length > maxBuffer) {
        _ring.removeRange(0, _ring.length - maxBuffer);
      }
      _lines.add(line);
    }
  }

  void _onDisconnect() {
    _socket?.destroy();
    _socket = null;
    _setState(RemoteLogState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!autoReconnect || _host == null) return;
    _retry?.cancel();
    _retry = Timer(reconnectDelay, () {
      if (_state == RemoteLogState.disconnected) {
        unawaited(_open());
      }
    });
  }

  void _setState(RemoteLogState s) {
    _state = s;
    _states.add(s);
  }
}
