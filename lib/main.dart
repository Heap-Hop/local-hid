import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hid_client.dart';
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
    with SingleTickerProviderStateMixin {
  final _client = HidClient();
  HidSettings? _settings;
  String _status = 'Loading settings...';
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    unawaited(_init());
  }

  @override
  void dispose() {
    _tabs.dispose();
    unawaited(_client.close());
    super.dispose();
  }

  Future<void> _init() async {
    final settings = await HidSettings.load();
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
    await _reconnect(settings);
  }

  Future<void> _reconnect(HidSettings settings) async {
    try {
      await _client.configure(host: settings.host, port: settings.port);
      _setStatus('Target ${settings.host}:${settings.port} (UDP)');
    } catch (error) {
      _setStatus('Configure failed: $error');
    }
  }

  void _setStatus(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _status = message);
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final updated = await Navigator.of(context).push<HidSettings>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(initial: settings),
      ),
    );
    if (updated == null) {
      return;
    }
    setState(() => _settings = updated);
    await _reconnect(updated);
  }

  Future<void> _send(
    String line, {
    bool awaitReply = true,
    bool showOk = false,
  }) async {
    if (!_client.isConfigured) {
      _setStatus('Not configured yet.');
      return;
    }
    try {
      final reply = await _client.sendLine(line, awaitReply: awaitReply);
      if (awaitReply) {
        if (reply == null) {
          _setStatus('Sent "$line" (no reply within 400ms)');
        } else if (reply.startsWith('err')) {
          _setStatus('Firmware: $reply');
        } else if (showOk) {
          _setStatus('Firmware: $reply');
        }
      }
    } catch (error) {
      _setStatus('Send failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              _status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

typedef HidSender = Future<void> Function(
  String line, {
  bool awaitReply,
  bool showOk,
});

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
  bool _sending = false;
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

  Future<void> _flush() async {
    if (_sending) {
      return;
    }
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
    _sending = true;
    try {
      await widget.onSend(
        'm $dx $dy',
        awaitReply: false,
        showOk: false,
      );
    } finally {
      _sending = false;
    }
  }

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
              onTap: () =>
                  widget.onSend('c left', awaitReply: false, showOk: false),
              onDoubleTap: () async {
                await widget.onSend('c left',
                    awaitReply: false, showOk: false);
                await widget.onSend('c left',
                    awaitReply: false, showOk: false);
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
                  onPressed: () =>
                      widget.onSend('c left', awaitReply: false, showOk: false),
                  child: const Text('Left click'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => widget.onSend('c middle',
                      awaitReply: false, showOk: false),
                  child: const Text('Middle'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => widget.onSend('c right',
                      awaitReply: false, showOk: false),
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

  Future<void> _sendKey(String name) =>
      widget.onSend('k $name', awaitReply: false, showOk: false);

  Future<void> _typeString(String text) async {
    for (final ch in text.split('')) {
      final lower = ch.toLowerCase();
      if (RegExp(r'^[a-z0-9]$').hasMatch(lower)) {
        await _sendKey(lower);
      } else if (ch == ' ') {
        await _sendKey('space');
      } else if (ch == '\n') {
        await _sendKey('enter');
      }
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
                onPressed: () async {
                  final text = _inputController.text;
                  if (text.isEmpty) {
                    return;
                  }
                  _inputController.clear();
                  await _typeString(text);
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
              _SpecialKey(label: 'Esc', onTap: () => _sendKey('esc')),
              _SpecialKey(label: 'Tab', onTap: () => _sendKey('tab')),
              _SpecialKey(label: 'Backspace', onTap: () => _sendKey('backspace')),
              _SpecialKey(label: 'Enter', onTap: () => _sendKey('enter')),
              _SpecialKey(label: 'Space', onTap: () => _sendKey('space')),
              _SpecialKey(label: '←', onTap: () => _sendKey('left')),
              _SpecialKey(label: '↑', onTap: () => _sendKey('up')),
              _SpecialKey(label: '↓', onTap: () => _sendKey('down')),
              _SpecialKey(label: '→', onTap: () => _sendKey('right')),
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
                                child:
                                    _Key(label: key, onTap: () => _sendKey(key)),
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
    _MediaButton(label: 'Play / Pause', name: 'playpause', icon: Icons.play_arrow),
    _MediaButton(label: 'Next', name: 'next', icon: Icons.skip_next),
    _MediaButton(label: 'Previous', name: 'prev', icon: Icons.skip_previous),
    _MediaButton(label: 'Stop', name: 'stop', icon: Icons.stop),
    _MediaButton(label: 'Volume +', name: 'volup', icon: Icons.volume_up),
    _MediaButton(label: 'Volume -', name: 'voldown', icon: Icons.volume_down),
    _MediaButton(label: 'Mute', name: 'mute', icon: Icons.volume_off),
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
              onPressed: () =>
                  onSend('md ${btn.name}', awaitReply: false, showOk: false),
              icon: Icon(btn.icon),
              label: Text(btn.label),
            ),
        ],
      ),
    );
  }
}

class _MediaButton {
  const _MediaButton({required this.label, required this.name, required this.icon});

  final String label;
  final String name;
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
    if (!mounted) {
      return;
    }
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
