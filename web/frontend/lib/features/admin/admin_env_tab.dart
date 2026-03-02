import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart' show terminalClientProvider;

/// Environment variables management tab: allows superadmins to dynamically
/// set, edit, and delete env vars that are injected into docker exec commands.
class AdminEnvTab extends ConsumerStatefulWidget {
  const AdminEnvTab({super.key});

  @override
  ConsumerState<AdminEnvTab> createState() => _AdminEnvTabState();
}

class _AdminEnvTabState extends ConsumerState<AdminEnvTab> {
  bool _loading = false;
  String? _error;
  Map<String, String> _vars = {};

  // Inline add/edit state
  bool _adding = false;
  String? _editingKey; // non-null when editing an existing row
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();
  final _keyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ref.read(terminalClientProvider);
      if (!client.isConnected || !client.isAuthenticated) {
        await client.connect();
      }

      final vars = await client.listEnvVars();
      if (!mounted) return;
      setState(() => _vars = vars);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load env vars: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startAdd() {
    setState(() {
      _adding = true;
      _editingKey = null;
      _keyController.clear();
      _valueController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyFocus.requestFocus();
    });
  }

  void _startEdit(String key, String value) {
    setState(() {
      _adding = false;
      _editingKey = key;
      _keyController.text = key;
      _valueController.text = value;
    });
  }

  void _cancelEdit() {
    setState(() {
      _adding = false;
      _editingKey = null;
      _keyController.clear();
      _valueController.clear();
    });
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    final value = _valueController.text;
    if (key.isEmpty) return;

    final client = ref.read(terminalClientProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await client.setEnvVar(key, value);
      if (!mounted) return;
      setState(() {
        _vars[key] = value;
        // If we were editing and the key changed, remove the old one
        if (_editingKey != null && _editingKey != key) {
          _vars.remove(_editingKey);
        }
        _adding = false;
        _editingKey = null;
        _keyController.clear();
        _valueController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String key) async {
    final client = ref.read(terminalClientProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await client.deleteEnvVar(key);
      if (!mounted) return;
      setState(() {
        _vars.remove(key);
        if (_editingKey == key) _cancelEdit();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final sortedKeys = _vars.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text(
                'environment variables (${_vars.length})',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              if (_loading)
                Text('loading...', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              if (_error != null)
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.statusError),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: _loading ? null : _startAdd,
                child: Text(
                  'add',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _loading ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _loading ? null : _load,
                child: Text(
                  'refresh',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _loading ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Table header
        if (sortedKeys.isNotEmpty || _adding)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: _buildHeaderRow(t, theme),
          ),
        // Inline add row
        if (_adding) _buildEditRow(t, theme, isNew: true),
        // Env var rows
        Expanded(
          child: sortedKeys.isEmpty && !_loading && !_adding
              ? Center(
                  child: Text(
                    _error != null ? '' : 'no environment variables set',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: sortedKeys.length,
                  itemBuilder: (context, index) {
                    final key = sortedKeys[index];
                    if (_editingKey == key) {
                      return _buildEditRow(t, theme, isNew: false);
                    }
                    return _buildVarRow(key, _vars[key]!, t, theme);
                  },
                ),
        ),
        // Caption
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Text(
            'these variables are injected into every terminal command executed via docker exec. '
            'changes take effect immediately and persist across restarts.',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(ShellTokens t, ThemeData theme) {
    final style = theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    return Row(
      children: [
        SizedBox(width: 220, child: Text('key', style: style)),
        Expanded(child: Text('value', style: style)),
        SizedBox(width: 80, child: Text('actions', style: style, textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _buildVarRow(String key, String value, ShellTokens t, ThemeData theme) {
    final cellStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final actionStyle = theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary, fontSize: 10);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: SelectableText(
              key,
              style: cellStyle?.copyWith(color: t.accentSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: cellStyle,
              maxLines: 1,
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => _startEdit(key, value),
                  child: Text('edit', style: actionStyle),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _delete(key),
                  child: Text(
                    'delete',
                    style: actionStyle?.copyWith(color: t.statusError),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditRow(ShellTokens t, ThemeData theme, {required bool isNew}) {
    final inputStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final actionStyle = theme.textTheme.labelSmall?.copyWith(fontSize: 10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 210,
            child: TextField(
              controller: _keyController,
              focusNode: isNew ? _keyFocus : null,
              enabled: isNew, // can't rename a key while editing
              style: inputStyle?.copyWith(color: t.accentSecondary),
              decoration: InputDecoration(
                hintText: 'KEY_NAME',
                hintStyle: inputStyle?.copyWith(color: t.fgPlaceholder),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                border: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.accentPrimary, width: 0.5),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _valueController,
              style: inputStyle,
              decoration: InputDecoration(
                hintText: 'value',
                hintStyle: inputStyle?.copyWith(color: t.fgPlaceholder),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                border: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.border, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: kShellBorderRadius,
                  borderSide: BorderSide(color: t.accentPrimary, width: 0.5),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: _loading ? null : _save,
                  child: Text(
                    'save',
                    style: actionStyle?.copyWith(
                      color: _loading ? t.fgDisabled : t.accentPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _cancelEdit,
                  child: Text(
                    'cancel',
                    style: actionStyle?.copyWith(color: t.fgMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
