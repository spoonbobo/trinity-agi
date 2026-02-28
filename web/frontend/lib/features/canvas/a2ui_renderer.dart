import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/a2ui_models.dart';
import '../../models/ws_frame.dart';
import '../shell/shell_page.dart';

final a2uiJsonlPattern = RegExp(r'```a2ui\n([\s\S]*?)```');

/// Renders A2UI v0.8 surfaces pushed by the agent via inline JSONL in chat.
class A2UIRendererPanel extends ConsumerStatefulWidget {
  const A2UIRendererPanel({super.key});

  @override
  ConsumerState<A2UIRendererPanel> createState() => _A2UIRendererPanelState();
}

class _A2UIRendererPanelState extends ConsumerState<A2UIRendererPanel> {
  final Map<String, A2UISurface> _surfaces = {};
  StreamSubscription<WsEvent>? _chatSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = ref.read(gatewayClientProvider);
      _chatSub = client.events.listen(_handleEvent);
    });
  }

  void _handleEvent(WsEvent event) {
    try {
      _handleEventInner(event);
    } catch (e, st) {
      debugPrint('[A2UI] error handling event: $e\n$st');
    }
  }

  void _handleEventInner(WsEvent event) {
    if (event.event == 'a2ui' || event.event == 'canvas') {
      _handleA2UIEvent(event);
      return;
    }

    if (event.event != 'chat') return;
    final state = event.payload['state'] as String?;
    if (state != 'final') return;

    final message = event.payload['message'];
    if (message is! Map<String, dynamic>) return;
    final contentList = message['content'];
    if (contentList is! List || contentList.isEmpty) return;
    final first = contentList[0];
    if (first is! Map<String, dynamic>) return;
    final text = first['text'] as String? ?? '';

    final match = a2uiJsonlPattern.firstMatch(text);
    if (match == null) return;

    final jsonlBlock = match.group(1) ?? '';
    for (final line in jsonlBlock.split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(line.trim()) as Map<String, dynamic>;
        _handleA2UIEvent(WsEvent(event: 'a2ui', payload: parsed));
      } catch (_) {}
    }
  }

  void _handleA2UIEvent(WsEvent event) {
    final payload = event.payload;

    if (payload.containsKey('surfaceUpdate')) {
      final raw = payload['surfaceUpdate'];
      if (raw is Map<String, dynamic>) {
        try {
          final update = SurfaceUpdate.fromJson(raw);
          setState(() {
            final surface = _surfaces.putIfAbsent(
              update.surfaceId,
              () => A2UISurface(surfaceId: update.surfaceId, components: []),
            );
            surface.components
              ..clear()
              ..addAll(update.components);
          });
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
          setState(() {
            _surfaces[begin.surfaceId]?.rootId = begin.root;
          });
        } catch (e) {
          debugPrint('[A2UI] bad beginRendering: $e');
        }
      }
    }

    if (payload.containsKey('dataModelUpdate')) {
      // Data model updates would refresh bound data in components
      setState(() {});
    }

    if (payload.containsKey('deleteSurface')) {
      final raw = payload['deleteSurface'];
      if (raw is Map<String, dynamic>) {
        try {
          final del = DeleteSurface.fromJson(raw);
          setState(() {
            _surfaces.remove(del.surfaceId);
          });
        } catch (e) {
          debugPrint('[A2UI] bad deleteSurface: $e');
        }
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

    if (_surfaces.isEmpty) {
      return Container(
        color: const Color(0xFF0A0A0A),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: _surfaces.values.map((surface) {
        if (surface.rootId == null) return const SizedBox.shrink();
        final rootComponent = surface.components.where(
          (c) => c.id == surface.rootId,
        );
        if (rootComponent.isEmpty) return const SizedBox.shrink();
        return _renderComponent(
          rootComponent.first,
          surface.components,
          theme,
        );
      }).toList(),
    );
  }

  Widget _renderComponent(
    A2UIComponent component,
    List<A2UIComponent> allComponents,
    ThemeData theme,
  ) {
    switch (component.type) {
      case 'Text':
        return _renderText(component, theme);
      case 'Column':
        return _renderColumn(component, allComponents, theme);
      case 'Row':
        return _renderRow(component, allComponents, theme);
      case 'Button':
        return _renderButton(component, theme);
      case 'Card':
        return _renderCard(component, allComponents, theme);
      case 'Image':
        return _renderImage(component);
      case 'TextField':
        return _renderTextField(component, theme);
      case 'Slider':
        return _renderSlider(component);
      case 'Toggle':
        return _renderToggle(component);
      case 'Progress':
        return _renderProgress(component, theme);
      case 'Divider':
        return const Divider(color: Color(0xFF2A2A2A), height: 16);
      case 'Spacer':
        return SizedBox(
          height: (component.props['height'] as num?)?.toDouble() ?? 16,
        );
      default:
        return Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF2A2A2A)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '[${component.type}]',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF6B6B6B),
            ),
          ),
        );
    }
  }

  Widget _renderText(A2UIComponent component, ThemeData theme) {
    final text = _resolveText(component.props['text']);
    final hint = component.props['usageHint'] as String?;

    TextStyle? style;
    switch (hint) {
      case 'h1':
        style = theme.textTheme.titleLarge;
        break;
      case 'h2':
        style = theme.textTheme.titleLarge?.copyWith(fontSize: 16);
        break;
      case 'caption':
      case 'label':
        style = theme.textTheme.labelSmall;
        break;
      default:
        style = theme.textTheme.bodyLarge;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(text, style: style),
    );
  }

  Widget _renderColumn(
    A2UIComponent component,
    List<A2UIComponent> all,
    ThemeData theme,
  ) {
    final childIds = _resolveChildIds(component.props['children']);
    final children = childIds
        .map((id) => all.where((c) => c.id == id))
        .where((matches) => matches.isNotEmpty)
        .map((matches) => _renderComponent(matches.first, all, theme))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _renderRow(
    A2UIComponent component,
    List<A2UIComponent> all,
    ThemeData theme,
  ) {
    final childIds = _resolveChildIds(component.props['children']);
    final children = childIds
        .map((id) => all.where((c) => c.id == id))
        .where((matches) => matches.isNotEmpty)
        .map((matches) => _renderComponent(matches.first, all, theme))
        .toList();

    return Row(
      children: children.map((c) => Flexible(child: c)).toList(),
    );
  }

  Widget _renderButton(A2UIComponent component, ThemeData theme) {
    final label = _resolveText(component.props['label'] ?? component.props['text']);
    final action = component.props['action'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        onPressed: action != null
            ? () {
                // Send button action back to the agent
                ref.read(gatewayClientProvider).sendChatMessage(
                      '/action $action',
                    );
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        child: Text(label, style: const TextStyle(fontFamily: 'monofur')),
      ),
    );
  }

  Widget _renderCard(
    A2UIComponent component,
    List<A2UIComponent> all,
    ThemeData theme,
  ) {
    final childIds = _resolveChildIds(component.props['children']);
    final children = childIds
        .map((id) => all.where((c) => c.id == id))
        .where((matches) => matches.isNotEmpty)
        .map((matches) => _renderComponent(matches.first, all, theme))
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _renderImage(A2UIComponent component) {
    final url = component.props['url'] as String? ??
        component.props['src'] as String? ??
        '';
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, fit: BoxFit.contain),
      ),
    );
  }

  Widget _renderTextField(A2UIComponent component, ThemeData theme) {
    final hint = component.props['placeholder'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        decoration: InputDecoration(hintText: hint),
        style: theme.textTheme.bodyLarge,
      ),
    );
  }

  Widget _renderSlider(A2UIComponent component) {
    final min = (component.props['min'] as num?)?.toDouble() ?? 0;
    final max = (component.props['max'] as num?)?.toDouble() ?? 100;
    final value = (component.props['value'] as num?)?.toDouble() ?? min;
    return StatefulBuilder(
      builder: (context, setSliderState) {
        var current = value;
        return Slider(
          value: current.clamp(min, max),
          min: min,
          max: max,
          activeColor: const Color(0xFF6EE7B7),
          onChanged: (v) => setSliderState(() => current = v),
        );
      },
    );
  }

  Widget _renderToggle(A2UIComponent component) {
    final value = component.props['value'] as bool? ?? false;
    final label = _resolveText(component.props['label']);
    return StatefulBuilder(
      builder: (context, setToggleState) {
        var current = value;
        return SwitchListTile(
          value: current,
          title: Text(label),
          activeColor: const Color(0xFF6EE7B7),
          onChanged: (v) => setToggleState(() => current = v),
          contentPadding: EdgeInsets.zero,
        );
      },
    );
  }

  Widget _renderProgress(A2UIComponent component, ThemeData theme) {
    final value = (component.props['value'] as num?)?.toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: value != null
          ? LinearProgressIndicator(
              value: value,
              backgroundColor: const Color(0xFF2A2A2A),
              color: theme.colorScheme.primary,
            )
          : LinearProgressIndicator(
              backgroundColor: const Color(0xFF2A2A2A),
              color: theme.colorScheme.primary,
            ),
    );
  }

  String _resolveText(dynamic textProp) {
    if (textProp == null) return '';
    if (textProp is String) return textProp;
    if (textProp is Map) {
      return textProp['literalString'] as String? ??
          textProp['value'] as String? ??
          textProp.toString();
    }
    return textProp.toString();
  }

  List<String> _resolveChildIds(dynamic childrenProp) {
    if (childrenProp == null) return [];
    if (childrenProp is List) {
      return childrenProp
          .where((e) => e != null)
          .map((e) => e.toString())
          .toList();
    }
    if (childrenProp is Map) {
      final explicit = childrenProp['explicitList'];
      if (explicit is List) {
        return explicit
            .where((e) => e != null)
            .map((e) => e.toString())
            .toList();
      }
    }
    return [];
  }
}
