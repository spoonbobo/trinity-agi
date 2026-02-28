import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/auth_client.dart';
import '../../core/toast_provider.dart';
import '../../core/rbac_constants.dart';
import '../../main.dart' show authClientProvider;

enum _RbacView { matrix, hierarchy, terminal }

/// RBAC overview + interactive permission editor.
/// The matrix view lets admins toggle which permissions each role has (industry standard).
class AdminRbacTab extends ConsumerStatefulWidget {
  const AdminRbacTab({super.key});

  @override
  ConsumerState<AdminRbacTab> createState() => _AdminRbacTabState();
}

class _AdminRbacTabState extends ConsumerState<AdminRbacTab> {
  _RbacView _view = _RbacView.matrix;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  // Live matrix data from DB
  List<_RolePerms> _roles = [];
  List<_PermInfo> _allPermissions = [];

  // Track pending changes per role
  final Map<String, Set<String>> _pendingChanges = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMatrix());
  }

  Future<void> _loadMatrix() async {
    final auth = ref.read(authClientProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await auth.fetchRolePermissionMatrix();
      final roles = (data['roles'] as List?)
              ?.map((r) => _RolePerms(
                    name: r['name'] as String,
                    permissions: Set<String>.from(r['permissions'] as List? ?? []),
                  ))
              .toList() ??
          [];
      final allPerms = (data['allPermissions'] as List?)
              ?.map((p) => _PermInfo(
                    action: p['action'] as String,
                    description: (p['description'] ?? '') as String,
                  ))
              .toList() ??
          [];

      if (!mounted) return;
      setState(() {
        _roles = roles;
        _allPermissions = allPerms;
        _pendingChanges.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load permissions: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _togglePermission(String roleName, String action) {
    if (roleName == 'superadmin') return; // superadmin inherits everything
    setState(() {
      final role = _roles.firstWhere((r) => r.name == roleName);
      if (role.permissions.contains(action)) {
        role.permissions.remove(action);
      } else {
        role.permissions.add(action);
      }
      _pendingChanges[roleName] = Set<String>.from(role.permissions);
    });
  }

  Future<void> _saveChanges() async {
    if (_pendingChanges.isEmpty) return;
    final auth = ref.read(authClientProvider);
    setState(() => _saving = true);

    try {
      for (final entry in _pendingChanges.entries) {
        await auth.updateRolePermissions(entry.key, entry.value.toList());
      }
      if (!mounted) return;
      ToastService.showInfo(context, 'permissions saved (${_pendingChanges.length} roles updated)');
      _pendingChanges.clear();
      await _loadMatrix(); // Reload to confirm
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final canManage = ref.read(authClientProvider).state.hasPermission('users.manage');

    return Column(
      children: [
        // Toolbar: view toggle + actions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              _viewToggle('matrix', _RbacView.matrix, t, theme),
              const SizedBox(width: 12),
              _viewToggle('hierarchy', _RbacView.hierarchy, t, theme),
              const SizedBox(width: 12),
              _viewToggle('terminal', _RbacView.terminal, t, theme),
              const SizedBox(width: 16),
              if (_loading)
                Text('loading...', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              if (_error != null)
                Expanded(
                  child: Text(_error!, style: theme.textTheme.labelSmall?.copyWith(color: t.statusError), overflow: TextOverflow.ellipsis),
                ),
              const Spacer(),
              if (_pendingChanges.isNotEmpty && canManage) ...[
                Text(
                  '${_pendingChanges.length} role(s) changed',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.statusWarning),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _saving ? null : _saveChanges,
                  child: Text(
                    _saving ? 'saving...' : 'save',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _saving ? t.fgDisabled : t.accentPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _loadMatrix,
                  child: Text('discard', style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
                ),
                const SizedBox(width: 16),
              ],
              GestureDetector(
                onTap: _loading ? null : _loadMatrix,
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
        Expanded(child: _buildContent(t, theme, canManage)),
      ],
    );
  }

  Widget _viewToggle(String label, _RbacView view, ShellTokens t, ThemeData theme) {
    return GestureDetector(
      onTap: () => setState(() => _view = view),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: _view == view ? t.accentPrimary : t.fgMuted,
        ),
      ),
    );
  }

  Widget _buildContent(ShellTokens t, ThemeData theme, bool canManage) {
    switch (_view) {
      case _RbacView.matrix:
        return _buildMatrix(t, theme, canManage);
      case _RbacView.hierarchy:
        return _buildHierarchy(t, theme);
      case _RbacView.terminal:
        return _buildTerminal(t, theme);
    }
  }

  // ── Matrix View: interactive permission editor ──

  Widget _buildMatrix(ShellTokens t, ThemeData theme, bool canManage) {
    if (_roles.isEmpty && !_loading) {
      return Center(
        child: Text('no data', style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder)),
      );
    }

    // Editable roles (superadmin excluded from editing)
    final editableRoles = _roles.where((r) => r.name != 'superadmin').toList();
    final colWidth = 80.0;
    final actionWidth = 210.0;

    // Group permissions by domain
    final groups = <String, List<_PermInfo>>{};
    for (final p in _allPermissions) {
      final domain = p.action.split('.').first;
      groups.putIfAbsent(domain, () => []).add(p);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Header info
        Text(
          canManage
              ? 'click cells to toggle permissions. superadmin inherits all and cannot be edited.'
              : 'read-only view. users.manage permission required to edit.',
          style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10),
        ),
        const SizedBox(height: 10),

        // Column headers
        Row(
          children: [
            SizedBox(
              width: actionWidth,
              child: Text('permission', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10)),
            ),
            ...editableRoles.map((r) => SizedBox(
                  width: colWidth,
                  child: Text(r.name, style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10)),
                )),
            SizedBox(
              width: colWidth,
              child: Text(
                'superadmin',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgDisabled, fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),

        // Permission rows, grouped by domain
        ...groups.entries.expand((group) => [
              // Domain header
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(
                  group.key,
                  style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary, fontSize: 10),
                ),
              ),
              // Permission rows
              ...group.value.map((perm) => _matrixRow(perm, editableRoles, t, theme, canManage, colWidth, actionWidth)),
            ]),
      ],
    );
  }

  Widget _matrixRow(
    _PermInfo perm,
    List<_RolePerms> editableRoles,
    ShellTokens t,
    ThemeData theme,
    bool canManage,
    double colWidth,
    double actionWidth,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: actionWidth,
            child: Tooltip(
              message: perm.description,
              child: Text(
                perm.action,
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11),
              ),
            ),
          ),
          ...editableRoles.map((role) {
            final hasIt = role.permissions.contains(perm.action);
            return SizedBox(
              width: colWidth,
              child: GestureDetector(
                onTap: canManage ? () => _togglePermission(role.name, perm.action) : null,
                child: Text(
                  hasIt ? 'x' : '-',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hasIt ? t.accentPrimary : t.fgDisabled,
                    fontSize: 11,
                  ),
                ),
              ),
            );
          }),
          // Superadmin column: always has everything (inherited)
          SizedBox(
            width: colWidth,
            child: Text(
              'x',
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgDisabled, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hierarchy View ──

  Widget _buildHierarchy(ShellTokens t, ThemeData theme) {
    final headStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('role hierarchy', style: headStyle),
        const SizedBox(height: 6),
        _roleRow(t, theme, 'superadmin', 'privileged', 'inherits: admin'),
        _roleRow(t, theme, 'admin', 'privileged', 'inherits: user'),
        _roleRow(t, theme, 'user', 'standard', 'inherits: guest'),
        _roleRow(t, theme, 'guest', 'safe', ''),
        const SizedBox(height: 18),
        Text('effective permission counts', style: headStyle),
        const SizedBox(height: 6),
        Text('guest: ${Permissions.guestPermissions.length} direct',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11)),
        Text(
            'user: ${Permissions.userPermissions.length} direct + ${Permissions.guestPermissions.length} inherited = ${Permissions.userPermissions.length + Permissions.guestPermissions.length}',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11)),
        Text(
            'admin: ${Permissions.adminPermissions.length} direct + ${Permissions.userPermissions.length + Permissions.guestPermissions.length} inherited = ${Permissions.adminPermissions.length + Permissions.userPermissions.length + Permissions.guestPermissions.length}',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11)),
        Text(
            'superadmin: 0 direct + ${Permissions.adminPermissions.length + Permissions.userPermissions.length + Permissions.guestPermissions.length} inherited = ${Permissions.adminPermissions.length + Permissions.userPermissions.length + Permissions.guestPermissions.length}',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11)),
      ],
    );
  }

  Widget _roleRow(ShellTokens t, ThemeData theme, String role, String tier, String note) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(role,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: role == 'superadmin' ? t.accentPrimary : t.fgPrimary,
                  fontSize: 12,
                )),
          ),
          SizedBox(
            width: 90,
            child: Text(tier, style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11)),
          ),
          Expanded(
            child: Text(note, style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ── Terminal View ──

  Widget _buildTerminal(ShellTokens t, ThemeData theme) {
    final headStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('terminal command tiers', style: headStyle),
        const SizedBox(height: 8),
        _termSection(t, theme, 'safe (guest+)', const [
          'status', 'health', 'models',
          'skills list', 'skills list --json',
          'crons list', 'crons list --json',
          'cron list', 'cron list --json',
        ]),
        const SizedBox(height: 10),
        _termSection(t, theme, 'standard (user+)', const [
          'doctor', 'skills', 'cron', 'clawhub',
          'sessions list', 'logs', 'channels',
          'tools', 'memory', 'config get', 'config validate',
        ]),
        const SizedBox(height: 10),
        _termSection(t, theme, 'privileged (admin+)', const [
          'doctor --fix', 'configure', 'onboard',
          'dashboard', 'config set',
        ]),
        const SizedBox(height: 18),
        Text('matching algorithm', style: headStyle),
        const SizedBox(height: 4),
        Text(
          'most-specific prefix match wins. e.g. "doctor --fix" matches privileged "doctor --fix" over standard "doctor".',
          style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11),
        ),
      ],
    );
  }

  Widget _termSection(ShellTokens t, ThemeData theme, String label, List<String> commands) {
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11);
    final cmdStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 3),
        Wrap(
          spacing: 16,
          runSpacing: 2,
          children: commands.map((c) => Text(c, style: cmdStyle)).toList(),
        ),
      ],
    );
  }
}

class _RolePerms {
  final String name;
  final Set<String> permissions;
  _RolePerms({required this.name, required this.permissions});
}

class _PermInfo {
  final String action;
  final String description;
  _PermInfo({required this.action, required this.description});
}
