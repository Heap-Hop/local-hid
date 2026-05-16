/// Listener + pluggable UI for ESP-IDF log lines streamed over UDP by the
/// `esp-remote-log` Rust crate.
///
/// The library has two layers, both usable independently:
///   * [RemoteLogService] — pure Dart, binds a UDP socket, yields each
///     incoming datagram as a [LogLine]. No Flutter dependency in the model.
///   * [RemoteLogPane] — a Material widget that subscribes to a service and
///     renders a scrolling, auto-tailing list. Drop into any tab / page.
library;

export 'src/log_line.dart';
export 'src/remote_log_pane.dart';
export 'src/remote_log_service.dart';
