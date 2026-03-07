import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart' show terminalClientProvider;
import '../../main.dart' show authClientProvider;

/// Fleet-wide health dashboard with per-claw drill-down.
/// Default view: fleet overview from GET /auth/openclaws/fleet/health.
/// Drill-down: single-claw detail via terminal proxy (status --json, health --json).
class AdminHealthTab extends ConsumerStatefulWidget {
  const AdminHealthTab({super.key});

  @override
  ConsumerState<AdminHealthTab> createState() => _AdminHealthTabState();
}

class _AdminHealthTabState extends ConsumerState<AdminHealthTab> {
  static const _baseUrl = String.fromEnvironment(
    'AUTH_SERVICE_URL', defaultValue: 'http://localhost');

  bool _loading = false;
  String? _error;

  // Fleet view state
  List<Map<String, dynamic>> _fleetClaws = [];

  // Single-claw drill-down state
  String? _drillDownClawName;
  Map<String, dynamic> _drillStatus = {};
  Map<String, dynamic> _drillHealth = {};

  String? get _token => ref.read(authClientProvider).state.token;
  String? get _activeClawName {
    final auth = ref.read(authClientProvider).state;
    return auth.activeOpenClaw?.name;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFleet());
  }

  // ── Fleet loading via auth-service API ─────────────────────────────────

  Future<void> _loadFleet() async {
    setState(() { _loading = true; _error = null; _drillDownClawName = null; });
    try {
      final url = '$_baseUrl/auth/openclaws/fleet/health';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $_token');
      final completer = Completer<String>();
      request.onLoad.listen((_) {
        if (request.status! >= 200 && request.status! < 300) {
          completer.complete(request.responseText ?? '{}');
        } else {
          completer.completeError('HTTP ${request.status}: ${request.responseText}');
        }
      });
      request.onError.listen((_) => completer.completeError('request failed'));
      request.send();
      final raw = await completer.future;
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final claws = (parsed['claws'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [];
      if (!mounted) return;
      setState(() => _fleetClaws = claws);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Single-claw drill-down via terminal proxy ──────────────────────────

  Future<void> _drillDown(String clawName) async {
    setState(() { _drillDownClawName = clawName; _loading = true; _error = null; });
    try {
      final client = ref.read(terminalClientProvider);
      if (!client.isConnected || !client.isAuthenticated) {
        await client.connect();
      }
      final statusRaw = await client.executeCommandForOutput(
        'status --json', timeout: const Duration(seconds: 15));
      final healthRaw = await client.executeCommandForOutput(
        'health --json', timeout: const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _drillStatus = _tryParseJson(statusRaw);
        _drillHealth = _tryParseJson(healthRaw);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _stripAnsi(String input) =>
      input.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');

  Map<String, dynamic> _tryParseJson(String raw) {
    final stripped = _stripAnsi(raw).trim();
    if (stripped.isEmpty) return {};
    try {
      final parsed = jsonDecode(stripped);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
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

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final isDrill = _drillDownClawName != null;

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
              Text(
                isDrill
                    ? 'health -- $_drillDownClawName'
                    : 'health (${_fleetClaws.length} claws)',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              if (_loading)
                Text('loading...', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              if (_error != null)
                Expanded(child: Text(_error!,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.statusError),
                    overflow: TextOverflow.ellipsis)),
              const Spacer(),
              if (isDrill) ...[
                GestureDetector(
                  onTap: _loadFleet,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('fleet',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              GestureDetector(
                onTap: _loading ? null : (isDrill ? () => _drillDown(_drillDownClawName!) : _loadFleet),
                child: Text('refresh',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _loading ? t.fgDisabled : t.accentPrimary)),
              ),
            ],
          ),
        ),
        // Content
        Expanded(child: isDrill ? _buildDrillDown(t, theme) : _buildFleetView(t, theme)),
      ],
    );
  }

  // ── Fleet view ─────────────────────────────────────────────────────────

  Widget _buildFleetView(ShellTokens t, ThemeData theme) {
    if (_fleetClaws.isEmpty && !_loading) {
      return Center(child: Text(_error != null ? '' : 'no claws',
          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder)));
    }
    final headerStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

    return Column(
      children: [
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(children: [
            SizedBox(width: 14, child: Text('', style: headerStyle)),
            SizedBox(width: 120, child: Text('name', style: headerStyle)),
            SizedBox(width: 100, child: Text('pod status', style: headerStyle)),
            SizedBox(width: 60, child: Text('ready', style: headerStyle)),
            SizedBox(width: 140, child: Text('model', style: headerStyle)),
            SizedBox(width: 60, child: Text('sessions', style: headerStyle)),
            Expanded(child: Text('error', style: headerStyle)),
          ]),
        ),
        // Rows
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _fleetClaws.length,
            itemBuilder: (ctx, i) {
              final claw = _fleetClaws[i];
              final name = claw['name'] as String? ?? '-';
              final podStatus = claw['podStatus'] as String? ?? '-';
              final ready = claw['ready'] == true;
              final error = claw['error'] as String? ?? '';
              final gateway = claw['gateway'] as Map<String, dynamic>?;

              // Extract model + session count from gateway status
              final sessions = gateway?['sessions'] as Map<String, dynamic>?;
              final sessionCount = sessions?['count'] ?? '-';
              final defaults = sessions?['defaults'] as Map<String, dynamic>?;
              final model = defaults?['model'] as String? ?? '-';

              final isActiveClaw = name == _activeClawName;

              return GestureDetector(
                onTap: isActiveClaw ? () => _drillDown(name) : null,
                child: MouseRegion(
                  cursor: isActiveClaw ? SystemMouseCursors.click : SystemMouseCursors.basic,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 6, height: 6,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: ready ? t.accentPrimary : t.statusError,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 120, child: Text(name,
                          style: cellStyle?.copyWith(
                            fontWeight: isActiveClaw ? FontWeight.bold : FontWeight.normal,
                            color: isActiveClaw ? t.accentPrimary : t.fgPrimary),
                          overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 100, child: Text(podStatus,
                          style: cellStyle?.copyWith(color: ready ? t.accentPrimary : t.statusWarning))),
                      SizedBox(width: 60, child: Text(ready ? 'yes' : 'no',
                          style: cellStyle?.copyWith(color: ready ? t.accentPrimary : t.fgMuted))),
                      SizedBox(width: 140, child: Text(model,
                          style: cellStyle?.copyWith(color: t.fgMuted),
                          overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 60, child: Text('$sessionCount', style: cellStyle)),
                      Expanded(child: Text(error,
                          style: cellStyle?.copyWith(color: t.statusError, fontSize: 9),
                          overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Single-claw drill-down ─────────────────────────────────────────────

  Widget _buildDrillDown(ShellTokens t, ThemeData theme) {
    final headStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_drillStatus.isNotEmpty) ...[
          Text('gateway status', style: headStyle),
          const SizedBox(height: 6),
          ..._renderMap(_drillStatus, t, theme, 0),
          const SizedBox(height: 18),
        ],
        if (_drillHealth.isNotEmpty) ...[
          Text('health check', style: headStyle),
          const SizedBox(height: 6),
          ..._renderMap(_drillHealth, t, theme, 0),
        ],
        if (_drillStatus.isEmpty && _drillHealth.isEmpty && !_loading && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(child: Text('no data',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder))),
          ),
      ],
    );
  }

  // ── JSON renderer ──────────────────────────────────────────────────────

  List<Widget> _renderMap(Map<String, dynamic> map, ShellTokens t, ThemeData theme, int depth) {
    final widgets = <Widget>[];
    final indent = depth * 12.0;
    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic>) {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 4),
          child: Text(key, style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11)),
        ));
        widgets.addAll(_renderMap(value, t, theme, depth + 1));
      } else if (value is List) {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 4),
          child: Text('$key: [${value.length} items]',
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11)),
        ));
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            widgets.addAll(_renderMap(item, t, theme, depth + 1));
            widgets.add(const SizedBox(height: 2));
          } else {
            widgets.add(Padding(
              padding: EdgeInsets.only(left: indent + 12),
              child: Text('- $item',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11)),
            ));
          }
        }
      } else {
        final valueStr = value?.toString() ?? '-';
        final valueColor = _statusColor(key, valueStr, t);
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 160, child: Text(key,
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11))),
            Expanded(child: Text(valueStr,
                style: theme.textTheme.bodySmall?.copyWith(color: valueColor, fontSize: 11))),
          ]),
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
