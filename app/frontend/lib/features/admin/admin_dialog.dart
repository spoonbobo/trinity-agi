import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/auth_client.dart';
import '../../main.dart' show languageProvider, authClientProvider;
import 'admin_users_tab.dart';
import 'admin_audit_tab.dart';
import 'admin_health_tab.dart';
import 'admin_rbac_tab.dart';
import 'admin_sessions_tab.dart';
import 'admin_openclaws_tab.dart';

enum AdminTab { users, audit, health, rbac, sessions, openclaws }

class AdminDialog extends ConsumerStatefulWidget {
  final AdminTab initialTab;

  const AdminDialog({super.key, this.initialTab = AdminTab.users});

  @override
  ConsumerState<AdminDialog> createState() => _AdminDialogState();
}

class _AdminDialogState extends ConsumerState<AdminDialog> {
  late AdminTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final language = ref.watch(languageProvider);
    final authState = ref.watch(authClientProvider).state;
    final isSuperadmin = authState.role == AuthRole.superadmin;

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.86,
        height: MediaQuery.of(context).size.height * 0.84,
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 780),
        child: Column(
          children: [
            // Tab bar header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  _tabToggle(tr(language, 'users'), AdminTab.users),
                  const SizedBox(width: 12),
                  _tabToggle(tr(language, 'audit'), AdminTab.audit),
                  const SizedBox(width: 12),
                  _tabToggle(tr(language, 'health'), AdminTab.health),
                  const SizedBox(width: 12),
                  _tabToggle(tr(language, 'rbac'), AdminTab.rbac),
                  const SizedBox(width: 12),
                  _tabToggle(tr(language, 'sessions'), AdminTab.sessions),
                  if (isSuperadmin) ...[
                    const SizedBox(width: 12),
                    _tabToggle('openclaws', AdminTab.openclaws),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(
                      tr(language, 'close'),
                      style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                    ),
                  ),
                ],
              ),
            ),
            // Tab content
            Expanded(child: _buildTabContent()),
          ],
        ),
      ),
    );
  }

  Widget _tabToggle(String label, AdminTab tab) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: _tab == tab ? t.accentPrimary : t.fgMuted,
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case AdminTab.users:
        return const AdminUsersTab();
      case AdminTab.audit:
        return const AdminAuditTab();
      case AdminTab.health:
        return const AdminHealthTab();
      case AdminTab.rbac:
        return const AdminRbacTab();
      case AdminTab.sessions:
        return const AdminSessionsTab();
      case AdminTab.openclaws:
        return const AdminOpenClawsTab();
    }
  }
}
