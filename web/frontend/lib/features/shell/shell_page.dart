import 'dart:async';
import 'dart:html' as html;
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
import '../automations/automations_dialog.dart';
import '../memory/memory_dialog.dart';
import '../settings/settings_dialog.dart';
import '../admin/admin_dialog.dart';

const _canvasSplitKey = 'trinity_canvas_split';
const _defaultCanvasFlex = 4.0;
const _canvasMinFlex = 1.0;
const _canvasMaxFlex = 8.0;

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  bool _showGovernance = false;
  StreamSubscription<WsEvent>? _approvalSub;
  double _canvasFlex = _defaultCanvasFlex;
  bool _dividerHovered = false;

  @override
  void initState() {
    super.initState();
    // (A) Restore persisted split ratio from localStorage
    final stored = html.window.localStorage[_canvasSplitKey];
    if (stored != null) {
      final parsed = double.tryParse(stored);
      if (parsed != null) {
        _canvasFlex = parsed.clamp(_canvasMinFlex, _canvasMaxFlex);
      }
    }
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
    showDialog(context: context, barrierDismissible: true,
      builder: (context) => const SkillsDialog());
  }

  void _showMemoryDialog() {
    showDialog(context: context, barrierDismissible: true,
      builder: (context) => const MemoryDialog());
  }

  void _showAutomationsDialog() {
    showDialog(context: context, barrierDismissible: true,
      builder: (context) => const AutomationsDialog());
  }

  void _showSettingsDialog() {
    showDialog(context: context, barrierDismissible: true,
      builder: (context) => const SettingsDialog());
  }

  void _showAdminDialog() {
    showDialog(context: context, barrierDismissible: true,
      builder: (context) => const AdminDialog());
  }

  // (A) Persist split ratio to localStorage
  void _persistSplit() {
    html.window.localStorage[_canvasSplitKey] = _canvasFlex.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(gatewayClientProvider);
    final isConnected = client.state == gw.ConnectionState.connected;
    final t = ShellTokens.of(context);

    // FIX: Both panels use dynamic flex derived from _canvasFlex
    final chatFlex = ((10 - _canvasFlex) * 100).round();
    final canvasFlex = (_canvasFlex * 100).round();

    return Scaffold(
      body: Column(
        children: [
          _buildStatusBar(client.state, t),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: chatFlex,
                  child: const ChatStreamView(),
                ),
                // Draggable divider: hover highlight (E) + double-click reset (B)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  onEnter: (_) => setState(() => _dividerHovered = true),
                  onExit: (_) => setState(() => _dividerHovered = false),
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final renderBox = context.findRenderObject() as RenderBox;
                      final totalWidth = renderBox.size.width;
                      final deltaFlex = (details.delta.dx / totalWidth) * 10;
                      setState(() {
                        _canvasFlex = (_canvasFlex - deltaFlex)
                            .clamp(_canvasMinFlex, _canvasMaxFlex);
                      });
                    },
                    onHorizontalDragEnd: (_) => _persistSplit(),
                    // (B) Double-click resets to default 60/40
                    onDoubleTap: () {
                      setState(() => _canvasFlex = _defaultCanvasFlex);
                      _persistSplit();
                    },
                    child: Container(
                      width: 6,
                      color: Colors.transparent,
                      child: Center(
                        // (E) Hover highlight: 2px mint on hover, 1px border normally
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: _dividerHovered ? 2 : 1,
                          color: _dividerHovered
                              ? t.accentPrimary.withOpacity(0.5)
                              : t.border,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: canvasFlex,
                  child: const A2UIRendererPanel(),
                ),
                if (_showGovernance)
                  Expanded(
                    flex: canvasFlex,
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
    final dotLabel = switch (state) {
      gw.ConnectionState.connected => 'connected',
      gw.ConnectionState.connecting => 'connecting...',
      gw.ConnectionState.error => 'connection error',
      gw.ConnectionState.disconnected => 'disconnected',
    };

    final language = ref.watch(languageProvider);
    final authState = ref.watch(authClientProvider).state;
    final isAdmin = authState.hasPermission('users.list');
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: t.fgMuted);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: dotLabel,
            child: Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          _HoverLabel(text: tr(language, 'memory'), style: labelStyle!, onTap: _showMemoryDialog),
          const Spacer(),
          _HoverLabel(text: tr(language, 'skills'), style: labelStyle, onTap: _showSkillsDialog),
          const SizedBox(width: 14),
          _HoverLabel(text: tr(language, 'automations'), style: labelStyle, onTap: _showAutomationsDialog),
          if (isAdmin) ...[
            const SizedBox(width: 14),
            _HoverLabel(text: tr(language, 'admin'), style: labelStyle, onTap: _showAdminDialog),
          ],
          const SizedBox(width: 14),
          _HoverLabel(text: tr(language, 'settings'), style: labelStyle, onTap: _showSettingsDialog),
        ],
      ),
    );
  }
}

class _HoverLabel extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback onTap;

  const _HoverLabel({required this.text, required this.style, required this.onTap});

  @override
  State<_HoverLabel> createState() => _HoverLabelState();
}

class _HoverLabelState extends State<_HoverLabel> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Opacity(
          opacity: _hovering ? 1.0 : 0.7,
          child: Text(widget.text, style: widget.style),
        ),
      ),
    );
  }
}
