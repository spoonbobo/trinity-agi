import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart' show terminalClientProvider;
import '../../main.dart' show authClientProvider;

/// Fleet-wide session dashboard with per-claw drill-down.
/// Default view: fleet session aggregation from GET /auth/openclaws/fleet/sessions.
/// Drill-down: single-claw sessions via terminal proxy (sessions --json).
class AdminSessionsTab extends ConsumerStatefulWidget {
  const AdminSessionsTab({super.key});

  @override
  ConsumerState<AdminSessionsTab> createState() => _AdminSessionsTabState();
}

class _AdminSessionsTabState extends ConsumerState<AdminSessionsTab> {
  static const _baseUrl = String.fromEnvironment(
    'AUTH_SERVICE_URL', defaultValue: 'http://localhost');

  bool _loading = false;
  String? _error;

  // Fleet view state
  List<Map<String, dynamic>> _fleetClaws = [];
  int _totalSessions = 0;

  // Drill-down state
  String? _drillDownClawName;
  List<Map<String, dynamic>> _drillSessions = [];

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

  // ── Fleet loading ──────────────────────────────────────────────────────

  Future<void> _loadFleet() async {
    setState(() { _loading = true; _error = null; _drillDownClawName = null; });
    try {
      final url = '$_baseUrl/auth/openclaws/fleet/sessions';
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
      final total = (parsed['totalSessions'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() { _fleetClaws = claws; _totalSessions = total; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Single-claw drill-down ─────────────────────────────────────────────

  Future<void> _drillDown(String clawName) async {
    setState(() { _drillDownClawName = clawName; _loading = true; _error = null; });
    try {
      final client = ref.read(terminalClientProvider);
      if (!client.isConnected || !client.isAuthenticated) {
        await client.connect();
      }
      final raw = await client.executeCommandForOutput(
        'sessions --json', timeout: const Duration(seconds: 15));
      final stripped = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '').trim();
      List<Map<String, dynamic>> sessions = [];
      try {
        final parsed = jsonDecode(stripped);
        if (parsed is List) {
          sessions = parsed.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (parsed is Map && parsed.containsKey('sessions')) {
          sessions = (parsed['sessions'] as List)
              .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {
        final start = stripped.indexOf('[');
        final end = stripped.lastIndexOf(']');
        if (start >= 0 && end > start) {
          try {
            final parsed = jsonDecode(stripped.substring(start, end + 1));
            if (parsed is List) {
              sessions = parsed.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            }
          } catch (_) {}
        }
      }
      if (!mounted) return;
      setState(() => _drillSessions = sessions);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    ? 'sessions -- $_drillDownClawName (${_drillSessions.length})'
                    : 'sessions ($_totalSessions total, ${_fleetClaws.length} claws)',
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

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _fleetClaws.length,
      itemBuilder: (ctx, i) {
        final claw = _fleetClaws[i];
        final name = claw['name'] as String? ?? '-';
        final count = claw['count'] as int? ?? 0;
        final error = claw['error'] as String? ?? '';
        final sessions = (claw['sessions'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        final isActiveClaw = name == _activeClawName;
        final headerStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
        final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Claw header
            GestureDetector(
              onTap: isActiveClaw ? () => _drillDown(name) : null,
              child: MouseRegion(
                cursor: isActiveClaw ? SystemMouseCursors.click : SystemMouseCursors.basic,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: t.surfaceCard,
                    border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: error.isEmpty ? t.accentPrimary : t.statusError,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(name, style: theme.textTheme.bodySmall?.copyWith(
                        color: isActiveClaw ? t.accentPrimary : t.fgPrimary,
                        fontWeight: isActiveClaw ? FontWeight.bold : FontWeight.normal)),
                    const SizedBox(width: 8),
                    Text('$count sessions', style: headerStyle),
                    if (error.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(error, style: headerStyle?.copyWith(color: t.statusError)),
                    ],
                  ]),
                ),
              ),
            ),
            // Session rows for this claw
            ...sessions.map((s) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Row(children: [
                const SizedBox(width: 14),
                SizedBox(width: 220, child: Text(
                    _truncate(s['key'] as String? ?? s['sessionId'] as String? ?? '-', 30),
                    style: cellStyle)),
                SizedBox(width: 80, child: Text(s['kind'] as String? ?? '-',
                    style: cellStyle?.copyWith(color: _kindColor(s['kind'] as String? ?? '', t)))),
                SizedBox(width: 140, child: Text(s['model'] as String? ?? '-',
                    style: cellStyle?.copyWith(color: t.fgMuted))),
                Expanded(child: Text(
                    _formatTimestamp(s['updatedAt']),
                    style: cellStyle?.copyWith(color: t.fgMuted))),
              ]),
            )),
          ],
        );
      },
    );
  }

  // ── Drill-down view ────────────────────────────────────────────────────

  Widget _buildDrillDown(ShellTokens t, ThemeData theme) {
    if (_drillSessions.isEmpty && !_loading) {
      return Center(child: Text(_error != null ? '' : 'no active sessions',
          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder)));
    }

    final headerStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
        ),
        child: Row(children: [
          SizedBox(width: 220, child: Text('session', style: headerStyle)),
          SizedBox(width: 80, child: Text('kind', style: headerStyle)),
          SizedBox(width: 140, child: Text('model', style: headerStyle)),
          Expanded(child: Text('updated', style: headerStyle)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _drillSessions.length,
          itemBuilder: (ctx, i) {
            final s = _drillSessions[i];
            final id = _truncate(
                (s['key'] ?? s['sessionId'] ?? s['id'] ?? '-').toString(), 30);
            final kind = (s['kind'] ?? '-').toString();
            final model = (s['model'] ?? s['modelProvider'] ?? '-').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 220, child: Text(id, style: cellStyle)),
                SizedBox(width: 80, child: Text(kind,
                    style: cellStyle?.copyWith(color: _kindColor(kind, t)))),
                SizedBox(width: 140, child: Text(model, style: cellStyle)),
                Expanded(child: Text(_formatTimestamp(s['updatedAt']),
                    style: cellStyle?.copyWith(color: t.fgMuted))),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _truncate(String s, int max) => s.length > max ? '${s.substring(0, max)}...' : s;

  Color _kindColor(String kind, ShellTokens t) {
    final lower = kind.toLowerCase();
    if (lower == 'direct') return t.accentPrimary;
    if (lower == 'group') return t.accentSecondary;
    if (lower == 'cron' || lower == 'hook') return t.statusWarning;
    return t.fgMuted;
  }

  String _formatTimestamp(dynamic updated) {
    if (updated is! num) return '-';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(updated.toInt());
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m:$s';
    } catch (_) {
      return '-';
    }
  }
}
