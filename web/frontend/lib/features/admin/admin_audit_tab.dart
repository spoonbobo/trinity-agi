import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../main.dart' show authClientProvider;

/// Paginated audit log viewer with action filtering.
class AdminAuditTab extends ConsumerStatefulWidget {
  const AdminAuditTab({super.key});

  @override
  ConsumerState<AdminAuditTab> createState() => _AdminAuditTabState();
}

class _AdminAuditTabState extends ConsumerState<AdminAuditTab> {
  static const int _pageSize = 50;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _logs = [];
  int _offset = 0;
  bool _hasMore = true;
  String _filterAction = '';
  String? _expandedId;

  final TextEditingController _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final auth = ref.read(authClientProvider);
    if (!append) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
        _hasMore = true;
      });
    } else {
      setState(() => _loading = true);
    }

    try {
      final logs = await auth.fetchAuditLog(limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        if (append) {
          _logs.addAll(logs);
        } else {
          _logs = logs;
        }
        _hasMore = logs.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load audit log: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadMore() {
    _offset += _pageSize;
    _load(append: true);
  }

  void _applyFilter() {
    setState(() {
      _filterAction = _filterController.text.trim().toLowerCase();
    });
  }

  List<Map<String, dynamic>> get _filteredLogs {
    if (_filterAction.isEmpty) return _logs;
    return _logs.where((log) {
      final action = (log['action'] ?? '').toString().toLowerCase();
      final resource = (log['resource'] ?? '').toString().toLowerCase();
      return action.contains(_filterAction) || resource.contains(_filterAction);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final filtered = _filteredLogs;

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
                'audit log (${filtered.length}${_filterAction.isNotEmpty ? ' filtered' : ''})',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              // Filter input
              SizedBox(
                width: 180,
                height: 24,
                child: TextField(
                  controller: _filterController,
                  style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'filter by action...',
                    hintStyle: theme.textTheme.bodySmall?.copyWith(color: t.fgPlaceholder, fontSize: 11),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: t.border, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: t.border, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: t.accentPrimary, width: 0.5),
                    ),
                  ),
                  onSubmitted: (_) => _applyFilter(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _applyFilter,
                child: Text(
                  'filter',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary),
                ),
              ),
              if (_filterAction.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _filterController.clear();
                    setState(() => _filterAction = '');
                  },
                  child: Text(
                    'clear',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                  ),
                ),
              ],
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text('loading...', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                ),
              if (_error != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      _error!,
                      style: theme.textTheme.labelSmall?.copyWith(color: t.statusError),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _loading ? null : () => _load(),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: _buildHeaderRow(t, theme),
        ),
        // Log rows
        Expanded(
          child: filtered.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _error != null ? '' : 'no audit entries',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      // "Load more" row
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: GestureDetector(
                            onTap: _loading ? null : _loadMore,
                            child: Text(
                              _loading ? 'loading...' : 'load older',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _loading ? t.fgDisabled : t.accentPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return _buildLogRow(filtered[index], t, theme);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(ShellTokens t, ThemeData theme) {
    final style = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    return Row(
      children: [
        SizedBox(width: 150, child: Text('timestamp', style: style)),
        SizedBox(width: 200, child: Text('user', style: style)),
        SizedBox(width: 160, child: Text('action', style: style)),
        SizedBox(width: 140, child: Text('resource', style: style)),
        Expanded(child: Text('ip', style: style)),
      ],
    );
  }

  Widget _buildLogRow(Map<String, dynamic> log, ShellTokens t, ThemeData theme) {
    final id = (log['id'] ?? '').toString();
    final timestamp = (log['created_at'] ?? log['timestamp'] ?? '-').toString();
    final userId = (log['user_id'] ?? '-').toString();
    final action = (log['action'] ?? '-').toString();
    final resource = (log['resource'] ?? '-').toString();
    final ip = (log['ip'] ?? '-').toString();
    final metadata = log['metadata'];
    final isExpanded = _expandedId == id;

    final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final displayUser = userId.length > 24 ? '${userId.substring(0, 24)}...' : userId;

    final actionColor = _actionColor(action, t);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: metadata != null ? () => setState(() => _expandedId = isExpanded ? null : id) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    _formatTimestamp(timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11),
                  ),
                ),
                SizedBox(width: 200, child: Text(displayUser, style: cellStyle, overflow: TextOverflow.ellipsis)),
                SizedBox(
                  width: 160,
                  child: Text(action, style: cellStyle?.copyWith(color: actionColor)),
                ),
                SizedBox(width: 140, child: Text(resource, style: cellStyle, overflow: TextOverflow.ellipsis)),
                Expanded(child: Text(ip, style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11))),
                if (metadata != null)
                  Text(
                    isExpanded ? '-' : '+',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded && metadata != null)
          Container(
            margin: const EdgeInsets.only(left: 16, bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: SelectableText(
              _formatMetadata(metadata),
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 10),
            ),
          ),
      ],
    );
  }

  Color _actionColor(String action, ShellTokens t) {
    final lower = action.toLowerCase();
    if (lower.contains('denied') || lower.contains('failed') || lower.contains('error')) return t.statusError;
    if (lower.contains('assign') || lower.contains('create') || lower.contains('grant')) return t.accentPrimary;
    if (lower.contains('login') || lower.contains('session')) return t.accentSecondary;
    return t.fgPrimary;
  }

  String _formatTimestamp(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m:$s';
    } catch (_) {
      return raw;
    }
  }

  String _formatMetadata(dynamic metadata) {
    if (metadata is String) return metadata;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(metadata);
    } catch (_) {
      return metadata.toString();
    }
  }
}
