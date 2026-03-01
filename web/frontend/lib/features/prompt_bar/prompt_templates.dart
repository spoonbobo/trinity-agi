import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/dialog_service.dart';
import 'prompt_template_manager.dart';

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
  PromptTemplate(name: 'Summarize', content: 'Summarize the following in clear, concise bullet points:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Explain', content: 'Explain this in simple terms that anyone can understand:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Rewrite', content: 'Rewrite the following to be clearer and more professional:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Translate', content: 'Translate the following to [language]:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Brainstorm', content: 'Help me brainstorm ideas for:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Draft Email', content: 'Draft a professional email about:\n\nTone: [formal/friendly/casual]\nTo: [recipient]\n\n', category: 'built-in'),
  PromptTemplate(name: 'Pros and Cons', content: 'List the pros and cons of:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Action Items', content: 'Extract the action items and next steps from:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Canvas Dashboard', content: 'Build a dashboard on the canvas showing:\n\n', category: 'built-in'),
  PromptTemplate(name: 'Compare', content: 'Compare and contrast the following options:\n\n1. \n2. \n\nConsider: cost, quality, ease of use, and timeline.', category: 'built-in'),
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

  static void updateCustom(String oldName, PromptTemplate updated) {
    final custom = loadCustom();
    final idx = custom.indexWhere((t) => t.name == oldName);
    if (idx >= 0) {
      custom[idx] = updated;
    } else {
      custom.add(updated);
    }
    saveCustom(custom);
  }
}

class PromptTemplatePanel extends StatefulWidget {
  final void Function(String content) onSelect;
  final VoidCallback? onDismiss;
  final String filter;
  final int activeIndex;

  const PromptTemplatePanel({
    super.key,
    required this.onSelect,
    this.onDismiss,
    this.filter = '',
    this.activeIndex = 0,
  });

  @override
  State<PromptTemplatePanel> createState() => _PromptTemplatePanelState();
}

class _PromptTemplatePanelState extends State<PromptTemplatePanel> {
  late List<PromptTemplate> _templates;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _templates = PromptTemplateStore.all();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PromptTemplatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to active item when activeIndex changes
    if (widget.activeIndex != oldWidget.activeIndex && _filtered.isNotEmpty) {
      final clampedIdx = widget.activeIndex.clamp(0, _filtered.length - 1);
      // Each row is approximately 36px tall
      final targetOffset = clampedIdx * 36.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          _scrollController.animateTo(
            targetOffset.clamp(0.0, maxScroll),
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
          );
        }
      });
    }
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
        borderRadius: kShellBorderRadius,
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Text('prompt templates',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    // Capture stable context before overlay removal
                    final navContext = Navigator.of(context).context;
                    widget.onDismiss?.call();
                    DialogService.instance.showUnique(
                      context: navContext,
                      id: 'template-manager',
                      builder: (_) => const PromptTemplateManagerDialog(),
                    );
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('manage',
                      style: TextStyle(fontSize: 10, color: t.fgMuted)),
                  ),
                ),
              ],
            ),
          ),
          // Templates list
          Flexible(
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final tmpl = _filtered[index];
                final clampedActive = _filtered.isEmpty ? -1
                    : widget.activeIndex.clamp(0, _filtered.length - 1);
                return _TemplateRow(
                  template: tmpl,
                  tokens: t,
                  theme: theme,
                  isActive: index == clampedActive,
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
          // Footer: + new
          GestureDetector(
            onTap: () {
              final navContext = Navigator.of(context).context;
              widget.onDismiss?.call();
              DialogService.instance.showUnique(
                context: navContext,
                id: 'template-manager',
                builder: (_) => const PromptTemplateManagerDialog(
                  initialMode: TemplateManagerMode.add,
                ),
              );
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.border, width: 0.5)),
                ),
                alignment: Alignment.center,
                child: Text('+ new',
                  style: TextStyle(fontSize: 10, color: t.accentPrimary)),
              ),
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
  final bool isActive;

  const _TemplateRow({
    required this.template,
    required this.tokens,
    required this.theme,
    required this.onSelect,
    this.onDelete,
    this.isActive = false,
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
          decoration: BoxDecoration(
            color: widget.isActive || _hovering ? t.surfaceCard : Colors.transparent,
            border: widget.isActive
                ? Border(left: BorderSide(color: t.accentPrimary, width: 2))
                : null,
          ),
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
                  borderRadius: kShellBorderRadiusSm,
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
