import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/gateway_client.dart' as gw;
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../models/ws_frame.dart';
import '../../core/auth_client.dart';
import '../../main.dart' show languageProvider, authClientProvider;
import '../prompt_bar/prompt_bar.dart';
import '../chat/chat_stream.dart';
import '../canvas/a2ui_renderer.dart';
import '../governance/approval_panel.dart';
import '../catalog/skills_cron_dialog.dart';
import '../memory/memory_dialog.dart';
import '../settings/settings_dialog.dart';
import '../admin/admin_dialog.dart';

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  bool _showGovernance = false;
  StreamSubscription<WsEvent>? _approvalSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = ref.read(gatewayClientProvider);
      client.connect().catchError((e) {
        debugPrint('[Shell] connect failed: $e');
      });
      _approvalSub = client.approvalEvents.listen((_) {
        if (!_showGovernance && mounted) {
          setState(() => _showGovernance = true);
        }
      });
    });
  }

  @override
  void dispose() {
    _approvalSub?.cancel();
    super.dispose();
  }

  void _showSkillsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SkillsCronDialog(initialTab: CatalogTab.skills),
    );
  }

  void _showMemoryDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const MemoryDialog(),
    );
  }

  void _showCronsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SkillsCronDialog(initialTab: CatalogTab.crons),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SettingsDialog(),
    );
  }

  void _showAdminDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AdminDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(gatewayClientProvider);
    final isConnected = client.state == gw.ConnectionState.connected;
    final t = ShellTokens.of(context);

    return Scaffold(
      body: Column(
        children: [
          _buildStatusBar(client.state, t),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: const ChatStreamView(),
                ),
                Expanded(
                  flex: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: t.border, width: 0.5),
                      ),
                    ),
                    child: const A2UIRendererPanel(),
                  ),
                ),
                if (_showGovernance)
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: t.border, width: 0.5),
                        ),
                      ),
                      child: ApprovalPanel(
                        onAllResolved: () {
                          if (mounted) setState(() => _showGovernance = false);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          PromptBar(
            enabled: isConnected &&
                ref.read(authClientProvider).state.hasPermission('chat.send'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(gw.ConnectionState state, ShellTokens t) {
    final dotColor = switch (state) {
      gw.ConnectionState.connected => t.accentPrimary,
      gw.ConnectionState.connecting => t.statusWarning,
      gw.ConnectionState.error => t.statusError,
      gw.ConnectionState.disconnected => t.fgDisabled,
    };

    final language = ref.watch(languageProvider);
    final authState = ref.watch(authClientProvider).state;
    final isAdmin = authState.hasPermission('users.list');
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: t.fgMuted);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showMemoryDialog,
            child: Text(tr(language, 'memory'), style: labelStyle),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showSkillsDialog,
            child: Text(tr(language, 'skills'), style: labelStyle),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _showCronsDialog,
            child: Text(tr(language, 'crons'), style: labelStyle),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 14),
            GestureDetector(
              onTap: _showAdminDialog,
              child: Text(tr(language, 'admin'), style: labelStyle),
            ),
          ],
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _showSettingsDialog,
            child: Text(tr(language, 'settings'), style: labelStyle),
          ),
        ],
      ),
    );
  }
}
