import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart' show terminalClientProvider;

/// System health dashboard: runs `status` and `health` via terminal proxy.
class AdminHealthTab extends ConsumerStatefulWidget {
  const AdminHealthTab({super.key});

  @override
  ConsumerState<AdminHealthTab> createState() => _AdminHealthTabState();
}

class _AdminHealthTabState extends ConsumerState<AdminHealthTab> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _statusData = {};
  Map<String, dynamic> _healthData = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
  }

  Map<String, dynamic> _tryParseJson(String raw) {
    final stripped = _stripAnsi(raw).trim();
    if (stripped.isEmpty) return {};
    // Try direct parse
    try {
      final parsed = jsonDecode(stripped);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    // Find first JSON object
    final start = stripped.indexOf('{');
    final end = stripped.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final parsed = jsonDecode(stripped.substring(start, end + 1));
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
    }
    return {};
  }

  Future<void> _load() async {
    final client = ref.read(terminalClientProvider);
    if (!client.isConnected || !client.isAuthenticated) {
      try {
        await client.connect();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (!client.isAuthenticated) {
      setState(() => _error = 'terminal proxy not connected');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final statusRaw = await client.executeCommandForOutput(
        'status',
        timeout: const Duration(seconds: 15),
      );
      final healthRaw = await client.executeCommandForOutput(
        'health',
        timeout: const Duration(seconds: 15),
      );

      if (!mounted) return;
      setState(() {
        _statusData = _tryParseJson(statusRaw);
        _healthData = _tryParseJson(healthRaw);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load health data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final headStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              if (_loading)
                Text('loading...', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              if (_error != null)
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.statusError),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _loading ? null : _load,
                child: Text(
                  'refresh',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _loading ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_statusData.isNotEmpty) ...[
                Text('gateway status', style: headStyle),
                const SizedBox(height: 6),
                ..._renderMap(_statusData, t, theme, 0),
                const SizedBox(height: 18),
              ],
              if (_healthData.isNotEmpty) ...[
                Text('health check', style: headStyle),
                const SizedBox(height: 6),
                ..._renderMap(_healthData, t, theme, 0),
              ],
              if (_statusData.isEmpty && _healthData.isEmpty && !_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      'no data',
                      style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Recursively render a JSON map as key-value rows with indentation.
  List<Widget> _renderMap(Map<String, dynamic> map, ShellTokens t, ThemeData theme, int depth) {
    final widgets = <Widget>[];
    final indent = depth * 12.0;
    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic>) {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 4),
          child: Text(
            key,
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11),
          ),
        ));
        widgets.addAll(_renderMap(value, t, theme, depth + 1));
      } else if (value is List) {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 4),
          child: Text(
            '$key: [${value.length} items]',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11),
          ),
        ));
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            widgets.addAll(_renderMap(item, t, theme, depth + 1));
            widgets.add(const SizedBox(height: 2));
          } else {
            widgets.add(Padding(
              padding: EdgeInsets.only(left: indent + 12),
              child: Text(
                '- $item',
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11),
              ),
            ));
          }
        }
      } else {
        final valueStr = value?.toString() ?? '-';
        final valueColor = _statusColor(key, valueStr, t);
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: Text(
                  key,
                  style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  valueStr,
                  style: theme.textTheme.bodySmall?.copyWith(color: valueColor, fontSize: 11),
                ),
              ),
            ],
          ),
        ));
      }
    }
    return widgets;
  }

  Color _statusColor(String key, String value, ShellTokens t) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == 'ok' || lower == 'connected' || lower == 'running' || lower == 'healthy') {
      return t.accentPrimary;
    }
    if (lower == 'false' || lower == 'error' || lower == 'disconnected' || lower == 'unhealthy' || lower == 'down') {
      return t.statusError;
    }
    if (lower == 'degraded' || lower == 'warning' || lower == 'connecting') {
      return t.statusWarning;
    }
    return t.fgPrimary;
  }
}
