import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'prompt_templates.dart';

enum TemplateManagerMode { list, add }

enum _Category { all, builtIn, custom }

class PromptTemplateManagerDialog extends StatefulWidget {
  final TemplateManagerMode initialMode;

  const PromptTemplateManagerDialog({
    super.key,
    this.initialMode = TemplateManagerMode.list,
  });

  @override
  State<PromptTemplateManagerDialog> createState() =>
      _PromptTemplateManagerDialogState();
}

class _PromptTemplateManagerDialogState
    extends State<PromptTemplateManagerDialog> {
  late List<PromptTemplate> _templates;
  _Category _category = _Category.all;
  int _page = 0;
  static const _pageSize = 10;

  // Form state
  bool _showForm = false;
  String? _editingName; // null = adding new, non-null = editing existing
  final _nameCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _templates = PromptTemplateStore.all();
    if (widget.initialMode == TemplateManagerMode.add) {
      _showForm = true;
      _editingName = null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _templates = PromptTemplateStore.all();
      _page = _page.clamp(0, _totalPages - 1);
    });
  }

  List<PromptTemplate> get _filtered {
    switch (_category) {
      case _Category.all:
        return _templates;
      case _Category.builtIn:
        return _templates.where((t) => t.category == 'built-in').toList();
      case _Category.custom:
        return _templates.where((t) => t.category == 'custom').toList();
    }
  }

  List<PromptTemplate> get _paged {
    final list = _filtered;
    final start = _page * _pageSize;
    if (start >= list.length) return [];
    return list.sublist(start, (start + _pageSize).clamp(0, list.length));
  }

  int get _totalPages => (_filtered.length / _pageSize).ceil().clamp(1, 999);

  // --- Form actions ---

  void _openAddForm() {
    _nameCtrl.clear();
    _contentCtrl.clear();
    setState(() {
      _showForm = true;
      _editingName = null;
    });
  }

  void _openEditForm(PromptTemplate tmpl) {
    _nameCtrl.text = tmpl.name;
    _contentCtrl.text = tmpl.content;
    setState(() {
      _showForm = true;
      _editingName = tmpl.name;
    });
  }

  void _cancelForm() {
    setState(() => _showForm = false);
  }

  void _submitForm() {
    final name = _nameCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (name.isEmpty || content.isEmpty) return;

    if (_editingName != null) {
      PromptTemplateStore.updateCustom(
        _editingName!,
        PromptTemplate(name: name, content: content),
      );
    } else {
      // Prevent duplicate names — use upsert semantics
      final existing = PromptTemplateStore.loadCustom();
      if (existing.any((t) => t.name == name)) {
        PromptTemplateStore.updateCustom(
          name,
          PromptTemplate(name: name, content: content),
        );
      } else {
        PromptTemplateStore.addCustom(
          PromptTemplate(name: name, content: content),
        );
      }
    }
    setState(() => _showForm = false);
    _reload();
  }

  void _deleteTemplate(String name) {
    PromptTemplateStore.removeCustom(name);
    _reload();
  }

  // --- Import / Export ---

  void _exportTemplates() {
    final custom = PromptTemplateStore.loadCustom();
    if (custom.isEmpty) return;
    final json = jsonEncode(custom.map((t) => t.toJson()).toList());
    final blob = html.Blob([json], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'prompt_templates.json')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _importTemplates() {
    final input = html.FileUploadInputElement()..accept = '.json';
    input.click();
    // Use .first to auto-cancel after one event (no subscription leak)
    input.onChange.first.then((_) {
      final file = input.files?.first;
      if (file == null) return;
      final reader = html.FileReader();
      reader.onLoadEnd.first.then((_) {
        try {
          final text = reader.result as String;
          final list = jsonDecode(text) as List;
          final imported = list
              .whereType<Map<String, dynamic>>()
              .map((j) => PromptTemplate.fromJson(j))
              .toList();
          if (imported.isEmpty) return;
          final existing = PromptTemplateStore.loadCustom();
          final existingNames = existing.map((t) => t.name).toSet();
          for (final tmpl in imported) {
            if (!existingNames.contains(tmpl.name)) {
              existing.add(PromptTemplate(
                name: tmpl.name,
                content: tmpl.content,
                category: 'custom',
              ));
              existingNames.add(tmpl.name);
            }
          }
          PromptTemplateStore.saveCustom(existing);
          if (mounted) _reload();
        } catch (_) {
          // Invalid JSON — silently ignore
        }
      });
      reader.readAsText(file);
    });
  }

  // --- UI ---

  Widget _categoryToggle(ShellTokens t, ThemeData theme, String label,
      _Category cat) {
    final active = _category == cat;
    return GestureDetector(
      onTap: () => setState(() {
        _category = cat;
        _page = 0;
      }),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: active ? t.accentPrimary : t.fgMuted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final customCount =
        _templates.where((t) => t.category == 'custom').length;

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        height: MediaQuery.of(context).size.height * 0.7,
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 560),
        child: Column(
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Text('prompt templates',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: t.fgPrimary)),
                  const SizedBox(width: 12),
                  Text('($customCount custom)',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: t.fgTertiary, fontSize: 10)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _importTemplates,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('import',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: t.fgMuted)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _exportTemplates,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('export',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: t.fgMuted)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('close',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: t.fgMuted)),
                    ),
                  ),
                ],
              ),
            ),
            // Sub-category bar + pagination + add
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  _categoryToggle(t, theme, 'all', _Category.all),
                  const SizedBox(width: 12),
                  _categoryToggle(t, theme, 'built-in', _Category.builtIn),
                  const SizedBox(width: 12),
                  _categoryToggle(t, theme, 'custom', _Category.custom),
                  const Spacer(),
                  if (_totalPages > 1) ...[
                    Text('${_page + 1}/$_totalPages',
                        style: TextStyle(fontSize: 10, color: t.fgTertiary)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _page > 0
                          ? () => setState(() => _page--)
                          : null,
                      child: MouseRegion(
                        cursor: _page > 0
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        child: Text('prev',
                            style: TextStyle(
                                fontSize: 10,
                                color: _page > 0
                                    ? t.fgMuted
                                    : t.fgDisabled)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _page < _totalPages - 1
                          ? () => setState(() => _page++)
                          : null,
                      child: MouseRegion(
                        cursor: _page < _totalPages - 1
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic,
                        child: Text('next',
                            style: TextStyle(
                                fontSize: 10,
                                color: _page < _totalPages - 1
                                    ? t.fgMuted
                                    : t.fgDisabled)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  GestureDetector(
                    onTap: _showForm ? _cancelForm : _openAddForm,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        _showForm ? 'cancel' : '+ add',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              _showForm ? t.fgMuted : t.accentPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Add/Edit form (collapsible)
            if (_showForm) _buildForm(t, theme),
            // Template list
            Expanded(
              child: _paged.isEmpty
                  ? Center(
                      child: Text(
                        _category == _Category.custom
                            ? 'no custom templates'
                            : 'no templates',
                        style: TextStyle(
                            fontSize: 11, color: t.fgDisabled),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _paged.length,
                      itemBuilder: (context, index) =>
                          _buildRow(t, theme, _paged[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ShellTokens t, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _editingName != null ? 'edit template' : 'new template',
            style: TextStyle(fontSize: 11, color: t.fgTertiary),
          ),
          const SizedBox(height: 8),
          // Name field
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'template name',
              isDense: true,
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.accentPrimary),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
          const SizedBox(height: 10),
          // Content field (multi-line)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: TextField(
              controller: _contentCtrl,
              maxLines: 8,
              minLines: 4,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'template content...\nuse \\n for line breaks',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _cancelForm,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text('cancel',
                      style: TextStyle(fontSize: 11, color: t.fgMuted)),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _submitForm,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    _editingName != null ? 'update' : 'save',
                    style:
                        TextStyle(fontSize: 11, color: t.accentPrimary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
      ShellTokens t, ThemeData theme, PromptTemplate tmpl) {
    final isCustom = tmpl.category == 'custom';
    return _ManagerTemplateRow(
      template: tmpl,
      tokens: t,
      theme: theme,
      onEdit: isCustom ? () => _openEditForm(tmpl) : null,
      onDelete: isCustom ? () => _deleteTemplate(tmpl.name) : null,
    );
  }
}

// --- Template row with hover actions ---

class _ManagerTemplateRow extends StatefulWidget {
  final PromptTemplate template;
  final ShellTokens tokens;
  final ThemeData theme;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ManagerTemplateRow({
    required this.template,
    required this.tokens,
    required this.theme,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_ManagerTemplateRow> createState() => _ManagerTemplateRowState();
}

class _ManagerTemplateRowState extends State<_ManagerTemplateRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final tmpl = widget.template;
    final isCustom = tmpl.category == 'custom';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _hovering ? t.surfaceCard : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Name
                Expanded(
                  child: Text(
                    tmpl.name,
                    style: widget.theme.textTheme.bodyMedium?.copyWith(
                      color: t.fgPrimary,
                    ),
                  ),
                ),
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Text(
                    tmpl.category,
                    style: TextStyle(fontSize: 9, color: t.fgDisabled),
                  ),
                ),
                // Hover actions
                if (_hovering && isCustom) ...[
                  if (widget.onEdit != null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: widget.onEdit,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text('edit',
                            style: TextStyle(
                                fontSize: 10, color: t.fgMuted)),
                      ),
                    ),
                  ],
                  if (widget.onDelete != null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text('delete',
                            style: TextStyle(
                                fontSize: 10, color: t.statusError)),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            // Content preview
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tmpl.content.replaceAll('\n', ' ').trim(),
                style: TextStyle(fontSize: 10, color: t.fgMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
