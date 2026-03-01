import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/a2ui_models.dart';

// =============================================================================
// Edit mode state & callbacks shared between renderer and editor widgets
// =============================================================================

/// Callback to notify the renderer that surfaces changed (user edit).
typedef OnSurfaceEdited = void Function();

/// Callback to send user edits to the agent via chat.
typedef OnSendEdit = void Function(String jsonl);

// =============================================================================
// Undo / Redo — canvas-scoped snapshot stack
// =============================================================================

/// A lightweight snapshot of a single surface for undo/redo.
class _SurfaceSnapshot {
  final String surfaceId;
  final Map<String, A2UIComponent> components;
  final String? rootId;
  final Map<String, dynamic> dataModel;

  _SurfaceSnapshot({
    required this.surfaceId,
    required this.components,
    required this.rootId,
    required this.dataModel,
  });

  factory _SurfaceSnapshot.capture(A2UISurface surface) {
    // Deep-clone components
    final clonedComponents = <String, A2UIComponent>{};
    for (final entry in surface.components.entries) {
      clonedComponents[entry.key] = A2UIComponent(
        id: entry.value.id,
        type: entry.value.type,
        props: jsonDecode(jsonEncode(entry.value.props)) as Map<String, dynamic>,
        weight: entry.value.weight,
      );
    }
    return _SurfaceSnapshot(
      surfaceId: surface.surfaceId,
      components: clonedComponents,
      rootId: surface.rootId,
      dataModel: jsonDecode(jsonEncode(surface.dataModel)) as Map<String, dynamic>,
    );
  }

  void restore(A2UISurface surface) {
    surface.components.clear();
    surface.components.addAll(components);
    surface.rootId = rootId;
    surface.dataModel.clear();
    surface.dataModel.addAll(dataModel);
  }
}

class UndoRedoManager {
  static const int maxStackDepth = 50;
  final List<Map<String, _SurfaceSnapshot>> _undoStack = [];
  final List<Map<String, _SurfaceSnapshot>> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Capture current state before a user edit.
  void pushSnapshot(Map<String, A2UISurface> surfaces) {
    final snap = <String, _SurfaceSnapshot>{};
    for (final entry in surfaces.entries) {
      snap[entry.key] = _SurfaceSnapshot.capture(entry.value);
    }
    _undoStack.add(snap);
    if (_undoStack.length > maxStackDepth) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// Undo: restore previous snapshot, push current to redo.
  bool undo(Map<String, A2UISurface> surfaces) {
    if (_undoStack.isEmpty) return false;
    // Save current to redo
    final current = <String, _SurfaceSnapshot>{};
    for (final entry in surfaces.entries) {
      current[entry.key] = _SurfaceSnapshot.capture(entry.value);
    }
    _redoStack.add(current);
    // Restore
    final snap = _undoStack.removeLast();
    for (final entry in snap.entries) {
      if (surfaces.containsKey(entry.key)) {
        entry.value.restore(surfaces[entry.key]!);
      }
    }
    return true;
  }

  /// Redo: restore next snapshot, push current to undo.
  bool redo(Map<String, A2UISurface> surfaces) {
    if (_redoStack.isEmpty) return false;
    final current = <String, _SurfaceSnapshot>{};
    for (final entry in surfaces.entries) {
      current[entry.key] = _SurfaceSnapshot.capture(entry.value);
    }
    _undoStack.add(current);
    final snap = _redoStack.removeLast();
    for (final entry in snap.entries) {
      if (surfaces.containsKey(entry.key)) {
        entry.value.restore(surfaces[entry.key]!);
      }
    }
    return true;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}

// =============================================================================
// Component palette — component type catalog with defaults
// =============================================================================

class ComponentTemplate {
  final String type;
  final String label;
  final IconData icon;
  final String category;
  /// Creates a default component with the given ID.
  final A2UIComponent Function(String id) create;

  const ComponentTemplate({
    required this.type,
    required this.label,
    required this.icon,
    required this.category,
    required this.create,
  });
}

int _nextId = 0;
String genComponentId() => 'user-${_nextId++}';

final List<ComponentTemplate> componentTemplates = [
  // Layout
  ComponentTemplate(
    type: 'Column', label: 'Column', icon: Icons.view_column_outlined,
    category: 'Layout',
    create: (id) => A2UIComponent(id: id, type: 'Column', props: {
      'children': {'explicitList': <String>[]},
    }),
  ),
  ComponentTemplate(
    type: 'Row', label: 'Row', icon: Icons.table_rows_outlined,
    category: 'Layout',
    create: (id) => A2UIComponent(id: id, type: 'Row', props: {
      'children': {'explicitList': <String>[]},
    }),
  ),
  ComponentTemplate(
    type: 'Divider', label: 'Divider', icon: Icons.horizontal_rule,
    category: 'Layout',
    create: (id) => A2UIComponent(id: id, type: 'Divider', props: {
      'axis': 'horizontal',
    }),
  ),
  ComponentTemplate(
    type: 'Spacer', label: 'Spacer', icon: Icons.space_bar,
    category: 'Layout',
    create: (id) => A2UIComponent(id: id, type: 'Spacer', props: {
      'height': 16,
    }),
  ),
  // Display
  ComponentTemplate(
    type: 'Text', label: 'Text', icon: Icons.text_fields,
    category: 'Display',
    create: (id) => A2UIComponent(id: id, type: 'Text', props: {
      'text': {'literalString': 'New text'},
      'usageHint': 'body',
    }),
  ),
  ComponentTemplate(
    type: 'Image', label: 'Image', icon: Icons.image,
    category: 'Display',
    create: (id) => A2UIComponent(id: id, type: 'Image', props: {
      'url': {'literalString': ''},
    }),
  ),
  ComponentTemplate(
    type: 'Icon', label: 'Icon', icon: Icons.star_border,
    category: 'Display',
    create: (id) => A2UIComponent(id: id, type: 'Icon', props: {
      'name': {'literalString': 'star'},
    }),
  ),
  ComponentTemplate(
    type: 'Progress', label: 'Progress', icon: Icons.linear_scale,
    category: 'Display',
    create: (id) => A2UIComponent(id: id, type: 'Progress', props: {
      'value': 0.5,
    }),
  ),
  // Interactive
  ComponentTemplate(
    type: 'Button', label: 'Button', icon: Icons.smart_button,
    category: 'Interactive',
    create: (id) {
      final textId = '${id}-label';
      // Note: caller must also add the child text component
      return A2UIComponent(id: id, type: 'Button', props: {
        'child': textId,
        'primary': false,
        'action': {'name': 'click_$id'},
      });
    },
  ),
  ComponentTemplate(
    type: 'TextField', label: 'TextField', icon: Icons.text_snippet_outlined,
    category: 'Interactive',
    create: (id) => A2UIComponent(id: id, type: 'TextField', props: {
      'label': {'literalString': 'Label'},
      'placeholder': 'Enter text...',
      'textFieldType': 'shortText',
      'text': {'path': '/user-input/$id'},
    }),
  ),
  ComponentTemplate(
    type: 'CheckBox', label: 'CheckBox', icon: Icons.check_box_outlined,
    category: 'Interactive',
    create: (id) => A2UIComponent(id: id, type: 'CheckBox', props: {
      'label': {'literalString': 'Check me'},
      'value': {'path': '/user-input/$id'},
    }),
  ),
  ComponentTemplate(
    type: 'Toggle', label: 'Toggle', icon: Icons.toggle_on_outlined,
    category: 'Interactive',
    create: (id) => A2UIComponent(id: id, type: 'Toggle', props: {
      'label': {'literalString': 'Toggle'},
      'value': {'path': '/user-input/$id'},
    }),
  ),
  ComponentTemplate(
    type: 'Slider', label: 'Slider', icon: Icons.tune,
    category: 'Interactive',
    create: (id) => A2UIComponent(id: id, type: 'Slider', props: {
      'min': 0, 'max': 100,
      'value': {'path': '/user-input/$id'},
    }),
  ),
  // Containers
  ComponentTemplate(
    type: 'Card', label: 'Card', icon: Icons.crop_square,
    category: 'Container',
    create: (id) => A2UIComponent(id: id, type: 'Card', props: {
      'children': {'explicitList': <String>[]},
    }),
  ),
  ComponentTemplate(
    type: 'Tabs', label: 'Tabs', icon: Icons.tab,
    category: 'Container',
    create: (id) => A2UIComponent(id: id, type: 'Tabs', props: {
      'tabItems': <Map<String, dynamic>>[],
    }),
  ),
  ComponentTemplate(
    type: 'CodeEditor', label: 'CodeEditor', icon: Icons.code,
    category: 'Display',
    create: (id) => A2UIComponent(id: id, type: 'CodeEditor', props: {
      'code': {'literalString': '// your code here'},
      'language': {'literalString': 'dart'},
      'editable': false,
      'lineNumbers': true,
    }),
  ),
];

// =============================================================================
// Component Palette Widget
// =============================================================================

class ComponentPalette extends StatefulWidget {
  final void Function(ComponentTemplate template) onAdd;
  final ShellTokens tokens;

  const ComponentPalette({
    super.key,
    required this.onAdd,
    required this.tokens,
  });

  @override
  State<ComponentPalette> createState() => _ComponentPaletteState();
}

class _ComponentPaletteState extends State<ComponentPalette> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return TapRegion(
      onTapOutside: (_) {
        if (_expanded) setState(() => _expanded = false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadiusSm,
                  color: t.surfaceBase.withOpacity(0.8),
                  border: Border.all(color: t.border, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 11, color: t.accentPrimary),
                    const SizedBox(width: 3),
                    Text('add', style: TextStyle(fontSize: 10, color: t.fgSecondary)),
                    const SizedBox(width: 2),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 10, color: t.fgMuted),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 2),
            Container(
              width: 160,
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                borderRadius: kShellBorderRadiusSm,
                color: t.surfaceBase,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 2),
                children: _buildGroupedList(t),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildGroupedList(ShellTokens t) {
    final groups = <String, List<ComponentTemplate>>{};
    for (final tmpl in componentTemplates) {
      groups.putIfAbsent(tmpl.category, () => []).add(tmpl);
    }
    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2),
        child: Text(entry.key,
            style: TextStyle(fontSize: 9, color: t.fgMuted, letterSpacing: 0.8)),
      ));
      for (final tmpl in entry.value) {
        widgets.add(_PaletteItem(
          template: tmpl,
          tokens: t,
          onTap: () {
            widget.onAdd(tmpl);
            setState(() => _expanded = false);
          },
        ));
      }
    }
    return widgets;
  }
}

class _PaletteItem extends StatefulWidget {
  final ComponentTemplate template;
  final ShellTokens tokens;
  final VoidCallback onTap;

  const _PaletteItem({
    required this.template,
    required this.tokens,
    required this.onTap,
  });

  @override
  State<_PaletteItem> createState() => _PaletteItemState();
}

class _PaletteItemState extends State<_PaletteItem> {
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: _hovering ? t.surfaceCard : Colors.transparent,
          child: Row(
            children: [
              Icon(widget.template.icon, size: 12, color: t.fgMuted),
              const SizedBox(width: 6),
              Text(widget.template.label,
                  style: TextStyle(fontSize: 10, color: t.fgSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Selection overlay — wraps each component in edit mode
// =============================================================================

class EditableComponentWrapper extends StatefulWidget {
  final Widget child;
  final String componentId;
  final bool isSelected;
  final VoidCallback onSelect;
  final ShellTokens tokens;

  const EditableComponentWrapper({
    super.key,
    required this.child,
    required this.componentId,
    required this.isSelected,
    required this.onSelect,
    required this.tokens,
  });

  @override
  State<EditableComponentWrapper> createState() => _EditableComponentWrapperState();
}

class _EditableComponentWrapperState extends State<EditableComponentWrapper> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final showBorder = widget.isSelected || _hovering;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            border: showBorder
                ? Border.all(
                    color: widget.isSelected
                        ? t.accentPrimary
                        : t.accentPrimary.withOpacity(0.3),
                    width: widget.isSelected ? 1.0 : 0.5,
                  )
                : Border.all(color: Colors.transparent, width: 1.0),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(1),
                child: widget.child,
              ),
              // Component type badge on hover/select
              if (showBorder)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? t.accentPrimary
                          : t.accentPrimary.withOpacity(0.7),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(2),
                        topRight: Radius.circular(2),
                      ),
                    ),
                    child: Text(
                      widget.componentId,
                      style: TextStyle(
                        fontSize: 8,
                        color: t.surfaceBase,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Property Inspector — right-side panel
// =============================================================================

class PropertyInspector extends StatefulWidget {
  final A2UIComponent component;
  final A2UISurface surface;
  final ShellTokens tokens;
  final ThemeData theme;
  final OnSurfaceEdited onEdited;
  final VoidCallback onDelete;
  final VoidCallback onDeselect;
  final void Function(int oldIndex, int newIndex)? onReorder;

  const PropertyInspector({
    super.key,
    required this.component,
    required this.surface,
    required this.tokens,
    required this.theme,
    required this.onEdited,
    required this.onDelete,
    required this.onDeselect,
    this.onReorder,
  });

  @override
  State<PropertyInspector> createState() => _PropertyInspectorState();
}

class _PropertyInspectorState extends State<PropertyInspector> {
  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final c = widget.component;
    _propFieldIndex = 0; // Reset per build

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: t.surfaceBase,
        border: Border(left: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, size: 12, color: t.accentPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('properties',
                      style: TextStyle(fontSize: 10, color: t.fgSecondary,
                          letterSpacing: 0.5)),
                ),
                GestureDetector(
                  onTap: widget.onDeselect,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.close, size: 12, color: t.fgMuted),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // ID (read only)
                _readOnlyField('id', c.id, t),
                const SizedBox(height: 6),
                // Type (read only)
                _readOnlyField('type', c.type, t),
                const SizedBox(height: 6),
                // Move up/down buttons
                _buildMoveButtons(c, t),
                const SizedBox(height: 8),
                Divider(color: t.border, height: 1),
                const SizedBox(height: 8),
                // Type-specific property editors
                ..._buildPropEditors(c, t),
                const SizedBox(height: 16),
                // Weight editor
                _weightEditor(c, t),
                const SizedBox(height: 16),
                Divider(color: t.border, height: 1),
                const SizedBox(height: 8),
                // Delete button
                GestureDetector(
                  onTap: widget.onDelete,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: kShellBorderRadiusSm,
                        border: Border.all(color: t.statusError.withOpacity(0.3), width: 0.5),
                      ),
                      child: Center(
                        child: Text('delete component',
                            style: TextStyle(fontSize: 10, color: t.statusError)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveButtons(A2UIComponent c, ShellTokens t) {
    final parent = findParent(c.id, widget.surface);
    if (parent == null) return const SizedBox.shrink();
    final siblings = resolveChildIds(parent);
    final index = siblings.indexOf(c.id);
    if (index < 0) return const SizedBox.shrink();
    final canMoveUp = index > 0;
    final canMoveDown = index < siblings.length - 1;
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text('order',
              style: TextStyle(fontSize: 9, color: t.fgMuted, letterSpacing: 0.3)),
        ),
        _moveButton(Icons.arrow_upward, canMoveUp, t, () {
          widget.onReorder?.call(index, index - 1);
        }),
        const SizedBox(width: 4),
        _moveButton(Icons.arrow_downward, canMoveDown, t, () {
          widget.onReorder?.call(index, index + 1);
        }),
      ],
    );
  }

  Widget _moveButton(IconData icon, bool enabled, ShellTokens t, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Icon(icon, size: 10,
              color: enabled ? t.fgSecondary : t.fgDisabled),
        ),
      ),
    );
  }

  Widget _readOnlyField(String label, String value, ShellTokens t) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label,
              style: TextStyle(fontSize: 9, color: t.fgMuted, letterSpacing: 0.3)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(fontSize: 10, color: t.fgSecondary),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _weightEditor(A2UIComponent c, ShellTokens t) {
    final currentWeight = c.weight?.toDouble() ?? 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('flex weight',
            style: TextStyle(fontSize: 9, color: t.fgMuted, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: currentWeight.clamp(1.0, 10.0),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: t.accentPrimary,
                onChanged: (v) {
                  _updateComponent(c, weight: v.round());
                },
              ),
            ),
            SizedBox(
              width: 24,
              child: Text('${currentWeight.round()}',
                  style: TextStyle(fontSize: 10, color: t.fgSecondary),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildPropEditors(A2UIComponent c, ShellTokens t) {
    switch (c.type) {
      case 'Text':
        return _textProps(c, t);
      case 'Button':
        return _buttonProps(c, t);
      case 'Image':
        return _imageProps(c, t);
      case 'Icon':
        return _iconProps(c, t);
      case 'TextField':
        return _textFieldProps(c, t);
      case 'CheckBox':
      case 'Toggle':
        return _labelProps(c, t);
      case 'Slider':
        return _sliderProps(c, t);
      case 'Progress':
        return _progressProps(c, t);
      case 'Spacer':
        return _spacerProps(c, t);
      case 'Divider':
        return _dividerProps(c, t);
      case 'Column':
      case 'Row':
        return _layoutProps(c, t);
      case 'Card':
        return _cardProps(c, t);
      case 'CodeEditor':
        return _codeEditorProps(c, t);
      default:
        return [Text('no editable properties',
            style: TextStyle(fontSize: 9, color: t.fgMuted))];
    }
  }

  // --- Text props ---
  List<Widget> _textProps(A2UIComponent c, ShellTokens t) {
    final textVal = _extractLiteral(c.props['text']) ?? '';
    final usageHint = c.props['usageHint'] as String? ?? 'body';
    return [
      _propLabel('text', t),
      _propTextField(textVal, t, (v) {
        c.props['text'] = {'literalString': v};
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('usageHint', t),
      _propDropdown(usageHint, ['h1', 'h2', 'h3', 'h4', 'h5', 'body', 'caption', 'label'], t,
          (v) {
        c.props['usageHint'] = v;
        widget.onEdited();
      }),
    ];
  }

  // --- Button props ---
  List<Widget> _buttonProps(A2UIComponent c, ShellTokens t) {
    final primary = c.props['primary'] as bool? ?? false;
    final actionRaw = c.props['action'];
    final actionName = actionRaw is Map ? (actionRaw['name'] as String? ?? '') : (actionRaw as String? ?? '');
    return [
      _propLabel('primary', t),
      _propToggle(primary, t, (v) {
        c.props['primary'] = v;
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('action name', t),
      _propTextField(actionName, t, (v) {
        if (c.props['action'] is Map) {
          (c.props['action'] as Map)['name'] = v;
        } else {
          c.props['action'] = {'name': v};
        }
        widget.onEdited();
      }),
    ];
  }

  // --- Image props ---
  List<Widget> _imageProps(A2UIComponent c, ShellTokens t) {
    final url = _extractLiteral(c.props['url']) ?? '';
    return [
      _propLabel('url', t),
      _propTextField(url, t, (v) {
        c.props['url'] = {'literalString': v};
        widget.onEdited();
      }),
    ];
  }

  // --- Icon props ---
  List<Widget> _iconProps(A2UIComponent c, ShellTokens t) {
    final name = _extractLiteral(c.props['name']) ?? 'star';
    return [
      _propLabel('name', t),
      _propTextField(name, t, (v) {
        c.props['name'] = {'literalString': v};
        widget.onEdited();
      }),
    ];
  }

  // --- TextField props ---
  List<Widget> _textFieldProps(A2UIComponent c, ShellTokens t) {
    final label = _extractLiteral(c.props['label']) ?? '';
    final placeholder = c.props['placeholder'] as String? ?? '';
    final type = c.props['textFieldType'] as String? ?? 'shortText';
    return [
      _propLabel('label', t),
      _propTextField(label, t, (v) {
        c.props['label'] = {'literalString': v};
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('placeholder', t),
      _propTextField(placeholder, t, (v) {
        c.props['placeholder'] = v;
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('type', t),
      _propDropdown(type, ['shortText', 'longText', 'number', 'date', 'obscured'], t, (v) {
        c.props['textFieldType'] = v;
        widget.onEdited();
      }),
    ];
  }

  // --- CheckBox/Toggle label ---
  List<Widget> _labelProps(A2UIComponent c, ShellTokens t) {
    final label = _extractLiteral(c.props['label']) ?? '';
    return [
      _propLabel('label', t),
      _propTextField(label, t, (v) {
        c.props['label'] = {'literalString': v};
        widget.onEdited();
      }),
    ];
  }

  // --- Slider props ---
  List<Widget> _sliderProps(A2UIComponent c, ShellTokens t) {
    final min = (c.props['min'] as num?)?.toDouble() ?? 0;
    final max = (c.props['max'] as num?)?.toDouble() ?? 100;
    return [
      _propLabel('min', t),
      _propTextField(min.toString(), t, (v) {
        c.props['min'] = double.tryParse(v) ?? 0;
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('max', t),
      _propTextField(max.toString(), t, (v) {
        c.props['max'] = double.tryParse(v) ?? 100;
        widget.onEdited();
      }),
    ];
  }

  // --- Progress props ---
  List<Widget> _progressProps(A2UIComponent c, ShellTokens t) {
    final value = (c.props['value'] as num?)?.toDouble() ?? 0.5;
    return [
      _propLabel('value (0-1)', t),
      Slider(
        value: value.clamp(0.0, 1.0),
        min: 0,
        max: 1,
        activeColor: t.accentPrimary,
        onChanged: (v) {
          c.props['value'] = double.parse(v.toStringAsFixed(2));
          widget.onEdited();
        },
      ),
    ];
  }

  // --- Spacer props ---
  List<Widget> _spacerProps(A2UIComponent c, ShellTokens t) {
    final height = (c.props['height'] as num?)?.toDouble() ?? 16;
    return [
      _propLabel('height', t),
      _propTextField(height.toString(), t, (v) {
        c.props['height'] = double.tryParse(v) ?? 16;
        widget.onEdited();
      }),
    ];
  }

  // --- Divider props ---
  List<Widget> _dividerProps(A2UIComponent c, ShellTokens t) {
    final axis = c.props['axis'] as String? ?? 'horizontal';
    return [
      _propLabel('axis', t),
      _propDropdown(axis, ['horizontal', 'vertical'], t, (v) {
        c.props['axis'] = v;
        widget.onEdited();
      }),
    ];
  }

  // --- Column/Row props ---
  List<Widget> _layoutProps(A2UIComponent c, ShellTokens t) {
    final distribution = c.props['distribution'] as String? ?? 'start';
    final alignment = c.props['alignment'] as String? ?? 'start';
    return [
      _propLabel('distribution', t),
      _propDropdown(distribution,
          ['start', 'center', 'end', 'spaceBetween', 'spaceAround', 'spaceEvenly'], t, (v) {
        c.props['distribution'] = v;
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('alignment', t),
      _propDropdown(alignment, ['start', 'center', 'end', 'stretch'], t, (v) {
        c.props['alignment'] = v;
        widget.onEdited();
      }),
    ];
  }

  // --- Card props ---
  List<Widget> _cardProps(A2UIComponent c, ShellTokens t) {
    return [
      Text('children are managed via the canvas',
          style: TextStyle(fontSize: 9, color: t.fgMuted)),
    ];
  }

  // --- CodeEditor props ---
  List<Widget> _codeEditorProps(A2UIComponent c, ShellTokens t) {
    final lang = _extractLiteral(c.props['language']) ?? 'dart';
    final editable = c.props['editable'] == true;
    final lineNumbers = c.props['lineNumbers'] != false;
    return [
      _propLabel('language', t),
      _propTextField(lang, t, (v) {
        c.props['language'] = {'literalString': v};
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('editable', t),
      _propToggle(editable, t, (v) {
        c.props['editable'] = v;
        widget.onEdited();
      }),
      const SizedBox(height: 6),
      _propLabel('lineNumbers', t),
      _propToggle(lineNumbers, t, (v) {
        c.props['lineNumbers'] = v;
        widget.onEdited();
      }),
    ];
  }

  // --- Generic property widgets ---

  Widget _propLabel(String label, ShellTokens t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(label,
          style: TextStyle(fontSize: 9, color: t.fgMuted, letterSpacing: 0.3)),
    );
  }

  // Track a counter to give each prop text field a stable key within
  // this inspector instance (reset per build via the stateful widget key).
  int _propFieldIndex = 0;

  Widget _propTextField(String value, ShellTokens t, ValueChanged<String> onChanged) {
    final idx = _propFieldIndex++;
    return _PropTextField(
      key: ValueKey('ptf-${widget.component.id}-$idx'),
      value: value,
      tokens: t,
      onChanged: onChanged,
    );
  }

  Widget _propDropdown(
      String value, List<String> options, ShellTokens t, ValueChanged<String> onChanged) {
    // Ensure value is in options
    if (!options.contains(value)) {
      value = options.first;
    }
    return SizedBox(
      height: 28,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: kShellBorderRadiusSm,
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: TextStyle(fontSize: 10, color: t.fgPrimary),
          dropdownColor: t.surfaceBase,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _propToggle(bool value, ShellTokens t, ValueChanged<bool> onChanged) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 24,
        child: Switch(
          value: value,
          activeColor: t.accentPrimary,
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _updateComponent(A2UIComponent c, {int? weight}) {
    if (weight != null) {
      // A2UIComponent is not truly immutable (props is mutable Map),
      // but weight is final. We need to replace the component.
      final newComp = A2UIComponent(
        id: c.id,
        type: c.type,
        props: c.props,
        weight: weight,
      );
      widget.surface.components[c.id] = newComp;
      widget.onEdited();
    }
  }

  String? _extractLiteral(dynamic prop) {
    if (prop is String) return prop;
    if (prop is Map) {
      return (prop['literalString'] ?? prop['value'])?.toString();
    }
    return prop?.toString();
  }
}

// =============================================================================
// Property text field with proper controller lifecycle
// =============================================================================

class _PropTextField extends StatefulWidget {
  final String value;
  final ShellTokens tokens;
  final ValueChanged<String> onChanged;

  const _PropTextField({
    super.key,
    required this.value,
    required this.tokens,
    required this.onChanged,
  });

  @override
  State<_PropTextField> createState() => _PropTextFieldState();
}

class _PropTextFieldState extends State<_PropTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _PropTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection =
          TextSelection.collapsed(offset: widget.value.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return SizedBox(
      height: 28,
      child: TextField(
        controller: _controller,
        style: TextStyle(fontSize: 10, color: t.fgPrimary),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: kShellBorderRadiusSm,
            borderSide: BorderSide(color: t.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: kShellBorderRadiusSm,
            borderSide: BorderSide(color: t.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: kShellBorderRadiusSm,
            borderSide: BorderSide(color: t.accentPrimary, width: 0.5),
          ),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

// =============================================================================
// Helpers: find parent of a component, resolve children
// =============================================================================

/// Find the parent component that contains [childId] in its children list.
A2UIComponent? findParent(String childId, A2UISurface surface) {
  for (final comp in surface.components.values) {
    final childIds = resolveChildIds(comp);
    if (childIds.contains(childId)) return comp;
  }
  return null;
}

/// Get child IDs from a component's children/child prop.
List<String> resolveChildIds(A2UIComponent comp) {
  final childrenProp = comp.props['children'];
  if (childrenProp is List) {
    return childrenProp.where((e) => e != null).map((e) => e.toString()).toList();
  }
  if (childrenProp is Map) {
    final explicit = childrenProp['explicitList'];
    if (explicit is List) {
      return explicit.where((e) => e != null).map((e) => e.toString()).toList();
    }
  }
  // Single child
  final child = comp.props['child'];
  if (child is String) return [child];
  return [];
}

/// Set child IDs on a component (Column, Row, Card, etc.)
void setChildIds(A2UIComponent comp, List<String> ids) {
  if (comp.props['children'] is Map) {
    (comp.props['children'] as Map)['explicitList'] = ids;
  } else {
    comp.props['children'] = {'explicitList': ids};
  }
}

/// Check if a component type is a container (can hold children).
bool isContainer(String type) {
  return const {'Column', 'Row', 'Card', 'List'}.contains(type);
}

/// Remove a component and its descendants from a surface. Also remove it from
/// its parent's child list.
void removeComponent(String componentId, A2UISurface surface) {
  // Remove from parent
  final parent = findParent(componentId, surface);
  if (parent != null) {
    final ids = resolveChildIds(parent);
    ids.remove(componentId);
    setChildIds(parent, ids);
  }
  // Cascade remove children
  _cascadeRemove(componentId, surface);
}

void _cascadeRemove(String id, A2UISurface surface) {
  final comp = surface.components.remove(id);
  if (comp == null) return;
  for (final childId in resolveChildIds(comp)) {
    _cascadeRemove(childId, surface);
  }
  // Also handle Button child
  final child = comp.props['child'];
  if (child is String) {
    _cascadeRemove(child, surface);
  }
}

/// Serialize surfaces to JSONL for sending to agent.
String surfacesToJsonl(Map<String, A2UISurface> surfaces) {
  final lines = <String>[];
  for (final surface in surfaces.values) {
    if (surface.rootId == null) continue;
    // surfaceUpdate with all components
    final components = surface.components.values.map((c) {
      final compMap = <String, dynamic>{
        'id': c.id,
        'component': {c.type: c.props},
      };
      if (c.weight != null) compMap['weight'] = c.weight;
      return compMap;
    }).toList();
    lines.add(jsonEncode({
      'surfaceUpdate': {
        'surfaceId': surface.surfaceId,
        'components': components,
      }
    }));
    // beginRendering
    lines.add(jsonEncode({
      'beginRendering': {
        'surfaceId': surface.surfaceId,
        'root': surface.rootId,
      }
    }));
    // dataModelUpdate if non-empty
    if (surface.dataModel.isNotEmpty) {
      final contents = _mapToContents(surface.dataModel);
      lines.add(jsonEncode({
        'dataModelUpdate': {
          'surfaceId': surface.surfaceId,
          'contents': contents,
        }
      }));
    }
  }
  return lines.join('\n');
}

List<Map<String, dynamic>> _mapToContents(Map<String, dynamic> map) {
  final contents = <Map<String, dynamic>>[];
  for (final entry in map.entries) {
    final val = entry.value;
    if (val is String) {
      contents.add({'key': entry.key, 'valueString': val});
    } else if (val is num) {
      contents.add({'key': entry.key, 'valueNumber': val});
    } else if (val is bool) {
      contents.add({'key': entry.key, 'valueBoolean': val});
    } else if (val is Map<String, dynamic>) {
      contents.add({'key': entry.key, 'valueMap': _mapToContents(val)});
    } else if (val is List) {
      contents.add({'key': entry.key, 'valueArray': val});
    }
  }
  return contents;
}
