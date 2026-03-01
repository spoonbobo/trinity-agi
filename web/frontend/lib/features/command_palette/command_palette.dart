import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class CommandItem {
  final String label;
  final String? description;
  final IconData icon;
  final VoidCallback action;
  final String category;

  const CommandItem({
    required this.label,
    this.description,
    required this.icon,
    required this.action,
    this.category = 'general',
  });
}

class CommandPalette extends StatefulWidget {
  final List<CommandItem> commands;

  const CommandPalette({super.key, required this.commands});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;
  List<CommandItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.commands;
    _controller.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _controller.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.commands;
      } else {
        _filtered = widget.commands.where((cmd) {
          return cmd.label.toLowerCase().contains(query) ||
              (cmd.description?.toLowerCase().contains(query) ?? false) ||
              cmd.category.toLowerCase().contains(query);
        }).toList();
      }
      _selectedIndex = 0;
    });
  }

  void _execute(CommandItem item) {
    Navigator.of(context).pop();
    item.action();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_filtered.isNotEmpty) {
        _execute(_filtered[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Align(
      alignment: const Alignment(0, -0.3),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadius,
            color: t.surfaceBase,
            border: Border.all(color: t.border, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t.border, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 14, color: t.fgMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'type a command...',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            isDense: true,
                          ),
                        ),
                      ),
                      Text('esc',
                        style: TextStyle(fontSize: 9, color: t.fgDisabled)),
                    ],
                  ),
                ),
                // Results
                if (_filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('no results',
                      style: TextStyle(fontSize: 11, color: t.fgMuted)),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final item = _filtered[index];
                        final isSelected = index == _selectedIndex;
                        return _CommandRow(
                          item: item,
                          isSelected: isSelected,
                          tokens: t,
                          theme: theme,
                          onTap: () => _execute(item),
                          onHover: () {
                            if (_selectedIndex != index) {
                              setState(() => _selectedIndex = index);
                            }
                          },
                        );
                      },
                    ),
                  ),
                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: t.border, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text('arrows to navigate',
                        style: TextStyle(fontSize: 9, color: t.fgDisabled)),
                      const SizedBox(width: 12),
                      Text('enter to select',
                        style: TextStyle(fontSize: 9, color: t.fgDisabled)),
                      const Spacer(),
                      Text('ctrl+k',
                        style: TextStyle(fontSize: 9, color: t.fgDisabled)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandRow extends StatefulWidget {
  final CommandItem item;
  final bool isSelected;
  final ShellTokens tokens;
  final ThemeData theme;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _CommandRow({
    required this.item,
    required this.isSelected,
    required this.tokens,
    required this.theme,
    required this.onTap,
    required this.onHover,
  });

  @override
  State<_CommandRow> createState() => _CommandRowState();
}

class _CommandRowState extends State<_CommandRow> {
  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onHover(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: widget.isSelected
              ? t.accentPrimary.withOpacity(0.08)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(widget.item.icon, size: 14,
                color: widget.isSelected ? t.accentPrimary : t.fgMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: widget.theme.textTheme.bodyMedium?.copyWith(
                    color: widget.isSelected ? t.fgPrimary : t.fgSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.item.description != null)
                Text(
                  widget.item.description!,
                  style: TextStyle(fontSize: 10, color: t.fgMuted),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadiusSm,
                  border: Border.all(color: t.border, width: 0.5),
                ),
                child: Text(
                  widget.item.category,
                  style: TextStyle(fontSize: 8, color: t.fgDisabled),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
