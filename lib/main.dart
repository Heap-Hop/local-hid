import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hid_client.dart';
import 'protocol.dart';
import 'settings.dart';

void main() {
  runApp(const LocalHidApp());
}

class LocalHidApp extends StatelessWidget {
  const LocalHidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local HID',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _pingInterval = Duration(seconds: 3);

  /// How many consecutive PING timeouts before we tear down and rebind the
  /// UDP socket. Two misses (~6 s of silence) is a good balance between
  /// recovering quickly from Wi-Fi sleep / NAT eviction and not thrashing
  /// when the firmware is just briefly slow.
  static const _rebindAfterFailures = 2;

  final _client = HidClient();
  HidSettings? _settings;
  String _status = 'Loading settings...';
  late final TabController _tabs;
  Timer? _pingTimer;
  Duration? _lastRtt;
  bool _online = false;
  int _consecutiveFailures = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pingTimer?.cancel();
    _tabs.dispose();
    unawaited(_client.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _settings != null) {
      // Coming back from background: the socket may have been torn down by
      // the OS while we were paused. Rebind eagerly so the next packet flies.
      unawaited(_rebindAndPing('resumed from background'));
    }
  }

  Future<void> _init() async {
    final settings = await HidSettings.load();
    if (!mounted) return;
    setState(() => _settings = settings);
    await _reconnect(settings);
  }

  Future<void> _reconnect(HidSettings settings) async {
    _pingTimer?.cancel();
    _consecutiveFailures = 0;
    try {
      await _client.configure(host: settings.host, port: settings.port);
      _setStatus('Target ${settings.host}:${settings.port}');
      unawaited(_pingNow());
      _pingTimer = Timer.periodic(_pingInterval, (_) => _pingNow());
    } catch (error) {
      _setOnline(false);
      _setStatus('Configure failed: $error');
    }
  }

  Future<void> _pingNow() async {
    try {
      final rtt = await _client.ping();
      if (!mounted) return;
      if (rtt != null) {
        _consecutiveFailures = 0;
        setState(() {
          _online = true;
          _lastRtt = rtt;
        });
        return;
      }

      // No PONG arrived in time — count it. After N misses, rebind the UDP
      // socket. The phone may have gone through Wi-Fi sleep or our NAT
      // mapping on the router may have been evicted; either way the cheapest
      // recovery is to throw the socket away and bind a fresh one.
      _consecutiveFailures++;
      setState(() {
        _online = false;
        _lastRtt = null;
      });
      if (_consecutiveFailures >= _rebindAfterFailures && _settings != null) {
        await _rebindAndPing(
            'auto-rebind after $_consecutiveFailures missed pings');
      }
    } catch (error) {
      _setOnline(false);
      _setStatus('Ping failed: $error');
    }
  }

  Future<void> _rebindAndPing(String reason) async {
    _consecutiveFailures = 0;
    try {
      await _client.rebind();
      _setStatus(reason);
      unawaited(_pingNow());
    } catch (error) {
      _setOnline(false);
      _setStatus('Rebind failed: $error');
    }
  }

  void _setOnline(bool value) {
    if (!mounted) return;
    setState(() {
      _online = value;
      if (!value) _lastRtt = null;
    });
  }

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _status = message);
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    final updated = await Navigator.of(context).push<HidSettings>(
      MaterialPageRoute(builder: (_) => SettingsPage(initial: settings)),
    );
    if (updated == null) return;
    setState(() => _settings = updated);
    await _reconnect(updated);
  }

  void _send(Uint8List packet) {
    if (!_client.isConfigured) {
      _setStatus('Not configured yet.');
      return;
    }
    try {
      _client.send(packet);
    } catch (error) {
      _setStatus('Send failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rttLabel = _online
        ? (_lastRtt == null
            ? 'connected'
            : 'connected · ${_lastRtt!.inMilliseconds}ms')
        : 'offline';
    final statusColor = _online
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local HID'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _settings == null ? null : _openSettings,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.touch_app), text: 'Touchpad'),
            Tab(icon: Icon(Icons.keyboard), text: 'Keys'),
            Tab(icon: Icon(Icons.music_note), text: 'Media'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                TouchpadPane(onSend: _send),
                KeyboardPane(onSend: _send),
                MediaPane(onSend: _send),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  _online ? Icons.cloud_done : Icons.cloud_off,
                  size: 16,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Text(rttLabel,
                    style: theme.textTheme.bodySmall?.copyWith(color: statusColor)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef HidSender = void Function(Uint8List packet);

// ─── Touchpad ────────────────────────────────────────────────────────────────

class TouchpadPane extends StatefulWidget {
  const TouchpadPane({super.key, required this.onSend});

  final HidSender onSend;

  @override
  State<TouchpadPane> createState() => _TouchpadPaneState();
}

class _TouchpadPaneState extends State<TouchpadPane> {
  static const _flushInterval = Duration(milliseconds: 16);
  static const _sensitivity = 1.6;

  Timer? _flushTimer;
  double _pendingDx = 0;
  double _pendingDy = 0;
  bool _active = false;

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _) {
    _active = true;
    _ensureTimer();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _pendingDx += details.delta.dx * _sensitivity;
    _pendingDy += details.delta.dy * _sensitivity;
    _ensureTimer();
  }

  void _onPanEnd(DragEndDetails _) {
    _active = false;
  }

  void _ensureTimer() {
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => _flush());
  }

  void _flush() {
    var dx = _pendingDx.round();
    var dy = _pendingDy.round();
    if (dx == 0 && dy == 0) {
      if (!_active) {
        _flushTimer?.cancel();
        _flushTimer = null;
      }
      return;
    }
    dx = dx.clamp(-127, 127);
    dy = dy.clamp(-127, 127);
    _pendingDx -= dx;
    _pendingDy -= dy;
    widget.onSend(HidProtocol.mouseMove(dx, dy));
  }

  void _click(int buttonMask) =>
      widget.onSend(HidProtocol.mouseClick(buttonMask));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onPanCancel: () => _active = false,
              onTap: () => _click(MouseButton.left),
              onDoubleTap: () {
                _click(MouseButton.left);
                _click(MouseButton.left);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Drag to move\nTap = left click  •  Double-tap = double click',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _click(MouseButton.left),
                  child: const Text('Left click'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _click(MouseButton.middle),
                  child: const Text('Middle'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => _click(MouseButton.right),
                  child: const Text('Right click'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Keyboard ────────────────────────────────────────────────────────────────

class KeyboardPane extends StatefulWidget {
  const KeyboardPane({super.key, required this.onSend});

  final HidSender onSend;

  @override
  State<KeyboardPane> createState() => _KeyboardPaneState();
}

class _KeyboardPaneState extends State<KeyboardPane> {
  static const _rows = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _tap(int keycode) =>
      widget.onSend(HidProtocol.keyTap(keycode));

  void _tapChar(String ch) {
    final keycode = HidKey.fromChar(ch);
    if (keycode != null) _tap(keycode);
  }

  void _typeString(String text) {
    for (final ch in text.split('')) {
      _tapChar(ch);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Type then "Send" (a-z, 0-9, space, enter)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final text = _inputController.text;
                  if (text.isEmpty) return;
                  _inputController.clear();
                  _typeString(text);
                },
                child: const Text('Send'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SpecialKey(label: 'Esc', onTap: () => _tap(HidKey.escape)),
              _SpecialKey(label: 'Tab', onTap: () => _tap(HidKey.tab)),
              _SpecialKey(
                  label: 'Backspace', onTap: () => _tap(HidKey.backspace)),
              _SpecialKey(label: 'Enter', onTap: () => _tap(HidKey.enter)),
              _SpecialKey(label: 'Space', onTap: () => _tap(HidKey.space)),
              _SpecialKey(label: '←', onTap: () => _tap(HidKey.left)),
              _SpecialKey(label: '↑', onTap: () => _tap(HidKey.up)),
              _SpecialKey(label: '↓', onTap: () => _tap(HidKey.down)),
              _SpecialKey(label: '→', onTap: () => _tap(HidKey.right)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final row in _rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          for (final key in row)
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: _Key(label: key, onTap: () => _tapChar(key)),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Text(label.toUpperCase()),
      ),
    );
  }
}

class _SpecialKey extends StatelessWidget {
  const _SpecialKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Text(label),
    );
  }
}

// ─── Media ───────────────────────────────────────────────────────────────────

class MediaPane extends StatelessWidget {
  const MediaPane({super.key, required this.onSend});

  final HidSender onSend;

  static const _buttons = <_MediaButton>[
    _MediaButton(
        label: 'Play / Pause', usage: HidMedia.playPause, icon: Icons.play_arrow),
    _MediaButton(label: 'Next', usage: HidMedia.scanNext, icon: Icons.skip_next),
    _MediaButton(
        label: 'Previous', usage: HidMedia.scanPrev, icon: Icons.skip_previous),
    _MediaButton(label: 'Stop', usage: HidMedia.stop, icon: Icons.stop),
    _MediaButton(label: 'Volume +', usage: HidMedia.volumeUp, icon: Icons.volume_up),
    _MediaButton(
        label: 'Volume -', usage: HidMedia.volumeDown, icon: Icons.volume_down),
    _MediaButton(label: 'Mute', usage: HidMedia.mute, icon: Icons.volume_off),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.4,
        children: [
          for (final btn in _buttons)
            FilledButton.tonalIcon(
              onPressed: () => onSend(HidProtocol.mediaTap(btn.usage)),
              icon: Icon(btn.icon),
              label: Text(btn.label),
            ),
        ],
      ),
    );
  }
}

class _MediaButton {
  const _MediaButton({
    required this.label,
    required this.usage,
    required this.icon,
  });

  final String label;
  final int usage;
  final IconData icon;
}

// ─── Settings ────────────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initial});

  final HidSettings initial;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _host =
      TextEditingController(text: widget.initial.host);
  late final TextEditingController _port =
      TextEditingController(text: widget.initial.port.toString());

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid host or port.')),
      );
      return;
    }
    final settings = HidSettings(host: host, port: port);
    await settings.save();
    if (!mounted) return;
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Target')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Set the IP and UDP port the ESP32-S3 firmware is listening on. '
              'The firmware logs its IP on the serial monitor at boot.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Host (IP)',
                hintText: '192.168.1.42',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'UDP port',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
