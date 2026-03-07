import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_client.dart';
import '../../core/theme.dart';
import '../../main.dart' show authClientProvider;

/// Paginated audit log viewer with server-side filtering, proper pagination,
/// and CSV/JSON export.
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
  int _total = 0;
  String? _expandedId;

  // ── Server-side filter state ─────────────────────────────────────────
  final TextEditingController _actionFilter = TextEditingController();
  final TextEditingController _userIdFilter = TextEditingController();
  final TextEditingController _resourceFilter = TextEditingController();
  final TextEditingController _ipFilter = TextEditingController();
  final TextEditingController _fromFilter = TextEditingController();
  final TextEditingController _toFilter = TextEditingController();
  bool _filtersExpanded = false;

  // ── User cache for resolving UUIDs to emails ─────────────────────────
  Map<String, String> _userEmailCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
      _load();
    });
  }

  @override
  void dispose() {
    _actionFilter.dispose();
    _userIdFilter.dispose();
    _resourceFilter.dispose();
    _ipFilter.dispose();
    _fromFilter.dispose();
    _toFilter.dispose();
    super.dispose();
  }

  /// Load users for email resolution.
  Future<void> _loadUsers() async {
    try {
      final auth = ref.read(authClientProvider);
      final users = await auth.fetchUsers();
      if (!mounted) return;
      setState(() {
        _userEmailCache = {
          for (final u in users)
            if (u['user_id'] != null)
              u['user_id'].toString(): u['email']?.toString() ?? u['role_name']?.toString() ?? '',
        };
      });
    } catch (_) {
      // Non-critical; UUIDs will display as-is
    }
  }

  Future<void> _load({bool append = false}) async {
    final auth = ref.read(authClientProvider);
    if (!append) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
      });
    } else {
      setState(() => _loading = true);
    }

    try {
      final result = await auth.fetchAuditLog(
        limit: _pageSize,
        offset: _offset,
        action: _actionFilter.text.trim().isNotEmpty ? _actionFilter.text.trim() : null,
        userId: _userIdFilter.text.trim().isNotEmpty ? _userIdFilter.text.trim() : null,
        resource: _resourceFilter.text.trim().isNotEmpty ? _resourceFilter.text.trim() : null,
        ip: _ipFilter.text.trim().isNotEmpty ? _ipFilter.text.trim() : null,
        from: _fromFilter.text.trim().isNotEmpty ? _fromFilter.text.trim() : null,
        to: _toFilter.text.trim().isNotEmpty ? _toFilter.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _logs.addAll(result.logs);
        } else {
          _logs = result.logs;
        }
        _total = result.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load audit log: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _nextPage() {
    _offset += _pageSize;
    _load(append: true);
  }

  void _applyFilters() {
    _offset = 0;
    _load();
  }

  void _clearFilters() {
    _actionFilter.clear();
    _userIdFilter.clear();
    _resourceFilter.clear();
    _ipFilter.clear();
    _fromFilter.clear();
    _toFilter.clear();
    _offset = 0;
    _load();
  }

  bool get _hasActiveFilters =>
      _actionFilter.text.trim().isNotEmpty ||
      _userIdFilter.text.trim().isNotEmpty ||
      _resourceFilter.text.trim().isNotEmpty ||
      _ipFilter.text.trim().isNotEmpty ||
      _fromFilter.text.trim().isNotEmpty ||
      _toFilter.text.trim().isNotEmpty;

  bool get _hasMore => _logs.length < _total;

  int get _currentPage => (_offset ~/ _pageSize) + 1;
  int get _totalPages => (_total / _pageSize).ceil().clamp(1, 9999);

  void _exportCsv() {
    final auth = ref.read(authClientProvider);
    final url = auth.getAuditExportUrl(
      format: 'csv',
      action: _actionFilter.text.trim().isNotEmpty ? _actionFilter.text.trim() : null,
      userId: _userIdFilter.text.trim().isNotEmpty ? _userIdFilter.text.trim() : null,
      from: _fromFilter.text.trim().isNotEmpty ? _fromFilter.text.trim() : null,
      to: _toFilter.text.trim().isNotEmpty ? _toFilter.text.trim() : null,
    );
    // Open in new tab (browser handles the download via Content-Disposition)
    html.window.open(url, '_blank');
  }

  void _exportJson() {
    final auth = ref.read(authClientProvider);
    final url = auth.getAuditExportUrl(
      format: 'json',
      action: _actionFilter.text.trim().isNotEmpty ? _actionFilter.text.trim() : null,
      userId: _userIdFilter.text.trim().isNotEmpty ? _userIdFilter.text.trim() : null,
      from: _fromFilter.text.trim().isNotEmpty ? _fromFilter.text.trim() : null,
      to: _toFilter.text.trim().isNotEmpty ? _toFilter.text.trim() : null,
    );
    html.window.open(url, '_blank');
  }

  String _resolveUser(String? userId) {
    if (userId == null || userId == '-') return '-';
    final email = _userEmailCache[userId];
    if (email != null && email.isNotEmpty) return email;
    return userId.length > 24 ? '${userId.substring(0, 24)}...' : userId;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Toolbar ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text(
                'audit log (${_logs.length} of $_total${_hasActiveFilters ? ', filtered' : ''})',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                child: Text(
                  _filtersExpanded ? 'hide filters' : 'filters',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _hasActiveFilters ? t.accentPrimary : t.fgMuted,
                  ),
                ),
              ),
              if (_hasActiveFilters) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearFilters,
                  child: Text('clear', style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
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
              // Export buttons
              GestureDetector(
                onTap: _exportCsv,
                child: Text('csv', style: theme.textTheme.labelSmall?.copyWith(color: t.accentSecondary)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _exportJson,
                child: Text('json', style: theme.textTheme.labelSmall?.copyWith(color: t.accentSecondary)),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _loading ? null : _applyFilters,
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
        // ── Filters panel (collapsible) ──────────────────────────────
        if (_filtersExpanded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildFilterField('action', _actionFilter, t, theme, width: 150),
                _buildFilterField('user_id', _userIdFilter, t, theme, width: 200),
                _buildFilterField('resource', _resourceFilter, t, theme, width: 140),
                _buildFilterField('ip', _ipFilter, t, theme, width: 120),
                _buildFilterField('from (ISO)', _fromFilter, t, theme, width: 160),
                _buildFilterField('to (ISO)', _toFilter, t, theme, width: 160),
                GestureDetector(
                  onTap: _applyFilters,
                  child: Text('apply', style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary)),
                ),
              ],
            ),
          ),
        // ── Table header ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: _buildHeaderRow(t, theme),
        ),
        // ── Log rows + pagination ────────────────────────────────────
        Expanded(
          child: _logs.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _error != null ? '' : 'no audit entries',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _logs.length + 1, // +1 for pagination row
                  itemBuilder: (context, index) {
                    if (index == _logs.length) {
                      return _buildPaginationRow(t, theme);
                    }
                    return _buildLogRow(_logs[index], t, theme);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterField(
    String hint,
    TextEditingController controller,
    ShellTokens t,
    ThemeData theme, {
    double width = 140,
  }) {
    return SizedBox(
      width: width,
      height: 24,
      child: TextField(
        controller: controller,
        style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11),
        decoration: InputDecoration(
          hintText: hint,
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
        onSubmitted: (_) => _applyFilters(),
      ),
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
    final userAgent = log['user_agent'];
    final requestPath = log['request_path'];
    final httpMethod = log['http_method'];
    final sessionId = log['session_id'];
    final isExpanded = _expandedId == id;

    final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final displayUser = _resolveUser(userId);

    final actionColor = _actionColor(action, t);

    // Build expanded metadata including new context fields
    final hasDetail = metadata != null || userAgent != null || requestPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: hasDetail ? () => setState(() => _expandedId = isExpanded ? null : id) : null,
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
                SizedBox(
                  width: 200,
                  child: Tooltip(
                    message: userId,
                    child: Text(displayUser, style: cellStyle, overflow: TextOverflow.ellipsis),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: Text(action, style: cellStyle?.copyWith(color: actionColor)),
                ),
                SizedBox(width: 140, child: Text(resource, style: cellStyle, overflow: TextOverflow.ellipsis)),
                Expanded(child: Text(ip, style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11))),
                if (hasDetail)
                  Text(
                    isExpanded ? '-' : '+',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded && hasDetail)
          Container(
            margin: const EdgeInsets.only(left: 16, bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: SelectableText(
              _formatExpandedDetails(
                metadata: metadata,
                userAgent: userAgent,
                requestPath: requestPath,
                httpMethod: httpMethod,
                sessionId: sessionId,
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 10),
            ),
          ),
      ],
    );
  }

  Widget _buildPaginationRow(ShellTokens t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'page $_currentPage of $_totalPages ($_total total)',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
          ),
          if (_hasMore) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _loading ? null : _nextPage,
              child: Text(
                _loading ? 'loading...' : 'load more',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _loading ? t.fgDisabled : t.accentPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _actionColor(String action, ShellTokens t) {
    final lower = action.toLowerCase();
    if (lower.contains('denied') || lower.contains('failed') || lower.contains('error') || lower.contains('expired')) {
      return t.statusError;
    }
    if (lower.contains('assign') || lower.contains('create') || lower.contains('grant') || lower.contains('ensured')) {
      return t.accentPrimary;
    }
    if (lower.contains('login') || lower.contains('session') || lower.contains('guest')) {
      return t.accentSecondary;
    }
    if (lower.contains('export') || lower.contains('audit.read')) {
      return t.statusWarning;
    }
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

  String _formatExpandedDetails({
    dynamic metadata,
    String? userAgent,
    String? requestPath,
    String? httpMethod,
    String? sessionId,
  }) {
    final parts = <String>[];

    if (metadata != null) {
      try {
        final metaStr = metadata is String
            ? metadata
            : const JsonEncoder.withIndent('  ').convert(metadata);
        parts.add('metadata: $metaStr');
      } catch (_) {
        parts.add('metadata: $metadata');
      }
    }

    if (httpMethod != null && requestPath != null) {
      parts.add('request: $httpMethod $requestPath');
    } else if (requestPath != null) {
      parts.add('path: $requestPath');
    }

    if (userAgent != null && userAgent.isNotEmpty) {
      parts.add('user-agent: $userAgent');
    }

    if (sessionId != null && sessionId.isNotEmpty) {
      parts.add('session: $sessionId');
    }

    return parts.join('\n');
  }
}
