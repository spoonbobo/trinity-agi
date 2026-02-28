import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/auth_client.dart';
import '../../core/toast_provider.dart';
import '../../main.dart' show authClientProvider;

/// User management tab: list users, view roles, assign roles.
class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  String? _updatingUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = ref.read(authClientProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await auth.fetchUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load users: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assignRole(String userId, String newRole) async {
    final auth = ref.read(authClientProvider);
    setState(() {
      _updatingUserId = userId;
      _error = null;
    });

    try {
      await auth.assignUserRole(userId, newRole);
      if (!mounted) return;
      ToastService.showInfo(context, 'role updated to $newRole');
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = 'failed to assign role: $e';
      ToastService.showError(context, msg);
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _updatingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final currentUserId = ref.read(authClientProvider).state.userId;

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
                'users (${_users.length})',
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: _buildHeaderRow(t, theme),
        ),
        // User rows
        Expanded(
          child: _users.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _error != null ? '' : 'no users',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _users.length,
                  itemBuilder: (context, index) =>
                      _buildUserRow(_users[index], t, theme, currentUserId),
                ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(ShellTokens t, ThemeData theme) {
    final style = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    return Row(
      children: [
        SizedBox(width: 280, child: Text('user', style: style)),
        SizedBox(width: 110, child: Text('role', style: style)),
        SizedBox(width: 160, child: Text('granted', style: style)),
        Expanded(child: Text('actions', style: style)),
      ],
    );
  }

  Widget _buildUserRow(
    Map<String, dynamic> user,
    ShellTokens t,
    ThemeData theme,
    String? currentUserId,
  ) {
    final userId = (user['user_id'] ?? user['id'] ?? '-').toString();
    final email = (user['email'] ?? '').toString();
    final role = (user['role_name'] ?? user['role'] ?? '-').toString();
    final granted = (user['granted_at'] ?? '-').toString();
    final isCurrentUser = userId == currentUserId;
    final isSuperadmin = role == 'superadmin';
    final isUpdating = _updatingUserId == userId;

    final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final displayUser = email.isNotEmpty ? email : (userId.length > 28 ? '${userId.substring(0, 28)}...' : userId);

    // Available roles for assignment (cannot assign superadmin via UI)
    const assignableRoles = ['guest', 'user', 'admin'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: Row(
              children: [
                Flexible(child: Text(displayUser, style: cellStyle, overflow: TextOverflow.ellipsis)),
                if (isCurrentUser) ...[
                  const SizedBox(width: 6),
                  Text('(you)', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 9)),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              role,
              style: cellStyle?.copyWith(
                color: isSuperadmin ? t.accentPrimary : t.fgPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              _formatTimestamp(granted),
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: isUpdating
                ? Text('updating...', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary))
                : (isSuperadmin || isCurrentUser)
                    ? Text(
                        isSuperadmin ? 'protected' : '',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.fgDisabled, fontSize: 10),
                      )
                    : Wrap(
                        spacing: 10,
                        children: assignableRoles
                            .where((r) => r != role)
                            .map((r) => GestureDetector(
                                  onTap: () => _assignRole(userId, r),
                                  child: Text(
                                    r,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: t.accentPrimary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
          ),
        ],
      ),
    );
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
