import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/toast_provider.dart';
import '../../main.dart' show authClientProvider, languageProvider;
import '../../core/providers.dart' show terminalClientProvider;

enum SkillsCategory { ready, clawhub, templates }

class SkillsDialog extends ConsumerStatefulWidget {
  const SkillsDialog({super.key});

  @override
  ConsumerState<SkillsDialog> createState() => _SkillsDialogState();
}

class _SkillsDialogState extends ConsumerState<SkillsDialog> {
  final TextEditingController _clawhubQueryController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _installingSkill;
  bool _clawhubSearching = false;
  String? _clawhubError;
  List<Map<String, String>> _clawhubResults = [];
  String? _inspectingSkill;
  Map<String, dynamic>? _inspectData;

  String _stripAnsi(String input) {
    final ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
    return input.replaceAll(ansi, '');
  }

  SkillsCategory _skillsCategory = SkillsCategory.ready;

  List<Map<String, dynamic>> _skills = [];

  int _skillsPage = 0;
  static const int _pageSize = 14;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _clawhubQueryController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _decodeJsonObject(String raw) {
    final stripped = _stripAnsi(raw);
    final trimmed = stripped.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(trimmed);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final parsed = jsonDecode(trimmed.substring(start, end + 1));
      if (parsed is Map<String, dynamic>) return parsed;
    }
    throw const FormatException('No JSON object found in output');
  }

  Future<void> _loadData() async {
    final client = ref.read(terminalClientProvider);
    if (!client.isConnected || !client.isAuthenticated) {
      try {
        await client.connect();
      } catch (_) {}
    }

    if (!client.isAuthenticated) {
      setState(() {
        _error = 'terminal proxy not connected';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final skillsRaw = await client.executeCommandForOutput(
        'skills list --json',
        timeout: const Duration(seconds: 45),
      );

      final skillsJson = _decodeJsonObject(skillsRaw);

      final skills = ((skillsJson['skills'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      setState(() {
        _skills = skills;
        _skillsPage = 0;
      });
    } catch (e) {
      if (!mounted) return;
      final errMsg = 'failed to load skills: $e';
      ToastService.showError(context, errMsg);
      setState(() {
        _error = errMsg;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _installSkill(Map<String, dynamic> row) async {
    final client = ref.read(terminalClientProvider);
    final rawName = (row['slug'] ?? row['name'] ?? '').toString().trim();
    if (rawName.isEmpty) return;

    if (!client.isAuthenticated) {
      ToastService.showError(context, 'terminal proxy not connected');
      setState(() {
        _error = 'terminal proxy not connected';
      });
      return;
    }

    setState(() {
      _installingSkill = rawName;
      _error = null;
    });

    try {
      await client.executeCommandForOutput(
        'clawhub install $rawName',
        timeout: const Duration(seconds: 90),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      final missing = row['missing'] as Map<String, dynamic>?;
      final missingHints = <String>[];
      if (missing != null) {
        final bins = (missing['bins'] as List?)?.cast<String>() ?? [];
        final anyBins = (missing['anyBins'] as List?)?.cast<String>() ?? [];
        final env = (missing['env'] as List?)?.cast<String>() ?? [];
        if (bins.isNotEmpty) missingHints.add('bins: ${bins.join(", ")}');
        if (anyBins.isNotEmpty) missingHints.add('any of: ${anyBins.join(", ")}');
        if (env.isNotEmpty) missingHints.add('env: ${env.join(", ")}');
      }
      final hint = missingHints.isNotEmpty ? ' (missing ${missingHints.join("; ")})' : '';
      final errMsg = 'install $rawName failed$hint';
      ToastService.showError(context, errMsg);
      setState(() {
        _error = errMsg;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _installingSkill = null;
      });
    }
  }

  Future<void> _searchClawhub() async {
    final client = ref.read(terminalClientProvider);
    final query = _clawhubQueryController.text.trim();
    if (query.isEmpty) return;

    if (!client.isAuthenticated) {
      ToastService.showError(context, 'terminal proxy not connected');
      setState(() {
        _error = 'terminal proxy not connected';
      });
      return;
    }

    final normalizedQuery = query
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();

    setState(() {
      _clawhubSearching = true;
      _clawhubError = null;
      _clawhubResults = [];
    });

    try {
      final raw = await client.executeCommandForOutput(
        'clawhub search $normalizedQuery --limit 20',
        timeout: const Duration(seconds: 60),
      );

      final parsed = <Map<String, String>>[];
      for (final line in raw.split('\n')) {
        final trimmed = _stripAnsi(line).trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.toLowerCase().contains('searching')) continue;
        if (trimmed.toLowerCase().startsWith('error:')) continue;

        final withoutPrefix = trimmed.startsWith('- ')
            ? trimmed.substring(2).trim()
            : trimmed;

        final pattern = RegExp(r'^([^\s]+)\s+(.+?)\s*\(([-0-9.]+)\)$');
        final match = pattern.firstMatch(withoutPrefix);
        if (match != null) {
          final slug = (match.group(1) ?? '').trim();
          final name = (match.group(2) ?? '').trim();
          final score = (match.group(3) ?? '').trim();
          if (slug.isNotEmpty) {
            parsed.add({'slug': slug, 'name': name.isEmpty ? slug : name, 'score': score});
            continue;
          }
        }

        final scoreStart = withoutPrefix.lastIndexOf('(');
        final scoreEnd = withoutPrefix.lastIndexOf(')');

        String score = '';
        String body = withoutPrefix;
        if (scoreStart > 0 && scoreEnd > scoreStart) {
          score = withoutPrefix.substring(scoreStart + 1, scoreEnd).trim();
          body = withoutPrefix.substring(0, scoreStart).trim();
        }

        if (body.isEmpty) continue;
        if (!body.contains('  ')) continue;
        final parts = body.split(RegExp(r'\s{2,}'));
        String slug = parts.isNotEmpty ? parts.first.trim() : body;
        String name = parts.length > 1 ? parts.sublist(1).join(' ').trim() : slug;

        if (parts.length <= 1) {
          final singleSplit = body.split(RegExp(r'\s+'));
          if (singleSplit.isNotEmpty) {
            slug = singleSplit.first.trim();
            name = singleSplit.length > 1 ? singleSplit.sublist(1).join(' ').trim() : slug;
          }
        }
        if (slug.isEmpty) continue;

        parsed.add({'slug': slug, 'name': name, 'score': score});
      }

      if (!mounted) return;
      setState(() {
        _clawhubResults = parsed;
        if (parsed.isEmpty) {
          final rawLines = raw
              .split('\n')
              .map(_stripAnsi)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && !s.startsWith('4 '))
              .take(4)
              .join(' | ');
          _clawhubError = rawLines.isEmpty
              ? 'no results. try simpler keywords (e.g. calendar, github, discord)'
              : 'no parsed results. raw: $rawLines';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clawhubError = 'search failed: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _clawhubSearching = false;
      });
    }
  }

  Future<void> _installClawhubSkill(Map<String, String> row) async {
    final client = ref.read(terminalClientProvider);
    final slug = (row['slug'] ?? '').trim();
    if (slug.isEmpty) return;

    setState(() {
      _installingSkill = slug;
      _error = null;
      _clawhubError = null;
    });

    try {
      await client.executeCommandForOutput(
        'clawhub install $slug',
        timeout: const Duration(seconds: 120),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clawhubError = 'failed to install $slug: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _installingSkill = null;
      });
    }
  }

  Future<void> _inspectClawhubSkill(String slug) async {
    final client = ref.read(terminalClientProvider);
    if (slug.isEmpty) return;

    setState(() {
      _inspectingSkill = slug;
      _inspectData = null;
    });

    try {
      final raw = await client.executeCommandForOutput(
        'clawhub inspect $slug --json',
        timeout: const Duration(seconds: 30),
      );

      final cleaned = _stripAnsi(raw).trim();
      final jsonStart = cleaned.indexOf('{');
      final jsonEnd = cleaned.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd < jsonStart) {
        if (!mounted) return;
        setState(() {
          _inspectingSkill = null;
        });
        return;
      }
      final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _inspectData = data;
        _inspectingSkill = null;
      });
      _showInspectDialog(slug, data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inspectingSkill = null;
        _clawhubError = 'inspect failed: $e';
      });
    }
  }

  void _showInspectDialog(String slug, Map<String, dynamic> data) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final skill = data['skill'] as Map<String, dynamic>? ?? {};
    final owner = data['owner'] as Map<String, dynamic>? ?? {};
    final latestVersion = data['latestVersion'] as Map<String, dynamic>? ?? {};

    final displayName = (skill['displayName'] ?? slug).toString();
    final summary = (skill['summary'] ?? '').toString();
    final ownerHandle = (owner['handle'] ?? '').toString();
    final version = (latestVersion['version'] ?? '').toString();
    final changelog = (latestVersion['changelog'] ?? '').toString();
    final stats = skill['stats'] as Map<String, dynamic>? ?? {};
    final downloads = stats['downloads'] ?? 0;
    final installs = stats['installsCurrent'] ?? stats['installsAllTime'] ?? 0;
    final stars = stats['stars'] ?? 0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: t.surfaceBase,
        shape: RoundedRectangleBorder(
          borderRadius: kShellBorderRadius,
          side: BorderSide(color: t.border, width: 0.5),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: theme.textTheme.titleMedium?.copyWith(color: t.fgPrimary),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Text('x', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    slug,
                    if (version.isNotEmpty) 'v$version',
                    if (ownerHandle.isNotEmpty) 'by $ownerHandle',
                  ].join('  '),
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    '$downloads downloads',
                    '$installs installs',
                    '$stars stars',
                  ].join('  '),
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                ),
                const SizedBox(height: 12),
                if (summary.isNotEmpty) ...[
                  Text(
                    summary,
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
                  ),
                  const SizedBox(height: 12),
                ],
                if (changelog.isNotEmpty) ...[
                  Text(
                    'changelog',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        changelog,
                        style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _inspectTemplateSkill(Map<String, dynamic> skill) async {
    final client = ref.read(terminalClientProvider);
    final name = (skill['name'] ?? '').toString().trim();
    if (name.isEmpty) return;

    setState(() => _inspectingSkill = name);

    try {
      String raw = '';
      try {
        raw = await client.executeCommandForOutput(
          'cat /home/node/.openclaw/skills/$name/SKILL.md',
          timeout: const Duration(seconds: 10),
        );
      } catch (_) {
        raw = await client.executeCommandForOutput(
          'cat /home/node/.openclaw/workspace/skills/$name/SKILL.md',
          timeout: const Duration(seconds: 10),
        );
      }

      final content = _stripAnsi(raw).trim();
      if (content.isEmpty || !mounted) {
        setState(() => _inspectingSkill = null);
        return;
      }

      String body = content;
      if (content.startsWith('---')) {
        final endIdx = content.indexOf('---', 3);
        if (endIdx > 3) {
          body = content.substring(endIdx + 3).trim();
        }
      }

      if (!mounted) return;
      setState(() => _inspectingSkill = null);
      _showTemplateInspectDialog(skill, body);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inspectingSkill = null;
        _error = 'inspect failed: $e';
      });
    }
  }

  void _showTemplateInspectDialog(Map<String, dynamic> skill, String markdownBody) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    final name = (skill['name'] ?? 'unknown').toString();
    final emoji = (skill['emoji'] ?? '').toString();
    final desc = (skill['description'] ?? '').toString();
    final homepage = (skill['homepage'] ?? '').toString();
    final eligible = skill['eligible'] == true;
    final source = (skill['source'] ?? '').toString();
    final missing = skill['missing'] as Map<String, dynamic>? ?? {};

    final missingBins = (missing['bins'] as List?)?.cast<String>() ?? [];
    final missingAnyBins = (missing['anyBins'] as List?)?.cast<String>() ?? [];
    final missingEnv = (missing['env'] as List?)?.cast<String>() ?? [];
    final missingConfig = (missing['config'] as List?)?.cast<String>() ?? [];
    final missingOs = (missing['os'] as List?)?.cast<String>() ?? [];

    final installing = _installingSkill == name;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: t.surfaceBase,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: t.border, width: 0.5),
        ),
        child: Container(
          width: MediaQuery.of(ctx).size.width * 0.7,
          height: MediaQuery.of(ctx).size.height * 0.78,
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (emoji.isNotEmpty) ...[
                          Text(emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(color: t.fgPrimary),
                          ),
                        ),
                        if (!eligible)
                          GestureDetector(
                            onTap: installing
                                ? null
                                : () {
                                    Navigator.of(ctx).pop();
                                    _installSkill(skill);
                                  },
                            child: Text(
                              installing ? 'installing...' : 'install',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: installing ? t.fgDisabled : t.accentPrimary,
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => Navigator.of(ctx).pop(),
                          child: Text('x', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        eligible ? 'ready' : 'not ready',
                        source,
                        if (homepage.isNotEmpty) homepage,
                      ].join('  '),
                      style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(desc, style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted)),
                    ],
                    if (!eligible) ...[
                      const SizedBox(height: 8),
                      if (missingBins.isNotEmpty)
                        _requirementChip('bins: ${missingBins.join(", ")}', t, theme),
                      if (missingAnyBins.isNotEmpty)
                        _requirementChip('any of: ${missingAnyBins.join(", ")}', t, theme),
                      if (missingEnv.isNotEmpty)
                        _requirementChip('env: ${missingEnv.join(", ")}', t, theme),
                      if (missingConfig.isNotEmpty)
                        _requirementChip('config: ${missingConfig.join(", ")}', t, theme),
                      if (missingOs.isNotEmpty)
                        _requirementChip('os: ${missingOs.join(", ")}', t, theme),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: markdownBody.isEmpty
                    ? Center(
                        child: Text('no content', style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder)),
                      )
                    : Markdown(
                        data: markdownBody,
                        selectable: true,
                        padding: const EdgeInsets.all(16),
                        styleSheet: MarkdownStyleSheet(
                          p: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 12, height: 1.5),
                          h1: theme.textTheme.titleMedium?.copyWith(color: t.fgPrimary),
                          h2: theme.textTheme.titleSmall?.copyWith(color: t.fgPrimary),
                          h3: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary, fontWeight: FontWeight.bold),
                          code: theme.textTheme.bodySmall?.copyWith(color: t.accentPrimary, fontSize: 11),
                          codeblockDecoration: BoxDecoration(
                            borderRadius: kShellBorderRadiusSm,
                            color: t.surfaceCard,
                            border: Border.all(color: t.border, width: 0.5),
                          ),
                          codeblockPadding: const EdgeInsets.all(10),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(left: BorderSide(color: t.border, width: 2)),
                          ),
                          listBullet: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 12),
                          tableHead: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11),
                          tableBody: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11),
                          tableBorder: TableBorder.all(color: t.border, width: 0.5),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(top: BorderSide(color: t.border, width: 0.5)),
                          ),
                          a: theme.textTheme.bodySmall?.copyWith(color: t.accentSecondary, fontSize: 12),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requirementChip(String text, ShellTokens t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'missing $text',
        style: theme.textTheme.labelSmall?.copyWith(color: t.statusWarning, fontSize: 10),
      ),
    );
  }

  List<Map<String, dynamic>> _slicePage(List<Map<String, dynamic>> rows, int page) {
    final start = page * _pageSize;
    if (start >= rows.length) return const [];
    final end = (start + _pageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  bool _isTemplate(Map<String, dynamic> skill) {
    return skill['bundled'] == true;
  }

  List<Map<String, dynamic>> _skillsForCategory() {
    switch (_skillsCategory) {
      case SkillsCategory.ready:
        return _skills.where((s) => s['eligible'] == true).toList();
      case SkillsCategory.clawhub:
        return _skills.where((s) => !_isTemplate(s)).toList();
      case SkillsCategory.templates:
        return _skills.where(_isTemplate).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final language = ref.watch(languageProvider);

    final categoryRows = _skillsForCategory();
    final skillsPages = (categoryRows.length / _pageSize).ceil().clamp(1, 9999);
    final skillsPageRows = _slicePage(categoryRows, _skillsPage);

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.82,
        height: MediaQuery.of(context).size.height * 0.82,
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Text(
                    tr(language, 'skills'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.accentPrimary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ref.watch(authClientProvider).state.activeOpenClaw?.name ?? '',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.accentSecondary, fontSize: 9),
                  ),
                  const SizedBox(width: 12),
                  if (_loading)
                    Text(
                      'loading...',
                      style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                    ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loading ? null : _loadData,
                    child: Text(
                      'refresh',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _loading ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(
                      tr(language, 'close'),
                      style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildSkillsView(
                skillsPageRows: skillsPageRows,
                pages: skillsPages,
                totalRows: categoryRows.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsView({
    required List<Map<String, dynamic>> skillsPageRows,
    required int pages,
    required int totalRows,
  }) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              _categoryToggle('ready', _skillsCategory == SkillsCategory.ready, () {
                setState(() {
                  _skillsCategory = SkillsCategory.ready;
                  _skillsPage = 0;
                });
              }),
              const SizedBox(width: 10),
              _categoryToggle('clawhub', _skillsCategory == SkillsCategory.clawhub, () {
                setState(() {
                  _skillsCategory = SkillsCategory.clawhub;
                  _skillsPage = 0;
                });
              }),
              const SizedBox(width: 10),
              _categoryToggle('templates', _skillsCategory == SkillsCategory.templates, () {
                setState(() {
                  _skillsCategory = SkillsCategory.templates;
                  _skillsPage = 0;
                });
              }),
              const Spacer(),
              Text(
                '${_skillsPage + 1}/$pages',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              const SizedBox(width: 10),
              _pageControl('prev', _skillsPage > 0, () {
                setState(() => _skillsPage -= 1);
              }),
              const SizedBox(width: 8),
              _pageControl('next', _skillsPage + 1 < pages, () {
                setState(() => _skillsPage += 1);
              }),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'skills ($totalRows)',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
          ),
        ),
        Expanded(
          child: _skillsCategory == SkillsCategory.clawhub
              ? _buildClawhubSearchView()
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: skillsPageRows.map(_skillRow).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildClawhubSearchView() {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final language = ref.watch(languageProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _clawhubQueryController,
                  decoration: const InputDecoration(
                    hintText: 'search clawhub skills',
                  ),
                  onSubmitted: (_) => _searchClawhub(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _clawhubSearching ? null : _searchClawhub,
                child: Text(
                  _clawhubSearching ? 'searching...' : tr(language, 'search'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _clawhubSearching ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_clawhubError != null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _clawhubError!,
                style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
              ),
            ),
          ),
        if (_clawhubResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    tr(language, 'similarity'),
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        Expanded(
          child: _clawhubResults.isEmpty
              ? Center(
                  child: Text(
                    _clawhubSearching ? 'searching...' : 'search to discover skills',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: _clawhubResults.map(_clawhubRow).toList(),
                ),
        ),
      ],
    );
  }

  Widget _clawhubRow(Map<String, String> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final slug = (row['slug'] ?? '').trim();
    final name = (row['name'] ?? slug).trim();
    final score = (row['score'] ?? '').trim();
    final installing = _installingSkill == slug;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              score.isEmpty ? '-' : score,
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$slug  $name',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
            ),
          ),
          GestureDetector(
            onTap: _inspectingSkill == slug ? null : () => _inspectClawhubSkill(slug),
            child: Text(
              _inspectingSkill == slug ? 'loading...' : 'detail',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _inspectingSkill == slug ? t.fgDisabled : t.fgTertiary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: installing ? null : () => _installClawhubSkill(row),
            child: Text(
              installing ? 'installing...' : 'install',
              style: theme.textTheme.labelSmall?.copyWith(
                color: installing ? t.fgDisabled : t.accentPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryToggle(String label, bool active, VoidCallback onTap) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: active ? t.accentPrimary : t.fgMuted,
        ),
      ),
    );
  }

  Widget _pageControl(String label, bool enabled, VoidCallback onTap) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: enabled ? t.accentPrimary : t.fgDisabled,
        ),
      ),
    );
  }

  Widget _skillRow(Map<String, dynamic> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final ready = row['eligible'] == true;
    final name = (row['name'] ?? 'unknown').toString();
    final desc = (row['description'] ?? '').toString();
    final emoji = (row['emoji'] ?? '').toString();
    final canInstall = !ready;
    final installing = _installingSkill == name;
    final inspecting = _inspectingSkill == name;
    final isBundled = row['bundled'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (emoji.isNotEmpty) ...[
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  '${ready ? 'ready' : 'missing'}  $name',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ready ? t.accentPrimary : t.fgMuted,
                  ),
                ),
              ),
              if (isBundled) ...[
                GestureDetector(
                  onTap: inspecting ? null : () => _inspectTemplateSkill(row),
                  child: Text(
                    inspecting ? 'loading...' : 'detail',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: inspecting ? t.fgDisabled : t.fgTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (canInstall)
                GestureDetector(
                  onTap: installing ? null : () => _installSkill(row),
                  child: Text(
                    installing ? 'installing...' : 'install',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: installing ? t.fgDisabled : t.accentPrimary,
                    ),
                  ),
                ),
            ],
          ),
          if (desc.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: emoji.isNotEmpty ? 25 : 14),
              child: Text(
                desc,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: t.fgTertiary,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
