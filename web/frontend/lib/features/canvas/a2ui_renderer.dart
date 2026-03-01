import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../models/a2ui_models.dart';
import '../../models/ws_frame.dart';
import '../../core/providers.dart';

/// Material icon name -> IconData lookup for the Icon component.
final Map<String, IconData> _materialIconMap = {
  'check': Icons.check,
  'close': Icons.close,
  'add': Icons.add,
  'remove': Icons.remove,
  'delete': Icons.delete,
  'edit': Icons.edit,
  'search': Icons.search,
  'settings': Icons.settings,
  'home': Icons.home,
  'star': Icons.star,
  'star_border': Icons.star_border,
  'favorite': Icons.favorite,
  'favorite_border': Icons.favorite_border,
  'info': Icons.info,
  'warning': Icons.warning,
  'error': Icons.error,
  'help': Icons.help,
  'visibility': Icons.visibility,
  'visibility_off': Icons.visibility_off,
  'arrow_back': Icons.arrow_back,
  'arrow_forward': Icons.arrow_forward,
  'arrow_upward': Icons.arrow_upward,
  'arrow_downward': Icons.arrow_downward,
  'expand_more': Icons.expand_more,
  'expand_less': Icons.expand_less,
  'chevron_right': Icons.chevron_right,
  'chevron_left': Icons.chevron_left,
  'menu': Icons.menu,
  'more_vert': Icons.more_vert,
  'more_horiz': Icons.more_horiz,
  'refresh': Icons.refresh,
  'copy': Icons.copy,
  'content_copy': Icons.content_copy,
  'content_paste': Icons.content_paste,
  'send': Icons.send,
  'download': Icons.download,
  'upload': Icons.upload,
  'share': Icons.share,
  'link': Icons.link,
  'open_in_new': Icons.open_in_new,
  'play_arrow': Icons.play_arrow,
  'pause': Icons.pause,
  'stop': Icons.stop,
  'skip_next': Icons.skip_next,
  'skip_previous': Icons.skip_previous,
  'person': Icons.person,
  'people': Icons.people,
  'group': Icons.group,
  'notifications': Icons.notifications,
  'email': Icons.email,
  'phone': Icons.phone,
  'chat': Icons.chat,
  'message': Icons.message,
  'calendar_today': Icons.calendar_today,
  'schedule': Icons.schedule,
  'access_time': Icons.access_time,
  'location_on': Icons.location_on,
  'map': Icons.map,
  'cloud': Icons.cloud,
  'cloud_upload': Icons.cloud_upload,
  'cloud_download': Icons.cloud_download,
  'folder': Icons.folder,
  'file_copy': Icons.file_copy,
  'attach_file': Icons.attach_file,
  'photo': Icons.photo,
  'camera': Icons.camera_alt,
  'mic': Icons.mic,
  'volume_up': Icons.volume_up,
  'volume_off': Icons.volume_off,
  'brightness_high': Icons.brightness_high,
  'brightness_low': Icons.brightness_low,
  'wifi': Icons.wifi,
  'bluetooth': Icons.bluetooth,
  'battery_full': Icons.battery_full,
  'power': Icons.power,
  'lock': Icons.lock,
  'lock_open': Icons.lock_open,
  'vpn_key': Icons.vpn_key,
  'security': Icons.security,
  'verified': Icons.verified,
  'thumb_up': Icons.thumb_up,
  'thumb_down': Icons.thumb_down,
  'code': Icons.code,
  'terminal': Icons.terminal,
  'bug_report': Icons.bug_report,
  'build': Icons.build,
  'dashboard': Icons.dashboard,
  'analytics': Icons.analytics,
  'bar_chart': Icons.bar_chart,
  'pie_chart': Icons.pie_chart,
  'show_chart': Icons.show_chart,
  'trending_up': Icons.trending_up,
  'trending_down': Icons.trending_down,
  'data_usage': Icons.data_usage,
  'memory': Icons.memory,
  'speed': Icons.speed,
  'grid_view': Icons.grid_view,
  'list': Icons.list,
  'view_list': Icons.view_list,
  'table_chart': Icons.table_chart,
  'check_circle': Icons.check_circle,
  'cancel': Icons.cancel,
  'do_not_disturb': Icons.do_not_disturb,
  'task_alt': Icons.task_alt,
  'pending': Icons.pending,
  'hourglass_empty': Icons.hourglass_empty,
  'sync': Icons.sync,
  'autorenew': Icons.autorenew,
  'rocket_launch': Icons.rocket_launch,
  'lightbulb': Icons.lightbulb,
  'psychology': Icons.psychology,
  'smart_toy': Icons.smart_toy,
};

/// Renders A2UI v0.8 surfaces pushed by the agent.
class A2UIRendererPanel extends ConsumerStatefulWidget {
  const A2UIRendererPanel({super.key});

  @override
  ConsumerState<A2UIRendererPanel> createState() => _A2UIRendererPanelState();
}

class _A2UIRendererPanelState extends ConsumerState<A2UIRendererPanel> {
  final Map<String, A2UISurface> _surfaces = {};
  StreamSubscription<WsEvent>? _chatSub;
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _showExportMenu = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = ref.read(gatewayClientProvider);
      _chatSub = client.events
          .where((e) => e.event == 'a2ui' || e.event == 'canvas')
          .listen(_handleEvent);
    });
  }

  void _handleEvent(WsEvent event) {
    try {
      _handleA2UIEvent(event);
    } catch (e, st) {
      debugPrint('[A2UI] error handling event: $e\n$st');
    }
  }

  void _handleA2UIEvent(WsEvent event) {
    final payload = event.payload;
    bool needsRebuild = false;

    if (payload.containsKey('surfaceUpdate')) {
      final raw = payload['surfaceUpdate'];
      if (raw is Map<String, dynamic>) {
        try {
          final update = SurfaceUpdate.fromJson(raw);
          final surface = _surfaces.putIfAbsent(
            update.surfaceId,
            () => A2UISurface(surfaceId: update.surfaceId),
          );
          for (final comp in update.components) {
            surface.components[comp.id] = comp;
          }
          needsRebuild = true;
        } catch (e) {
          debugPrint('[A2UI] bad surfaceUpdate: $e');
        }
      }
    }

    if (payload.containsKey('beginRendering')) {
      final raw = payload['beginRendering'];
      if (raw is Map<String, dynamic>) {
        try {
          final begin = BeginRendering.fromJson(raw);
          final surface = _surfaces[begin.surfaceId];
          if (surface != null) {
            surface.rootId = begin.root;
            if (begin.catalogId != null) {
              surface.catalogId = begin.catalogId;
            }
            needsRebuild = true;
          }
        } catch (e) {
          debugPrint('[A2UI] bad beginRendering: $e');
        }
      }
    }

    if (payload.containsKey('dataModelUpdate')) {
      final raw = payload['dataModelUpdate'];
      if (raw is Map<String, dynamic>) {
        try {
          final update = DataModelUpdate.fromJson(raw);
          final surface = _surfaces.putIfAbsent(
            update.surfaceId,
            () => A2UISurface(surfaceId: update.surfaceId),
          );
          surface.mergeContents(update.path, update.contents);
          needsRebuild = true;
        } catch (e) {
          debugPrint('[A2UI] bad dataModelUpdate: $e');
        }
      }
    }

    if (payload.containsKey('deleteSurface')) {
      final raw = payload['deleteSurface'];
      if (raw is Map<String, dynamic>) {
        try {
          final del = DeleteSurface.fromJson(raw);
          if (_surfaces.remove(del.surfaceId) != null) {
            needsRebuild = true;
          }
        } catch (e) {
          debugPrint('[A2UI] bad deleteSurface: $e');
        }
      }
    }

    if (needsRebuild) setState(() {});
  }

  void _sendUserAction(String actionName, A2UISurface surface,
      String sourceComponentId, Map<String, dynamic>? actionContext) {
    final resolvedContext = <String, dynamic>{};
    if (actionContext != null) {
      for (final entry in actionContext.entries) {
        resolvedContext[entry.key] =
            resolveBoundValue(entry.value, surface) ?? entry.value;
      }
    }

    final action = UserAction(
      name: actionName,
      surfaceId: surface.surfaceId,
      sourceComponentId: sourceComponentId,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      context: resolvedContext,
    );

    final client = ref.read(gatewayClientProvider);
    final payload = jsonEncode(action.toJson());
    client.sendChatMessage('/a2ui-action $payload');
  }

  // Canvas export: download as PNG
  Future<void> _exportAsPng() async {
    try {
      final boundary = _repaintBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final base64 = base64Encode(bytes);
      final dataUrl = 'data:image/png;base64,$base64';
      final anchor = html.AnchorElement(href: dataUrl)
        ..setAttribute('download', 'canvas-${DateTime.now().millisecondsSinceEpoch}.png')
        ..click();
    } catch (e) {
      debugPrint('[Canvas] export PNG error: $e');
    }
    setState(() => _showExportMenu = false);
  }

  // Canvas export: download as JSON
  void _exportAsJson() {
    try {
      final data = <String, dynamic>{};
      for (final surface in _surfaces.values) {
        data[surface.surfaceId] = {
          'rootId': surface.rootId,
          'components': surface.components.map((k, v) => MapEntry(k, {
            'id': v.id,
            'type': v.type,
            'props': v.props,
            if (v.weight != null) 'weight': v.weight,
          })),
          'dataModel': surface.dataModel,
        };
      }
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final bytes = utf8.encode(jsonStr);
      final base64 = base64Encode(bytes);
      final dataUrl = 'data:application/json;base64,$base64';
      final anchor = html.AnchorElement(href: dataUrl)
        ..setAttribute('download', 'canvas-${DateTime.now().millisecondsSinceEpoch}.json')
        ..click();
    } catch (e) {
      debugPrint('[Canvas] export JSON error: $e');
    }
    setState(() => _showExportMenu = false);
  }

  // Canvas export: copy as image to clipboard (browser Clipboard API)
  bool _copyingImage = false;
  bool _imageCopied = false;
  Future<void> _copyAsImage() async {
    if (_copyingImage) return;
    setState(() { _copyingImage = true; _imageCopied = false; });
    try {
      final boundary = _repaintBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      // Use dart:html Blob + JS interop on the native ClipboardItem
      // to avoid the unreliable eval+promiseToFuture path.
      bool copied = false;
      try {
        final blob = html.Blob([bytes], 'image/png');
        final clipboardItem = js_util.callConstructor(
          js_util.getProperty(html.window, 'ClipboardItem'),
          [js_util.jsify({'image/png': blob})],
        );
        final clipboard = js_util.getProperty(html.window.navigator, 'clipboard');
        final promise = js_util.callMethod(clipboard, 'write', [
          js_util.jsify([clipboardItem]),
        ]);
        await js_util.promiseToFuture(promise);
        copied = true;
      } catch (clipErr) {
        debugPrint('[Canvas] clipboard write failed: $clipErr');
      }

      if (copied) {
        if (mounted) setState(() => _imageCopied = true);
      } else {
        // Fallback: download the image only when clipboard truly failed
        debugPrint('[Canvas] falling back to download');
        final b64 = base64Encode(bytes);
        final dataUrl = 'data:image/png;base64,$b64';
        html.AnchorElement(href: dataUrl)
          ..setAttribute('download', 'canvas-${DateTime.now().millisecondsSinceEpoch}.png')
          ..click();
      }
    } catch (e) {
      debugPrint('[Canvas] copy image error: $e');
    }
    if (mounted) {
      setState(() => _copyingImage = false);
      if (_imageCopied) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _imageCopied = false);
        });
      }
    }
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);

    // #6: Better empty state with label
    if (_surfaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_rounded, size: 20, color: t.fgPlaceholder),
            const SizedBox(height: 6),
            Text('canvas', style: TextStyle(
              fontSize: 10, color: t.fgPlaceholder, letterSpacing: 1.5)),
          ],
        ),
      );
    }

    // #14: Show loading indicator when surfaces exist but no root yet
    final hasRenderable = _surfaces.values.any(
        (s) => s.rootId != null && s.components.containsKey(s.rootId));
    if (!hasRenderable) {
      return Center(
        child: SizedBox(
          width: 80,
          child: LinearProgressIndicator(
            backgroundColor: t.surfaceElevated,
            color: t.accentPrimary,
            minHeight: 2,
          ),
        ),
      );
    }

    // #23: AnimatedSwitcher for surface transitions + export toolbar
    return Stack(
      children: [
        RepaintBoundary(
          key: _repaintBoundaryKey,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: ListView(
              key: ValueKey(_surfaces.keys.join(',')),
              padding: const EdgeInsets.all(12),
              children: _surfaces.values.map((surface) {
                if (surface.rootId == null) return const SizedBox.shrink();
                final rootComponent = surface.components[surface.rootId];
                if (rootComponent == null) return const SizedBox.shrink();
                return KeyedSubtree(
                  key: ValueKey('surface-${surface.surfaceId}'),
                  child: _renderComponent(rootComponent, surface, theme, t),
                );
              }).toList(),
            ),
          ),
        ),
        // Export toolbar: copy image button (standalone) + download menu
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Copy image button (standalone, separate from menu)
              GestureDetector(
                onTap: _copyAsImage,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: t.surfaceBase.withOpacity(0.8),
                      border: Border.all(color: t.border, width: 0.5),
                    ),
                    child: _copyingImage
                      ? SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: t.accentPrimary))
                      : Icon(
                          _imageCopied ? Icons.check : Icons.content_copy,
                          size: 12,
                          color: _imageCopied ? t.accentPrimary : t.fgMuted,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // Download menu
              _buildExportToolbar(t, theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExportToolbar(ShellTokens t, ThemeData theme) {
    return TapRegion(
      onTapOutside: (_) {
        if (_showExportMenu) setState(() => _showExportMenu = false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showExportMenu = !_showExportMenu),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: t.surfaceBase.withOpacity(0.8),
                  border: Border.all(color: t.border, width: 0.5),
                ),
                child: Icon(Icons.download, size: 12, color: t.fgMuted),
              ),
            ),
          ),
          if (_showExportMenu) ...[
            const SizedBox(height: 2),
            Container(
              decoration: BoxDecoration(
                color: t.surfaceBase,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ExportMenuItem(
                    label: 'download PNG',
                    icon: Icons.image,
                    onTap: _exportAsPng,
                    tokens: t, theme: theme,
                  ),
                  _ExportMenuItem(
                    label: 'download JSON',
                    icon: Icons.code,
                    onTap: _exportAsJson,
                    tokens: t, theme: theme,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Component rendering
  // ---------------------------------------------------------------------------

  Widget _renderComponent(
    A2UIComponent component,
    A2UISurface surface,
    ThemeData theme,
    ShellTokens t,
  ) {
    final Widget child;
    switch (component.type) {
      case 'Text':
        child = _renderText(component, surface, theme);
        break;
      case 'Column':
        child = _renderColumn(component, surface, theme, t);
        break;
      case 'Row':
        child = _renderRow(component, surface, theme, t);
        break;
      case 'Button':
        child = _renderButton(component, surface, theme);
        break;
      case 'Card':
        child = _renderCard(component, surface, theme, t);
        break;
      case 'Image':
        child = _renderImage(component, surface, t);
        break;
      case 'TextField':
        child = _A2UITextField(
          key: ValueKey('tf-${component.id}'),
          component: component,
          surface: surface,
          theme: theme,
        );
        break;
      case 'Icon':
        child = _renderIcon(component, surface, theme);
        break;
      case 'CheckBox':
        child = _A2UICheckBox(
          key: ValueKey('cb-${component.id}'),
          component: component,
          surface: surface,
          theme: theme,
          tokens: t,
        );
        break;
      case 'Modal':
        child = _renderModal(component, surface, theme, t);
        break;
      case 'Tabs':
        child = _renderTabs(component, surface, theme, t);
        break;
      case 'List':
        child = _renderList(component, surface, theme, t);
        break;
      case 'Slider':
        child = _A2UISlider(
          key: ValueKey('sl-${component.id}'),
          component: component,
          surface: surface,
          tokens: t,
        );
        break;
      case 'Toggle':
        child = _A2UIToggle(
          key: ValueKey('tg-${component.id}'),
          component: component,
          surface: surface,
          tokens: t,
        );
        break;
      case 'Progress':
        child = _renderProgress(component, surface, theme, t);
        break;
      case 'Divider':
        child = _renderDivider(component, t);
        break;
      case 'Spacer':
        child = SizedBox(
          height: (component.props['height'] as num?)?.toDouble() ?? 16,
        );
        break;
      case 'CodeEditor':
        child = _A2UICodeEditor(
          key: ValueKey('ce-${component.id}'),
          component: component,
          surface: surface,
          theme: theme,
          tokens: t,
        );
        break;
      default:
        // Subtle fallback for unknown components
        child = Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('[${component.type}]',
            style: TextStyle(color: t.fgMuted, fontSize: 11)),
        );
    }

    return KeyedSubtree(key: ValueKey(component.id), child: child);
  }

  Widget _renderText(A2UIComponent c, A2UISurface surface, ThemeData theme) {
    final text = resolveBoundString(c.props['text'], surface);
    final hint = c.props['usageHint'] as String?;

    TextStyle? style;
    switch (hint) {
      case 'h1': style = theme.textTheme.titleLarge; break;
      case 'h2': style = theme.textTheme.titleLarge?.copyWith(fontSize: 16); break;
      case 'h3': style = theme.textTheme.titleMedium; break;
      case 'h4': style = theme.textTheme.titleSmall; break;
      case 'h5': style = theme.textTheme.labelLarge; break;
      case 'caption':
      case 'label': style = theme.textTheme.labelSmall; break;
      default: style = theme.textTheme.bodyLarge;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(text, style: style),
    );
  }

  Widget _renderColumn(A2UIComponent c, A2UISurface surface, ThemeData theme, ShellTokens t) {
    final childIds = _resolveChildIds(c.props['children']);
    final distribution = c.props['distribution'] as String?;
    final alignment = c.props['alignment'] as String?;

    return Column(
      crossAxisAlignment: _parseCrossAxisAlignment(alignment) ?? CrossAxisAlignment.start,
      mainAxisAlignment: _parseMainAxisAlignment(distribution) ?? MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _buildChildren(childIds, surface, theme, t),
    );
  }

  Widget _renderRow(A2UIComponent c, A2UISurface surface, ThemeData theme, ShellTokens t) {
    final childIds = _resolveChildIds(c.props['children']);
    final distribution = c.props['distribution'] as String?;
    final alignment = c.props['alignment'] as String?;

    final children = <Widget>[];
    for (final id in childIds) {
      final comp = surface.components[id];
      if (comp == null) continue;
      final widget = _renderComponent(comp, surface, theme, t);
      final flex = comp.weight?.toInt() ?? 1;
      children.add(Flexible(key: ValueKey('flex-$id'), flex: flex, child: widget));
    }

    return Row(
      mainAxisAlignment: _parseMainAxisAlignment(distribution) ?? MainAxisAlignment.start,
      crossAxisAlignment: _parseCrossAxisAlignment(alignment) ?? CrossAxisAlignment.center,
      children: children,
    );
  }

  Widget _renderButton(A2UIComponent c, A2UISurface surface, ThemeData theme) {
    final actionProp = c.props['action'];
    String? actionName;
    Map<String, dynamic>? actionContext;

    if (actionProp is Map<String, dynamic>) {
      actionName = actionProp['name'] as String?;
      final ctxRaw = actionProp['context'];
      if (ctxRaw is Map<String, dynamic>) {
        actionContext = ctxRaw;
      } else if (ctxRaw is List) {
        actionContext = {};
        for (final entry in ctxRaw) {
          if (entry is Map<String, dynamic>) {
            final key = entry['key'] as String?;
            if (key != null) actionContext[key] = entry['value'] ?? entry;
          }
        }
      }
    } else if (actionProp is String) {
      actionName = actionProp;
    }

    final primary = c.props['primary'] as bool? ?? false;

    final childId = c.props['child'] as String?;
    Widget? childWidget;
    if (childId != null && surface.components.containsKey(childId)) {
      childWidget = _renderComponent(
          surface.components[childId]!, surface, theme, ShellTokens.of(context));
    }
    final label = resolveBoundString(c.props['label'] ?? c.props['text'], surface);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        onPressed: actionName != null
            ? () => _sendUserAction(actionName!, surface, c.id, actionContext)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? theme.colorScheme.primary : theme.colorScheme.surface,
          foregroundColor: primary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        child: childWidget ?? Text(label),
      ),
    );
  }

  Widget _renderCard(A2UIComponent c, A2UISurface surface, ThemeData theme, ShellTokens t) {
    final singleChild = c.props['child'] as String?;
    List<Widget> children;

    if (singleChild != null && surface.components.containsKey(singleChild)) {
      children = [_renderComponent(surface.components[singleChild]!, surface, theme, t)];
    } else {
      children = _buildChildren(_resolveChildIds(c.props['children']), surface, theme, t);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  // #16: Image with loading placeholder
  Widget _renderImage(A2UIComponent c, A2UISurface surface, ShellTokens t) {
    final url = resolveBoundString(c.props['url'] ?? c.props['src'], surface);
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
        child: Image.network(url, fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              height: 80,
              width: double.infinity,
              child: Center(child: LinearProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                    : null,
                backgroundColor: t.surfaceElevated,
                color: t.accentPrimary,
                minHeight: 2,
              )),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            padding: const EdgeInsets.all(8),
            color: t.surfaceCard,
            child: Text('[Image failed to load]',
                style: TextStyle(color: t.fgMuted, fontSize: 12)),
          ),
        ),
      ),
    );
  }

  // #22: Icon size from props
  Widget _renderIcon(A2UIComponent c, A2UISurface surface, ThemeData theme) {
    final name = resolveBoundString(c.props['name'], surface);
    final size = (c.props['size'] as num?)?.toDouble() ?? 20;
    final iconData = _materialIconMap[name] ?? Icons.help_outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Icon(iconData, color: theme.colorScheme.onSurface, size: size),
    );
  }

  Widget _renderModal(A2UIComponent c, A2UISurface surface, ThemeData theme, ShellTokens t) {
    final entryPointChildId = c.props['entryPointChild'] as String?;
    final contentChildId = c.props['contentChild'] as String?;

    Widget entryPoint = const SizedBox.shrink();
    if (entryPointChildId != null && surface.components.containsKey(entryPointChildId)) {
      entryPoint = _renderComponent(surface.components[entryPointChildId]!, surface, theme, t);
    }

    return GestureDetector(
      onTap: () {
        if (contentChildId != null && surface.components.containsKey(contentChildId)) {
          showDialog(context: context, builder: (dialogContext) {
            return Dialog(
              shape: const RoundedRectangleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: _renderComponent(
                      surface.components[contentChildId]!, surface, theme, t),
                ),
              ),
            );
          });
        }
      },
      child: entryPoint,
    );
  }

  // #13: Flexible height for Tabs
  Widget _renderTabs(A2UIComponent c, A2UISurface surface, ThemeData theme, ShellTokens t) {
    final tabItems = c.props['tabItems'] as List<dynamic>? ?? [];
    if (tabItems.isEmpty) return const SizedBox.shrink();

    final tabs = <Tab>[];
    final tabChildren = <Widget>[];

    for (int i = 0; i < tabItems.length; i++) {
      final item = tabItems[i];
      if (item is! Map<String, dynamic>) continue;
      final title = resolveBoundString(item['title'], surface);
      final childId = item['child'] as String?;
      tabs.add(Tab(key: ValueKey('tab-$i'), text: title));
      if (childId != null && surface.components.containsKey(childId)) {
        tabChildren.add(KeyedSubtree(
          key: ValueKey('tab-content-$childId'),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _renderComponent(surface.components[childId]!, surface, theme, t),
          ),
        ));
      } else {
        tabChildren.add(const SizedBox.shrink());
      }
    }

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            tabs: tabs,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: t.fgMuted,
            indicatorColor: theme.colorScheme.primary,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: TabBarView(children: tabChildren),
          ),
        ],
      ),
    );
  }

  // #13 + #21: Flexible height for List + safe per-item scoping
  Widget _renderList(A2UIComponent c, A2UISurface surface, ThemeData theme, ShellTokens t) {
    final childrenProp = c.props['children'];

    if (childrenProp is Map<String, dynamic> && childrenProp.containsKey('template')) {
      final template = childrenProp['template'] as Map<String, dynamic>;
      final dataBinding = template['dataBinding'] as String?;
      final templateId = template['componentId'] as String?;

      if (dataBinding != null && templateId != null) {
        final listData = surface.getPath(dataBinding);
        if (listData is List) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: listData.length,
              itemBuilder: (context, index) {
                final templateComp = surface.components[templateId];
                if (templateComp == null) return const SizedBox.shrink();
                // #21: Per-item scoping via isolated data overlay
                final item = listData[index];
                final itemSurface = _createItemScope(surface, item, index);
                return KeyedSubtree(
                  key: ValueKey('list-item-$index'),
                  child: _renderComponent(templateComp, itemSurface, theme, t),
                );
              },
            ),
          );
        }
      }
      return const SizedBox.shrink();
    }

    final childIds = _resolveChildIds(childrenProp);
    final children = _buildChildren(childIds, surface, theme, t);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ListView(children: children),
    );
  }

  // #21: Create a scoped surface for list item rendering
  A2UISurface _createItemScope(A2UISurface parent, dynamic item, int index) {
    final scoped = A2UISurface(surfaceId: parent.surfaceId);
    scoped.dataModel.addAll(parent.dataModel);
    scoped.components.addAll(parent.components);
    scoped.rootId = parent.rootId;
    if (item is Map<String, dynamic>) {
      scoped.setPath('_current', item);
    }
    scoped.setPath('_index', index);
    return scoped;
  }

  Widget _renderProgress(A2UIComponent c, A2UISurface surface, ThemeData theme, ShellTokens t) {
    final value = resolveBoundNum(c.props['value'], surface)?.toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: value != null
          ? LinearProgressIndicator(value: value, backgroundColor: t.surfaceElevated, color: theme.colorScheme.primary)
          : LinearProgressIndicator(backgroundColor: t.surfaceElevated, color: theme.colorScheme.primary),
    );
  }

  Widget _renderDivider(A2UIComponent c, ShellTokens t) {
    final axis = c.props['axis'] as String? ?? 'horizontal';
    if (axis == 'vertical') {
      return SizedBox(height: 40, child: VerticalDivider(color: t.border, width: 16));
    }
    return Divider(color: t.border, height: 16);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<Widget> _buildChildren(
      List<String> childIds, A2UISurface surface, ThemeData theme, ShellTokens t) {
    return childIds
        .map((id) => surface.components[id])
        .where((c) => c != null)
        .map((c) => _renderComponent(c!, surface, theme, t))
        .toList();
  }

  List<String> _resolveChildIds(dynamic childrenProp) {
    if (childrenProp == null) return [];
    if (childrenProp is List) {
      return childrenProp.where((e) => e != null).map((e) => e.toString()).toList();
    }
    if (childrenProp is Map) {
      final explicit = childrenProp['explicitList'];
      if (explicit is List) {
        return explicit.where((e) => e != null).map((e) => e.toString()).toList();
      }
    }
    return [];
  }

  MainAxisAlignment? _parseMainAxisAlignment(String? value) {
    switch (value) {
      case 'start': return MainAxisAlignment.start;
      case 'center': return MainAxisAlignment.center;
      case 'end': return MainAxisAlignment.end;
      case 'spaceBetween': return MainAxisAlignment.spaceBetween;
      case 'spaceAround': return MainAxisAlignment.spaceAround;
      case 'spaceEvenly': return MainAxisAlignment.spaceEvenly;
      default: return null;
    }
  }

  CrossAxisAlignment? _parseCrossAxisAlignment(String? value) {
    switch (value) {
      case 'start': return CrossAxisAlignment.start;
      case 'center': return CrossAxisAlignment.center;
      case 'end': return CrossAxisAlignment.end;
      case 'stretch': return CrossAxisAlignment.stretch;
      default: return null;
    }
  }
}

// =============================================================================
// Input StatefulWidgets with didUpdateWidget (#1)
// =============================================================================

/// TextField with proper controller lifecycle, data model write-back,
/// and server-side update handling via didUpdateWidget.
class _A2UITextField extends StatefulWidget {
  final A2UIComponent component;
  final A2UISurface surface;
  final ThemeData theme;

  const _A2UITextField({
    super.key,
    required this.component,
    required this.surface,
    required this.theme,
  });

  @override
  State<_A2UITextField> createState() => _A2UITextFieldState();
}

class _A2UITextFieldState extends State<_A2UITextField> {
  late final TextEditingController _controller;
  String? _textPath;

  @override
  void initState() {
    super.initState();
    _textPath = _extractPath(widget.component.props['text']);
    final initialValue = resolveBoundString(widget.component.props['text'], widget.surface);
    _controller = TextEditingController(text: initialValue);
  }

  @override
  void didUpdateWidget(covariant _A2UITextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newValue = resolveBoundString(widget.component.props['text'], widget.surface);
    if (newValue != _controller.text) {
      _controller.text = newValue;
      _controller.selection = TextSelection.collapsed(offset: newValue.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _extractPath(dynamic prop) {
    if (prop is Map) return prop['path'] as String?;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.component;
    final label = resolveBoundString(c.props['label'], widget.surface);
    final placeholder = c.props['placeholder'] as String? ?? '';
    final textFieldType = c.props['textFieldType'] as String? ?? 'shortText';

    final isMultiline = textFieldType == 'longText';
    final isObscured = textFieldType == 'obscured';
    final keyboardType = textFieldType == 'number'
        ? TextInputType.number
        : textFieldType == 'date'
            ? TextInputType.datetime
            : isMultiline ? TextInputType.multiline : TextInputType.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: placeholder,
          labelText: label.isNotEmpty ? label : null,
        ),
        style: widget.theme.textTheme.bodyLarge,
        obscureText: isObscured,
        keyboardType: keyboardType,
        maxLines: isMultiline ? 5 : 1,
        onChanged: (value) {
          if (_textPath != null) widget.surface.setPath(_textPath!, value);
        },
      ),
    );
  }
}

class _A2UICheckBox extends StatefulWidget {
  final A2UIComponent component;
  final A2UISurface surface;
  final ThemeData theme;
  final ShellTokens tokens;

  const _A2UICheckBox({
    super.key,
    required this.component,
    required this.surface,
    required this.theme,
    required this.tokens,
  });

  @override
  State<_A2UICheckBox> createState() => _A2UICheckBoxState();
}

class _A2UICheckBoxState extends State<_A2UICheckBox> {
  late bool _current;
  String? _valuePath;

  @override
  void initState() {
    super.initState();
    _valuePath = _extractPath(widget.component.props['value']);
    _current = resolveBoundBool(widget.component.props['value'], widget.surface);
  }

  @override
  void didUpdateWidget(covariant _A2UICheckBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newValue = resolveBoundBool(widget.component.props['value'], widget.surface);
    if (newValue != _current) setState(() => _current = newValue);
  }

  String? _extractPath(dynamic prop) {
    if (prop is Map) return prop['path'] as String?;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final label = resolveBoundString(widget.component.props['label'], widget.surface);
    return CheckboxListTile(
      value: _current,
      title: Text(label, style: widget.theme.textTheme.bodyLarge),
      activeColor: widget.tokens.accentPrimary,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      onChanged: (v) {
        setState(() => _current = v ?? false);
        if (_valuePath != null) widget.surface.setPath(_valuePath!, v ?? false);
      },
    );
  }
}

class _A2UISlider extends StatefulWidget {
  final A2UIComponent component;
  final A2UISurface surface;
  final ShellTokens tokens;

  const _A2UISlider({
    super.key,
    required this.component,
    required this.surface,
    required this.tokens,
  });

  @override
  State<_A2UISlider> createState() => _A2UISliderState();
}

class _A2UISliderState extends State<_A2UISlider> {
  late double _current;
  late double _min;
  late double _max;
  String? _valuePath;

  @override
  void initState() {
    super.initState();
    _min = (widget.component.props['min'] as num?)?.toDouble() ?? 0;
    _max = (widget.component.props['max'] as num?)?.toDouble() ?? 100;
    _valuePath = _extractPath(widget.component.props['value']);
    final initial = (resolveBoundNum(widget.component.props['value'], widget.surface) ?? _min)
        .toDouble();
    _current = initial.clamp(_min, _max);
  }

  @override
  void didUpdateWidget(covariant _A2UISlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newValue = (resolveBoundNum(widget.component.props['value'], widget.surface) ?? _min)
        .toDouble().clamp(_min, _max);
    if ((newValue - _current).abs() > 0.001) setState(() => _current = newValue);
  }

  String? _extractPath(dynamic prop) {
    if (prop is Map) return prop['path'] as String?;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _current,
      min: _min,
      max: _max,
      activeColor: widget.tokens.accentPrimary,
      onChanged: (v) {
        setState(() => _current = v);
        if (_valuePath != null) widget.surface.setPath(_valuePath!, v);
      },
    );
  }
}

class _A2UIToggle extends StatefulWidget {
  final A2UIComponent component;
  final A2UISurface surface;
  final ShellTokens tokens;

  const _A2UIToggle({
    super.key,
    required this.component,
    required this.surface,
    required this.tokens,
  });

  @override
  State<_A2UIToggle> createState() => _A2UIToggleState();
}

class _A2UIToggleState extends State<_A2UIToggle> {
  late bool _current;
  String? _valuePath;

  @override
  void initState() {
    super.initState();
    _valuePath = _extractPath(widget.component.props['value']);
    _current = resolveBoundBool(widget.component.props['value'], widget.surface);
  }

  @override
  void didUpdateWidget(covariant _A2UIToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newValue = resolveBoundBool(widget.component.props['value'], widget.surface);
    if (newValue != _current) setState(() => _current = newValue);
  }

  String? _extractPath(dynamic prop) {
    if (prop is Map) return prop['path'] as String?;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final label = resolveBoundString(widget.component.props['label'], widget.surface);
    return SwitchListTile(
      value: _current,
      title: Text(label),
      activeColor: widget.tokens.accentPrimary,
      contentPadding: EdgeInsets.zero,
      onChanged: (v) {
        setState(() => _current = v);
        if (_valuePath != null) widget.surface.setPath(_valuePath!, v);
      },
    );
  }
}

// =============================================================================
// Export menu item
// =============================================================================

class _ExportMenuItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final ShellTokens tokens;
  final ThemeData theme;

  const _ExportMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.tokens,
    required this.theme,
  });

  @override
  State<_ExportMenuItem> createState() => _ExportMenuItemState();
}

class _ExportMenuItemState extends State<_ExportMenuItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          color: _hovering ? t.surfaceCard : Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 11, color: t.fgMuted),
              const SizedBox(width: 6),
              Text(widget.label,
                style: TextStyle(fontSize: 10, color: t.fgSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CodeEditor A2UI Component
// =============================================================================

/// A syntax-highlighted code block component for A2UI surfaces.
/// Props:
///   - code: BoundValue (the code text)
///   - language: BoundValue (language label, e.g. "dart", "python")
///   - editable: bool (default false)
///   - lineNumbers: bool (default true)
class _A2UICodeEditor extends StatefulWidget {
  final A2UIComponent component;
  final A2UISurface surface;
  final ThemeData theme;
  final ShellTokens tokens;

  const _A2UICodeEditor({
    super.key,
    required this.component,
    required this.surface,
    required this.theme,
    required this.tokens,
  });

  @override
  State<_A2UICodeEditor> createState() => _A2UICodeEditorState();
}

class _A2UICodeEditorState extends State<_A2UICodeEditor> {
  late TextEditingController _controller;
  String? _codePath;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _codePath = _extractPath(widget.component.props['code']);
    final initialCode = resolveBoundString(widget.component.props['code'], widget.surface);
    _controller = TextEditingController(text: initialCode);
  }

  @override
  void didUpdateWidget(covariant _A2UICodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCode = resolveBoundString(widget.component.props['code'], widget.surface);
    if (newCode != _controller.text) {
      _controller.text = newCode;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _extractPath(dynamic prop) {
    if (prop is Map) return prop['path'] as String?;
    return null;
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _controller.text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final c = widget.component;
    final language = resolveBoundString(c.props['language'], widget.surface);
    final editable = c.props['editable'] == true;
    final showLineNumbers = c.props['lineNumbers'] != false;

    final lines = _controller.text.split('\n');
    final lineCount = lines.length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: t.surfaceBase,
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar with language label + copy button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: t.surfaceCard,
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  if (language.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                      child: Text(language,
                        style: TextStyle(fontSize: 9, color: t.accentPrimary)),
                    ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _copyCode,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.content_copy,
                            size: 11,
                            color: _copied ? t.accentPrimary : t.fgMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'copied' : 'copy',
                            style: TextStyle(
                              fontSize: 9,
                              color: _copied ? t.accentPrimary : t.fgMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Code area
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showLineNumbers)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(lineCount, (i) {
                          return Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: t.fgDisabled,
                              height: 1.5,
                              fontFamily: 'monospace',
                            ),
                          );
                        }),
                      ),
                    ),
                  Expanded(
                    child: editable
                        ? TextField(
                            controller: _controller,
                            maxLines: null,
                            style: TextStyle(
                              fontSize: 12,
                              color: t.accentPrimary,
                              height: 1.5,
                              fontFamily: 'monospace',
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) {
                              if (_codePath != null) {
                                widget.surface.setPath(_codePath!, value);
                              }
                              setState(() {}); // Refresh line numbers
                            },
                          )
                        : SelectableText(
                            _controller.text,
                            style: TextStyle(
                              fontSize: 12,
                              color: t.accentPrimary,
                              height: 1.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
