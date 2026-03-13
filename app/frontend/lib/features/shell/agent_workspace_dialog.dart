import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/http_utils.dart';
import '../../core/theme.dart';
import '../../core/toast_provider.dart';
import '../../core/providers.dart' show terminalClientProvider;
import '../../main.dart' show authClientProvider;

/// Unified agents dialog for the active OpenClaw instance.
/// Combines: ACP configuration, agents list, bindings, and per-agent memory viewer.
/// Opened from the status bar "agents" label (admin+ only).
class AgentWorkspaceDialog extends ConsumerStatefulWidget {
  const AgentWorkspaceDialog({super.key});

  @override
  ConsumerState<AgentWorkspaceDialog> createState() => _AgentWorkspaceDialogState();
}

class _AgentWorkspaceDialogState extends ConsumerState<AgentWorkspaceDialog> {
  bool _loading = true;
  String? _error;
  bool _saving = false;

  // ── ACP state ──────────────────────────────────────────────────────────
  bool _acpEnabled = false;
  bool _acpDispatchEnabled = true;
  String _acpBackend = 'acpx';
  String _acpDefaultAgent = '';
  List<String> _acpAllowedAgents = [];
  int _acpMaxConcurrent = 8;
  int _acpTtlMinutes = 120;

  // ── Agents state ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> _agents = [];
  String? _expandedAgentId;
  bool _showAddAgent = false;
  final _newAgentIdCtrl = TextEditingController();
  final _newAgentNameCtrl = TextEditingController();
  final _newAgentWorkspaceCtrl = TextEditingController();

  // ── Bindings state ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _bindings = [];
  bool _showAddBinding = false;
  final _newBindAgentCtrl = TextEditingController();
  final _newBindChannelCtrl = TextEditingController();
  final _newBindAccountCtrl = TextEditingController();
  final _newBindPeerKindCtrl = TextEditingController();
  final _newBindPeerIdCtrl = TextEditingController();

  // ── Inline editing state ───────────────────────────────────────────────
  final _addAgentTagCtrl = TextEditingController();
  String? _confirmDeleteAgentId;
  int? _confirmDeleteBindingIndex;

  // ── Memory state ───────────────────────────────────────────────────────
  bool _memLoading = false;
  String? _memError;
  String _memContent = '';
  bool _memLoaded = false;
  String _memoryAgentId = 'main';

  // ── Agents defaults (for implicit main agent) ─────────────────────────
  Map<String, dynamic> _agentsDefaults = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _newAgentIdCtrl.dispose();
    _newAgentNameCtrl.dispose();
    _newAgentWorkspaceCtrl.dispose();
    _addAgentTagCtrl.dispose();
    _newBindAgentCtrl.dispose();
    _newBindChannelCtrl.dispose();
    _newBindAccountCtrl.dispose();
    _newBindPeerKindCtrl.dispose();
    _newBindPeerIdCtrl.dispose();
    super.dispose();
  }

  // ── API helpers ─────────────────────────────────────────────────────────

  static const _baseUrl = String.fromEnvironment(
    'AUTH_SERVICE_URL',
    defaultValue: 'http://localhost',
  );

  String? get _token => ref.read(authClientProvider).state.token;
  String? get _activeOpenClawId => ref.read(authClientProvider).state.activeOpenClawId;

  /// GET the full openclaw.json for the active claw via auth-service API.
  Future<Map<String, dynamic>> _getConfig() async {
    final openclawId = _activeOpenClawId;
    if (openclawId == null) throw StateError('no active openclaw');

    final url = '$_baseUrl/auth/openclaws/$openclawId/config';
    final request = html.HttpRequest();
    request.open('GET', url);
    request.setRequestHeader('Authorization', 'Bearer $_token');
    request.setRequestHeader('Content-Type', 'application/json');
    final raw = await safeXhr(request);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// PATCH the full openclaw.json for the active claw via auth-service API.
  Future<void> _saveConfig(Map<String, dynamic> config, {bool restart = false}) async {
    final openclawId = _activeOpenClawId;
    if (openclawId == null) throw StateError('no active openclaw');

    final url = '$_baseUrl/auth/openclaws/$openclawId/config';
    final request = html.HttpRequest();
    request.open('PATCH', url);
    request.setRequestHeader('Authorization', 'Bearer $_token');
    request.setRequestHeader('Content-Type', 'application/json');
    await safeXhr(request, body: jsonEncode({'config': config, 'restart': restart}));
  }

  /// The full config as last loaded from the API.
  Map<String, dynamic> _fullConfig = {};

  // ── Data loading ───────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });

    try {
      _fullConfig = await _getConfig();

      if (!mounted) return;

      // Parse ACP
      final acpData = _fullConfig['acp'] as Map<String, dynamic>?;
      if (acpData != null) {
        _acpEnabled = acpData['enabled'] == true;
        final dispatch = acpData['dispatch'];
        _acpDispatchEnabled = dispatch is Map ? (dispatch['enabled'] != false) : true;
        _acpBackend = (acpData['backend'] as String?) ?? 'acpx';
        _acpDefaultAgent = (acpData['defaultAgent'] as String?) ?? '';
        final aa = acpData['allowedAgents'];
        _acpAllowedAgents = aa is List ? aa.map((e) => e.toString()).toList() : [];
        _acpMaxConcurrent = (acpData['maxConcurrentSessions'] as num?)?.toInt() ?? 8;
        final runtime = acpData['runtime'];
        _acpTtlMinutes = runtime is Map
            ? (runtime['ttlMinutes'] as num?)?.toInt() ?? 120
            : 120;
      }

      // Parse agents
      final agentsData = _fullConfig['agents'] as Map<String, dynamic>?;
      if (agentsData != null) {
        final defaults = agentsData['defaults'];
        _agentsDefaults = defaults is Map<String, dynamic>
            ? Map<String, dynamic>.from(defaults)
            : {};
        final list = agentsData['list'];
        _agents = list is List
            ? list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : [];
      } else {
        _agents = [];
      }

      // Synthesize implicit main agent when agents.list is empty
      if (_agents.isEmpty) {
        final d = _agentsDefaults;
        _agents = [
          <String, dynamic>{
            'id': 'main',
            'name': 'main',
            'default': true,
            'workspace': d['workspace'] ?? '/home/node/.openclaw/workspace',
            '_implicit': true,
            if (d['model'] != null) 'model': d['model'],
            if (d['sandbox'] != null) 'sandbox': d['sandbox'],
          },
        ];
      }

      // Parse bindings
      final bindingsData = _fullConfig['bindings'] as List?;
      if (bindingsData != null) {
        _bindings = bindingsData.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } else {
        _bindings = [];
      }

      // Set memory agent to first agent if not already set or invalid
      if (_agents.isNotEmpty) {
        final agentIds = _agents.map((a) => a['id'] as String? ?? '').toSet();
        if (!agentIds.contains(_memoryAgentId)) {
          _memoryAgentId = _agents.first['id'] as String? ?? 'main';
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);

      // Also load memory for the selected agent
      _loadMemory();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  /// Build a patched copy of the full config with the given changes applied,
  /// then save it via the API.
  Future<void> _patchAndSave(Map<String, dynamic> patch, {bool restart = false}) async {
    final updated = Map<String, dynamic>.from(_fullConfig);
    for (final entry in patch.entries) {
      updated[entry.key] = entry.value;
    }
    await _saveConfig(updated, restart: restart);
    _fullConfig = updated;
  }

  // ── Memory loading ─────────────────────────────────────────────────────

  /// Resolve workspace path for the given agent id.
  String _resolveWorkspace(String agentId) {
    final agent = _agents.firstWhere(
      (a) => a['id'] == agentId,
      orElse: () => _agents.isNotEmpty ? _agents.first : <String, dynamic>{},
    );
    final workspace = agent['workspace'] as String? ??
        _agentsDefaults['workspace'] as String? ??
        '/home/node/.openclaw/workspace';
    // Resolve ~ to /home/node (container home dir)
    return workspace.replaceFirst('~', '/home/node');
  }

  Future<void> _loadMemory({int retries = 1}) async {
    final client = ref.read(terminalClientProvider);
    if (!mounted) return;
    setState(() { _memLoading = true; _memError = null; });
    try {
      // Ensure terminal proxy is connected and authenticated
      if (!client.isConnected || !client.isAuthenticated) {
        await client.connect();
        // Wait for auth handshake to complete
        int waitMs = 0;
        while (!client.isAuthenticated && waitMs < 3000) {
          await Future.delayed(const Duration(milliseconds: 200));
          waitMs += 200;
        }
      }
      if (!mounted) return;
      if (!client.isAuthenticated) {
        setState(() { _memError = 'terminal proxy not authenticated'; });
        return;
      }
      final workspace = _resolveWorkspace(_memoryAgentId);
      final raw = await client.executeCommandForOutput(
        'cat $workspace/MEMORY.md',
        timeout: const Duration(seconds: 20),
      );
      if (!mounted) return;
      // Filter out error frames from terminal proxy in the output
      final lines = raw.split('\n')
          .where((l) => !l.contains('Invalid JSON') && !l.contains('Not authenticated'))
          .join('\n')
          .trim();
      if (lines.isEmpty) {
        setState(() { _memContent = '(empty)'; _memLoaded = true; });
      } else {
        setState(() { _memContent = lines; _memLoaded = true; });
      }
    } catch (e) {
      if (!mounted) return;
      // Retry once if the terminal proxy wasn't ready
      if (retries > 0 && '$e'.contains('Not connected')) {
        await Future.delayed(const Duration(milliseconds: 1000));
        if (mounted) return _loadMemory(retries: retries - 1);
      }
      setState(() { _memError = '$e'; });
    } finally {
      if (mounted) setState(() => _memLoading = false);
    }
  }

  void _switchMemoryAgent(String agentId) {
    setState(() {
      _memoryAgentId = agentId;
      _memLoaded = false;
      _memContent = '';
      _memError = null;
    });
    _loadMemory();
  }

  // ── ACP save ───────────────────────────────────────────────────────────

  Future<void> _saveAcp() async {
    setState(() => _saving = true);
    try {
      await _patchAndSave({
        'acp': {
          'enabled': _acpEnabled,
          'dispatch': {'enabled': _acpDispatchEnabled},
          'backend': _acpBackend,
          'defaultAgent': _acpDefaultAgent,
          'allowedAgents': _acpAllowedAgents,
          'maxConcurrentSessions': _acpMaxConcurrent,
          'runtime': {'ttlMinutes': _acpTtlMinutes},
        },
      });
      if (mounted) ToastService.showInfo(context, 'acp config saved');
    } catch (e) {
      if (mounted) ToastService.showError(context, 'save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Agent operations ───────────────────────────────────────────────────

  Future<void> _addAgent() async {
    final id = _newAgentIdCtrl.text.trim();
    final name = _newAgentNameCtrl.text.trim();
    final workspace = _newAgentWorkspaceCtrl.text.trim();
    if (id.isEmpty) {
      ToastService.showError(context, 'agent id is required');
      return;
    }
    if (_agents.any((a) => a['id'] == id)) {
      ToastService.showError(context, 'agent "$id" already exists');
      return;
    }

    setState(() => _saving = true);
    try {
      final newAgent = <String, dynamic>{
        'id': id,
        if (name.isNotEmpty) 'name': name,
        'workspace': workspace.isNotEmpty ? workspace : '~/.openclaw/workspace-$id',
      };
      final updated = [..._agents.where((a) => a['_implicit'] != true), newAgent];
      final agentsSection = Map<String, dynamic>.from(_fullConfig['agents'] as Map? ?? {});
      agentsSection['list'] = updated;
      await _patchAndSave({'agents': agentsSection}, restart: true);
      _agents = updated;
      _newAgentIdCtrl.clear();
      _newAgentNameCtrl.clear();
      _newAgentWorkspaceCtrl.clear();
      _showAddAgent = false;
      if (mounted) ToastService.showInfo(context, 'agent "$id" added');
    } catch (e) {
      if (mounted) ToastService.showError(context, 'add failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeAgent(String id) async {
    setState(() => _saving = true);
    try {
      final updated = _agents.where((a) => a['id'] != id && a['_implicit'] != true).toList();
      final agentsSection = Map<String, dynamic>.from(_fullConfig['agents'] as Map? ?? {});
      if (updated.isEmpty) {
        agentsSection.remove('list');
      } else {
        agentsSection['list'] = updated;
      }
      await _patchAndSave({'agents': agentsSection}, restart: true);
      // Re-synthesize implicit if empty
      if (updated.isEmpty) {
        final d = _agentsDefaults;
        _agents = [
          <String, dynamic>{
            'id': 'main', 'name': 'main', 'default': true,
            'workspace': d['workspace'] ?? '/home/node/.openclaw/workspace',
            '_implicit': true,
            if (d['model'] != null) 'model': d['model'],
            if (d['sandbox'] != null) 'sandbox': d['sandbox'],
          },
        ];
      } else {
        _agents = updated;
      }
      _confirmDeleteAgentId = null;
      _expandedAgentId = null;
      if (mounted) ToastService.showInfo(context, 'agent "$id" removed');
    } catch (e) {
      if (mounted) ToastService.showError(context, 'remove failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Binding operations ─────────────────────────────────────────────────

  Future<void> _addBinding() async {
    final agentId = _newBindAgentCtrl.text.trim();
    final channel = _newBindChannelCtrl.text.trim();
    if (agentId.isEmpty || channel.isEmpty) {
      ToastService.showError(context, 'agent and channel are required');
      return;
    }

    setState(() => _saving = true);
    try {
      final match = <String, dynamic>{'channel': channel};
      final accountId = _newBindAccountCtrl.text.trim();
      if (accountId.isNotEmpty) match['accountId'] = accountId;
      final peerKind = _newBindPeerKindCtrl.text.trim();
      final peerId = _newBindPeerIdCtrl.text.trim();
      if (peerKind.isNotEmpty && peerId.isNotEmpty) {
        match['peer'] = {'kind': peerKind, 'id': peerId};
      }

      final newBinding = <String, dynamic>{'agentId': agentId, 'match': match};
      final updated = [..._bindings, newBinding];
      await _patchAndSave({'bindings': updated});
      _bindings = updated;
      _newBindAgentCtrl.clear();
      _newBindChannelCtrl.clear();
      _newBindAccountCtrl.clear();
      _newBindPeerKindCtrl.clear();
      _newBindPeerIdCtrl.clear();
      _showAddBinding = false;
      if (mounted) ToastService.showInfo(context, 'binding added');
    } catch (e) {
      if (mounted) ToastService.showError(context, 'add failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeBinding(int index) async {
    setState(() => _saving = true);
    try {
      final updated = [..._bindings]..removeAt(index);
      await _patchAndSave({'bindings': updated.isEmpty ? null : updated});
      _bindings = updated;
      _confirmDeleteBindingIndex = null;
      if (mounted) ToastService.showInfo(context, 'binding removed');
    } catch (e) {
      if (mounted) ToastService.showError(context, 'remove failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Allowed agents tag management ──────────────────────────────────────

  void _addAllowedAgent() {
    final tag = _addAgentTagCtrl.text.trim();
    if (tag.isEmpty || _acpAllowedAgents.contains(tag)) return;
    setState(() => _acpAllowedAgents = [..._acpAllowedAgents, tag]);
    _addAgentTagCtrl.clear();
  }

  void _removeAllowedAgent(String tag) {
    setState(() => _acpAllowedAgents = _acpAllowedAgents.where((a) => a != tag).toList());
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Text('agents',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.accentPrimary)),
                  const Spacer(),
                  if (!_loading) ...[
                    GestureDetector(
                      onTap: _loadAll,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text('refresh',
                          style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('close',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
                    ),
                  ),
                ],
              ),
            ),
            // ── Content ────────────────────────────────────────────────
            Flexible(child: _buildContent(t, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ShellTokens t, ThemeData theme) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('loading config...',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted)),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!,
                style: theme.textTheme.bodySmall?.copyWith(color: t.statusError)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _loadAll,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text('retry',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary)),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAcpSection(t, theme),
          _buildAgentsSection(t, theme),
          _buildBindingsSection(t, theme),
          _buildMemorySection(t, theme),
        ],
      ),
    );
  }

  // ── ACP section ────────────────────────────────────────────────────────

  Widget _buildAcpSection(ShellTokens t, ThemeData theme) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9);
    final valueStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text('acp configuration',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.accentPrimary)),
              const Spacer(),
              if (_saving)
                Text('saving...', style: labelStyle)
              else ...[
                GestureDetector(
                  onTap: _saveAcp,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('save', style: labelStyle?.copyWith(color: t.accentPrimary)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              _boolRow('enabled', _acpEnabled, (v) => setState(() => _acpEnabled = v), t, theme),
              _boolRow('dispatch', _acpDispatchEnabled, (v) => setState(() => _acpDispatchEnabled = v), t, theme),
              _textRow('backend', _acpBackend, (v) => setState(() => _acpBackend = v), t, theme),
              _textRow('default agent', _acpDefaultAgent, (v) => setState(() => _acpDefaultAgent = v), t, theme),
              _intRow('max concurrent', _acpMaxConcurrent, (v) => setState(() => _acpMaxConcurrent = v), t, theme),
              _intRow('ttl (minutes)', _acpTtlMinutes, (v) => setState(() => _acpTtlMinutes = v), t, theme),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 110, child: Text('allowed agents', style: labelStyle)),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ..._acpAllowedAgents.map((agent) => _agentTag(agent, t, theme)),
                        SizedBox(
                          width: 80,
                          height: 18,
                          child: TextField(
                            controller: _addAgentTagCtrl,
                            style: valueStyle?.copyWith(fontSize: 9),
                            decoration: InputDecoration(
                              hintText: '+ add',
                              hintStyle: theme.textTheme.labelSmall?.copyWith(
                                color: t.fgDisabled, fontSize: 9),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              isDense: true,
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
                            onSubmitted: (_) => _addAllowedAgent(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _agentTag(String name, ShellTokens t, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: t.border, width: 0.5),
        borderRadius: kShellBorderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary, fontSize: 9)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _removeAllowedAgent(name),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text('x',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Agents section ─────────────────────────────────────────────────────

  Widget _buildAgentsSection(ShellTokens t, ThemeData theme) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text('agents', style: theme.textTheme.bodySmall?.copyWith(color: t.accentPrimary)),
              const SizedBox(width: 6),
              Text('${_agents.length}', style: labelStyle),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showAddAgent = !_showAddAgent),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(_showAddAgent ? 'cancel' : '+ add',
                      style: labelStyle?.copyWith(color: t.accentPrimary)),
                ),
              ),
            ],
          ),
        ),
        if (_showAddAgent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                _inlineTextField('id *', _newAgentIdCtrl, 80, t, theme),
                const SizedBox(width: 8),
                _inlineTextField('name', _newAgentNameCtrl, 100, t, theme),
                const SizedBox(width: 8),
                _inlineTextField('workspace', _newAgentWorkspaceCtrl, 160, t, theme),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _saving ? null : _addAgent,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('create',
                        style: labelStyle?.copyWith(
                          color: _saving ? t.fgDisabled : t.accentPrimary)),
                  ),
                ),
              ],
            ),
          ),
        if (_agents.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(flex: 2, child: Text('id', style: labelStyle)),
                Expanded(flex: 2, child: Text('name', style: labelStyle)),
                Expanded(flex: 3, child: Text('model', style: labelStyle)),
                SizedBox(width: 50, child: Text('sandbox', style: labelStyle)),
                SizedBox(width: 50, child: Text('default', textAlign: TextAlign.right, style: labelStyle)),
                const SizedBox(width: 40),
              ],
            ),
          ),
        ..._agents.asMap().entries.map((entry) {
          final agent = entry.value;
          final id = agent['id'] as String? ?? '';
          final isExpanded = _expandedAgentId == id;
          final isDefault = agent['default'] == true;
          final isImplicit = agent['_implicit'] == true;
          final name = agent['name'] as String? ?? '';
          final model = _extractModel(agent);
          final sandbox = _extractSandbox(agent);

          return Column(
            children: [
              GestureDetector(
                onTap: () => setState(() => _expandedAgentId = isExpanded ? null : id),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isExpanded ? t.surfaceCard : Colors.transparent,
                      border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          child: Text(isExpanded ? '-' : '+',
                              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9)),
                        ),
                        Expanded(flex: 2, child: Text(id,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: t.fgPrimary, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis)),
                        Expanded(flex: 2, child: Row(
                          children: [
                            Flexible(child: Text(name,
                                style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted),
                                overflow: TextOverflow.ellipsis)),
                            if (isImplicit) ...[
                              const SizedBox(width: 4),
                              Text('(implicit)',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: t.fgDisabled, fontSize: 8)),
                            ],
                          ],
                        )),
                        Expanded(flex: 3, child: Text(model,
                            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9),
                            overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 50, child: Text(sandbox,
                            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9))),
                        SizedBox(
                          width: 50,
                          child: isDefault
                              ? Text('yes', textAlign: TextAlign.right,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: t.accentPrimary, fontSize: 9))
                              : const SizedBox.shrink(),
                        ),
                        SizedBox(
                          width: 40,
                          child: isImplicit
                              ? const SizedBox.shrink()
                              : _confirmDeleteAgentId == id
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _removeAgent(id),
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: Text('yes',
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                  color: t.statusError, fontSize: 9)),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () => setState(() => _confirmDeleteAgentId = null),
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: Text('no',
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                  color: t.fgMuted, fontSize: 9)),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Align(
                                      alignment: Alignment.centerRight,
                                      child: GestureDetector(
                                        onTap: () => setState(() => _confirmDeleteAgentId = id),
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Text('x',
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: t.fgMuted, fontSize: 9)),
                                        ),
                                      ),
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isExpanded) _buildAgentDetail(agent, t, theme),
            ],
          );
        }),
        if (_agents.isEmpty && !_showAddAgent)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('no agents configured',
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted)),
          ),
      ],
    );
  }

  Widget _buildAgentDetail(Map<String, dynamic> agent, ShellTokens t, ThemeData theme) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9);
    final valueStyle = theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 10);
    final workspace = agent['workspace'] as String? ?? '-';
    final model = _extractModel(agent);
    final sandbox = _extractSandbox(agent);

    final identity = agent['identity'] as Map<String, dynamic>?;
    final identityName = identity?['name'] as String? ?? '';
    final identityEmoji = identity?['emoji'] as String? ?? '';

    final tools = agent['tools'] as Map<String, dynamic>?;
    final toolsProfile = tools?['profile'] as String? ?? '';
    final toolsAllow = (tools?['allow'] as List?)?.map((e) => e.toString()).join(', ') ?? '';
    final toolsDeny = (tools?['deny'] as List?)?.map((e) => e.toString()).join(', ') ?? '';

    final runtime = agent['runtime'] as Map<String, dynamic>?;
    final runtimeType = runtime?['type'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(26, 4, 12, 8),
      decoration: BoxDecoration(
        color: t.surfaceCard,
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow('workspace', workspace, labelStyle!, valueStyle!, t),
          _detailRow('model', model, labelStyle, valueStyle, t),
          _detailRow('sandbox', sandbox, labelStyle, valueStyle, t),
          if (identityName.isNotEmpty)
            _detailRow('identity', '$identityEmoji $identityName'.trim(), labelStyle, valueStyle, t),
          if (toolsProfile.isNotEmpty)
            _detailRow('tools.profile', toolsProfile, labelStyle, valueStyle, t),
          if (toolsAllow.isNotEmpty)
            _detailRow('tools.allow', toolsAllow, labelStyle, valueStyle, t),
          if (toolsDeny.isNotEmpty)
            _detailRow('tools.deny', toolsDeny, labelStyle, valueStyle, t),
          if (runtimeType.isNotEmpty)
            _detailRow('runtime', runtimeType, labelStyle, valueStyle, t),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, TextStyle labelStyle,
      TextStyle valueStyle, ShellTokens t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: labelStyle)),
          Expanded(child: Text(value, style: valueStyle, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // ── Bindings section ───────────────────────────────────────────────────

  Widget _buildBindingsSection(ShellTokens t, ThemeData theme) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text('bindings', style: theme.textTheme.bodySmall?.copyWith(color: t.accentPrimary)),
              const SizedBox(width: 6),
              Text('${_bindings.length}', style: labelStyle),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showAddBinding = !_showAddBinding),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(_showAddBinding ? 'cancel' : '+ add',
                      style: labelStyle?.copyWith(color: t.accentPrimary)),
                ),
              ),
            ],
          ),
        ),
        if (_showAddBinding)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _inlineTextField('agent *', _newBindAgentCtrl, 80, t, theme),
                    const SizedBox(width: 8),
                    _inlineTextField('channel *', _newBindChannelCtrl, 80, t, theme),
                    const SizedBox(width: 8),
                    _inlineTextField('account', _newBindAccountCtrl, 80, t, theme),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _inlineTextField('peer kind', _newBindPeerKindCtrl, 80, t, theme),
                    const SizedBox(width: 8),
                    _inlineTextField('peer id', _newBindPeerIdCtrl, 140, t, theme),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _saving ? null : _addBinding,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text('create',
                            style: labelStyle?.copyWith(
                              color: _saving ? t.fgDisabled : t.accentPrimary)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_bindings.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('agent', style: labelStyle)),
                Expanded(flex: 2, child: Text('channel', style: labelStyle)),
                Expanded(flex: 2, child: Text('account', style: labelStyle)),
                Expanded(flex: 3, child: Text('peer', style: labelStyle)),
                const SizedBox(width: 30),
              ],
            ),
          ),
        ..._bindings.asMap().entries.map((entry) {
          final idx = entry.key;
          final binding = entry.value;
          final agentId = binding['agentId'] as String? ?? '-';
          final match = binding['match'] as Map<String, dynamic>? ?? {};
          final channel = match['channel'] as String? ?? '-';
          final accountId = match['accountId'] as String? ?? '';
          final peer = match['peer'] as Map<String, dynamic>?;
          final peerStr = peer != null ? '${peer['kind']}:${peer['id']}' : '';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(agentId,
                    style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary),
                    overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(channel,
                    style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted),
                    overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(accountId,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9),
                    overflow: TextOverflow.ellipsis)),
                Expanded(flex: 3, child: Text(peerStr,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9),
                    overflow: TextOverflow.ellipsis)),
                SizedBox(
                  width: 30,
                  child: _confirmDeleteBindingIndex == idx
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => _removeBinding(idx),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Text('y',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: t.statusError, fontSize: 9)),
                              ),
                            ),
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: () => setState(() => _confirmDeleteBindingIndex = null),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Text('n',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: t.fgMuted, fontSize: 9)),
                              ),
                            ),
                          ],
                        )
                      : Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => setState(() => _confirmDeleteBindingIndex = idx),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Text('x',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: t.fgMuted, fontSize: 9)),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        }),
        if (_bindings.isEmpty && !_showAddBinding)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('no bindings configured',
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted)),
          ),
      ],
    );
  }

  // ── Memory section ─────────────────────────────────────────────────────

  Widget _buildMemorySection(ShellTokens t, ThemeData theme) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text('memory',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.accentPrimary)),
              const SizedBox(width: 10),
              // Agent selector dropdown
              if (_agents.length > 1) ...[
                _buildAgentMemorySelector(t, theme),
              ] else if (_agents.isNotEmpty) ...[
                Text(_agents.first['id'] as String? ?? 'main',
                    style: labelStyle?.copyWith(color: t.fgPrimary)),
              ],
              const Spacer(),
              GestureDetector(
                onTap: _memLoading ? null : _loadMemory,
                child: MouseRegion(
                  cursor: _memLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: Text(_memLoading ? 'loading...' : 'refresh',
                      style: labelStyle?.copyWith(
                        color: _memLoading ? t.fgDisabled : t.accentPrimary)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _memLoading && !_memLoaded
              ? Text('loading...',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted))
              : _memError != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_memError!,
                            style: theme.textTheme.bodySmall?.copyWith(color: t.statusError)),
                        const SizedBox(height: 4),
                        Text('workspace: ${_resolveWorkspace(_memoryAgentId)}/MEMORY.md',
                            style: labelStyle),
                      ],
                    )
                  : _memLoaded
                      ? MarkdownBody(
                          data: _memContent,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: theme.textTheme.bodySmall?.copyWith(
                              color: t.fgPrimary,
                              height: 1.6,
                            ),
                            h1: theme.textTheme.bodyMedium?.copyWith(
                              color: t.fgPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            h2: theme.textTheme.bodyMedium?.copyWith(
                              color: t.fgPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            h3: theme.textTheme.bodySmall?.copyWith(
                              color: t.fgPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            code: theme.textTheme.bodySmall?.copyWith(
                              color: t.accentPrimary,
                              fontSize: 11,
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: t.surfaceCard,
                              border: Border.all(color: t.border, width: 0.5),
                            ),
                            blockquoteDecoration: BoxDecoration(
                              color: t.surfaceCard.withOpacity(0.5),
                              border: Border(
                                left: BorderSide(color: t.border, width: 2),
                              ),
                            ),
                            listBullet: theme.textTheme.bodySmall?.copyWith(
                              color: t.fgMuted,
                            ),
                          ),
                        )
                      : Text('loading...',
                          style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted)),
        ),
      ],
    );
  }

  /// Dropdown-style selector for which agent's memory to view.
  Widget _buildAgentMemorySelector(ShellTokens t, ThemeData theme) {
    return GestureDetector(
      onTap: () {
        // Cycle through agents, or show a dropdown
        final ids = _agents.map((a) => a['id'] as String? ?? '').toList();
        final currentIdx = ids.indexOf(_memoryAgentId);
        final nextIdx = (currentIdx + 1) % ids.length;
        _switchMemoryAgent(ids[nextIdx]);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: t.border, width: 0.5),
            borderRadius: kShellBorderRadiusSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_memoryAgentId,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.accentPrimary, fontSize: 9)),
              const SizedBox(width: 3),
              Icon(Icons.unfold_more, size: 8, color: t.fgMuted),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared field widgets ───────────────────────────────────────────────

  Widget _boolRow(String label, bool value, ValueChanged<bool> onChanged,
      ShellTokens t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9)),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: value ? t.accentPrimary : t.fgDisabled,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(value ? 'on' : 'off',
              style: theme.textTheme.bodySmall?.copyWith(
                color: value ? t.accentPrimary : t.fgMuted,
                fontSize: 10,
              )),
        ],
      ),
    );
  }

  Widget _textRow(String label, String value, ValueChanged<String> onChanged,
      ShellTokens t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9)),
          ),
          Expanded(
            child: SizedBox(
              height: 20,
              child: TextField(
                controller: TextEditingController(text: value),
                style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 10),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  isDense: true,
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
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intRow(String label, int value, ValueChanged<int> onChanged,
      ShellTokens t, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 9)),
          ),
          SizedBox(
            width: 60,
            height: 20,
            child: TextField(
              controller: TextEditingController(text: value.toString()),
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 10),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                isDense: true,
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
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null) onChanged(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineTextField(String hint, TextEditingController ctrl, double width,
      ShellTokens t, ThemeData theme) {
    return SizedBox(
      width: width,
      height: 20,
      child: TextField(
        controller: ctrl,
        style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 9),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: theme.textTheme.labelSmall?.copyWith(color: t.fgDisabled, fontSize: 9),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          isDense: true,
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
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _extractModel(Map<String, dynamic> agent) {
    final m = agent['model'];
    if (m is String) return m;
    if (m is Map) return (m['primary'] as String?) ?? '-';
    return '-';
  }

  String _extractSandbox(Map<String, dynamic> agent) {
    final sb = agent['sandbox'];
    if (sb is Map) return (sb['mode'] as String?) ?? 'off';
    return '-';
  }
}
