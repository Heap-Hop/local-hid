# esp_remote_log_viewer

Flutter side of the [`esp-remote-log`](https://github.com/Heap-Hop/esp32-rust-c-hid-example/tree/main/crates/esp-remote-log)
Rust crate. Binds a UDP socket, listens for ESP-IDF log lines streamed from
the firmware, and renders them in a scrolling auto-tailing widget.

The library has two layers — use whichever you need:

```dart
import 'package:esp_remote_log_viewer/esp_remote_log_viewer.dart';

// 1. Just the data: bind a port and listen.
final service = RemoteLogService(port: 9001);
await service.start();
service.stream.listen((line) => print(line.text));

// 2. With UI: drop the pluggable widget into any tab / page.
Scaffold(body: RemoteLogPane(service: service));
```

`RemoteLogPane` strips ANSI colour codes, colour-codes I / W / E lines, and
pins to the bottom unless the user scrolls up.

## Wire format

The firmware sends each log line as a single UTF-8 UDP datagram (no envelope,
no framing — keep it simple). A datagram may carry multiple `\n`-separated
lines; the service splits them.
