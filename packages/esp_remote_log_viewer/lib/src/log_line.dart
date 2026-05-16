/// One log line received from the firmware over UDP.
class LogLine {
  LogLine({
    required this.text,
    required this.received,
    this.level,
  });

  /// The raw line text. ANSI colour codes from ESP-IDF are stripped.
  final String text;

  /// Local clock when the datagram arrived.
  final DateTime received;

  /// Detected log level (`I`, `W`, `E`, …) if the line matches the standard
  /// ESP-IDF `I (12345) tag: …` format; null otherwise.
  final LogLevel? level;

  static final _ansiPattern = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
  static final _esp = RegExp(r'^([IWEDV])\s*\(\s*\d+\s*\)\s+');

  static LogLine parse(String raw) {
    final cleaned = raw.replaceAll(_ansiPattern, '').replaceAll('\r', '');
    final trimmed = cleaned.endsWith('\n')
        ? cleaned.substring(0, cleaned.length - 1)
        : cleaned;
    final match = _esp.firstMatch(trimmed);
    return LogLine(
      text: trimmed,
      received: DateTime.now(),
      level: match == null ? null : LogLevel.fromChar(match.group(1)!),
    );
  }
}

enum LogLevel {
  error('E'),
  warn('W'),
  info('I'),
  debug('D'),
  verbose('V');

  const LogLevel(this.shortName);
  final String shortName;

  static LogLevel? fromChar(String ch) {
    for (final v in LogLevel.values) {
      if (v.shortName == ch) return v;
    }
    return null;
  }
}
