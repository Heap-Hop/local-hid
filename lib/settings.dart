import 'package:shared_preferences/shared_preferences.dart';

class HidSettings {
  HidSettings({required this.host, required this.port});

  static const defaultHost = '192.168.1.42';
  static const defaultPort = 9000;
  static const _hostKey = 'hid-host';
  static const _portKey = 'hid-port';

  String host;
  int port;

  static Future<HidSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return HidSettings(
      host: prefs.getString(_hostKey) ?? defaultHost,
      port: prefs.getInt(_portKey) ?? defaultPort,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setInt(_portKey, port);
  }
}
