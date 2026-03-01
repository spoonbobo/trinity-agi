import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/toast_provider.dart';
import '../../core/cron_utils.dart';
import '../../main.dart' show languageProvider;
import '../../core/providers.dart' show terminalClientProvider;

enum AutomationTab { crons, hooks, webhooks, polls }

enum CronCategory { existing, templates }

class AutomationsDialog extends ConsumerStatefulWidget {
  final AutomationTab initialTab;

  const AutomationsDialog({
    super.key,
    this.initialTab = AutomationTab.crons,
  });

  @override
  ConsumerState<AutomationsDialog> createState() => _AutomationsDialogState();
}

class _AutomationsDialogState extends ConsumerState<AutomationsDialog> {
  late AutomationTab _tab;
  bool _loading = false;
  String? _error;

  // -- Crons state --
  CronCategory _cronCategory = CronCategory.existing;
  List<Map<String, dynamic>> _cronJobs = [];
  int _cronPage = 0;
  static const int _pageSize = 14;
  String? _togglingCronId;
  String? _deletingCronId;

  // -- Cron add form state --
  bool _showAddCronForm = false;
  final _cronNameCtrl = TextEditingController();
  final _cronScheduleCtrl = TextEditingController();
  final _cronMessageCtrl = TextEditingController();
  String _cronSession = 'isolated';
  bool _cronDeleteAfterRun = false;
  bool _addingCron = false;

  // -- Simple schedule mode state --
  bool _simpleMode = true; // true = simple picker, false = raw cron
  ScheduleFrequency _frequency = ScheduleFrequency.dailyAt;
  int _schedHour = 7;
  int _schedMinute = 0;
  int _intervalMinutes = 15;
  int _intervalHours = 1;
  List<int> _selectedDays = [0]; // 0=Mon
  int _dayOfMonth = 1;
  int _oneShotMinutes = 20;

  // -- Hooks state --
  List<Map<String, dynamic>> _hooks = [];
  String? _togglingHook;

  // -- Webhooks state --
  Map<String, dynamic>? _healthData;

  // -- Polls state --
  final _pollQuestionCtrl = TextEditingController();
  final _pollOptionsCtrl = TextEditingController();
  final _pollTargetCtrl = TextEditingController();
  String _pollChannel = 'whatsapp';
  bool _pollMulti = false;
  bool _sendingPoll = false;

  String _stripAnsi(String input) {
    final ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
    return input.replaceAll(ansi, '');
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

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    // Trigger rebuild on cron text changes so the live preview updates.
    _cronScheduleCtrl.addListener(_onCronTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _onCronTextChanged() {
    if (!_simpleMode && mounted) setState(() {});
  }

  @override
  void dispose() {
    _cronScheduleCtrl.removeListener(_onCronTextChanged);
    _cronNameCtrl.dispose();
    _cronScheduleCtrl.dispose();
    _cronMessageCtrl.dispose();
    _pollQuestionCtrl.dispose();
    _pollOptionsCtrl.dispose();
    _pollTargetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final client = ref.read(terminalClientProvider);
    if (!client.isConnected || !client.isAuthenticated) {
      try { await client.connect(); } catch (_) {}
    }

    if (!client.isAuthenticated) {
      setState(() => _error = 'terminal proxy not connected');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Run commands sequentially to avoid output interleaving on the
      // single WebSocket connection. The command queue in the client
      // also serializes, but sequential awaits are clearest.
      final cronRaw = await client.executeCommandForOutput(
        'cron list --all --json', timeout: const Duration(seconds: 30),
      ).catchError((_) => '{}');
      final hooksRaw = await client.executeCommandForOutput(
        'hooks list --json', timeout: const Duration(seconds: 30),
      ).catchError((_) => '{}');
      final healthRaw = await client.executeCommandForOutput(
        'health --json', timeout: const Duration(seconds: 15),
      ).catchError((_) => '{}');

      final cronJson = _decodeJsonObject(cronRaw);
      final hooksJson = _decodeJsonObject(hooksRaw);
      final healthJson = _decodeJsonObject(healthRaw);

      final jobs = ((cronJson['jobs'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      final hooks = ((hooksJson['hooks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      setState(() {
        _cronJobs = jobs;
        _hooks = hooks;
        _healthData = healthJson;
        _cronPage = 0;
      });
    } catch (e) {
      if (!mounted) return;
      final errMsg = 'failed to load automations: $e';
      ToastService.showError(context, errMsg);
      setState(() => _error = errMsg);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Cron helpers
  // ---------------------------------------------------------------------------

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

  List<Map<String, dynamic>> _slicePage(List<Map<String, dynamic>> rows, int page) {
    final start = page * _pageSize;
    if (start >= rows.length) return const [];
    final end = (start + _pageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  Future<void> _toggleCronJob(Map<String, dynamic> job) async {
    final client = ref.read(terminalClientProvider);
    final id = (job['id'] ?? job['jobId'] ?? '').toString();
    if (id.isEmpty) return;
    final enabled = job['enabled'] != false;

    setState(() => _togglingCronId = id);
    try {
      await client.executeCommandForOutput(
        'cron edit $id --${enabled ? 'disable' : 'enable'}',
        timeout: const Duration(seconds: 15),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'toggle failed: $e');
    } finally {
      if (mounted) setState(() => _togglingCronId = null);
    }
  }

  Future<void> _deleteCronJob(Map<String, dynamic> job) async {
    final client = ref.read(terminalClientProvider);
    final id = (job['id'] ?? job['jobId'] ?? '').toString();
    if (id.isEmpty) return;

    setState(() => _deletingCronId = id);
    try {
      await client.executeCommandForOutput(
        'cron remove $id',
        timeout: const Duration(seconds: 15),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'delete failed: $e');
    } finally {
      if (mounted) setState(() => _deletingCronId = null);
    }
  }

  /// Returns the effective schedule expression from whichever mode is active.
  String _effectiveSchedule() {
    if (!_simpleMode) return _cronScheduleCtrl.text.trim();
    return buildCronExpression(
      frequency: _frequency,
      intervalMinutes: _intervalMinutes,
      intervalHours: _intervalHours,
      hour: _schedHour,
      minute: _schedMinute,
      selectedDays: _selectedDays,
      dayOfMonth: _dayOfMonth,
      oneShotMinutes: _oneShotMinutes,
    );
  }

  /// Attempt to switch from cron mode to simple mode by reverse-parsing.
  void _trySwitchToSimple() {
    final parsed = tryParseSimple(_cronScheduleCtrl.text.trim());
    if (parsed != null) {
      setState(() {
        _simpleMode = true;
        _frequency = parsed.frequency;
        _intervalMinutes = parsed.intervalMinutes;
        _intervalHours = parsed.intervalHours;
        _schedHour = parsed.hour;
        _schedMinute = parsed.minute;
        _selectedDays = List.of(parsed.selectedDays);
        _dayOfMonth = parsed.dayOfMonth;
        _oneShotMinutes = parsed.oneShotMinutes;
      });
    } else {
      // Can't parse -- stay in cron mode
      ToastService.showError(context, 'expression too complex for simple mode');
    }
  }

  /// Sync simple-mode fields into the raw cron text controller (for when
  /// user switches from simple to cron).
  void _syncSimpleToCronCtrl() {
    _cronScheduleCtrl.text = _effectiveSchedule();
  }

  /// Pre-fill the add-cron form from a template job's data.
  void _prefillFromTemplate(Map<String, dynamic> job) {
    final name = (job['name'] ?? '').toString();
    final schedule = (job['schedule'] ?? '').toString();
    final command = (job['command'] ?? job['message'] ?? '').toString();
    final session = (job['sessionTarget'] ?? job['session'] ?? 'isolated').toString();
    final deleteAfterRun = job['deleteAfterRun'] == true;
    final parsed = tryParseSimple(schedule);
    setState(() {
      _showAddCronForm = true;
      _cronCategory = CronCategory.existing; // Switch to existing tab to show form
      _cronNameCtrl.text = name;
      _cronScheduleCtrl.text = schedule;
      _cronMessageCtrl.text = command;
      _cronSession = session == 'main' ? 'main' : 'isolated';
      _cronDeleteAfterRun = deleteAfterRun;
      if (parsed != null) {
        _simpleMode = true;
        _frequency = parsed.frequency;
        _intervalMinutes = parsed.intervalMinutes;
        _intervalHours = parsed.intervalHours;
        _schedHour = parsed.hour;
        _schedMinute = parsed.minute;
        _selectedDays = List.of(parsed.selectedDays);
        _dayOfMonth = parsed.dayOfMonth;
        _oneShotMinutes = parsed.oneShotMinutes;
      } else {
        _simpleMode = false;
      }
    });
  }

  Future<void> _addCronJob() async {
    final client = ref.read(terminalClientProvider);
    final name = _cronNameCtrl.text.trim();
    final schedule = _effectiveSchedule();
    final message = _cronMessageCtrl.text.trim();
    if (name.isEmpty || schedule.isEmpty || message.isEmpty) {
      ToastService.showError(context, 'name, schedule, and message are required');
      return;
    }

    // Validate cron expression (skip for one-shot)
    final validationError = validateCron(schedule);
    if (validationError != null) {
      ToastService.showError(context, 'invalid schedule: $validationError');
      return;
    }

    setState(() => _addingCron = true);

    try {
      // Build command
      final isOneShot = schedule.startsWith('+') || schedule.contains('T');
      final scheduleFlag = isOneShot ? '--at "$schedule"' : '--cron "$schedule"';
      final sessionFlag = '--session $_cronSession';
      final payloadFlag = _cronSession == 'main'
          ? '--system-event "$message"'
          : '--message "$message"';
      final deleteFlag = _cronDeleteAfterRun ? '--delete-after-run' : '';
      final announceFlag = _cronSession == 'isolated' ? '--announce' : '';

      final cmd = 'cron add --name "$name" $scheduleFlag $sessionFlag $payloadFlag $announceFlag $deleteFlag'.replaceAll(RegExp(r'\s+'), ' ').trim();

      await client.executeCommandForOutput(cmd, timeout: const Duration(seconds: 30));

      if (!mounted) return;
      ToastService.showInfo(context, 'cron job "$name" added');
      setState(() {
        _showAddCronForm = false;
        _cronNameCtrl.clear();
        _cronScheduleCtrl.clear();
        _cronMessageCtrl.clear();
        _cronSession = 'isolated';
        _cronDeleteAfterRun = false;
        _simpleMode = true;
        _frequency = ScheduleFrequency.dailyAt;
        _schedHour = 7;
        _schedMinute = 0;
        _intervalMinutes = 15;
        _intervalHours = 1;
        _selectedDays = [0];
        _dayOfMonth = 1;
        _oneShotMinutes = 20;
        _cronCategory = CronCategory.existing;
      });
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'add cron failed: $e');
    } finally {
      if (mounted) setState(() => _addingCron = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Hooks helpers
  // ---------------------------------------------------------------------------

  Future<void> _toggleHook(Map<String, dynamic> hook) async {
    final client = ref.read(terminalClientProvider);
    final name = (hook['name'] ?? '').toString();
    if (name.isEmpty) return;
    final disabled = hook['disabled'] == true;

    setState(() => _togglingHook = name);
    try {
      await client.executeCommandForOutput(
        'hooks ${disabled ? 'enable' : 'disable'} $name',
        timeout: const Duration(seconds: 15),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'toggle failed: $e');
    } finally {
      if (mounted) setState(() => _togglingHook = null);
    }
  }

  // ---------------------------------------------------------------------------
  // Polls helpers
  // ---------------------------------------------------------------------------

  Future<void> _sendPoll() async {
    final client = ref.read(terminalClientProvider);
    final question = _pollQuestionCtrl.text.trim();
    final optionsRaw = _pollOptionsCtrl.text.trim();
    final target = _pollTargetCtrl.text.trim();

    if (question.isEmpty || optionsRaw.isEmpty || target.isEmpty) {
      ToastService.showError(context, 'question, options, and target are required');
      return;
    }

    final options = optionsRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (options.length < 2) {
      ToastService.showError(context, 'at least 2 options required (comma-separated)');
      return;
    }

    setState(() => _sendingPoll = true);
    try {
      final optionFlags = options.map((o) => '--poll-option "$o"').join(' ');
      final multiFlag = _pollMulti ? '--poll-multi' : '';
      final cmd = 'message poll --channel $_pollChannel --target $target --poll-question "$question" $optionFlags $multiFlag'.replaceAll(RegExp(r'\s+'), ' ').trim();

      await client.executeCommandForOutput(cmd, timeout: const Duration(seconds: 30));

      if (!mounted) return;
      ToastService.showInfo(context, 'poll sent');
      setState(() {
        _pollQuestionCtrl.clear();
        _pollOptionsCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, 'send poll failed: $e');
    } finally {
      if (mounted) setState(() => _sendingPoll = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final language = ref.watch(languageProvider);

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.86,
        height: MediaQuery.of(context).size.height * 0.84,
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 780),
        child: Column(
          children: [
            // Tab bar header (matches admin dialog pattern)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  _tabToggle(tr(language, 'crons'), AutomationTab.crons),
                  const SizedBox(width: 12),
                  _tabToggle(tr(language, 'hooks'), AutomationTab.hooks),
                  const SizedBox(width: 12),
                  _tabToggle(tr(language, 'webhooks'), AutomationTab.webhooks),
                  const SizedBox(width: 12),
                  _tabToggle(tr(language, 'polls'), AutomationTab.polls),
                  const SizedBox(width: 12),
                  if (_loading)
                    Text('loading...', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
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
            // Tab content
            Expanded(child: _buildTabContent()),
          ],
        ),
      ),
    );
  }

  Widget _tabToggle(String label, AutomationTab tab) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: _tab == tab ? t.accentPrimary : t.fgMuted,
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case AutomationTab.crons:
        return _buildCronsTab();
      case AutomationTab.hooks:
        return _buildHooksTab();
      case AutomationTab.webhooks:
        return _buildWebhooksTab();
      case AutomationTab.polls:
        return _buildPollsTab();
    }
  }

  // ---------------------------------------------------------------------------
  // CRONS TAB
  // ---------------------------------------------------------------------------

  Widget _buildCronsTab() {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    final cronCategoryRows = _cronsForCategory();
    final cronPages = (cronCategoryRows.length / _pageSize).ceil().clamp(1, 9999);
    final cronPageRows = _slicePage(cronCategoryRows, _cronPage);
    final totalRows = cronCategoryRows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-category toolbar
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
                setState(() { _cronCategory = CronCategory.existing; _cronPage = 0; _showAddCronForm = false; });
              }),
              const SizedBox(width: 10),
              _categoryToggle('templates', _cronCategory == CronCategory.templates, () {
                setState(() { _cronCategory = CronCategory.templates; _cronPage = 0; _showAddCronForm = false; });
              }),
              const Spacer(),
              Text(
                '${_cronPage + 1}/$cronPages',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              const SizedBox(width: 10),
              _pageControl('prev', _cronPage > 0, () {
                setState(() => _cronPage -= 1);
              }),
              const SizedBox(width: 8),
              _pageControl('next', _cronPage + 1 < cronPages, () {
                setState(() => _cronPage += 1);
              }),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => setState(() => _showAddCronForm = !_showAddCronForm),
                child: Text(
                  _showAddCronForm ? 'cancel' : 'add',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary),
                ),
              ),
            ],
          ),
        ),
        // Add cron form (collapsible)
        if (_showAddCronForm) _buildAddCronForm(),
        // Content
        Expanded(
          child: totalRows == 0
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _cronCategory == CronCategory.templates
                        ? 'no cron templates'
                        : 'no cron jobs configured',
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

  Widget _buildAddCronForm() {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final schedule = _effectiveSchedule();
    final description = describeCron(schedule);
    final validError = validateCron(schedule);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: title + mode toggle
          Row(
            children: [
              Text('add cron job', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const Spacer(),
              Text('mode: ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(width: 4),
              _categoryToggle('simple', _simpleMode, () {
                if (!_simpleMode) _trySwitchToSimple();
              }),
              const SizedBox(width: 10),
              _categoryToggle('cron', !_simpleMode, () {
                if (_simpleMode) {
                  _syncSimpleToCronCtrl();
                  setState(() => _simpleMode = false);
                }
              }),
            ],
          ),
          const SizedBox(height: 8),
          // Name field
          _formField(_cronNameCtrl, 'name', t, theme),
          const SizedBox(height: 6),
          // Schedule input (mode-dependent)
          if (_simpleMode)
            _buildSimpleSchedule(t, theme)
          else
            _formField(_cronScheduleCtrl, 'cron expression (e.g. 0 7 * * *) or +20m', t, theme),
          const SizedBox(height: 4),
          // Live human-readable preview
          Row(
            children: [
              Text(
                '> ',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              Expanded(
                child: Text(
                  validError != null ? validError : description,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: validError != null ? t.statusError : t.accentPrimary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!_simpleMode) ...[
                const SizedBox(width: 8),
                Text(
                  schedule,
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Message field
          _formField(_cronMessageCtrl, 'message / prompt', t, theme),
          const SizedBox(height: 6),
          // Bottom row: session, options, submit
          Row(
            children: [
              Text('run in: ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(width: 4),
              _categoryToggle('new session', _cronSession == 'isolated', () {
                setState(() => _cronSession = 'isolated');
              }),
              const SizedBox(width: 10),
              _categoryToggle('main chat', _cronSession == 'main', () {
                setState(() => _cronSession = 'main');
              }),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _cronSession == 'isolated'
                      ? 'fresh session each run, results announced back'
                      : 'injects into your main conversation',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _cronDeleteAfterRun = !_cronDeleteAfterRun),
                child: Text(
                  'delete after run: ${_cronDeleteAfterRun ? 'yes' : 'no'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _cronDeleteAfterRun ? t.accentPrimary : t.fgMuted,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _addingCron ? null : _addCronJob,
                child: Text(
                  _addingCron ? 'adding...' : 'submit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _addingCron ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- Simple schedule picker (structured form) --
  Widget _buildSimpleSchedule(ShellTokens t, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Frequency selector row
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('frequency:', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
            ...ScheduleFrequency.values.map((f) {
              return _categoryToggle(
                frequencyLabels[f]!,
                _frequency == f,
                () => setState(() {
                  _frequency = f;
                  // Auto-set delete-after-run for one-shot
                  if (f == ScheduleFrequency.inNMinutes) {
                    _cronDeleteAfterRun = true;
                  }
                }),
              );
            }),
          ],
        ),
        const SizedBox(height: 6),
        // Context-dependent fields
        _buildFrequencyFields(t, theme),
      ],
    );
  }

  Widget _buildFrequencyFields(ShellTokens t, ThemeData theme) {
    switch (_frequency) {
      case ScheduleFrequency.everyNMinutes:
        return Row(
          children: [
            Text('every ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
            ...[5, 10, 15, 20, 30].map((n) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _categoryToggle(
                '${n}m',
                _intervalMinutes == n,
                () => setState(() => _intervalMinutes = n),
              ),
            )),
          ],
        );

      case ScheduleFrequency.everyNHours:
        return Row(
          children: [
            Text('every ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
            ...[1, 2, 3, 4, 6, 8, 12].map((n) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _categoryToggle(
                '${n}h',
                _intervalHours == n,
                () => setState(() => _intervalHours = n),
              ),
            )),
          ],
        );

      case ScheduleFrequency.dailyAt:
        return _buildTimePicker(t, theme);

      case ScheduleFrequency.weeklyOn:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day-of-week toggles
            Row(
              children: [
                Text('days: ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                ...List.generate(7, (i) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      if (_selectedDays.contains(i)) {
                        if (_selectedDays.length > 1) _selectedDays.remove(i);
                      } else {
                        _selectedDays.add(i);
                        _selectedDays.sort();
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _selectedDays.contains(i) ? t.accentPrimary : t.border,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        dayNames[i],
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _selectedDays.contains(i) ? t.accentPrimary : t.fgMuted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                )),
              ],
            ),
            const SizedBox(height: 4),
            _buildTimePicker(t, theme),
          ],
        );

      case ScheduleFrequency.monthlyOn:
        return Row(
          children: [
            Text('day ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
            _buildNumberScroller(
              value: _dayOfMonth,
              min: 1,
              max: 31,
              onChanged: (v) => setState(() => _dayOfMonth = v),
              t: t,
              theme: theme,
            ),
            const SizedBox(width: 12),
            _buildTimePicker(t, theme),
          ],
        );

      case ScheduleFrequency.inNMinutes:
        return Row(
          children: [
            Text('in ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
            ...[5, 10, 15, 20, 30, 60].map((n) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _categoryToggle(
                '${n}m',
                _oneShotMinutes == n,
                () => setState(() => _oneShotMinutes = n),
              ),
            )),
            const SizedBox(width: 4),
            Text('(one-shot)', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10)),
          ],
        );
    }
  }

  Widget _buildTimePicker(ShellTokens t, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('at ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
        _buildNumberScroller(
          value: _schedHour,
          min: 0,
          max: 23,
          onChanged: (v) => setState(() => _schedHour = v),
          t: t,
          theme: theme,
          pad: true,
        ),
        Text(' : ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
        _buildNumberScroller(
          value: _schedMinute,
          min: 0,
          max: 59,
          step: 5,
          onChanged: (v) => setState(() => _schedMinute = v),
          t: t,
          theme: theme,
          pad: true,
        ),
      ],
    );
  }

  Widget _buildNumberScroller({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    required ShellTokens t,
    required ThemeData theme,
    int step = 1,
    bool pad = false,
  }) {
    final display = pad ? value.toString().padLeft(2, '0') : value.toString();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            var next = value - step;
            if (next < min) next = max;
            onChanged(next);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Text(
              '<',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 10),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          constraints: const BoxConstraints(minWidth: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Text(
            display,
            style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary, fontSize: 11),
          ),
        ),
        GestureDetector(
          onTap: () {
            var next = value + step;
            if (next > max) next = min;
            onChanged(next);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Text(
              '>',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _formField(TextEditingController ctrl, String hint, ShellTokens t, ThemeData theme) {
    return SizedBox(
      height: 28,
      child: TextField(
        controller: ctrl,
        style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: theme.textTheme.bodySmall?.copyWith(color: t.fgPlaceholder, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: t.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: t.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: t.accentPrimary, width: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _cronRow(Map<String, dynamic> row) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final id = (row['id'] ?? row['jobId'] ?? '(job)').toString();
    final name = (row['name'] ?? '').toString();
    final schedule = (row['schedule'] ?? '-').toString();
    final enabled = row['enabled'] != false;
    final toggling = _togglingCronId == id;
    final deleting = _deletingCronId == id;
    final sessionTarget = (row['sessionTarget'] ?? '').toString();
    final displayName = name.isNotEmpty ? name : id;
    final humanDesc = describeCron(schedule);
    final isTemplate = _isCronTemplate(row);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: enabled ? t.accentPrimary : t.fgDisabled,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled ? t.fgPrimary : t.fgMuted,
                  ),
                ),
              ),
              Text(
                schedule,
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
              if (sessionTarget.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  sessionTarget == 'main' ? 'main chat' : sessionTarget == 'isolated' ? 'new session' : sessionTarget,
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
              ],
              if (isTemplate) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _prefillFromTemplate(row),
                  child: Text(
                    'use',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: t.accentSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              GestureDetector(
                onTap: toggling ? null : () => _toggleCronJob(row),
                child: Text(
                  toggling ? '...' : (enabled ? 'disable' : 'enable'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: toggling ? t.fgDisabled : t.fgMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: deleting ? null : () => _deleteCronJob(row),
                child: Text(
                  deleting ? '...' : 'delete',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: deleting ? t.fgDisabled : t.statusError,
                  ),
                ),
              ),
            ],
          ),
          // Human-readable description + job ID
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              humanDesc != schedule ? humanDesc : '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: t.accentPrimary,
                fontSize: 11,
              ),
            ),
          ),
          if (name.isNotEmpty && name != id)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Text(
                id,
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HOOKS TAB
  // ---------------------------------------------------------------------------

  Widget _buildHooksTab() {
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
                'hooks (${_hooks.length})',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const Spacer(),
              Text(
                'event-driven scripts that run on agent lifecycle events',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
            ],
          ),
        ),
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              SizedBox(width: 24, child: Text('', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Text('name', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary))),
              Expanded(flex: 3, child: Text('description', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary))),
              Expanded(flex: 2, child: Text('events', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary))),
              SizedBox(width: 60, child: Text('status', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary))),
              SizedBox(width: 50, child: Text('action', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary))),
            ],
          ),
        ),
        Expanded(
          child: _hooks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'no hooks discovered',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  children: _hooks.map(_hookRow).toList(),
                ),
        ),
      ],
    );
  }

  Widget _hookRow(Map<String, dynamic> hook) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final name = (hook['name'] ?? 'unknown').toString();
    final emoji = (hook['emoji'] ?? '').toString();
    final desc = (hook['description'] ?? '').toString();
    final events = ((hook['events'] as List?) ?? []).map((e) => e.toString()).join(', ');
    final eligible = hook['eligible'] == true;
    final disabled = hook['disabled'] == true;
    final source = (hook['source'] ?? '').toString();
    final toggling = _togglingHook == name;

    final statusText = !eligible ? 'ineligible' : (disabled ? 'disabled' : 'enabled');
    final statusColor = !eligible ? t.statusWarning : (disabled ? t.fgMuted : t.accentPrimary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(emoji, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary)),
                if (source.isNotEmpty)
                  Text(source, style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              desc,
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              events,
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              statusText,
              style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
            ),
          ),
          SizedBox(
            width: 50,
            child: eligible
                ? GestureDetector(
                    onTap: toggling ? null : () => _toggleHook(hook),
                    child: Text(
                      toggling ? '...' : (disabled ? 'enable' : 'disable'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: toggling ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  )
                : Text('-', style: theme.textTheme.labelSmall?.copyWith(color: t.fgDisabled)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WEBHOOKS TAB
  // ---------------------------------------------------------------------------

  Widget _buildWebhooksTab() {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    // Extract webhook-relevant info from health data
    final channels = _healthData?['channels'] as Map<String, dynamic>? ?? {};
    final channelOrder = (_healthData?['channelOrder'] as List?)?.cast<String>() ?? [];
    final channelLabels = _healthData?['channelLabels'] as Map<String, dynamic>? ?? {};

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
                'webhooks',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const Spacer(),
              Text(
                'external HTTP triggers for the gateway',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('endpoints', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(height: 6),
              _webhookInfoRow('POST /hooks/wake', 'enqueue system event + trigger heartbeat', t, theme),
              const SizedBox(height: 4),
              _webhookInfoRow('POST /hooks/agent', 'run isolated agent turn with delivery', t, theme),
              const SizedBox(height: 4),
              _webhookInfoRow('POST /hooks/<name>', 'mapped webhook (config-driven)', t, theme),
              const SizedBox(height: 16),
              Text('auth', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(height: 6),
              Text(
                'Authorization: Bearer <hooks.token>  or  x-openclaw-token: <token>',
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11),
              ),
              const SizedBox(height: 16),
              Text('active channels (${channelOrder.length})', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(height: 6),
              ...channelOrder.map((ch) {
                final info = channels[ch] as Map<String, dynamic>? ?? {};
                final label = (channelLabels[ch] ?? ch).toString();
                final configured = info['configured'] == true;
                final linked = info['linked'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: linked ? t.accentPrimary : (configured ? t.statusWarning : t.fgDisabled),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary)),
                      const SizedBox(width: 8),
                      Text(
                        linked ? 'linked' : (configured ? 'configured' : 'off'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: linked ? t.accentPrimary : (configured ? t.statusWarning : t.fgMuted),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              Text('configuration', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(height: 6),
              Text(
                'webhooks are configured in openclaw config:\n'
                '  hooks.enabled: true\n'
                '  hooks.token: "shared-secret"\n'
                '  hooks.path: "/hooks"\n'
                '  hooks.mappings: { ... }\n\n'
                'use "openclaw config set" or edit ~/.openclaw/config.json5',
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _webhookInfoRow(String endpoint, String desc, ShellTokens t, ThemeData theme) {
    return Row(
      children: [
        Text(
          endpoint,
          style: theme.textTheme.bodySmall?.copyWith(color: t.accentPrimary, fontSize: 12),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            desc,
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // POLLS TAB
  // ---------------------------------------------------------------------------

  Widget _buildPollsTab() {
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
                'polls',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const Spacer(),
              Text(
                'send polls to messaging channels',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('supported channels', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(height: 6),
              _pollChannelInfo('whatsapp', '2-12 options, maxSelections supported', t, theme),
              _pollChannelInfo('discord', '2-10 options, configurable duration (1-768h)', t, theme),
              _pollChannelInfo('msteams', 'Adaptive Card polls (gateway-managed)', t, theme),
              const SizedBox(height: 16),
              Text('send a poll', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('channel: ', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                  const SizedBox(width: 4),
                  _categoryToggle('whatsapp', _pollChannel == 'whatsapp', () {
                    setState(() => _pollChannel = 'whatsapp');
                  }),
                  const SizedBox(width: 10),
                  _categoryToggle('discord', _pollChannel == 'discord', () {
                    setState(() => _pollChannel = 'discord');
                  }),
                  const SizedBox(width: 10),
                  _categoryToggle('msteams', _pollChannel == 'msteams', () {
                    setState(() => _pollChannel = 'msteams');
                  }),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setState(() => _pollMulti = !_pollMulti),
                    child: Text(
                      'multi-select: ${_pollMulti ? 'yes' : 'no'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _pollMulti ? t.accentPrimary : t.fgMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _formField(_pollTargetCtrl, 'target (phone, channel id, conversation id)', t, theme),
              const SizedBox(height: 6),
              _formField(_pollQuestionCtrl, 'question', t, theme),
              const SizedBox(height: 6),
              _formField(_pollOptionsCtrl, 'options (comma-separated: Yes, No, Maybe)', t, theme),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _sendingPoll ? null : _sendPoll,
                  child: Text(
                    _sendingPoll ? 'sending...' : 'send poll',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _sendingPoll ? t.fgDisabled : t.accentPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pollChannelInfo(String name, String desc, ShellTokens t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(name, style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary)),
          ),
          Expanded(
            child: Text(desc, style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared toggle widgets
  // ---------------------------------------------------------------------------

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
}
