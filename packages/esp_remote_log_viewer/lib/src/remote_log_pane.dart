import 'dart:async';

import 'package:flutter/material.dart';

import 'log_line.dart';
import 'remote_log_service.dart';

/// Drop-in scrolling log viewer.
///
/// The widget subscribes to a [RemoteLogService] and renders each new line
/// at the bottom. Auto-tails to the latest line unless the user scrolls up;
/// shows the connection state in a small status row above the list.
class RemoteLogPane extends StatefulWidget {
  const RemoteLogPane({
    super.key,
    required this.service,
    this.padding = const EdgeInsets.all(8),
    this.maxLines = 2000,
  });

  final RemoteLogService service;
  final EdgeInsets padding;
  final int maxLines;

  @override
  State<RemoteLogPane> createState() => _RemoteLogPaneState();
}

class _RemoteLogPaneState extends State<RemoteLogPane> {
  final List<LogLine> _lines = [];
  final ScrollController _scroll = ScrollController();
  StreamSubscription<LogLine>? _lineSub;
  StreamSubscription<RemoteLogState>? _stateSub;
  bool _autoTail = true;

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.service.recent);
    _lineSub = widget.service.stream.listen(_onLine);
    _stateSub = widget.service.states.listen((_) => setState(() {}));
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _lineSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  void _onLine(LogLine line) {
    setState(() {
      _lines.add(line);
      if (_lines.length > widget.maxLines) {
        _lines.removeRange(0, _lines.length - widget.maxLines);
      }
    });
    if (_autoTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 8;
    if (atBottom != _autoTail) {
      setState(() => _autoTail = atBottom);
    }
  }

  Color _colorFor(LogLevel? level, ColorScheme scheme) {
    switch (level) {
      case LogLevel.error:
        return scheme.error;
      case LogLevel.warn:
        return Colors.amber.shade700;
      case LogLevel.info:
        return scheme.primary;
      case LogLevel.debug:
      case LogLevel.verbose:
        return scheme.onSurfaceVariant;
      case null:
        return scheme.onSurface;
    }
  }

  (IconData, Color, String) _statusGlyph(ColorScheme scheme) {
    switch (widget.service.state) {
      case RemoteLogState.connected:
        return (Icons.podcasts, scheme.primary, 'Streaming');
      case RemoteLogState.connecting:
        return (Icons.sync, scheme.tertiary, 'Connecting…');
      case RemoteLogState.disconnected:
        return (
          Icons.cloud_off,
          scheme.error,
          'Disconnected${widget.service.lastError == null ? '' : ' · ${widget.service.lastError}'}'
        );
      case RemoteLogState.idle:
        return (Icons.cloud_off_outlined, scheme.outline, 'Not configured');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, status) = _statusGlyph(theme.colorScheme);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 8),
              Text('${_lines.length} lines',
                  style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(_lines.clear),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear'),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _autoTail = true);
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                },
                icon: Icon(
                  _autoTail ? Icons.vertical_align_bottom : Icons.lock_open,
                  size: 16,
                ),
                label: Text(_autoTail ? 'Tailing' : 'Tail'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _lines.isEmpty
              ? Center(
                  child: Text(
                    'No log lines yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: widget.padding,
                  itemCount: _lines.length,
                  itemBuilder: (context, i) {
                    final line = _lines[i];
                    return Text(
                      line.text,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _colorFor(line.level, theme.colorScheme),
                        height: 1.25,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
