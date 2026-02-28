import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/toast_provider.dart';
import '../../main.dart' show languageProvider;
import '../shell/shell_page.dart' show terminalClientProvider;

enum CatalogTab { skills, crons }

enum SkillsCategory { ready, notReady, clawhub, templates }

enum CronCategory { existing, templates }

class SkillsCronDialog extends ConsumerStatefulWidget {
  final CatalogTab initialTab;

  const SkillsCronDialog({
    super.key,
    this.initialTab = CatalogTab.skills,
  });

  @override
  ConsumerState<SkillsCronDialog> createState() => _SkillsCronDialogState();
}

class _SkillsCronDialogState extends ConsumerState<SkillsCronDialog> {
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

  CatalogTab _tab = CatalogTab.skills;
  SkillsCategory _skillsCategory = SkillsCategory.ready;
  CronCategory _cronCategory = CronCategory.existing;

  List<Map<String, dynamic>> _skills = [];
  List<Map<String, dynamic>> _cronJobs = [];

  int _skillsPage = 0;
  int _cronPage = 0;
  static const int _pageSize = 14;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
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
      await Future.delayed(const Duration(milliseconds: 400));
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
      final cronRaw = await client.executeCommandForOutput(
        'cron list --json',
        timeout: const Duration(seconds: 30),
      );

      final skillsJson = _decodeJsonObject(skillsRaw);
      final cronJson = _decodeJsonObject(cronRaw);

      final skills = ((skillsJson['skills'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      final jobs = ((cronJson['jobs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      setState(() {
        _skills = skills;
        _cronJobs = jobs;
        _skillsPage = 0;
        _cronPage = 0;
      });
    } catch (e) {
      if (!mounted) return;
      final errMsg = 'failed to load skills/cron: $e';
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
      final errMsg = 'failed to install $rawName: $e';
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
              .where((s) => s.isNotEmpty && !s.startsWith('4 '))
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
      // Find the first '{' to skip any leading text like "- Fetching skill"
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
          borderRadius: BorderRadius.circular(8),
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
                // Header: name + close
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
                // Slug + version + author
                Text(
                  [
                    slug,
                    if (version.isNotEmpty) 'v$version',
                    if (ownerHandle.isNotEmpty) 'by $ownerHandle',
                  ].join('  '),
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
                const SizedBox(height: 4),
                // Stats row
                Text(
                  [
                    '$downloads downloads',
                    '$installs installs',
                    '$stars stars',
                  ].join('  '),
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                ),
                const SizedBox(height: 12),
                // Summary
                if (summary.isNotEmpty) ...[
                  Text(
                    summary,
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
                  ),
                  const SizedBox(height: 12),
                ],
                // Changelog
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

  List<Map<String, dynamic>> _slicePage(List<Map<String, dynamic>> rows, int page) {
    final start = page * _pageSize;
    if (start >= rows.length) return const [];
    final end = (start + _pageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  bool _isTemplate(Map<String, dynamic> skill) {
    final source = (skill['source'] ?? '').toString().toLowerCase();
    final kind = (skill['kind'] ?? '').toString().toLowerCase();
    final name = (skill['name'] ?? '').toString().toLowerCase();
    return source.contains('template') ||
        kind.contains('template') ||
        name.contains('template');
  }

  List<Map<String, dynamic>> _skillsForCategory() {
    switch (_skillsCategory) {
      case SkillsCategory.ready:
        return _skills.where((s) => s['eligible'] == true && !_isTemplate(s)).toList();
      case SkillsCategory.notReady:
        return _skills.where((s) => s['eligible'] != true && !_isTemplate(s)).toList();
      case SkillsCategory.clawhub:
        return _skills.where((s) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          final source = (s['source'] ?? '').toString().toLowerCase();
          return name.contains('clawhub') || source.contains('clawhub');
        }).toList();
      case SkillsCategory.templates:
        return _skills.where(_isTemplate).toList();
    }
  }

  bool _isCronTemplate(Map<String, dynamic> job) {
    final source = (job['source'] ?? '').toString().toLowerCase();
    final kind = (job['kind'] ?? '').toString().toLowerCase();
    final id = (job['id'] ?? '').toString().toLowerCase();
    final name = (job['name'] ?? '').toString().toLowerCase();
    return source.contains('template') ||
        kind.contains('template') ||
        id.contains('template') ||
        name.contains('template');
  }

  List<Map<String, dynamic>> _cronsForCategory() {
    switch (_cronCategory) {
      case CronCategory.existing:
        return _cronJobs.where((j) => !_isCronTemplate(j)).toList();
      case CronCategory.templates:
        return _cronJobs.where(_isCronTemplate).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    final categoryRows = _skillsForCategory();
    final cronCategoryRows = _cronsForCategory();
    final skillsPages = (categoryRows.length / _pageSize).ceil().clamp(1, 9999);
    final cronPages = (cronCategoryRows.length / _pageSize).ceil().clamp(1, 9999);

    final skillsPageRows = _slicePage(categoryRows, _skillsPage);
    final cronPageRows = _slicePage(cronCategoryRows, _cronPage);

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
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
                  _topToggle('skills', _tab == CatalogTab.skills, () {
                    setState(() {
                      _tab = CatalogTab.skills;
                      _skillsPage = 0;
                    });
                  }),
                  const SizedBox(width: 12),
                  _topToggle('crons', _tab == CatalogTab.crons, () {
                    setState(() {
                      _tab = CatalogTab.crons;
                      _cronPage = 0;
                    });
                  }),
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
                ],
              ),
            ),
            Expanded(
                child: _tab == CatalogTab.skills
                    ? _buildSkillsView(
                        skillsPageRows: skillsPageRows,
                        pages: skillsPages,
                        totalRows: categoryRows.length,
                      )
                    : _buildCronsView(
                        cronPageRows: cronPageRows,
                        pages: cronPages,
                        totalRows: cronCategoryRows.length,
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
              _categoryToggle('not ready', _skillsCategory == SkillsCategory.notReady, () {
                setState(() {
                  _skillsCategory = SkillsCategory.notReady;
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

  Widget _buildCronsView({
    required List<Map<String, dynamic>> cronPageRows,
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
              Text(
                'cron jobs ($totalRows)',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 12),
              _categoryToggle('existing', _cronCategory == CronCategory.existing, () {
                setState(() {
                  _cronCategory = CronCategory.existing;
                  _cronPage = 0;
                });
              }),
              const SizedBox(width: 10),
              _categoryToggle('templates', _cronCategory == CronCategory.templates, () {
                setState(() {
                  _cronCategory = CronCategory.templates;
                  _cronPage = 0;
                });
              }),
              const Spacer(),
              Text(
                '${_cronPage + 1}/$pages',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              const SizedBox(width: 10),
              _pageControl('prev', _cronPage > 0, () {
                setState(() => _cronPage -= 1);
              }),
              const SizedBox(width: 8),
              _pageControl('next', _cronPage + 1 < pages, () {
                setState(() => _cronPage += 1);
              }),
            ],
          ),
        ),
        Expanded(
          child: totalRows == 0
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'no cron jobs configured',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: cronPageRows.map(_cronRow).toList(),
                ),
        ),
      ],
    );
  }

  Widget _topToggle(String label, bool active, VoidCallback onTap) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: active ? t.accentPrimary : t.fgMuted,
        ),
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
    final canInstall = !ready;
    final installing = _installingSkill == name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ready ? 'ready' : 'missing'}  $name',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ready ? t.accentPrimary : t.fgMuted,
                  ),
                ),
              ),
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
          if (!canInstall && _skillsCategory == SkillsCategory.templates)
            Text(
              'template',
              style: theme.textTheme.labelSmall?.copyWith(
                color: t.fgTertiary,
                fontSize: 10,
              ),
            ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14),
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

  Widget _cronRow(Map<String, dynamic> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final id = (row['id'] ?? '(job)').toString();
    final schedule = (row['schedule'] ?? '-').toString();
    final command = (row['command'] ?? row['task'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        '$id  $schedule  $command',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: t.fgTertiary,
          fontSize: 12,
        ),
      ),
    );
  }
}
