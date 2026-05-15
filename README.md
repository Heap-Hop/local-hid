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
  hid_client.dart  Bound UDP socket + sendLine() with optional reply wait
  settings.dart    Persisted target host/port
```

## Protocol (mirrors the firmware)

One command per UDP datagram, ASCII text. Whitespace-separated.

```
k <name>                  # key tap: a-z, 0-9, enter, esc, space, tab,
                          # backspace, left, right, up, down
m <dx> <dy>               # relative mouse, each axis -127..127
c [left|right|middle]     # mouse click, default left
md <name>                 # media key: playpause, next, prev, stop,
                          # mute, volup, voldown
```
