import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/http_utils.dart';
import '../../core/theme.dart';
import '../../core/toast_provider.dart';
import '../../main.dart' show authClientProvider;

/// Admin tab for managing OpenClaw instances and user assignments.
class AdminOpenClawsTab extends ConsumerStatefulWidget {
  const AdminOpenClawsTab({super.key});

  @override
  ConsumerState<AdminOpenClawsTab> createState() => _AdminOpenClawsTabState();
}

class _AdminOpenClawsTabState extends ConsumerState<AdminOpenClawsTab> {
  static const _baseUrl = String.fromEnvironment(
    'AUTH_SERVICE_URL',
    defaultValue: 'http://localhost',
  );

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _instances = [];

  // Create form
  bool _showCreateForm = false;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _creating = false;

  // Expanded instance for assignments
  String? _expandedId;
  bool _loadingAssignments = false;
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _allUsers = [];
  bool _loadingUsers = false;

  // Delete confirmation
  String? _confirmDeleteId;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    if (!mounted) return;
    final hasTransitional = _instances.any((i) {
      final s = (i['status'] ?? '').toString().toLowerCase();
      return s == 'provisioning' || s == 'pending' || s == 'deleting';
    });
    if (hasTransitional) {
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) _load();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------------

  String? get _token {
    if (!mounted) return null;
    return ref.read(authClientProvider).state.token;
  }

  Future<String> _httpGet(String path) async {
    final token = _token;
    final url = '$_baseUrl$path';
    final request = html.HttpRequest();
    request.open('GET', url);
    request.setRequestHeader('Authorization', 'Bearer $token');
    request.setRequestHeader('Content-Type', 'application/json');
    return safeXhr(request);
  }

  Future<String> _httpPost(String path, Map<String, dynamic> body) async {
    final token = _token;
    final url = '$_baseUrl$path';
    final request = html.HttpRequest();
    request.open('POST', url);
    request.setRequestHeader('Authorization', 'Bearer $token');
    request.setRequestHeader('Content-Type', 'application/json');
    return safeXhr(request, body: jsonEncode(body));
  }

  Future<String> _httpDelete(String path) async {
    final token = _token;
    final url = '$_baseUrl$path';
    final request = html.HttpRequest();
    request.open('DELETE', url);
    request.setRequestHeader('Authorization', 'Bearer $token');
    request.setRequestHeader('Content-Type', 'application/json');
    return safeXhr(request);
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _httpGet('/auth/openclaws/all');
      if (!mounted) return;
      final body = jsonDecode(response);
      final list = body is List ? body : (body['openclaws'] as List? ?? []);
      setState(() {
        _instances = List<Map<String, dynamic>>.from(
          list.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      });
      _startPollingIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load instances: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAssignments(String instanceId) async {
    if (!mounted) return;
    setState(() {
      _loadingAssignments = true;
      _assignments = [];
    });

    try {
      final response = await _httpGet('/auth/openclaws/$instanceId/assignments');
      if (!mounted) return;
      final body = jsonDecode(response);
      final list = body is List ? body : (body['assignments'] as List? ?? []);
      setState(() {
        _assignments = List<Map<String, dynamic>>.from(
          list.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _assignments = []);
    } finally {
      if (mounted) setState(() => _loadingAssignments = false);
    }
  }

  Future<void> _loadAllUsers() async {
    if (_allUsers.isNotEmpty || !mounted) return;
    setState(() => _loadingUsers = true);

    try {
      final response = await _httpGet('/auth/users');
      if (!mounted) return;
      final body = jsonDecode(response);
      final list = body['users'] as List? ?? [];
      setState(() {
        _allUsers = List<Map<String, dynamic>>.from(
          list.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      });
    } catch (_) {
      // Silently fail; the dropdown just won't populate.
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _createInstance() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || !mounted) return;
    final description = _descController.text.trim();

    setState(() => _creating = true);

    try {
      await _httpPost('/auth/openclaws/create', {
        'name': name,
        if (description.isNotEmpty) 'description': description,
      });
      if (!mounted) return;
      _nameController.clear();
      _descController.clear();
      setState(() => _showCreateForm = false);
      ToastService.showInfo(context, 'instance "$name" created');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'create failed: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteInstance(String id, String name) async {
    if (!mounted) return;
    setState(() => _confirmDeleteId = null);

    try {
      await _httpDelete('/auth/openclaws/$id');
      if (!mounted) return;
      ToastService.showInfo(context, 'instance "$name" deleted');
      if (_expandedId == id) {
        _expandedId = null;
        _assignments = [];
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'delete failed: $e');
    }
  }

  Future<void> _assignUser(String instanceId, String userId) async {
    try {
      await _httpPost('/auth/openclaws/$instanceId/assign', {'userId': userId});
      if (!mounted) return;
      ToastService.showInfo(context, 'user assigned');
      await _loadAssignments(instanceId);
      if (!mounted) return;
      ref.read(authClientProvider).fetchUserOpenClaws();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'assign failed: $e');
    }
  }

  Future<void> _unassignUser(String instanceId, String userId) async {
    try {
      await _httpDelete('/auth/openclaws/$instanceId/assign/$userId');
      if (!mounted) return;
      ToastService.showInfo(context, 'user unassigned');
      await _loadAssignments(instanceId);
      if (!mounted) return;
      ref.read(authClientProvider).fetchUserOpenClaws();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'unassign failed: $e');
    }
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedId == id) {
        _expandedId = null;
        _assignments = [];
      } else {
        _expandedId = id;
        _confirmDeleteId = null;
      }
    });
    if (_expandedId == id) {
      _loadAssignments(id);
      _loadAllUsers();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
                'openclaws (${_instances.length})',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              if (_loading)
                Text('loading...',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: t.fgTertiary)),
              if (_error != null)
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: t.statusError),
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
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => setState(() => _showCreateForm = !_showCreateForm),
                child: Text(
                  'create',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Create form (inline)
        if (_showCreateForm) _buildCreateForm(t, theme),
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: _buildHeaderRow(t, theme),
        ),
        // Instance list
        Expanded(
          child: _instances.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _error != null ? '' : 'no instances',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _instances.length,
                  itemBuilder: (context, index) {
                    return _buildInstanceSection(
                        _instances[index], t, theme);
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Create form
  // ---------------------------------------------------------------------------

  Widget _buildCreateForm(ShellTokens t, ThemeData theme) {
    final inputStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: TextField(
              controller: _nameController,
              style: inputStyle,
              decoration: InputDecoration(
                hintText: 'name (required)',
                hintStyle: inputStyle?.copyWith(color: t.fgPlaceholder),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                border: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.accentPrimary, width: 0.5),
                ),
              ),
              onSubmitted: (_) => _createInstance(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _descController,
              style: inputStyle,
              decoration: InputDecoration(
                hintText: 'description (optional)',
                hintStyle: inputStyle?.copyWith(color: t.fgPlaceholder),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                border: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.accentPrimary, width: 0.5),
                ),
              ),
              onSubmitted: (_) => _createInstance(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _creating ? null : _createInstance,
            child: Text(
              _creating ? 'creating...' : 'create',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _creating ? t.fgDisabled : t.accentPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _showCreateForm = false;
              _nameController.clear();
              _descController.clear();
            }),
            child: Text(
              'cancel',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table header
  // ---------------------------------------------------------------------------

  Widget _buildHeaderRow(ShellTokens t, ThemeData theme) {
    final style =
        theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    return Row(
      children: [
        SizedBox(width: 20, child: Text('', style: style)),
        SizedBox(width: 140, child: Text('name', style: style)),
        SizedBox(width: 70, child: Text('status', style: style)),
        SizedBox(width: 180, child: Text('pod', style: style)),
        SizedBox(width: 60, child: Text('users', style: style)),
        SizedBox(width: 140, child: Text('created', style: style)),
        Expanded(
            child: Text('actions', style: style, textAlign: TextAlign.right)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Instance row + expandable assignment panel
  // ---------------------------------------------------------------------------

  Widget _buildInstanceSection(
      Map<String, dynamic> instance, ShellTokens t, ThemeData theme) {
    final id = (instance['id'] ?? '').toString();
    final name = (instance['name'] ?? '-').toString();
    final status = (instance['status'] ?? 'unknown').toString();
    final podName = (instance['pod_name'] ?? '-').toString();
    final createdAt = (instance['created_at'] ?? '-').toString();
    final isExpanded = _expandedId == id;
    final isConfirmingDelete = _confirmDeleteId == id;

    final cellStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

    // User count from the API response (always available)
    final assignedCount = instance['user_count'] as int?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary row
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggleExpand(id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isExpanded ? t.surfaceCard : Colors.transparent,
              border:
                  Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                // Expand indicator
                SizedBox(
                  width: 20,
                  child: Text(
                    isExpanded ? '-' : '+',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgMuted, fontSize: 11),
                  ),
                ),
                // Name
                SizedBox(width: 140, child: Text(name, style: cellStyle)),
                // Status dot + label
                SizedBox(
                  width: 70,
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor(status, t),
                        ),
                      ),
                      Text(
                        status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _statusColor(status, t),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Pod name
                SizedBox(
                  width: 180,
                  child: Text(
                    podName,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Assigned users count
                SizedBox(
                  width: 60,
                  child: Text(
                    assignedCount != null ? '$assignedCount' : '--',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgMuted, fontSize: 11),
                  ),
                ),
                // Created date
                SizedBox(
                  width: 140,
                  child: Text(
                    _formatTimestamp(createdAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgMuted, fontSize: 11),
                  ),
                ),
                // Actions
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => _toggleExpand(id),
                        child: Text(
                          'assignments',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.accentPrimary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isConfirmingDelete) ...[
                        Text(
                          'confirm?',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.statusWarning,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _deleteInstance(id, name),
                          child: Text(
                            'yes',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.statusError,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _confirmDeleteId = null),
                          child: Text(
                            'no',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgMuted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ] else
                        GestureDetector(
                          onTap: () =>
                              setState(() => _confirmDeleteId = id),
                          child: Text(
                            'delete',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.statusError,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expanded assignments panel
        if (isExpanded) _buildAssignmentsPanel(id, t, theme),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Assignments panel
  // ---------------------------------------------------------------------------

  Widget _buildAssignmentsPanel(
      String instanceId, ShellTokens t, ThemeData theme) {
    final assignedUserIds =
        _assignments.map((a) => a['user_id'].toString()).toSet();

    // Users not yet assigned to this instance
    final availableUsers = _allUsers.where((u) {
      final uid = (u['user_id'] ?? u['id'] ?? '').toString();
      return uid.isNotEmpty && !assignedUserIds.contains(uid);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceCard,
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section header
          Row(
            children: [
              Text(
                'assigned users (${_assignments.length})',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: t.fgTertiary, fontSize: 10),
              ),
              const SizedBox(width: 8),
              if (_loadingAssignments)
                Text(
                  'loading...',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: t.fgTertiary, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Assignment rows
          if (_assignments.isEmpty && !_loadingAssignments)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 6),
              child: Text(
                'no users assigned',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: t.fgPlaceholder, fontSize: 11),
              ),
            )
          else
            ..._assignments.map((a) {
              final userId = (a['user_id'] ?? '').toString();
              final assignedAt = (a['assigned_at'] ?? '').toString();
              // Try to find user email from _allUsers
              final userInfo = _allUsers.firstWhere(
                (u) =>
                    (u['user_id'] ?? u['id'] ?? '').toString() == userId,
                orElse: () => <String, dynamic>{},
              );
              final email = (userInfo['email'] ?? '').toString();
              final displayUser = email.isNotEmpty
                  ? email
                  : (userId.length > 24
                      ? '${userId.substring(0, 24)}...'
                      : userId);

              return Padding(
                padding:
                    const EdgeInsets.only(left: 20, top: 2, bottom: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 240,
                      child: Text(
                        displayUser,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: t.fgPrimary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: Text(
                        _formatTimestamp(assignedAt),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: t.fgMuted, fontSize: 11),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _unassignUser(instanceId, userId),
                      child: Text(
                        'remove',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: t.statusError,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          // Add user row
          _buildAddUserRow(instanceId, availableUsers, t, theme),
        ],
      ),
    );
  }

  Widget _buildAddUserRow(
    String instanceId,
    List<Map<String, dynamic>> availableUsers,
    ShellTokens t,
    ThemeData theme,
  ) {
    if (_loadingUsers) {
      return Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Text(
          'loading users...',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: t.fgTertiary, fontSize: 10),
        ),
      );
    }

    if (availableUsers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Text(
          _allUsers.isEmpty ? 'no users loaded' : 'all users assigned',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: t.fgTertiary, fontSize: 10),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Row(
        children: [
          Text(
            'add user:',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: t.fgTertiary, fontSize: 10),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: availableUsers.take(20).map((u) {
              final uid = (u['user_id'] ?? u['id'] ?? '').toString();
              final email = (u['email'] ?? '').toString();
              final label = email.isNotEmpty
                  ? (email.length > 28 ? '${email.substring(0, 28)}...' : email)
                  : (uid.length > 16 ? '${uid.substring(0, 16)}...' : uid);

              return GestureDetector(
                onTap: () => _assignUser(instanceId, uid),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: kShellBorderRadius,
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: t.accentPrimary,
                      fontSize: 10,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (availableUsers.length > 20) ...[
            const SizedBox(width: 6),
            Text(
              '+${availableUsers.length - 20} more',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: t.fgTertiary, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Color _statusColor(String status, ShellTokens t) {
    switch (status.toLowerCase()) {
      case 'running':
        return t.accentPrimary;
      case 'stopped':
      case 'error':
      case 'failed':
        return t.statusError;
      case 'starting':
      case 'pending':
        return t.statusWarning;
      default:
        return t.fgMuted;
    }
  }

  String _formatTimestamp(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m';
    } catch (_) {
      return raw;
    }
  }
}
