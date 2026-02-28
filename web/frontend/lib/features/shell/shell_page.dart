import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/gateway_client.dart' as gw;
import '../../core/auth.dart';
import '../../core/terminal_client.dart';
import '../../core/theme.dart';
import '../../models/ws_frame.dart';
import '../../main.dart' show themeModeProvider;
import '../prompt_bar/prompt_bar.dart';
import '../chat/chat_stream.dart';
import '../canvas/a2ui_renderer.dart';
import '../governance/approval_panel.dart';
import '../onboarding/onboarding_wizard.dart';
import '../catalog/skills_cron_dialog.dart';

final _sharedDevice = DeviceIdentity.generate();
final _sharedAuth = GatewayAuth(
  token: const String.fromEnvironment(
    'GATEWAY_TOKEN',
    defaultValue: 'replace-me-with-a-real-token',
  ),
  device: _sharedDevice,
);
const _wsUrl = String.fromEnvironment(
  'GATEWAY_WS_URL',
  defaultValue: 'ws://localhost:18789',
);
const _terminalWsUrl = String.fromEnvironment(
  'TERMINAL_WS_URL',
  defaultValue: 'ws://localhost/terminal/',
);

final gatewayClientProvider = ChangeNotifierProvider<gw.GatewayClient>((ref) {
  return gw.GatewayClient(url: _wsUrl, auth: _sharedAuth);
});

final terminalClientProvider = ChangeNotifierProvider<TerminalProxyClient>((ref) {
  return TerminalProxyClient(url: _terminalWsUrl, auth: _sharedAuth);
});

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

  void _showOnboardingDialog({OnboardingStep initialStep = OnboardingStep.welcome}) {
    final t = ShellTokens.of(context);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: t.surfaceBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: t.border, width: 0.5),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.82,
          height: MediaQuery.of(context).size.height * 0.84,
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
          child: OnboardingWizard(
            initialStep: initialStep,
            onComplete: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  void _showSkillsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SkillsCronDialog(initialTab: CatalogTab.skills),
    );
  }

  void _showCronsDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SkillsCronDialog(initialTab: CatalogTab.crons),
    );
  }

  void _cycleTheme() {
    final current = ref.read(themeModeProvider);
    final next = switch (current) {
      ThemeMode.system => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.light => ThemeMode.system,
    };
    ref.read(themeModeProvider.notifier).state = next;
    saveThemeMode(next);
  }

  String _themeModeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'sys',
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
    };
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
          PromptBar(enabled: isConnected),
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

    final themeMode = ref.watch(themeModeProvider);
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
          const Spacer(),
          GestureDetector(
            onTap: _cycleTheme,
            child: Text(_themeModeLabel(themeMode), style: labelStyle),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _showOnboardingDialog(initialStep: OnboardingStep.welcome),
            child: Text('setup', style: labelStyle),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _showSkillsDialog,
            child: Text('skills', style: labelStyle),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _showCronsDialog,
            child: Text('crons', style: labelStyle),
          ),
        ],
      ),
    );
  }
}
