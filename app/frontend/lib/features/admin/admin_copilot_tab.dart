import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_client.dart';
import '../../core/copilot_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/toast_provider.dart';

String _formatCopilotTimestamp(DateTime ts) {
  final h = ts.hour.toString().padLeft(2, '0');
  final m = ts.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

class AdminCopilotTab extends ConsumerStatefulWidget {
  const AdminCopilotTab({super.key});

  @override
  ConsumerState<AdminCopilotTab> createState() => _AdminCopilotTabState();
}

class _AdminCopilotTabState extends ConsumerState<AdminCopilotTab> {
  final _client = CopilotClient();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  List<CopilotMessage> _messages = const [];
  CopilotStatus? _status;
  String? _sessionId;
  String? _error;
  bool _loading = false;
  bool _sending = false;
  String? _lastOpenClawId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMessages());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final authState = ref.read(authClientProvider).state;
    final token = authState.token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await _client.fetchStatus(
        token,
        openclawId: authState.activeOpenClawId,
      );
      final response = await _client.fetchMessages(
        token,
        openclawId: authState.activeOpenClawId,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _sessionId = response.sessionId;
        _messages = response.messages;
        _lastOpenClawId = authState.activeOpenClawId;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final authState = ref.read(authClientProvider).state;
    final token = authState.token;
    final text = _controller.text.trim();
    if (token == null || token.isEmpty || text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      final response = await _client.sendPrompt(
        token,
        text,
        openclawId: authState.activeOpenClawId,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = response.sessionId;
        _messages = response.messages;
        _error = null;
      });
      await _refreshStatusSilently();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _controller.text = text;
      ToastService.showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resetSession() async {
    final authState = ref.read(authClientProvider).state;
    final token = authState.token;
    if (token == null || token.isEmpty) return;

    try {
      final response = await _client.resetSession(
        token,
        openclawId: authState.activeOpenClawId,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = response.sessionId;
        _messages = response.messages;
        _error = null;
      });
      await _refreshStatusSilently();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, e.toString());
    }
  }

  Future<void> _refreshStatusSilently() async {
    final authState = ref.read(authClientProvider).state;
    final token = authState.token;
    if (token == null || token.isEmpty) return;
    try {
      final status = await _client.fetchStatus(
        token,
        openclawId: authState.activeOpenClawId,
      );
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final authState = ref.watch(authClientProvider).state;
    final currentOpenClawId = authState.activeOpenClawId;

    if (_lastOpenClawId != currentOpenClawId && !_loading && !_sending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMessages());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Text(
                'copilot',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: t.accentPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                authState.activeOpenClaw?.name ?? 'no active openclaw',
                style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
              ),
              if (_status != null) ...[
                const SizedBox(width: 12),
                Text(
                  _status!.desiredDefaultAvailable
                      ? 'model: ${_status!.defaults['opencode'] ?? _status!.defaults['chat'] ?? _status!.defaults['default'] ?? '-'}'
                      : 'model missing: ${_status!.desiredDefaultModel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _status!.desiredDefaultAvailable
                        ? t.fgTertiary
                        : t.statusWarning,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _status!.connectedProviders.isEmpty
                      ? 'providers: none'
                      : 'providers: ${_status!.connectedProviders.join(', ')}',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
              ],
              if (_sessionId != null) ...[
                const SizedBox(width: 12),
                Text(
                  _sessionId!,
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: _sending ? null : _resetSession,
                child: Text(
                  'new session',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _sending ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: t.statusError),
            ),
          ),
        if (_status != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Text(
              'role=${_status!.user?['role'] ?? '-'}  perms=${(_status!.user?['permissions'] as List?)?.length ?? 0}  workspace=${_status!.workspace}',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
            ),
          ),
        Expanded(
          child: _loading
              ? Center(
                  child: Text(
                    'loading...',
                    style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isUser = message.role == 'user';
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        constraints: const BoxConstraints(maxWidth: 680),
                        decoration: BoxDecoration(
                          border: Border.all(color: t.border, width: 0.5),
                          color: isUser ? t.surfaceCard : Colors.transparent,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUser ? 'you' : 'copilot',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isUser ? t.accentPrimary : t.fgMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              message.content,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: t.fgPrimary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatCopilotTimestamp(message.createdAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: t.fgTertiary,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 6,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'ask copilot...',
                    isDense: true,
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: t.border),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: t.accentPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _sending ? null : _send,
                child: Text(
                  _sending ? 'sending...' : 'send',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _sending ? t.fgDisabled : t.accentPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
