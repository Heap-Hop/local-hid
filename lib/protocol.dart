import 'dart:typed_data';

/// Binary wire format for [`esp32-rust-c-hid-example`](https://github.com/Heap-Hop/esp32-rust-c-hid-example).
///
/// Every datagram is `[magic, version, opcode, ...payload]`. Requests use
/// magic `0x48` ('H'); replies use `0x68` ('h'). The only reply opcode
/// currently emitted by the firmware is [opPong].
class HidProtocol {
  HidProtocol._();

  static const int magicRequest = 0x48;
  static const int magicReply = 0x68;
  static const int version = 1;

  static const int opKeyTap = 0x01;
  static const int opKeyDown = 0x02;
  static const int opKeyUp = 0x03;
  static const int opMouseMove = 0x10;
  static const int opMouseClick = 0x11;
  static const int opMouseButtons = 0x12;
  static const int opMediaTap = 0x20;
  static const int opPing = 0xf0;
  static const int opPong = 0xf1;

  static Uint8List keyTap(int keycode, {int modifier = 0}) =>
      Uint8List.fromList([
        magicRequest,
        version,
        opKeyTap,
        modifier & 0xff,
        keycode & 0xff,
      ]);

  static Uint8List keyDown(int keycode, {int modifier = 0}) =>
      Uint8List.fromList([
        magicRequest,
        version,
        opKeyDown,
        modifier & 0xff,
        keycode & 0xff,
      ]);

  static Uint8List keyUp() =>
      Uint8List.fromList([magicRequest, version, opKeyUp]);

  static Uint8List mouseMove(int dx, int dy, {int wheel = 0}) =>
      Uint8List.fromList([
        magicRequest,
        version,
        opMouseMove,
        _i8(dx),
        _i8(dy),
        _i8(wheel),
      ]);

  static Uint8List mouseClick(int buttonMask) => Uint8List.fromList([
        magicRequest,
        version,
        opMouseClick,
        buttonMask & 0xff,
      ]);

  static Uint8List mouseButtons(int buttonMask) => Uint8List.fromList([
        magicRequest,
        version,
        opMouseButtons,
        buttonMask & 0xff,
      ]);

  static Uint8List mediaTap(int usageCode) {
    final bytes = Uint8List(5);
    bytes[0] = magicRequest;
    bytes[1] = version;
    bytes[2] = opMediaTap;
    bytes[3] = usageCode & 0xff;
    bytes[4] = (usageCode >> 8) & 0xff;
    return bytes;
  }

  static Uint8List ping(int seq) {
    final bytes = Uint8List(7);
    bytes[0] = magicRequest;
    bytes[1] = version;
    bytes[2] = opPing;
    bytes[3] = seq & 0xff;
    bytes[4] = (seq >> 8) & 0xff;
    bytes[5] = (seq >> 16) & 0xff;
    bytes[6] = (seq >> 24) & 0xff;
    return bytes;
  }

  /// Parse a `PONG` reply. Returns the echoed seq number, or `null` if the
  /// bytes are not a valid pong for our version.
  static int? parsePong(Uint8List bytes) {
    if (bytes.length < 7) return null;
    if (bytes[0] != magicReply) return null;
    if (bytes[1] != version) return null;
    if (bytes[2] != opPong) return null;
    return bytes[3] |
        (bytes[4] << 8) |
        (bytes[5] << 16) |
        (bytes[6] << 24);
  }

  static int _i8(int v) {
    final clamped = v.clamp(-128, 127);
    return clamped & 0xff;
  }
}

/// Mouse button mask bits.
class MouseButton {
  MouseButton._();
  static const int left = 1 << 0;
  static const int right = 1 << 1;
  static const int middle = 1 << 2;
}

/// HID usage IDs on Usage Page 0x07 (Keyboard / Keypad). Letters and digits
/// have helpers below; the named keys are listed explicitly.
class HidKey {
  HidKey._();

  static const int enter = 0x28;
  static const int escape = 0x29;
  static const int backspace = 0x2a;
  static const int tab = 0x2b;
  static const int space = 0x2c;
  static const int right = 0x4f;
  static const int left = 0x50;
  static const int down = 0x51;
  static const int up = 0x52;

  /// Returns the keycode for an a-z letter (case-insensitive) or null.
  static int? letter(String ch) {
    if (ch.length != 1) return null;
    final lower = ch.toLowerCase().codeUnitAt(0);
    if (lower < 0x61 || lower > 0x7a) return null;
    return 0x04 + (lower - 0x61);
  }

  /// Returns the keycode for a single digit '0'..'9' or null.
  static int? digit(String ch) {
    if (ch.length != 1) return null;
    final code = ch.codeUnitAt(0);
    if (code < 0x30 || code > 0x39) return null;
    // HID ordering: 1,2,...,9,0 starting at 0x1e.
    final n = code - 0x30;
    return n == 0 ? 0x27 : 0x1e + (n - 1);
  }

  /// Best-effort lookup for the characters our virtual keyboard exposes.
  static int? fromChar(String ch) {
    if (ch == ' ') return space;
    if (ch == '\n') return enter;
    return letter(ch) ?? digit(ch);
  }
}

/// HID consumer-control usage IDs (Usage Page 0x0c).
class HidMedia {
  HidMedia._();
  static const int playPause = 0x00cd;
  static const int scanNext = 0x00b5;
  static const int scanPrev = 0x00b6;
  static const int stop = 0x00b7;
  static const int mute = 0x00e2;
  static const int volumeUp = 0x00e9;
  static const int volumeDown = 0x00ea;
}
