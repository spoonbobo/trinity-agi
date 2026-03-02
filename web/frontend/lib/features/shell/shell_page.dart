import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/gateway_client.dart' as gw;
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../models/ws_frame.dart';
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
import '../sessions/session_drawer.dart';
import '../command_palette/command_palette.dart';
import '../notifications/notification_center.dart';
import '../../core/dialog_service.dart';

const _canvasSplitKey = 'trinity_canvas_split';
const _defaultCanvasFlex = 7.0;
const _canvasMinFlex = 1.0;
const _canvasMaxFlex = 8.0;

/// Responsive breakpoints.
const _mobileBreakpoint = 600.0;
const _tabletBreakpoint = 1024.0;

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  bool _showGovernance = false;
  bool _showSessionDrawer = false;
  bool _showNotifications = false;
  bool _draggingOver = false;
  StreamSubscription<WsEvent>? _approvalSub;
  StreamSubscription<WsEvent>? _notifSub;
  StreamSubscription? _dragEnterSub;
  StreamSubscription? _dragOverSub;
  StreamSubscription? _dragLeaveSub;
  StreamSubscription? _dropSub;
  double _canvasFlex = _defaultCanvasFlex;
  bool _dividerHovered = false;
  // Mobile: which panel is visible (0=chat, 1=canvas)
  int _mobilePanel = 0;

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
    // Register global Ctrl+K handler so it works even when prompt bar has focus
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    // Register drag-and-drop on the document body
    _dragEnterSub = html.document.body?.onDragEnter.listen((e) {
      e.preventDefault();
      if (mounted && !_draggingOver) setState(() => _draggingOver = true);
    });
    _dragOverSub = html.document.body?.onDragOver.listen((e) {
      e.preventDefault(); // Required to allow drop
    });
    _dragLeaveSub = html.document.body?.onDragLeave.listen((e) {
      // Only dismiss when leaving the document body (not child elements)
      if (e.relatedTarget == null && mounted) {
        setState(() => _draggingOver = false);
      }
    });
    _dropSub = html.document.body?.onDrop.listen((e) {
      e.preventDefault();
      e.stopImmediatePropagation(); // Prevent duplicate dispatch in Flutter Web
      if (mounted) setState(() => _draggingOver = false);
      final files = e.dataTransfer.files;
      if (files == null || files.isEmpty) return;
      final promptBarState = PromptBar.globalKey.currentState;
      if (promptBarState != null) {
        promptBarState.addDroppedFiles(List<html.File>.from(files));
      }
    });
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
      // Feed approval events into notification center
      final notifs = ref.read(notificationProvider);
      _notifSub = client.approvalEvents.listen((event) {
        notifs.processEvent(event);
      });
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _approvalSub?.cancel();
    _notifSub?.cancel();
    _dragEnterSub?.cancel();
    _dragOverSub?.cancel();
    _dragLeaveSub?.cancel();
    _dropSub?.cancel();
    super.dispose();
  }

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
                   HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyK) {
      _openCommandPalette();
      return true;
    }
    return false;
  }

  final _dialogs = DialogService.instance;

  void _showSkillsDialog() {
    _dialogs.showUnique(context: context, id: 'skills',
      builder: (_) => const SkillsDialog());
  }

  void _showMemoryDialog() {
    _dialogs.showUnique(context: context, id: 'memory',
      builder: (_) => const MemoryDialog());
  }

  void _showAutomationsDialog() {
    _dialogs.showUnique(context: context, id: 'automations',
      builder: (_) => const AutomationsDialog());
  }

  void _showSettingsDialog() {
    _dialogs.showUnique(context: context, id: 'settings',
      builder: (_) => const SettingsDialog());
  }

  void _showAdminDialog() {
    _dialogs.showUnique(context: context, id: 'admin',
      builder: (_) => const AdminDialog());
  }

  void _toggleSessionDrawer() {
    setState(() => _showSessionDrawer = !_showSessionDrawer);
  }

  void _toggleNotifications() {
    setState(() => _showNotifications = !_showNotifications);
  }

  // (A) Persist split ratio to localStorage
  void _persistSplit() {
    html.window.localStorage[_canvasSplitKey] = _canvasFlex.toStringAsFixed(2);
  }

  // Command palette
  void _openCommandPalette() {
    final language = ref.read(languageProvider);
    final authState = ref.read(authClientProvider).state;
    final isAdmin = authState.hasPermission('users.list');

    final commands = <CommandItem>[
      CommandItem(
        label: tr(language, 'new_session'),
        icon: Icons.add,
        action: () {
          _toggleSessionDrawer();
        },
        category: 'sessions',
      ),
      CommandItem(
        label: tr(language, 'sessions_label'),
        icon: Icons.forum,
        action: _toggleSessionDrawer,
        category: 'sessions',
      ),
      CommandItem(
        label: tr(language, 'memory'),
        icon: Icons.psychology,
        action: _showMemoryDialog,
        category: 'navigation',
      ),
      CommandItem(
        label: tr(language, 'skills'),
        icon: Icons.extension,
        action: _showSkillsDialog,
        category: 'navigation',
      ),
      CommandItem(
        label: tr(language, 'automations'),
        icon: Icons.schedule,
        action: _showAutomationsDialog,
        category: 'navigation',
      ),
      CommandItem(
        label: tr(language, 'settings'),
        icon: Icons.settings,
        action: _showSettingsDialog,
        category: 'navigation',
      ),
      if (isAdmin)
        CommandItem(
          label: tr(language, 'admin'),
          icon: Icons.admin_panel_settings,
          action: _showAdminDialog,
          category: 'navigation',
        ),
      CommandItem(
        label: tr(language, 'notifications'),
        icon: Icons.notifications,
        action: _toggleNotifications,
        category: 'navigation',
      ),
      CommandItem(
        label: 'Toggle Theme',
        description: 'dark / light / system',
        icon: Icons.brightness_6,
        action: () {
          _showSettingsDialog();
        },
        category: 'settings',
      ),
    ];

    _dialogs.showUnique(
      context: context,
      id: 'command-palette',
      barrierColor: Colors.black54,
      builder: (_) => CommandPalette(commands: commands),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(gatewayClientProvider);
    final isConnected = client.state == gw.ConnectionState.connected;
    final t = ShellTokens.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < _mobileBreakpoint;
    final isTablet = screenWidth >= _mobileBreakpoint && screenWidth < _tabletBreakpoint;

    // FIX: Both panels use dynamic flex derived from _canvasFlex
    final chatFlex = ((10 - _canvasFlex) * 100).round();
    final canvasFlex = (_canvasFlex * 100).round();

    return Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                _buildStatusBar(client.state, t, isMobile),
                // Mobile tab bar
                if (isMobile)
                  _buildMobileTabBar(t),
                Expanded(
                  child: Row(
                    children: [
                      // Session drawer (left side, not shown on mobile via overlay)
                      if (_showSessionDrawer && !isMobile)
                        SessionDrawer(
                          onClose: () => setState(() => _showSessionDrawer = false),
                          onSessionChanged: () => setState(() {}),
                        ),
                      // Main content
                      if (isMobile)
                        // Mobile: show one panel at a time
                        Expanded(
                          child: _mobilePanel == 0
                              ? const ChatStreamView()
                              : const A2UIRendererPanel(),
                        )
                      else ...[
                        Expanded(
                          flex: chatFlex,
                          child: const ChatStreamView(),
                        ),
                        // Draggable divider
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
                            onDoubleTap: () {
                              setState(() => _canvasFlex = _defaultCanvasFlex);
                              _persistSplit();
                            },
                            child: Container(
                              width: 6,
                              color: Colors.transparent,
                              child: Center(
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
                    ],
                  ),
                ),
                PromptBar(
                  key: PromptBar.globalKey,
                  enabled: isConnected &&
                      ref.read(authClientProvider).state.hasPermission('chat.send'),
                ),
              ],
            ),
            // Notification dropdown overlay
            if (_showNotifications)
              Positioned(
                top: 28,
                right: 12,
                child: TapRegion(
                  onTapOutside: (_) => setState(() => _showNotifications = false),
                  child: const NotificationCenter(),
                ),
              ),
            // Mobile session drawer overlay
            if (_showSessionDrawer && isMobile) ...[
              GestureDetector(
                onTap: () => setState(() => _showSessionDrawer = false),
                child: Container(color: Colors.black54),
              ),
              Positioned(
                top: 0, bottom: 0, left: 0,
                child: SessionDrawer(
                  onClose: () => setState(() => _showSessionDrawer = false),
                  onSessionChanged: () => setState(() {}),
                ),
              ),
            ],
            // Drag-and-drop border indicator (non-destructive overlay)
            if (_draggingOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: t.accentPrimary.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
    );
  }

  Widget _buildMobileTabBar(ShellTokens t) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mobilePanel = 0),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: _mobilePanel == 0
                      ? Border(bottom: BorderSide(color: t.accentPrimary, width: 1))
                      : null,
                ),
                child: Text('chat',
                  style: TextStyle(
                    fontSize: 10,
                    color: _mobilePanel == 0 ? t.accentPrimary : t.fgMuted,
                  )),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _mobilePanel = 1),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: _mobilePanel == 1
                      ? Border(bottom: BorderSide(color: t.accentPrimary, width: 1))
                      : null,
                ),
                child: Text('canvas',
                  style: TextStyle(
                    fontSize: 10,
                    color: _mobilePanel == 1 ? t.accentPrimary : t.fgMuted,
                  )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(gw.ConnectionState state, ShellTokens t, bool isMobile) {
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
    final unreadCount = ref.watch(notificationProvider).unreadCount;
    final activeSession = ref.watch(activeSessionProvider);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Session drawer toggle
          GestureDetector(
            onTap: _toggleSessionDrawer,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined, size: 12, color: t.fgMuted),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          Tooltip(
            message: dotLabel,
            child: Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          // Active session indicator (always visible)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: kShellBorderRadiusSm,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Text(activeSession,
                style: TextStyle(fontSize: 8, color: t.accentPrimary),
                overflow: TextOverflow.ellipsis),
            ),
          ),
          if (!isMobile) ...[
            _HoverLabel(text: tr(language, 'memory'), style: labelStyle!, onTap: _showMemoryDialog),
          ],
          const Spacer(),
          if (!isMobile) ...[
            _HoverLabel(text: tr(language, 'skills'), style: labelStyle!, onTap: _showSkillsDialog),
            const SizedBox(width: 14),
            _HoverLabel(text: tr(language, 'automations'), style: labelStyle!, onTap: _showAutomationsDialog),
            if (isAdmin) ...[
              const SizedBox(width: 14),
              _HoverLabel(text: tr(language, 'admin'), style: labelStyle!, onTap: _showAdminDialog),
            ],
            const SizedBox(width: 14),
            _HoverLabel(text: tr(language, 'settings'), style: labelStyle!, onTap: _showSettingsDialog),
            const SizedBox(width: 14),
          ],
          // Notification bell
          GestureDetector(
            onTap: _toggleNotifications,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Stack(
                children: [
                  Icon(Icons.notifications_none, size: 14, color: t.fgMuted),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0, top: 0,
                      child: Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: t.statusError,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 10),
            // Command palette hint
            GestureDetector(
              onTap: _openCommandPalette,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: kShellBorderRadiusSm,
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Text('ctrl+k',
                    style: TextStyle(fontSize: 8, color: t.fgDisabled)),
                ),
              ),
            ),
          ],
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
