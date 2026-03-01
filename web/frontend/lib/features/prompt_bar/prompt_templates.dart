import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class PromptTemplate {
  final String name;
  final String content;
  final String category;

  const PromptTemplate({
    required this.name,
    required this.content,
    this.category = 'custom',
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'content': content, 'category': category,
  };

  factory PromptTemplate.fromJson(Map<String, dynamic> json) => PromptTemplate(
    name: json['name'] as String? ?? '',
    content: json['content'] as String? ?? '',
    category: json['category'] as String? ?? 'custom',
  );
}

const _storageKey = 'trinity_prompt_templates';

const _builtInTemplates = <PromptTemplate>[
  PromptTemplate(name: 'Summarize', content: 'Summarize the following:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Explain Code', content: 'Explain this code in detail:\n\n```\n\n```', category: 'built-in'),
  PromptTemplate(name: 'Debug', content: 'Help me debug this issue:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Refactor', content: 'Refactor the following code for clarity and performance:\n\n```\n\n```', category: 'built-in'),
  PromptTemplate(name: 'Write Tests', content: 'Write comprehensive tests for:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Code Review', content: 'Review this code and suggest improvements:\n\n```\n\n```', category: 'built-in'),
  PromptTemplate(name: 'Documentation', content: 'Write documentation for the following:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Canvas Dashboard', content: 'Build a dashboard on the canvas showing:\n\n', category: 'built-in'),
];

class PromptTemplateStore {
  static List<PromptTemplate> loadCustom() {
    final stored = html.window.localStorage[_storageKey];
    if (stored == null || stored.isEmpty) return [];
    try {
      final list = jsonDecode(stored) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((j) => PromptTemplate.fromJson(j))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void saveCustom(List<PromptTemplate> templates) {
    final json = templates.map((t) => t.toJson()).toList();
    html.window.localStorage[_storageKey] = jsonEncode(json);
  }

  static List<PromptTemplate> all() {
    return [..._builtInTemplates, ...loadCustom()];
  }

  static void addCustom(PromptTemplate template) {
    final custom = loadCustom();
    custom.add(template);
    saveCustom(custom);
  }

  static void removeCustom(String name) {
    final custom = loadCustom();
    custom.removeWhere((t) => t.name == name);
    saveCustom(custom);
  }
}

class PromptTemplatePanel extends StatefulWidget {
  final void Function(String content) onSelect;
  final String filter;

  const PromptTemplatePanel({
    super.key,
    required this.onSelect,
    this.filter = '',
  });

  @override
  State<PromptTemplatePanel> createState() => _PromptTemplatePanelState();
}

class _PromptTemplatePanelState extends State<PromptTemplatePanel> {
  late List<PromptTemplate> _templates;

  @override
  void initState() {
    super.initState();
    _templates = PromptTemplateStore.all();
  }

  List<PromptTemplate> get _filtered {
    if (widget.filter.isEmpty) return _templates;
    final q = widget.filter.toLowerCase();
    return _templates.where((t) =>
      t.name.toLowerCase().contains(q) ||
      t.category.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: t.surfaceBase,
        border: Border.all(color: t.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Text('templates',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
          ),
          // Templates list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final tmpl = _filtered[index];
                return _TemplateRow(
                  template: tmpl,
                  tokens: t,
                  theme: theme,
                  onSelect: () => widget.onSelect(tmpl.content),
                  onDelete: tmpl.category == 'custom'
                      ? () {
                          PromptTemplateStore.removeCustom(tmpl.name);
                          setState(() {
                            _templates = PromptTemplateStore.all();
                          });
                        }
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatefulWidget {
  final PromptTemplate template;
  final ShellTokens tokens;
  final ThemeData theme;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  const _TemplateRow({
    required this.template,
    required this.tokens,
    required this.theme,
    required this.onSelect,
    this.onDelete,
  });

  @override
  State<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends State<_TemplateRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: _hovering ? t.surfaceCard : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.template.name,
                      style: widget.theme.textTheme.labelSmall?.copyWith(
                        color: t.fgSecondary, fontSize: 11)),
                    Text(widget.template.content.replaceAll('\n', ' ').trim(),
                      style: TextStyle(fontSize: 9, color: t.fgMuted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: t.border, width: 0.5),
                ),
                child: Text(widget.template.category,
                  style: TextStyle(fontSize: 8, color: t.fgDisabled)),
              ),
              if (widget.onDelete != null && _hovering)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Icon(Icons.close, size: 10, color: t.fgMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
