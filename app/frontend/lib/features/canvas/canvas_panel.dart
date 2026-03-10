import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../core/theme.dart';
import '../../core/dialog_service.dart';
import 'canvas_mode_provider.dart';
import 'a2ui_renderer.dart';
import 'drawio_renderer.dart';
import 'browser_renderer.dart';
import 'browser_provider.dart';

/// Unified canvas panel: A2UI | DrawIO | Browser.
/// Mode toggle and mode-specific toolbars fixed at bottom-right.
class CanvasPanel extends ConsumerStatefulWidget {
  const CanvasPanel({super.key});

  static final GlobalKey<DrawIORendererState> drawioKey = GlobalKey();

  @override
  ConsumerState<CanvasPanel> createState() => _CanvasPanelState();
}

class _CanvasPanelState extends ConsumerState<CanvasPanel> {
  void _showLoadXmlDialog() {
    DialogService.instance.showUnique(
      context: context,
      id: 'drawio-load-xml',
      builder: (_) => const _DrawIOLoadDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(canvasModeProvider);
    final modeNotifier = ref.read(canvasModeProvider.notifier);
    final drawIOTheme = ref.watch(drawIOThemeProvider);
    final drawIOThemeNotifier = ref.read(drawIOThemeProvider.notifier);
    final t = ShellTokens.of(context);

    return Stack(
      children: [
        // Renderer area
        Positioned.fill(
          child: switch (mode) {
            CanvasMode.a2ui => A2UIRendererPanel(),
            CanvasMode.drawio => ValueListenableBuilder<bool>(
                valueListenable: DialogService.instance.dialogIsOpenNotifier,
                builder: (context, dialogIsOpen, child) => DrawIORenderer(
                  key: CanvasPanel.drawioKey,
                  dialogIsOpen: dialogIsOpen,
                ),
              ),
            CanvasMode.browser => const BrowserRenderer(),
          },
        ),

        // DrawIO theme toggle – bottom-right (only in drawio mode)
        if (mode == CanvasMode.drawio)
          Positioned(
            bottom: 4,
            right: 70,
            child: PointerInterceptor(
              child: GestureDetector(
                onTap: () {
                  drawIOThemeNotifier.toggle();
                  CanvasPanel.drawioKey.currentState?.reloadWithTheme();
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: kShellBorderRadiusSm,
                      color: t.surfaceBase.withOpacity(0.95),
                      border: Border.all(color: t.border, width: 0.5),
                    ),
                    child: Icon(
                      drawIOTheme == DrawIOTheme.dark 
                          ? Icons.light_mode 
                          : Icons.dark_mode,
                      size: 12,
                      color: t.fgMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Draw.io toolbar – bottom-right above mode toggle
        if (mode == CanvasMode.drawio)
          Positioned(
            bottom: 36,
            right: 4,
            child: PointerInterceptor(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallButton(
                    icon: Icons.content_copy,
                    tooltip: 'copy image',
                    onTap: () => CanvasPanel.drawioKey.currentState?.copyPng(),
                    tokens: t,
                  ),
                  const SizedBox(width: 2),
                  _SmallButton(
                    icon: Icons.download,
                    tooltip: 'export PNG',
                    onTap: () => CanvasPanel.drawioKey.currentState?.exportPng(),
                    tokens: t,
                  ),
                  const SizedBox(width: 2),
                  _SmallTextButton(
                    label: 'save xml',
                    tooltip: 'save xml snapshot',
                    onTap: () async {
                      final state = CanvasPanel.drawioKey.currentState;
                      if (state == null) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('drawio not ready (state unavailable)'),
                            duration: Duration(milliseconds: 1600),
                          ),
                        );
                        return;
                      }

                      final ok = await state.saveXmlSnapshot();
                      if (!mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final details = state.lastSaveError ?? state.debugStatus;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'saved XML snapshot'
                              : 'unable to save XML snapshot ($details)'),
                          duration: const Duration(milliseconds: 2200),
                        ),
                      );
                    },
                    tokens: t,
                  ),
                  const SizedBox(width: 2),
                  _SmallTextButton(
                    label: 'load xml',
                    tooltip: 'load xml snapshot',
                    onTap: _showLoadXmlDialog,
                    tokens: t,
                  ),
                ],
              ),
            ),
          ),

        // Browser toolbar – bottom-right above mode toggle
        if (mode == CanvasMode.browser)
          Positioned(
            bottom: 36,
            right: 4,
            child: PointerInterceptor(
              child: Consumer(
                builder: (context, ref, _) {
                  final browserState = ref.watch(browserProvider);
                  final browserNotifier = ref.read(browserProvider.notifier);
                  if (browserState.runState != BrowserRunState.running) {
                    return const SizedBox.shrink();
                  }
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SmallButton(
                        icon: Icons.refresh,
                        tooltip: 'refresh screenshot',
                        onTap: () => browserNotifier.manualRefresh(),
                        tokens: t,
                      ),
                      const SizedBox(width: 2),
                      _SmallButton(
                        icon: Icons.stop,
                        tooltip: 'stop browser',
                        onTap: () => browserNotifier.stopBrowser(),
                        tokens: t,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

        // Mode toggle – bottom-right
        Positioned(
          bottom: 4,
          right: 4,
          child: PointerInterceptor(
            child: _ModeToggle(
              currentMode: mode,
              drawIOTheme: drawIOTheme,
              onModeChanged: (newMode) {
                modeNotifier.setMode(newMode);
              },
              onDrawioThemeToggle: () {
                drawIOThemeNotifier.toggle();
                CanvasPanel.drawioKey.currentState?.reloadWithTheme();
              },
              tokens: t,
            ),
          ),
        ),
      ],
    );
  }
}

class _DrawIOLoadDialog extends StatefulWidget {
  const _DrawIOLoadDialog();

  @override
  State<_DrawIOLoadDialog> createState() => _DrawIOLoadDialogState();
}

class _DrawIOLoadDialogState extends State<_DrawIOLoadDialog> {
  late List<DrawIOSnapshot> _snapshots;

  @override
  void initState() {
    super.initState();
    _snapshots = DrawIOSnapshotStore.list();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: kShellBorderRadius),
      backgroundColor: t.surfaceBase,
      child: Container(
        width: 420,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          borderRadius: kShellBorderRadius,
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Text(
                    'load drawio snapshot',
                    style: TextStyle(fontSize: 11, color: t.fgMuted),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.close, size: 12, color: t.fgMuted),
                    ),
                  ),
                ],
              ),
            ),
            if (_snapshots.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'no saved snapshots yet',
                  style: TextStyle(fontSize: 11, color: t.fgMuted),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _snapshots.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: t.border),
                  itemBuilder: (context, index) {
                    final snap = _snapshots[index];
                    final ts = _formatTimestamp(snap.createdAt);
                    return _SnapshotRow(
                      snapshot: snap,
                      subtitle: ts,
                      onLoad: () {
                        CanvasPanel.drawioKey.currentState?.loadXmlSnapshot(snap.xml);
                        Navigator.of(context).pop();
                      },
                      onDelete: () {
                        DrawIOSnapshotStore.deleteById(snap.id);
                        setState(() => _snapshots = DrawIOSnapshotStore.list());
                      },
                      tokens: t,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$min:$sec';
  }
}

class _SnapshotRow extends StatefulWidget {
  final DrawIOSnapshot snapshot;
  final String subtitle;
  final VoidCallback onLoad;
  final VoidCallback onDelete;
  final ShellTokens tokens;

  const _SnapshotRow({
    required this.snapshot,
    required this.subtitle,
    required this.onLoad,
    required this.onDelete,
    required this.tokens,
  });

  @override
  State<_SnapshotRow> createState() => _SnapshotRowState();
}

class _SnapshotRowState extends State<_SnapshotRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onLoad,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: _hovering ? t.surfaceCard : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.snapshot.name,
                      style: TextStyle(fontSize: 11, color: t.fgSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(fontSize: 9, color: t.fgMuted),
                    ),
                  ],
                ),
              ),
              if (_hovering)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.delete_outline, size: 12, color: t.fgMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode toggle
// ---------------------------------------------------------------------------

class _ModeToggle extends StatelessWidget {
  final CanvasMode currentMode;
  final DrawIOTheme drawIOTheme;
  final ValueChanged<CanvasMode> onModeChanged;
  final VoidCallback onDrawioThemeToggle;
  final ShellTokens tokens;

  const _ModeToggle({
    required this.currentMode,
    required this.drawIOTheme,
    required this.onModeChanged,
    required this.onDrawioThemeToggle,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: kShellBorderRadiusSm,
        color: tokens.surfaceBase.withOpacity(0.95),
        border: Border.all(color: tokens.border, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            label: 'a2ui',
            isSelected: currentMode == CanvasMode.a2ui,
            onTap: () => onModeChanged(CanvasMode.a2ui),
            tokens: tokens,
          ),
          _divider(),
          _ModeButton(
            label: 'drawio',
            isSelected: currentMode == CanvasMode.drawio,
            onTap: () => onModeChanged(CanvasMode.drawio),
            trailing: currentMode == CanvasMode.drawio
                ? GestureDetector(
                    onTap: onDrawioThemeToggle,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          drawIOTheme == DrawIOTheme.dark
                              ? Icons.light_mode
                              : Icons.dark_mode,
                          size: 10,
                          color: tokens.fgMuted,
                        ),
                      ),
                    ),
                  )
                : null,
            tokens: tokens,
          ),
          _divider(),
          _ModeButton(
            label: 'browser',
            isSelected: currentMode == CanvasMode.browser,
            onTap: () => onModeChanged(CanvasMode.browser),
            tokens: tokens,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 14,
        color: tokens.border,
        margin: const EdgeInsets.symmetric(horizontal: 2),
      );
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;
  final ShellTokens tokens;

  const _ModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.trailing,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSelected ? null : onTap,
      child: MouseRegion(
        cursor: isSelected ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            color: isSelected
                ? tokens.accentPrimary.withOpacity(0.15)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? tokens.accentPrimary : tokens.fgMuted,
                  letterSpacing: 0.5,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ShellTokens tokens;

  const _SmallButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadiusSm,
              color: tokens.surfaceBase.withOpacity(0.8),
              border: Border.all(color: tokens.border, width: 0.5),
            ),
            child: Icon(icon, size: 12, color: tokens.fgMuted),
          ),
        ),
      ),
    );
  }
}

class _SmallTextButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final ShellTokens tokens;

  const _SmallTextButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadiusSm,
              color: tokens.surfaceBase.withOpacity(0.9),
              border: Border.all(color: tokens.border, width: 0.5),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: tokens.fgMuted,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
