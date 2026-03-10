import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/gateway_client.dart' as gw;
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/auth_client.dart'
    show AuthRole, OpenClawInfo, OpenClawStatus, roleToString;
import '../../core/providers.dart';
import '../../core/terminal_client.dart' show TerminalConnectionState;
import '../../core/toast_provider.dart';
import '../../models/ws_frame.dart';
import '../../main.dart' show languageProvider, authClientProvider;
import '../prompt_bar/prompt_bar.dart';
import '../chat/chat_stream.dart';
import '../canvas/canvas_panel.dart';
import '../canvas/canvas_mode_provider.dart';
import '../governance/approval_panel.dart';
import '../catalog/skills_cron_dialog.dart';
import '../automations/automations_dialog.dart';

import '../settings/settings_dialog.dart';
import '../admin/admin_dialog.dart';
import '../admin/admin_copilot_tab.dart';
import '../admin/admin_channels_tab.dart';
import '../sessions/session_drawer.dart';
import '../command_palette/command_palette.dart';
import '../notifications/notification_center.dart';
import '../../core/dialog_service.dart';
import 'agent_workspace_dialog.dart';

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
  StreamSubscription? _domKeyDownSub;
  StreamSubscription? _domClickSub;
  double _canvasFlex = _defaultCanvasFlex;
  bool _dividerHovered = false;
  // Mobile: which panel is visible (0=chat, 1=canvas)
  int _mobilePanel = 0;
  // Track previous gateway state for reconnect toasts
  gw.ConnectionState? _prevGatewayState;
  TerminalConnectionState? _prevTerminalState;
  String? _lastObservedOpenClawId;
  bool _switchInProgress = false;
  String? _switchTargetName;

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
    // Register DOM-level keydown to catch Escape even when iframe is focused
    _domKeyDownSub = html.window.onKeyDown.listen(_handleDomKeyDown);
    // Auto-blur DrawIO iframe when clicking outside canvas
    _domClickSub = html.window.onClick.listen(_handleDomClick);
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
      final authClient = ref.read(authClientProvider);
      final client = ref.read(gatewayClientProvider);
      final terminalClient = ref.read(terminalClientProvider);
      // Track connection state changes for reconnect toasts
      _prevGatewayState = client.state;
      _prevTerminalState = terminalClient.state;
      _lastObservedOpenClawId = authClient.state.activeOpenClawId;
      client.addListener(_onGatewayStateChange);
      terminalClient.addListener(_onTerminalStateChange);
      // Listen for OpenClaw status changes (e.g. user gets unassigned)
      authClient.addListener(_onAuthStateChange);
      _syncOpenClawRouting();
      _connectActiveOpenClaw();
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

  void _syncOpenClawRouting() {
    final authClient = ref.read(authClientProvider);
    final activeId = authClient.state.activeOpenClawId;
    final gwClient = ref.read(gatewayClientProvider);
    final terminalClient = ref.read(terminalClientProvider);
    gwClient.setOpenClawId(activeId);
    terminalClient
      ..setOpenClawId(activeId)
      ..updateRole(roleToString(authClient.state.role));
  }

  void _connectActiveOpenClaw({bool showFeedback = false}) {
    final authClient = ref.read(authClientProvider);
    final gwClient = ref.read(gatewayClientProvider);
    final terminalClient = ref.read(terminalClientProvider);

    _syncOpenClawRouting();

    switch (authClient.openClawStatus) {
      case OpenClawStatus.loading:
      case OpenClawStatus.unknown:
        if (showFeedback && mounted) {
          ToastService.showInfo(context, 'loading openclaws...');
        }
        return;
      case OpenClawStatus.noOpenClaws:
        if (showFeedback && mounted) {
          ToastService.showError(context, 'no openclaw assigned');
        }
        return;
      case OpenClawStatus.error:
        if (showFeedback && mounted) {
          ToastService.showError(
            context,
            authClient.openClawError ?? 'failed to load openclaws',
          );
        }
        return;
      case OpenClawStatus.ready:
        break;
    }

    if (authClient.state.activeOpenClaw == null) {
      if (showFeedback && mounted) {
        ToastService.showError(context, 'no active openclaw selected');
      }
      return;
    }

    if (gwClient.state != gw.ConnectionState.connected &&
        gwClient.state != gw.ConnectionState.connecting) {
      gwClient.connect().catchError((e) {
        debugPrint('[Shell] gateway connect failed: $e');
      });
    }

    if (terminalClient.state != TerminalConnectionState.connected &&
        terminalClient.state != TerminalConnectionState.connecting) {
      terminalClient.connect().catchError((e) {
        debugPrint('[Shell] terminal connect failed: $e');
      });
    }
  }

  void _onAuthStateChange() {
    final authClient = ref.read(authClientProvider);
    final gwClient = ref.read(gatewayClientProvider);
    final terminalClient = ref.read(terminalClientProvider);
    final nextOpenClawId = authClient.state.activeOpenClawId;
    final openClawChanged =
        _lastObservedOpenClawId != null &&
        nextOpenClawId != null &&
        _lastObservedOpenClawId != nextOpenClawId;
    _lastObservedOpenClawId = nextOpenClawId;

    if (authClient.openClawStatus == OpenClawStatus.noOpenClaws) {
      // User lost all assignments -- disconnect
      gwClient.disconnect();
      terminalClient.disconnect();
      _switchInProgress = false;
      _switchTargetName = null;
      _syncOpenClawRouting();
      return;
    }

    _syncOpenClawRouting();

    if (authClient.openClawStatus == OpenClawStatus.ready) {
      if (openClawChanged) {
        _switchInProgress = true;
        _switchTargetName = authClient.state.activeOpenClaw?.name ?? 'openclaw';
        ToastService.showInfo(context, 'switching to ${_switchTargetName!}...');
        gwClient.disconnect();
        terminalClient.disconnect();
      }
      final needsReconnect =
          gwClient.state == gw.ConnectionState.disconnected ||
          gwClient.state == gw.ConnectionState.error ||
          terminalClient.state == TerminalConnectionState.disconnected ||
          terminalClient.state == TerminalConnectionState.error;
      if (needsReconnect) {
        _connectActiveOpenClaw();
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _domKeyDownSub?.cancel();
    _domClickSub?.cancel();
    ref.read(authClientProvider).removeListener(_onAuthStateChange);
    ref.read(gatewayClientProvider).removeListener(_onGatewayStateChange);
    ref.read(terminalClientProvider).removeListener(_onTerminalStateChange);
    _approvalSub?.cancel();
    _notifSub?.cancel();
    _dragEnterSub?.cancel();
    _dragOverSub?.cancel();
    _dragLeaveSub?.cancel();
    _dropSub?.cancel();
    super.dispose();
  }

  void _onGatewayStateChange() {
    if (!mounted) return;
    final gwClient = ref.read(gatewayClientProvider);
    final current = gwClient.state;
    final prev = _prevGatewayState;
    _prevGatewayState = current;

    if ((current == gw.ConnectionState.disconnected || current == gw.ConnectionState.error) &&
        prev == gw.ConnectionState.connected &&
        !_switchInProgress) {
      ToastService.showError(context, 'gateway disconnected, reconnecting...');
    }

    if (current == gw.ConnectionState.connected &&
        (prev == gw.ConnectionState.disconnected || prev == gw.ConnectionState.error) &&
        !_switchInProgress) {
      ToastService.showInfo(context, 'gateway reconnected');
    }

    _maybeShowSwitchConnectionToast();
  }

  void _onTerminalStateChange() {
    if (!mounted) return;
    final terminalClient = ref.read(terminalClientProvider);
    final current = terminalClient.state;
    final prev = _prevTerminalState;
    _prevTerminalState = current;

    if ((current == TerminalConnectionState.disconnected ||
            current == TerminalConnectionState.error) &&
        prev == TerminalConnectionState.connected &&
        !_switchInProgress) {
      ToastService.showError(context, 'terminal disconnected');
    }

    _maybeShowSwitchConnectionToast();
  }

  void _maybeShowSwitchConnectionToast() {
    if (!_switchInProgress || !mounted) return;
    final gwState = ref.read(gatewayClientProvider).state;
    final terminalState = ref.read(terminalClientProvider).state;
    final target = _switchTargetName ??
        ref.read(authClientProvider).state.activeOpenClaw?.name ??
        'openclaw';

    if (gwState == gw.ConnectionState.connected &&
        terminalState == TerminalConnectionState.connected) {
      ToastService.showInfo(context, 'connected to $target');
      _switchInProgress = false;
      _switchTargetName = null;
      return;
    }

    if (gwState == gw.ConnectionState.error ||
        terminalState == TerminalConnectionState.error) {
      ToastService.showError(context, 'failed to connect to $target');
      _switchInProgress = false;
      _switchTargetName = null;
    }
  }

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Escape: blur DrawIO iframe to return focus to app
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final canvasMode = ref.read(canvasModeProvider);
      if (canvasMode == CanvasMode.drawio) {
        CanvasPanel.drawioKey.currentState?.blur();
        return true;
      }
      // Browser mode: Escape is a no-op at the shell level
      // (URL bar handles its own Escape)
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
                   HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyK) {
      _openCommandPalette();
      return true;
    }
    return false;
  }

  void _handleDomKeyDown(html.KeyboardEvent event) {
    // DOM-level handler catches key events even when iframe is focused
    if (event.keyCode == 27) { // Escape
      final canvasMode = ref.read(canvasModeProvider);
      if (canvasMode == CanvasMode.drawio) {
        CanvasPanel.drawioKey.currentState?.blur();
      }
      // Browser mode: no iframe to blur
    }
  }

  void _handleDomClick(html.MouseEvent event) {
    final canvasMode = ref.read(canvasModeProvider);
    if (canvasMode == CanvasMode.drawio) {
      CanvasPanel.drawioKey.currentState?.blur();
    }
    // Browser mode: no iframe to blur
  }

  final _dialogs = DialogService.instance;

  void _showSkillsDialog() {
    _dialogs.showUnique(context: context, id: 'skills',
      builder: (_) => const SkillsDialog());
  }

  void _showAgentWorkspaceDialog() {
    _dialogs.showUnique(context: context, id: 'agent-workspace',
      builder: (_) => const AgentWorkspaceDialog());
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

  void _showChannelsDialog() {
    final t = ShellTokens.of(context);
    _dialogs.showUnique(
      context: context,
      id: 'channels',
      builder: (_) => Dialog(
        backgroundColor: t.surfaceBase,
        shape: RoundedRectangleBorder(
          borderRadius: kShellBorderRadius,
          side: BorderSide(color: t.border, width: 0.5),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.86,
          height: MediaQuery.of(context).size.height * 0.84,
          constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 780),
          child: const AdminChannelsTab(),
        ),
      ),
    );
  }

  void _showCopilotDialog() {
    final t = ShellTokens.of(context);
    _dialogs.showUnique(
      context: context,
      id: 'copilot',
      builder: (_) => Dialog(
        backgroundColor: t.surfaceBase,
        shape: RoundedRectangleBorder(
          borderRadius: kShellBorderRadius,
          side: BorderSide(color: t.border, width: 0.5),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          height: MediaQuery.of(context).size.height * 0.84,
          constraints: const BoxConstraints(maxWidth: 1240, maxHeight: 820),
          child: const AdminCopilotTab(),
        ),
      ),
    );
  }

  void _showOpenClawSwitcher({
    required List<OpenClawInfo> openclaws,
    required String? activeId,
  }) {
    DialogService.instance.showUnique(
      context: context,
      id: 'openclaw-switcher',
      barrierColor: Colors.black54,
      builder: (_) => _OpenClawSwitcherDialog(
        openclaws: openclaws,
        activeId: activeId,
        onSelect: (id) {
          Navigator.of(context).pop();
          if (id == activeId) return;
          final gwClient = ref.read(gatewayClientProvider);
          final terminalClient = ref.read(terminalClientProvider);
          gwClient.disconnect();
          terminalClient.disconnect();
          ref.read(authClientProvider).selectOpenClaw(id);
          _syncOpenClawRouting();
          _connectActiveOpenClaw();
        },
      ),
    );
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
    final isSuperadmin = authState.role == AuthRole.superadmin;

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
      if (isSuperadmin)
        CommandItem(
          label: tr(language, 'configure'),
          icon: Icons.smart_toy,
          action: _showCopilotDialog,
          category: 'navigation',
        ),
      if (authState.hasPermission('acp.manage'))
        CommandItem(
          label: tr(language, 'agents'),
          icon: Icons.hub,
          action: _showAgentWorkspaceDialog,
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
      if (isSuperadmin)
        CommandItem(
          label: tr(language, 'channels'),
          icon: Icons.alt_route,
          action: _showChannelsDialog,
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
    final authClient = ref.watch(authClientProvider);
    final hasNoOpenClaws = authClient.openClawStatus == OpenClawStatus.noOpenClaws;

    if (authClient.openClawStatus == OpenClawStatus.ready &&
        authClient.state.activeOpenClaw != null &&
        client.state == gw.ConnectionState.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connectActiveOpenClaw();
      });
    }

    // FIX: Both panels use dynamic flex derived from _canvasFlex
    final chatFlex = ((10 - _canvasFlex) * 100).round();
    final canvasFlex = (_canvasFlex * 100).round();

    if (hasNoOpenClaws && authClient.state.role != AuthRole.superadmin) {
      return Scaffold(
        backgroundColor: t.surfaceBase,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Trinity icon (4-pointed star from favicon.svg)
              CustomPaint(
                size: const Size(48, 48),
                painter: _TrinityIconPainter(color: t.accentPrimary),
              ),
              const SizedBox(height: 16),
              Text('trinity',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: t.accentPrimary,
                )),
              const SizedBox(height: 12),
              Text('you have no team',
                style: TextStyle(fontSize: 12, color: t.fgMuted)),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () => ref.read(authClientProvider).logout(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text('logout',
                    style: TextStyle(fontSize: 10, color: t.fgDisabled)),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                              : const CanvasPanel(),
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
                          child: const CanvasPanel(),
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
    final authClient = ref.watch(authClientProvider);
    final authState = authClient.state;
    final openClawStatus = authClient.openClawStatus;
    final isAdmin = authState.hasPermission('users.list');
    final unreadCount = ref.watch(notificationProvider).unreadCount;
    final activeSession = ref.watch(activeSessionProvider);
    final activeSessionLabel = activeSession
        .replaceAll(RegExp(r'\s*\((light|dark|system)\)\s*', caseSensitive: false), '')
        .trim();
    final groupTooltip = switch (openClawStatus) {
      OpenClawStatus.loading => 'loading openclaws...',
      OpenClawStatus.unknown => 'loading openclaws...',
      OpenClawStatus.noOpenClaws => 'no openclaw assigned',
      OpenClawStatus.error => authClient.openClawError ?? 'failed to load openclaws',
      OpenClawStatus.ready => dotLabel,
    };
    final shortcutLabel =
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS)
        ? 'cmd+k'
        : 'ctrl+k';

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
        child: Row(
          children: [
            Tooltip(
              message: groupTooltip,
              child: GestureDetector(
                onTap: _toggleSessionDrawer,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: kShellBorderRadiusSm,
                      border: Border.all(
                        color: state == gw.ConnectionState.connected
                            ? t.accentPrimary.withOpacity(0.35)
                            : t.border,
                        width: 0.5,
                      ),
                      color: state == gw.ConnectionState.connected
                          ? t.accentPrimary.withOpacity(0.08)
                          : t.surfaceBase,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          activeSessionLabel.isEmpty ? 'main' : activeSessionLabel,
                          style: TextStyle(fontSize: 9, color: t.accentPrimary, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 7),
                        Icon(Icons.forum_outlined, size: 11, color: t.fgMuted),
                        const SizedBox(width: 3),
                        Icon(Icons.unfold_more, size: 8, color: t.fgMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!isMobile) ...[
              const SizedBox(width: 10),
              if (authState.openclaws.isNotEmpty) ...[
                if (authState.role == AuthRole.superadmin) ...[
                  _ConfigureWithCopilotLink(
                    clawName: authState.activeOpenClaw?.name ?? 'claw',
                    configureLabel: tr(language, 'configure'),
                    switchLabel: tr(language, 'switch'),
                    onSwitchTap: () => _showOpenClawSwitcher(
                      openclaws: authState.openclaws,
                      activeId: authState.activeOpenClawId,
                    ),
                    onTap: _showCopilotDialog,
                    t: t,
                  ),
                ] else
                  _StatusModeActionLink(
                    label: tr(language, 'switch_claw'),
                    onTap: () => _showOpenClawSwitcher(
                      openclaws: authState.openclaws,
                      activeId: authState.activeOpenClawId,
                    ),
                    t: t,
                    textColor: t.accentPrimary,
                  ),
              ],
            ],
            const Spacer(),
            if (!isMobile) ...[
              if (authState.hasPermission('acp.manage')) ...[
                _StatusModeActionLink(
                  label: tr(language, 'agents'),
                  onTap: _showAgentWorkspaceDialog,
                  t: t,
                  textColor: t.accentSecondary,
                ),
                const SizedBox(width: 8),
              ],
              _StatusModeActionLink(
                label: tr(language, 'skills'),
                onTap: _showSkillsDialog,
                t: t,
                textColor: t.accentPrimary,
              ),
              const SizedBox(width: 8),
              _StatusModeActionLink(
                label: tr(language, 'automations'),
                onTap: _showAutomationsDialog,
                t: t,
                textColor: t.statusWarning,
              ),
              if (authState.role == AuthRole.superadmin) ...[
                const SizedBox(width: 8),
                _StatusModeActionLink(
                  label: tr(language, 'channels'),
                  onTap: _showChannelsDialog,
                  t: t,
                  textColor: t.fgPrimary,
                ),
              ],
              const SizedBox(width: 10),
            if (isAdmin) ...[
              _StatusModeActionLink(
                label: tr(language, 'admin'),
                onTap: _showAdminDialog,
                t: t,
                textColor: t.fgPrimary,
              ),
            ],
            const SizedBox(width: 14),
            GestureDetector(
              onTap: _showSettingsDialog,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(Icons.settings, size: 14, color: t.fgMuted),
              ),
            ),
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
                  child: Text(shortcutLabel,
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

class _ConfigureWithCopilotLink extends StatelessWidget {
  final String clawName;
  final String configureLabel;
  final String switchLabel;
  final VoidCallback onSwitchTap;
  final VoidCallback onTap;
  final ShellTokens t;

  const _ConfigureWithCopilotLink({
    super.key,
    required this.clawName,
    required this.configureLabel,
    required this.switchLabel,
    required this.onSwitchTap,
    required this.onTap,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$configureLabel ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: t.accentPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: clawName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: t.accentSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSwitchTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switchLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.fgMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.swap_horiz, size: 12, color: t.fgMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusModeActionLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final ShellTokens t;
  final Color textColor;

  const _StatusModeActionLink({
    required this.label,
    required this.onTap,
    required this.t,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: textColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Status bar badge that opens the OpenClaw switcher dialog.
class _OpenClawSelector extends StatelessWidget {
  final List<OpenClawInfo> openclaws;
  final String? activeId;
  final TextStyle? labelStyle;
  final ShellTokens t;
  final ValueChanged<String> onSelect;

  const _OpenClawSelector({
    required this.openclaws,
    required this.activeId,
    required this.labelStyle,
    required this.t,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final active = openclaws.where((oc) => oc.id == activeId).firstOrNull;
    return GestureDetector(
      onTap: () => _showSwitcherDialog(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5, height: 5,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: (active?.ready ?? false) ? t.accentPrimary : t.fgDisabled,
                  shape: BoxShape.circle,
                ),
              ),
              Text(active?.name ?? 'select',
                style: TextStyle(fontSize: 8, color: t.accentPrimary)),
              const SizedBox(width: 2),
              Icon(Icons.unfold_more, size: 8, color: t.fgMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showSwitcherDialog(BuildContext context) {
    DialogService.instance.showUnique(
      context: context,
      id: 'openclaw-switcher',
      barrierColor: Colors.black54,
      builder: (_) => _OpenClawSwitcherDialog(
        openclaws: openclaws,
        activeId: activeId,
        onSelect: (id) {
          Navigator.of(context).pop();
          onSelect(id);
        },
      ),
    );
  }
}

/// Dialog for switching between assigned OpenClaw instances.
class _OpenClawSwitcherDialog extends StatelessWidget {
  final List<OpenClawInfo> openclaws;
  final String? activeId;
  final ValueChanged<String> onSelect;

  const _OpenClawSwitcherDialog({
    required this.openclaws,
    required this.activeId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.5,
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Text('openclaws',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.accentPrimary)),
                  const SizedBox(width: 8),
                  Text('${openclaws.length}',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('close',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
                    ),
                  ),
                ],
              ),
            ),
            // ── Column headers ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Expanded(flex: 4, child: Text('name',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 9))),
                  Expanded(flex: 3, child: Text('description',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 9))),
                  SizedBox(width: 60, child: Text('users',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 9))),
                  SizedBox(width: 60, child: Text('status',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 9))),
                ],
              ),
            ),
            // ── Instance list ──────────────────────────────────────────
            ...openclaws.map((oc) {
              final isActive = oc.id == activeId;
              return GestureDetector(
                onTap: isActive ? null : () => onSelect(oc.id),
                child: MouseRegion(
                  cursor: isActive ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? t.surfaceCard : Colors.transparent,
                      border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6, height: 6,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: oc.ready ? t.accentPrimary : t.fgDisabled,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(oc.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isActive ? t.accentPrimary : t.fgPrimary,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            oc.description ?? '',
                            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9),
                            overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 60,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_outline, size: 11, color: t.fgMuted),
                              const SizedBox(width: 2),
                              Text(
                                '${oc.userCount ?? '-'}',
                                style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            isActive ? 'active' : (oc.ready ? 'ready' : oc.status),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isActive ? t.accentPrimary : t.fgMuted,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (openclaws.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('no openclaws assigned',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Paints the Trinity 4-pointed star icon (matching favicon.svg).
class _TrinityIconPainter extends CustomPainter {
  final Color color;
  _TrinityIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final cx = size.width / 2;
    final cy = size.height / 2;
    // 4-pointed star: top, right, bottom, left with curved edges
    final path = Path()
      ..moveTo(cx, 0)
      ..cubicTo(cx, cx * 0.625, cx * 0.625, cx, 0, cy)
      ..cubicTo(cx * 0.625, cy, cx, cy + (size.height - cy) * 0.375, cx, size.height)
      ..cubicTo(cx, cy + (size.height - cy) * 0.375, cx + (size.width - cx) * 0.375, cy, size.width, cy)
      ..cubicTo(cx + (size.width - cx) * 0.375, cy, cx, cx * 0.625, cx, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrinityIconPainter old) => old.color != color;
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
