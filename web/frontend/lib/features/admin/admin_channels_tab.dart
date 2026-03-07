import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/toast_provider.dart';
import '../../core/terminal_client.dart';
import '../../core/providers.dart' show terminalClientProvider, createScopedTerminalClient;
import '../../main.dart' show authClientProvider;
import '../terminal/terminal_view.dart';

// ---------------------------------------------------------------------------
// Known channel definitions
// ---------------------------------------------------------------------------

class _ChannelField {
  final String key;
  final String label;
  final String type; // text, number, bool, select, list
  final List<String>? options; // for select type
  final String? hint;

  const _ChannelField(this.key, this.label, this.type, {this.options, this.hint});
}

class _ChannelDef {
  final String id;
  final String label;
  final List<_ChannelField> specificFields;
  final List<String> setupCommands;

  const _ChannelDef(this.id, this.label, this.specificFields, this.setupCommands);
}

const _dmPolicies = ['pairing', 'allowlist', 'open', 'disabled'];
const _groupPolicies = ['allowlist', 'open', 'disabled'];

const _commonFields = <_ChannelField>[
  _ChannelField('enabled', 'enabled', 'bool'),
  _ChannelField('dmPolicy', 'dm policy', 'select', options: _dmPolicies),
  _ChannelField('allowFrom', 'allow from', 'list', hint: '+15551234567, +447700900123'),
  _ChannelField('groupPolicy', 'group policy', 'select', options: _groupPolicies),
  _ChannelField('groupAllowFrom', 'group allow from', 'list', hint: '+15551234567'),
  _ChannelField('mediaMaxMb', 'media max MB', 'number', hint: '50'),
];

/// Fields that can be overridden per-account
const _accountOverrideFields = <_ChannelField>[
  _ChannelField('enabled', 'enabled', 'bool'),
  _ChannelField('dmPolicy', 'dm policy', 'select', options: _dmPolicies),
  _ChannelField('allowFrom', 'allow from', 'list', hint: '+15551234567'),
  _ChannelField('groupPolicy', 'group policy', 'select', options: _groupPolicies),
  _ChannelField('groupAllowFrom', 'group allow from', 'list', hint: '+15551234567'),
  _ChannelField('sendReadReceipts', 'send read receipts', 'bool'),
];

const _knownChannels = <_ChannelDef>[
  _ChannelDef('whatsapp', 'WhatsApp', [
    _ChannelField('selfChatMode', 'self-chat mode', 'bool'),
    _ChannelField('sendReadReceipts', 'send read receipts', 'bool'),
    _ChannelField('textChunkLimit', 'text chunk limit', 'number', hint: '4000'),
    _ChannelField('chunkMode', 'chunk mode', 'select', options: ['length', 'newline']),
    _ChannelField('debounceMs', 'debounce (ms)', 'number', hint: '0'),
    _ChannelField('ackReaction.emoji', 'ack reaction emoji', 'text', hint: ''),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels login --channel whatsapp', 'channels status', 'channels list']),
  _ChannelDef('telegram', 'Telegram', [
    _ChannelField('botToken', 'bot token', 'text', hint: 'your-bot-token'),
    _ChannelField('historyLimit', 'history limit', 'number', hint: '50'),
    _ChannelField('replyToMode', 'reply-to mode', 'select', options: ['off', 'first', 'all']),
    _ChannelField('linkPreview', 'link preview', 'bool'),
    _ChannelField('streaming', 'streaming', 'select', options: ['off', 'partial', 'block', 'progress']),
    _ChannelField('reactionNotifications', 'reaction notifications', 'select', options: ['off', 'own', 'all']),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels status', 'channels list', 'doctor']),
  _ChannelDef('discord', 'Discord', [
    _ChannelField('token', 'bot token', 'text', hint: 'your-bot-token'),
    _ChannelField('historyLimit', 'history limit', 'number', hint: '20'),
    _ChannelField('replyToMode', 'reply-to mode', 'select', options: ['off', 'first', 'all']),
    _ChannelField('streaming', 'streaming', 'select', options: ['off', 'partial', 'block', 'progress']),
    _ChannelField('textChunkLimit', 'text chunk limit', 'number', hint: '2000'),
    _ChannelField('allowBots', 'allow bots', 'bool'),
    _ChannelField('threadBindings.enabled', 'thread bindings', 'bool'),
    _ChannelField('reactionNotifications', 'reaction notifications', 'select', options: ['off', 'own', 'all', 'allowlist']),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels status', 'channels list', 'doctor']),
  _ChannelDef('slack', 'Slack', [
    _ChannelField('botToken', 'bot token', 'text', hint: 'xoxb-...'),
    _ChannelField('appToken', 'app token', 'text', hint: 'xapp-...'),
    _ChannelField('historyLimit', 'history limit', 'number', hint: '50'),
    _ChannelField('replyToMode', 'reply-to mode', 'select', options: ['off', 'first', 'all']),
    _ChannelField('streaming', 'streaming', 'select', options: ['off', 'partial', 'block', 'progress']),
    _ChannelField('textChunkLimit', 'text chunk limit', 'number', hint: '4000'),
    _ChannelField('allowBots', 'allow bots', 'bool'),
    _ChannelField('reactionNotifications', 'reaction notifications', 'select', options: ['off', 'own', 'all', 'allowlist']),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels status', 'channels list', 'doctor']),
  _ChannelDef('signal', 'Signal', [
    _ChannelField('account', 'account', 'text', hint: '+15555550123'),
    _ChannelField('cliPath', 'CLI path', 'text', hint: 'signal-cli'),
    _ChannelField('httpUrl', 'daemon URL', 'text', hint: 'http://127.0.0.1:8080'),
    _ChannelField('historyLimit', 'history limit', 'number', hint: '50'),
    _ChannelField('sendReadReceipts', 'send read receipts', 'bool'),
    _ChannelField('reactionNotifications', 'reaction notifications', 'select', options: ['off', 'own', 'all', 'allowlist']),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels status', 'channels list', 'doctor']),
  _ChannelDef('googlechat', 'Google Chat', [
    _ChannelField('serviceAccountFile', 'service account file', 'text', hint: '/path/to/service-account.json'),
    _ChannelField('audienceType', 'audience type', 'select', options: ['app-url', 'project-number']),
    _ChannelField('audience', 'audience', 'text', hint: 'https://gateway.example.com/googlechat'),
    _ChannelField('webhookPath', 'webhook path', 'text', hint: '/googlechat'),
    _ChannelField('botUser', 'bot user', 'text', hint: 'users/1234567890'),
    _ChannelField('typingIndicator', 'typing indicator', 'select', options: ['message', 'off']),
  ], ['channels status', 'channels list', 'doctor']),
  _ChannelDef('irc', 'IRC', [
    _ChannelField('host', 'host', 'text', hint: 'irc.libera.chat'),
    _ChannelField('port', 'port', 'number', hint: '6697'),
    _ChannelField('tls', 'TLS', 'bool'),
    _ChannelField('nick', 'nick', 'text', hint: 'openclaw-bot'),
    _ChannelField('nickserv.enabled', 'NickServ enabled', 'bool'),
    _ChannelField('nickserv.password', 'NickServ password', 'text', hint: 'password'),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels status', 'channels list', 'doctor']),
  _ChannelDef('imessage', 'iMessage', [
    _ChannelField('cliPath', 'CLI path', 'text', hint: 'imsg'),
    _ChannelField('dbPath', 'DB path', 'text', hint: '~/Library/Messages/chat.db'),
    _ChannelField('remoteHost', 'remote host', 'text', hint: 'user@gateway-host'),
    _ChannelField('historyLimit', 'history limit', 'number', hint: '50'),
    _ChannelField('includeAttachments', 'include attachments', 'bool'),
    _ChannelField('service', 'service', 'select', options: ['auto', 'iMessage', 'SMS']),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels status', 'channels list', 'doctor']),
  _ChannelDef('bluebubbles', 'BlueBubbles', [
    _ChannelField('serverUrl', 'server URL', 'text', hint: 'http://192.168.1.100:1234'),
    _ChannelField('password', 'password', 'text', hint: 'api-password'),
    _ChannelField('webhookPath', 'webhook path', 'text', hint: '/bluebubbles-webhook'),
    _ChannelField('sendReadReceipts', 'send read receipts', 'bool'),
    _ChannelField('blockStreaming', 'block streaming', 'bool'),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['channels add bluebubbles --http-url "http://HOST:PORT" --password "PASSWORD"', 'channels status', 'channels list']),
  _ChannelDef('msteams', 'MS Teams', [
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['plugins install @openclaw/msteams', 'channels status', 'channels list']),
  _ChannelDef('mattermost', 'Mattermost', [
    _ChannelField('botToken', 'bot token', 'text', hint: 'mm-token'),
    _ChannelField('baseUrl', 'base URL', 'text', hint: 'https://chat.example.com'),
    _ChannelField('chatmode', 'chat mode', 'select', options: ['oncall', 'onmessage', 'onchar']),
    _ChannelField('textChunkLimit', 'text chunk limit', 'number', hint: '4000'),
    _ChannelField('chunkMode', 'chunk mode', 'select', options: ['length', 'newline']),
    _ChannelField('configWrites', 'config writes', 'bool'),
  ], ['plugins install @openclaw/mattermost', 'channels status', 'channels list']),
];

// ---------------------------------------------------------------------------
// Sub-view enum for channel detail panel
// ---------------------------------------------------------------------------

enum _DetailView { config, terminal }

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class AdminChannelsTab extends ConsumerStatefulWidget {
  const AdminChannelsTab({super.key});

  @override
  ConsumerState<AdminChannelsTab> createState() => _AdminChannelsTabState();
}

class _AdminChannelsTabState extends ConsumerState<AdminChannelsTab> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _channelsConfig = {};
  Map<String, dynamic> _healthChannels = {};
  String? _expandedChannel;
  _DetailView _detailView = _DetailView.config;

  // Per-field editing
  String? _editingFieldKey; // e.g. "whatsapp:dmPolicy" or "whatsapp:accounts:biz:dmPolicy"
  final _fieldController = TextEditingController();
  final _fieldFocus = FocusNode();

  // Add-account inline editor
  bool _addingAccount = false;
  final _accountIdController = TextEditingController();
  final _accountIdFocus = FocusNode();

  // Scoped terminal client for channel onboarding (separate WebSocket session)
  TerminalProxyClient? _scopedTerminalClient;
  String? _scopedTerminalChannelId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _fieldController.dispose();
    _fieldFocus.dispose();
    _accountIdController.dispose();
    _accountIdFocus.dispose();
    _disposeScopedTerminal();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scoped terminal lifecycle
  // ---------------------------------------------------------------------------

  void _disposeScopedTerminal() {
    _scopedTerminalClient?.dispose();
    _scopedTerminalClient = null;
    _scopedTerminalChannelId = null;
  }

  Future<void> _ensureScopedTerminal(String channelId) async {
    if (_scopedTerminalClient != null && _scopedTerminalChannelId == channelId) {
      return; // Already have a terminal for this channel
    }
    _disposeScopedTerminal();
    final client = createScopedTerminalClient(ref);
    _scopedTerminalChannelId = channelId;
    _scopedTerminalClient = client;
    try {
      await client.connect();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  String _stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
  }

  Map<String, dynamic> _tryParseJson(String raw) {
    final stripped = _stripAnsi(raw).trim();
    if (stripped.isEmpty) return {};
    try {
      final parsed = jsonDecode(stripped);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    final start = stripped.indexOf('{');
    final end = stripped.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final parsed = jsonDecode(stripped.substring(start, end + 1));
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
    }
    return {};
  }

  Future<void> _load() async {
    final client = ref.read(terminalClientProvider);
    if (!client.isConnected || !client.isAuthenticated) {
      try {
        await client.connect();
      } catch (_) {}
    }

    if (!client.isAuthenticated) {
      setState(() => _error = 'terminal proxy not connected');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final configRaw = await client.executeCommandForOutput(
        'config get channels',
        timeout: const Duration(seconds: 15),
      );
      final healthRaw = await client.executeCommandForOutput(
        'health --json',
        timeout: const Duration(seconds: 15),
      );

      if (!mounted) return;

      final configParsed = _tryParseJson(configRaw);
      final healthParsed = _tryParseJson(healthRaw);
      final healthChannels = healthParsed['channels'] as Map<String, dynamic>? ?? {};

      setState(() {
        _channelsConfig = configParsed;
        _healthChannels = healthChannels;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'failed to load channels: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Config writing
  // ---------------------------------------------------------------------------

  Future<void> _setConfigValue(String channel, String fieldPath, String value) async {
    final client = ref.read(terminalClientProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fullPath = 'channels.$channel.$fieldPath';
      await client.executeCommandForOutput(
        'config set $fullPath $value',
        timeout: const Duration(seconds: 10),
      );
      if (!mounted) return;
      // Refresh config to reflect changes
      final configRaw = await client.executeCommandForOutput(
        'config get channels',
        timeout: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _channelsConfig = _tryParseJson(configRaw);
        _editingFieldKey = null;
        _fieldController.clear();
      });
      ToastService.showInfo(context, '$fullPath updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'config set failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enableChannel(String channelId) async {
    await _setConfigValue(channelId, 'enabled', 'true');
  }

  Future<void> _disableChannel(String channelId) async {
    await _setConfigValue(channelId, 'enabled', 'false');
  }

  // ---------------------------------------------------------------------------
  // Field value helpers
  // ---------------------------------------------------------------------------

  dynamic _getNestedValue(Map<String, dynamic> map, String dotPath) {
    final parts = dotPath.split('.');
    dynamic current = map;
    for (final part in parts) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  String _displayValue(dynamic value) {
    if (value == null) return '--';
    if (value is List) return value.map((e) => e.toString()).join(', ');
    if (value is Map) return jsonEncode(value);
    return value.toString();
  }

  void _startEditField(String configPath, _ChannelField field, dynamic currentValue) {
    final editKey = '$configPath:${field.key}';
    String textValue;
    if (field.type == 'list' && currentValue is List) {
      textValue = currentValue.map((e) => e.toString()).join(', ');
    } else if (field.type == 'bool') {
      final newVal = !(currentValue == true);
      _setConfigValue(configPath, field.key, newVal.toString());
      return;
    } else if (field.type == 'select') {
      textValue = currentValue?.toString() ?? '';
    } else {
      textValue = currentValue?.toString() ?? '';
    }

    setState(() {
      _editingFieldKey = editKey;
      _fieldController.text = textValue;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fieldFocus.requestFocus();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingFieldKey = null;
      _fieldController.clear();
    });
  }

  Future<void> _saveField(String configPath, _ChannelField field) async {
    final raw = _fieldController.text.trim();
    String value;

    if (field.type == 'list') {
      final items = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      value = jsonEncode(items);
    } else if (field.type == 'number') {
      value = raw;
    } else if (field.type == 'bool') {
      value = raw.toLowerCase() == 'true' ? 'true' : 'false';
    } else {
      if (raw.startsWith('{') || raw.startsWith('[') || raw == 'true' || raw == 'false') {
        value = raw;
      } else {
        value = '"$raw"';
      }
    }

    await _setConfigValue(configPath, field.key, value);
  }

  // ---------------------------------------------------------------------------
  // Account management
  // ---------------------------------------------------------------------------

  Future<void> _addAccount(String channelId) async {
    final accountId = _accountIdController.text.trim();
    if (accountId.isEmpty) return;
    setState(() => _addingAccount = false);
    _accountIdController.clear();
    await _setConfigValue(channelId, 'accounts.$accountId.enabled', 'true');
  }

  void _startAddAccount() {
    setState(() {
      _addingAccount = true;
      _accountIdController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _accountIdFocus.requestFocus();
    });
  }

  void _cancelAddAccount() {
    setState(() {
      _addingAccount = false;
      _accountIdController.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Channel status
  // ---------------------------------------------------------------------------

  _ChannelStatus _getChannelStatus(String channelId) {
    final healthInfo = _healthChannels[channelId];
    if (healthInfo is Map<String, dynamic>) {
      if (healthInfo['linked'] == true) return _ChannelStatus.linked;
      if (healthInfo['configured'] == true) return _ChannelStatus.configured;
    }
    final config = _channelsConfig[channelId];
    if (config is Map<String, dynamic>) {
      if (config['enabled'] == false) return _ChannelStatus.disabled;
      return _ChannelStatus.configured;
    }
    return _ChannelStatus.off;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  List<String> _getChannelIds() {
    final knownIds = _knownChannels.map((c) => c.id).toSet();
    final configIds = _channelsConfig.keys.toSet();
    final allIds = <String>[...knownIds];
    for (final id in configIds) {
      if (!knownIds.contains(id)) allIds.add(id);
    }
    return allIds;
  }

  _ChannelDef? _getChannelDef(String id) {
    for (final def in _knownChannels) {
      if (def.id == id) return def;
    }
    return null;
  }

  List<String> _getSetupCommands(String channelId) {
    final def = _getChannelDef(channelId);
    if (def != null) return def.setupCommands;
    return ['channels status', 'channels list', 'doctor'];
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final channelIds = _getChannelIds();
    final configuredCount =
        channelIds.where((id) => _channelsConfig.containsKey(id)).length;

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
                'channels ($configuredCount configured)',
                style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
              ),
              const SizedBox(width: 8),
              Text(
                ref.watch(authClientProvider).state.activeOpenClaw?.name ?? '',
                style: theme.textTheme.labelSmall?.copyWith(color: t.accentSecondary, fontSize: 9),
              ),
              const SizedBox(width: 12),
              if (_loading)
                Text('loading...',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: t.fgTertiary)),
              if (_error != null)
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: t.statusError),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const Spacer(),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: _buildHeaderRow(t, theme),
        ),
        // Channel rows
        Expanded(
          child: channelIds.isEmpty && !_loading
              ? Center(
                  child: Text(
                    'no channels available',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: t.fgPlaceholder),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: channelIds.length,
                  itemBuilder: (context, index) {
                    final channelId = channelIds[index];
                    return _buildChannelSection(channelId, t, theme);
                  },
                ),
        ),
        // Footer caption
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Text(
            'channel config is written to openclaw.json via "config set". '
            'use the terminal view for interactive onboarding (QR codes, token setup).',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: t.fgTertiary, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(ShellTokens t, ThemeData theme) {
    final style =
        theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10);
    return Row(
      children: [
        SizedBox(width: 20, child: Text('', style: style)),
        SizedBox(width: 120, child: Text('channel', style: style)),
        SizedBox(width: 80, child: Text('status', style: style)),
        SizedBox(width: 90, child: Text('dm policy', style: style)),
        SizedBox(width: 90, child: Text('group policy', style: style)),
        Expanded(child: Text('allow from', style: style)),
        SizedBox(
            width: 80,
            child: Text('actions', style: style, textAlign: TextAlign.right)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Channel summary row
  // ---------------------------------------------------------------------------

  Widget _buildChannelSection(
      String channelId, ShellTokens t, ThemeData theme) {
    final isExpanded = _expandedChannel == channelId;
    final channelConfig =
        _channelsConfig[channelId] as Map<String, dynamic>? ?? {};
    final status = _getChannelStatus(channelId);
    final def = _getChannelDef(channelId);
    final label = def?.label ?? channelId;
    final isConfigured = _channelsConfig.containsKey(channelId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary row
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedChannel = null;
                _detailView = _DetailView.config;
              } else {
                _expandedChannel = channelId;
                _detailView = _DetailView.config;
              }
              _editingFieldKey = null;
              _fieldController.clear();
              _addingAccount = false;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isExpanded ? t.surfaceCard : Colors.transparent,
              border:
                  Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    isExpanded ? '-' : '+',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgMuted, fontSize: 11),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isConfigured ? t.fgPrimary : t.fgMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor(status, t),
                        ),
                      ),
                      Text(
                        _statusLabel(status),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _statusColor(status, t),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    _displayValue(channelConfig['dmPolicy']),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgPrimary, fontSize: 11),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    _displayValue(channelConfig['groupPolicy']),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgPrimary, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Text(
                    _displayValue(channelConfig['allowFrom']),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: t.fgMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isConfigured &&
                          channelConfig['enabled'] != false)
                        GestureDetector(
                          onTap: _loading
                              ? null
                              : () => _disableChannel(channelId),
                          child: Text(
                            'disable',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _loading
                                  ? t.fgDisabled
                                  : t.statusError,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      if (isConfigured &&
                          channelConfig['enabled'] == false)
                        GestureDetector(
                          onTap: _loading
                              ? null
                              : () => _enableChannel(channelId),
                          child: Text(
                            'enable',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _loading
                                  ? t.fgDisabled
                                  : t.accentPrimary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      if (!isConfigured)
                        GestureDetector(
                          onTap: _loading
                              ? null
                              : () => _enableChannel(channelId),
                          child: Text(
                            'enable',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _loading
                                  ? t.fgDisabled
                                  : t.accentPrimary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expanded detail
        if (isExpanded)
          _buildChannelDetailPanel(channelId, channelConfig, def, t, theme),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Channel detail panel (config + terminal sub-views)
  // ---------------------------------------------------------------------------

  Widget _buildChannelDetailPanel(
    String channelId,
    Map<String, dynamic> channelConfig,
    _ChannelDef? def,
    ShellTokens t,
    ThemeData theme,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceCard,
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sub-view toggle header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                _detailToggle('config', _DetailView.config, t, theme),
                const SizedBox(width: 12),
                _detailToggle('terminal', _DetailView.terminal, t, theme),
                const Spacer(),
                Text(
                  def?.label ?? channelId,
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10),
                ),
              ],
            ),
          ),
          // Sub-view content
          if (_detailView == _DetailView.config)
            _buildConfigView(channelId, channelConfig, def, t, theme)
          else
            _buildTerminalView(channelId, t, theme),
        ],
      ),
    );
  }

  Widget _detailToggle(String label, _DetailView view, ShellTokens t, ThemeData theme) {
    final isActive = _detailView == view;
    return GestureDetector(
      onTap: () {
        if (view == _DetailView.terminal) {
          _ensureScopedTerminal(_expandedChannel ?? '');
        }
        setState(() => _detailView = view);
      },
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isActive ? t.accentPrimary : t.fgMuted,
          fontSize: 11,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Config view (field editor + accounts)
  // ---------------------------------------------------------------------------

  Widget _buildConfigView(
    String channelId,
    Map<String, dynamic> channelConfig,
    _ChannelDef? def,
    ShellTokens t,
    ThemeData theme,
  ) {
    final sectionHeader = theme.textTheme.labelSmall
        ?.copyWith(color: t.fgTertiary, fontSize: 10);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Common fields
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 4),
            child: Text('common', style: sectionHeader),
          ),
          ..._commonFields.map(
              (field) => _buildFieldRow(channelId, field, channelConfig, t, theme)),
          // Channel-specific fields
          if (def != null && def.specificFields.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 4),
              child: Text('${def.label.toLowerCase()} specific', style: sectionHeader),
            ),
            ...def.specificFields.map(
                (field) => _buildFieldRow(channelId, field, channelConfig, t, theme)),
          ],
          // Accounts section
          _buildAccountsSection(channelId, channelConfig, t, theme),
          // Extra fields
          ..._buildExtraFields(channelId, channelConfig, def, t, theme),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Multi-account section
  // ---------------------------------------------------------------------------

  Widget _buildAccountsSection(
    String channelId,
    Map<String, dynamic> channelConfig,
    ShellTokens t,
    ThemeData theme,
  ) {
    final accounts = channelConfig['accounts'] as Map<String, dynamic>? ?? {};
    final accountIds = accounts.keys.toList()..sort();
    final sectionHeader = theme.textTheme.labelSmall
        ?.copyWith(color: t.fgTertiary, fontSize: 10);
    final actionStyle = theme.textTheme.labelSmall
        ?.copyWith(color: t.accentPrimary, fontSize: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 4),
          child: Row(
            children: [
              Text('accounts (${accountIds.length})', style: sectionHeader),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loading ? null : _startAddAccount,
                child: Text(
                  'add account',
                  style: actionStyle?.copyWith(
                    color: _loading ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Add account inline
        if (_addingAccount)
          _buildAddAccountRow(channelId, t, theme),
        // Existing accounts
        ...accountIds.map((accountId) {
          final accountConfig = accounts[accountId] as Map<String, dynamic>? ?? {};
          return _buildAccountRow(channelId, accountId, accountConfig, t, theme);
        }),
        if (accountIds.isEmpty && !_addingAccount)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 2),
            child: Text(
              'no accounts configured (single-account mode)',
              style: theme.textTheme.bodySmall?.copyWith(color: t.fgPlaceholder, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildAddAccountRow(String channelId, ShellTokens t, ThemeData theme) {
    final inputStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final actionStyle =
        theme.textTheme.labelSmall?.copyWith(fontSize: 10);

    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text('new account id', style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11))),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _accountIdController,
              focusNode: _accountIdFocus,
              style: inputStyle?.copyWith(color: t.accentSecondary),
              decoration: InputDecoration(
                hintText: 'e.g. default, personal, biz',
                hintStyle: inputStyle?.copyWith(color: t.fgPlaceholder),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
              onSubmitted: (_) => _addAccount(channelId),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loading ? null : () => _addAccount(channelId),
            child: Text('save',
                style: actionStyle?.copyWith(
                  color: _loading ? t.fgDisabled : t.accentPrimary,
                )),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _cancelAddAccount,
            child: Text('cancel',
                style: actionStyle?.copyWith(color: t.fgMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow(
    String channelId,
    String accountId,
    Map<String, dynamic> accountConfig,
    ShellTokens t,
    ThemeData theme,
  ) {
    final configPath = '$channelId.accounts.$accountId';
    final labelStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.accentSecondary, fontSize: 11);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account header
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 6, bottom: 2),
          child: Row(
            children: [
              Text(accountId, style: labelStyle),
              const SizedBox(width: 8),
              if (accountConfig.isNotEmpty)
                Text(
                  '(${accountConfig.length} fields)',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary, fontSize: 10),
                ),
            ],
          ),
        ),
        // Account override fields
        ..._accountOverrideFields.map((field) {
          final currentValue = _getNestedValue(accountConfig, field.key);
          // Only show fields that are set or being edited
          final editKey = '$configPath:${field.key}';
          final isEditing = _editingFieldKey == editKey;
          if (currentValue == null && !isEditing) return const SizedBox.shrink();
          return _buildFieldRow(configPath, field, accountConfig, t, theme);
        }),
        // Show any extra account fields not in our known list
        ..._buildAccountExtraFields(configPath, accountConfig, t, theme),
        // "edit more fields" link to reveal all override fields
        Padding(
          padding: const EdgeInsets.only(left: 40, top: 2, bottom: 2),
          child: GestureDetector(
            onTap: () {
              // Pick the first unset field and start editing it
              for (final field in _accountOverrideFields) {
                if (_getNestedValue(accountConfig, field.key) == null) {
                  _startEditField(configPath, field, null);
                  return;
                }
              }
            },
            child: Text(
              'add override',
              style: theme.textTheme.labelSmall?.copyWith(
                color: t.accentPrimary,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAccountExtraFields(
    String configPath,
    Map<String, dynamic> accountConfig,
    ShellTokens t,
    ThemeData theme,
  ) {
    final knownKeys = _accountOverrideFields.map((f) => f.key.split('.').first).toSet();
    final extraKeys = accountConfig.keys.where((k) => !knownKeys.contains(k)).toList()..sort();
    if (extraKeys.isEmpty) return [];

    final labelStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11);
    final valueStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

    return extraKeys.map((key) {
      final value = accountConfig[key];
      return Padding(
        padding: const EdgeInsets.only(left: 40, top: 2, bottom: 2),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(key, style: labelStyle)),
            Expanded(
              child: Text(
                _displayValue(value),
                style: valueStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Terminal view (embedded onboarding terminal)
  // ---------------------------------------------------------------------------

  Widget _buildTerminalView(String channelId, ShellTokens t, ThemeData theme) {
    final client = _scopedTerminalClient;
    if (client == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'connecting terminal...',
          style: theme.textTheme.bodySmall?.copyWith(color: t.fgTertiary),
        ),
      );
    }

    return SizedBox(
      height: 280,
      child: TerminalView(
        client: client,
        showInput: true,
        suggestedCommands: _getSetupCommands(channelId),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Field row builder (shared by config view + account rows)
  // ---------------------------------------------------------------------------

  Widget _buildFieldRow(
    String configPath, // e.g. "whatsapp" or "whatsapp.accounts.biz"
    _ChannelField field,
    Map<String, dynamic> config,
    ShellTokens t,
    ThemeData theme,
  ) {
    final editKey = '$configPath:${field.key}';
    final isEditing = _editingFieldKey == editKey;
    final currentValue = _getNestedValue(config, field.key);
    final labelStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11);
    final valueStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final actionStyle =
        theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary, fontSize: 10);

    // Increase left padding for account fields
    final isAccountField = configPath.contains('.accounts.');
    final leftPad = isAccountField ? 40.0 : 20.0;

    return Padding(
      padding: EdgeInsets.only(left: leftPad, top: 2, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: isAccountField ? 140.0 : 160.0,
            child: Text(field.label, style: labelStyle),
          ),
          if (isEditing && field.type != 'bool')
            _buildInlineEditor(configPath, field, t, theme)
          else ...[
            // Value display
            Expanded(
              child: field.type == 'bool'
                  ? Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(2)),
                            color: currentValue == true
                                ? t.accentPrimary
                                : Colors.transparent,
                            border: Border.all(
                              color: currentValue == true
                                  ? t.accentPrimary
                                  : t.border,
                              width: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          currentValue == true ? 'true' : (currentValue == false ? 'false' : '--'),
                          style: valueStyle?.copyWith(
                            color: currentValue == true
                                ? t.accentPrimary
                                : (currentValue == false ? t.fgMuted : t.fgPlaceholder),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      _displayValue(currentValue),
                      style: valueStyle?.copyWith(
                        color: currentValue != null ? t.fgPrimary : t.fgPlaceholder,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            // Edit action
            SizedBox(
              width: 40,
              child: GestureDetector(
                onTap: _loading
                    ? null
                    : () => _startEditField(configPath, field, currentValue),
                child: Text(
                  field.type == 'bool' ? 'toggle' : 'edit',
                  style: actionStyle?.copyWith(
                    color: _loading ? t.fgDisabled : t.accentPrimary,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineEditor(
    String configPath,
    _ChannelField field,
    ShellTokens t,
    ThemeData theme,
  ) {
    final inputStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);
    final actionStyle =
        theme.textTheme.labelSmall?.copyWith(fontSize: 10);

    if (field.type == 'select' && field.options != null) {
      return Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...field.options!.map((opt) {
              final isSelected = _fieldController.text == opt;
              return GestureDetector(
                onTap: () {
                  setState(() => _fieldController.text = opt);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: kShellBorderRadius,
                    border: Border.all(
                      color: isSelected ? t.accentPrimary : t.border,
                      width: 0.5,
                    ),
                    color: isSelected
                        ? t.accentPrimary.withOpacity(0.1)
                        : Colors.transparent,
                  ),
                  child: Text(
                    opt,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isSelected ? t.accentPrimary : t.fgMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: _loading ? null : () => _saveField(configPath, field),
              child: Text('save',
                  style: actionStyle?.copyWith(
                    color: _loading ? t.fgDisabled : t.accentPrimary,
                  )),
            ),
            GestureDetector(
              onTap: _cancelEdit,
              child: Text('cancel',
                  style: actionStyle?.copyWith(color: t.fgMuted)),
            ),
          ],
        ),
      );
    }

    // Text / number / list editor
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _fieldController,
              focusNode: _fieldFocus,
              style: inputStyle,
              keyboardType: field.type == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                hintText: field.hint ?? field.key,
                hintStyle: inputStyle?.copyWith(color: t.fgPlaceholder),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
                  borderSide:
                      BorderSide(color: t.accentPrimary, width: 0.5),
                ),
              ),
              onSubmitted: (_) => _saveField(configPath, field),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loading ? null : () => _saveField(configPath, field),
            child: Text('save',
                style: actionStyle?.copyWith(
                  color: _loading ? t.fgDisabled : t.accentPrimary,
                )),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _cancelEdit,
            child: Text('cancel',
                style: actionStyle?.copyWith(color: t.fgMuted)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Extra fields (in config but not in our known field definitions)
  // ---------------------------------------------------------------------------

  List<Widget> _buildExtraFields(
    String channelId,
    Map<String, dynamic> channelConfig,
    _ChannelDef? def,
    ShellTokens t,
    ThemeData theme,
  ) {
    final knownKeys = <String>{};
    for (final f in _commonFields) {
      knownKeys.add(f.key.split('.').first);
    }
    if (def != null) {
      for (final f in def.specificFields) {
        knownKeys.add(f.key.split('.').first);
      }
    }
    knownKeys.add('accounts'); // Handled separately

    final extraKeys =
        channelConfig.keys.where((k) => !knownKeys.contains(k)).toList()..sort();
    if (extraKeys.isEmpty) return [];

    final sectionHeader = theme.textTheme.labelSmall
        ?.copyWith(color: t.fgTertiary, fontSize: 10);
    final labelStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgMuted, fontSize: 11);
    final valueStyle =
        theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary, fontSize: 11);

    return [
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 4),
        child: Text('other config', style: sectionHeader),
      ),
      ...extraKeys.map((key) {
        final value = channelConfig[key];
        return Padding(
          padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
          child: Row(
            children: [
              SizedBox(width: 160, child: Text(key, style: labelStyle)),
              Expanded(
                child: Text(
                  _displayValue(value),
                  style: valueStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }),
    ];
  }

  // ---------------------------------------------------------------------------
  // Status helpers
  // ---------------------------------------------------------------------------

  Color _statusColor(_ChannelStatus status, ShellTokens t) {
    switch (status) {
      case _ChannelStatus.linked:
        return t.accentPrimary;
      case _ChannelStatus.configured:
        return t.statusWarning;
      case _ChannelStatus.disabled:
        return t.fgDisabled;
      case _ChannelStatus.off:
        return t.fgTertiary;
    }
  }

  String _statusLabel(_ChannelStatus status) {
    switch (status) {
      case _ChannelStatus.linked:
        return 'linked';
      case _ChannelStatus.configured:
        return 'ready';
      case _ChannelStatus.disabled:
        return 'disabled';
      case _ChannelStatus.off:
        return 'off';
    }
  }
}

enum _ChannelStatus { linked, configured, disabled, off }
