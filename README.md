# local-hid

Flutter client for the [`esp32-rust-c-hid-example`](https://github.com/Heap-Hop/esp32-rust-c-hid-example) firmware.
The phone (or laptop) acts as a wireless touchpad / virtual keyboard / media
remote; the ESP32-S3 receives plain-text UDP commands on the local network and
replays them as USB HID reports on the computer it is plugged into.

## Features (v1)

- **Touchpad tab** — drag for relative mouse movement, tap = left click,
  double-tap = double click. Explicit left/middle/right click buttons.
- **Keys tab** — on-screen lowercase QWERTY + digits, plus Esc / Tab /
  Backspace / Enter / Space / arrow keys. A "type and send" text field types a
  whole string a-key-at-a-time. (Modifier keys / shifted characters are not
  yet supported by the firmware protocol.)
- **Media tab** — Play/Pause, Next, Previous, Stop, Volume ±, Mute.
- **Settings** — target IP + UDP port; persisted with `shared_preferences`.

Transport is **fire-and-forget UDP** over the same Wi-Fi as the ESP32-S3. The
firmware sends back a one-line `ok …` / `err …` reply per command for
debugging, but the app does not block on it.

## Run

1. Flash the firmware
   ([Heap-Hop/esp32-rust-c-hid-example](https://github.com/Heap-Hop/esp32-rust-c-hid-example))
   and read the IP it prints on the serial monitor.
2. Make sure the phone is on the same Wi-Fi.
3. `flutter run` from this directory.
4. Tap the gear icon and set the host (board IP) + port (default `9000`).

## Project layout

```
lib/
  main.dart        UI: tabs, touchpad, keyboard, media, settings
  hid_client.dart  Bound UDP socket, fire-and-forget send, PING/PONG RTT
  protocol.dart    Binary wire format + HID keycode / media-usage constants
  settings.dart    Persisted target host/port
```

## Protocol

Compact binary, one command per UDP datagram. The full spec lives in the
firmware repo
([README §Command protocol](https://github.com/Heap-Hop/esp32-rust-c-hid-example#command-protocol)
and [`src/protocol.rs`](https://github.com/Heap-Hop/esp32-rust-c-hid-example/blob/main/src/protocol.rs))
and is mirrored in [`lib/protocol.dart`](lib/protocol.dart).

Each datagram is `[0x48, version=1, opcode, ...payload]`. Typical packet sizes
are 3–7 bytes. The app pings the firmware every 3 s to drive the
connected / RTT indicator in the status bar; everything else is
fire-and-forget.
