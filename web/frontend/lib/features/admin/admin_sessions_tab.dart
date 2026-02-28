import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart' show terminalClientProvider;

/// Session management tab: lists active gateway sessions via terminal proxy.
class AdminSessionsTab extends ConsumerStatefulWidget {
  const AdminSessionsTab({super.key});

  @override
  ConsumerState<AdminSessionsTab> createState() => _AdminSessionsTabState();
}

class _AdminSessionsTabState extends ConsumerState<AdminSessionsTab> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
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
      final raw = await client.executeCommandForOutput(
        'sessions list',
        timeout: const Duration(seconds: 15),
      );

      final stripped = _stripAnsi(raw).trim();
      List<Map<String, dynamic>> sessions = [];

      // Try to parse as JSON
      try {
        final parsed = jsonDecode(stripped);
        if (parsed is List) {
          sessions = parsed.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (parsed is Map && parsed.containsKey('sessions')) {
          sessions = (parsed['sessions'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        // Try finding JSON in output
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

        // Try JSON object with sessions key
        if (sessions.isEmpty) {
          final objStart = stripped.indexOf('{');
          final objEnd = stripped.lastIndexOf('}');
          if (objStart >= 0 && objEnd > objStart) {
            try {
              final parsed = jsonDecode(stripped.substring(objStart, objEnd + 1));
              if (parsed is Map && parsed.containsKey('sessions')) {
                sessions = (parsed['sessions'] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
              }
            } catch (_) {}
          }
        }
      }

      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load sessions: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

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
                'sessions (${_sessions.length})',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
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
        // Table header
        if (_sessions.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: _buildHeaderRow(t, theme),
          ),
        // Session rows
        Expanded(
          child: _sessions.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _error != null ? '' : 'no active sessions',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) => _buildSessionRow(_sessions[index], t, theme),
                ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(ShellTokens t, ThemeData theme) {
    final style = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    return Row(
      children: [
        SizedBox(width: 200, child: Text('session', style: style)),
        SizedBox(width: 100, child: Text('status', style: style)),
        SizedBox(width: 140, child: Text('model', style: style)),
        Expanded(child: Text('created', style: style)),
      ],
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> session, ShellTokens t, ThemeData theme) {
    final id = (session['id'] ?? session['sessionId'] ?? session['key'] ?? '-').toString();
    final status = (session['status'] ?? session['state'] ?? '-').toString();
    final model = (session['model'] ?? session['provider'] ?? '-').toString();
    final created = (session['createdAt'] ?? session['created'] ?? session['startedAt'] ?? '-').toString();

    final statusColor = _sessionStatusColor(status, t);
    final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

    // Truncate ID to fit
    final displayId = id.length > 24 ? '${id.substring(0, 24)}...' : id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 200, child: Text(displayId, style: cellStyle)),
          SizedBox(
            width: 100,
            child: Text(status, style: cellStyle?.copyWith(color: statusColor)),
          ),
          SizedBox(width: 140, child: Text(model, style: cellStyle)),
          Expanded(
            child: Text(
              _formatTimestamp(created),
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Color _sessionStatusColor(String status, ShellTokens t) {
    final lower = status.toLowerCase();
    if (lower == 'active' || lower == 'running' || lower == 'connected') return t.accentPrimary;
    if (lower == 'error' || lower == 'failed' || lower == 'dead') return t.statusError;
    if (lower == 'idle' || lower == 'waiting') return t.statusWarning;
    return t.fgMuted;
  }

  String _formatTimestamp(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m:$s';
    } catch (_) {
      return raw;
    }
  }
}
