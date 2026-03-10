import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_client.dart';
import '../../core/copilot_client.dart';
import '../../core/providers.dart';
import '../../core/terminal_client.dart';
import '../../core/theme.dart';
import '../../core/toast_provider.dart';
import '../terminal/pty_terminal_view.dart';

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
  final _focusNode = FocusNode();

  List<CopilotMessage> _messages = const [];
  CopilotStatus? _status;
  CopilotModelsResponse? _models;
  String? _sessionId;
  String? _error;
  bool _loading = false;
  bool _sending = false;
  String? _lastOpenClawId;
  TerminalProxyClient? _ptyClient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
      _ensurePtyClient();
    });
  }

  @override
  void dispose() {
    _ptyClient?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _ensurePtyClient() async {
    if (_ptyClient != null) return;
    final client = createScopedTerminalClient(ref);
    _ptyClient = client;
    try {
      await client.connect();
    } catch (_) {}
    if (mounted) setState(() {});
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
      final results = await Future.wait([
        _client.fetchStatus(token, openclawId: authState.activeOpenClawId),
        _client.fetchMessages(token, openclawId: authState.activeOpenClawId),
        _client.fetchModels(token, openclawId: authState.activeOpenClawId),
      ]);
      if (!mounted) return;
      final status = results[0] as CopilotStatus;
      final response = results[1] as CopilotMessagesResponse;
      final models = results[2] as CopilotModelsResponse;
      setState(() {
        _status = status;
        _sessionId = response.sessionId;
        _messages = response.messages;
        _models = models;
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

    // Optimistic: show user message immediately
    final optimistic = CopilotMessage(
      id: 'pending-${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );
    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
    });
    _controller.clear();
    _scrollToBottom();

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
      // Remove optimistic message on failure, restore text
      setState(() {
        _messages = _messages.where((m) => m.id != optimistic.id).toList();
      });
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
      final results = await Future.wait([
        _client.fetchStatus(token, openclawId: authState.activeOpenClawId),
        _client.fetchModels(token, openclawId: authState.activeOpenClawId),
      ]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as CopilotStatus;
        _models = results[1] as CopilotModelsResponse;
      });
    } catch (_) {}
  }

  Future<void> _switchModel(String model) async {
    final authState = ref.read(authClientProvider).state;
    final token = authState.token;
    if (token == null || token.isEmpty) return;
    try {
      final updated = await _client.setModel(
        token,
        model,
        openclawId: authState.activeOpenClawId,
      );
      if (!mounted) return;
      setState(() => _models = updated);
      await _refreshStatusSilently();
    } catch (e) {
      if (!mounted) return;
      ToastService.showError(context, e.toString());
    }
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _currentModelLabel() {
    final current = _models?.current ??
        _status?.actualModel ??
        _status?.defaults['opencode']?.toString() ??
        _status?.defaults['chat']?.toString() ??
        _status?.defaults['default']?.toString();
    if (current != null && current.isNotEmpty) return current;
    return 'no model';
  }

  void _showModelPicker() {
    final models = _models?.available ?? [];
    if (models.isEmpty) return;
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final current = _models?.current;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx + 120, offset.dy + 36, 0, 0),
      color: t.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      items: models.map((m) {
        final isCurrent = m == current;
        return PopupMenuItem<String>(
          value: m,
          height: 32,
          child: Text(
            isCurrent ? '$m  (active)' : m,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isCurrent ? t.accentPrimary : t.fgPrimary,
            ),
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null && selected != current) {
        _switchModel(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authClientProvider).state;
    final currentOpenClawId = authState.activeOpenClawId;

    if (_lastOpenClawId != currentOpenClawId && !_loading && !_sending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ptyClient?.dispose();
        _ptyClient = null;
        setState(() {});
        _loadMessages();
        _ensurePtyClient();
      });
    }

    final t = ShellTokens.of(context);
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _buildConversationPanel(authState),
        ),
        Container(width: 0.5, color: t.border),
        SizedBox(
          width: 430,
          child: _buildTerminalPane(authState),
        ),
      ],
    );
  }

  Widget _buildConversationPanel(AuthState authState) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
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
                GestureDetector(
                  onTap: (_models?.available.isNotEmpty ?? false)
                      ? _showModelPicker
                      : null,
                  child: MouseRegion(
                    cursor: (_models?.available.isNotEmpty ?? false)
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentModelLabel(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.accentPrimary,
                          ),
                        ),
                        if (_models != null && _models!.available.length > 1) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.unfold_more, size: 12, color: t.fgMuted),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status!.connectedProviders.isEmpty
                        ? 'providers: none'
                        : 'providers: ${_status!.connectedProviders.join(', ')}',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                const Spacer(),
              if (_sessionId != null) ...[
                const SizedBox(width: 12),
                Text(
                  _sessionId!,
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
              ],
              const SizedBox(width: 12),
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
        Expanded(
          child: _loading
              ? Center(
                  child: Text(
                    'loading...',
                    style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted),
                  ),
                )
              : _messages.isEmpty && !_sending
                  ? _buildEmptyState(theme, t)
                  : _buildMessageList(theme, t),
        ),
        _buildInputBar(theme, t),
      ],
    );
  }

  Widget _buildTerminalPane(AuthState authState) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final clawName = authState.activeOpenClaw?.name ?? 'no active claw';

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
                'interactive terminal',
                style: theme.textTheme.bodySmall?.copyWith(color: t.accentSecondary),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadiusSm,
                  border: Border.all(color: t.border, width: 0.5),
                  color: t.surfaceBase,
                ),
                child: Text(
                  clawName,
                  style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _ptyClient == null
              ? Center(
                  child: Text(
                    'connecting terminal...',
                    style: theme.textTheme.bodySmall?.copyWith(color: t.fgMuted),
                  ),
                )
              : PtyTerminalView(
                  key: ValueKey(authState.activeOpenClawId ?? 'none'),
                  client: _ptyClient!,
                  showHeader: false,
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme, ShellTokens t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadius,
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Icon(Icons.smart_toy_outlined, size: 16, color: t.fgMuted),
          ),
          const SizedBox(height: 10),
          Text('ask copilot anything',
            style: TextStyle(fontSize: 11, color: t.fgMuted, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text('type a message below',
            style: TextStyle(fontSize: 10, color: t.fgPlaceholder)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _templateChip('openclaw gateway status', theme, t),
              _templateChip('openclaw dashboard', theme, t),
              _templateChip('openclaw channels list', theme, t),
              _templateChip('openclaw channels status', theme, t),
              _templateChip('openclaw channels capabilities --channel <name>', theme, t),
              _templateChip('openclaw channels login --channel <name>', theme, t),
              _templateChip('openclaw doctor', theme, t),
              _templateChip('openclaw logs --follow', theme, t),
            ],
          ),
        ],
      ),
    );
  }

  Widget _templateChip(String command, ThemeData theme, ShellTokens t) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: command));
        _controller.text = 'Explain when to use: `$command` and expected output.';
        _focusNode.requestFocus();
        ToastService.showInfo(context, 'command copied: $command');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: t.border, width: 0.5),
          borderRadius: kShellBorderRadiusSm,
          color: t.surfaceBase,
        ),
        child: Text(
          command,
          style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary),
        ),
      ),
    );
  }

  Widget _buildMessageList(ThemeData theme, ShellTokens t) {
    final itemCount = _messages.length + (_sending ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == _messages.length && _sending) {
          return _CopilotThinkingIndicator();
        }
        final message = _messages[index];
        final prev = index > 0 ? _messages[index - 1] : null;
        final isNewSender = prev == null || prev.role != message.role;
        if (message.role == 'user') {
          return _CopilotUserBubble(message: message, isNewSender: isNewSender);
        }
        return _CopilotAssistantBubble(
          message: message,
          isNewSender: isNewSender,
        );
      },
    );
  }

  Widget _buildInputBar(ThemeData theme, ShellTokens t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: t.border, width: 0.5),
                borderRadius: kShellBorderRadiusSm,
                color: t.surfaceBase,
              ),
              child: Focus(
                onKeyEvent: _handleKeyEvent,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 6,
                  style: theme.textTheme.bodySmall?.copyWith(color: t.fgPrimary),
                  decoration: InputDecoration(
                    hintText: 'ask copilot... (enter to send)',
                    hintStyle: theme.textTheme.bodySmall?.copyWith(color: t.fgPlaceholder),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: kShellBorderRadiusSm,
                border: Border.all(
                  color: _sending ? t.fgDisabled : t.accentPrimary.withOpacity(0.45),
                  width: 0.5,
                ),
                color: _sending ? t.surfaceCard : t.accentPrimary.withOpacity(0.08),
              ),
              child: Text(
                _sending ? 'sending...' : 'send',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _sending ? t.fgDisabled : t.accentPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User bubble -- matches main chat _UserBubble style
// ---------------------------------------------------------------------------

class _CopilotUserBubble extends StatefulWidget {
  final CopilotMessage message;
  final bool isNewSender;
  const _CopilotUserBubble({required this.message, this.isNewSender = true});

  @override
  State<_CopilotUserBubble> createState() => _CopilotUserBubbleState();
}

class _CopilotUserBubbleState extends State<_CopilotUserBubble> {
  bool _hovering = false;
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.message.content)).then((_) {
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final baseStyle = theme.textTheme.bodyLarge ?? const TextStyle();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.isNewSender ? 14 : 3,
          bottom: 1,
          left: 80,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadius,
                  color: t.accentPrimary.withOpacity(0.08),
                  border: Border.all(color: t.accentPrimary.withOpacity(0.18), width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SelectionArea(
                      child: MarkdownBody(
                        data: widget.message.content,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet(
                          p: baseStyle.copyWith(color: t.fgPrimary),
                          code: baseStyle.copyWith(fontSize: 13, color: t.accentPrimary, backgroundColor: t.surfaceCodeInline),
                          codeblockDecoration: BoxDecoration(
                            borderRadius: kShellBorderRadiusSm,
                            color: t.surfaceBase,
                            border: Border(left: BorderSide(color: t.border, width: 2)),
                          ),
                          codeblockPadding: const EdgeInsets.only(left: 12, top: 8, bottom: 8, right: 8),
                          strong: baseStyle.copyWith(fontWeight: FontWeight.bold, color: t.fgPrimary),
                          em: baseStyle.copyWith(fontStyle: FontStyle.italic, color: t.fgPrimary),
                          a: baseStyle.copyWith(
                            color: t.accentPrimary,
                            decoration: TextDecoration.underline,
                            decorationColor: t.accentPrimaryMuted,
                          ),
                        ),
                        onTapLink: (text, href, title) {
                          if (href != null) {
                            Clipboard.setData(ClipboardData(text: href));
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hovering)
                          GestureDetector(
                            onTap: _copy,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _copied ? Icons.check : Icons.copy,
                                      size: 12,
                                      color: _copied ? t.accentPrimary : t.fgMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _copied ? 'copied' : 'copy',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: _copied ? t.accentPrimary : t.fgMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Text(
                          _formatCopilotTimestamp(widget.message.createdAt),
                          style: TextStyle(fontSize: 9, color: t.fgMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assistant bubble -- matches main chat _AssistantBubble style
// ---------------------------------------------------------------------------

class _CopilotAssistantBubble extends StatefulWidget {
  final CopilotMessage message;
  final bool isNewSender;

  const _CopilotAssistantBubble({
    required this.message,
    this.isNewSender = true,
  });

  @override
  State<_CopilotAssistantBubble> createState() => _CopilotAssistantBubbleState();
}

class _CopilotAssistantBubbleState extends State<_CopilotAssistantBubble> {
  bool _hovering = false;
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.message.content)).then((_) {
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final baseStyle = theme.textTheme.bodyLarge ?? const TextStyle();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.isNewSender ? 14 : 3,
          bottom: 1,
          right: 48,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isNewSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Text(
                  'copilot',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.fgTertiary,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: kShellBorderRadius,
                color: t.surfaceCard,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectionArea(
                    child: MarkdownBody(
                      data: widget.message.content,
                      selectable: false,
                      builders: {
                        'pre': _CopyableCodeBlockBuilder(t, baseStyle),
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: baseStyle,
                        h1: baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: t.fgPrimary),
                        h2: baseStyle.copyWith(fontSize: 15, fontWeight: FontWeight.bold, color: t.fgPrimary),
                        h3: baseStyle.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                        code: baseStyle.copyWith(fontSize: 13, color: t.accentPrimary, backgroundColor: t.surfaceCodeInline),
                        codeblockDecoration: BoxDecoration(
                          borderRadius: kShellBorderRadiusSm,
                          color: t.surfaceBase,
                          border: Border(left: BorderSide(color: t.border, width: 2)),
                        ),
                        codeblockPadding: const EdgeInsets.only(left: 12, top: 8, bottom: 8, right: 8),
                        blockquoteDecoration: BoxDecoration(
                          borderRadius: kShellBorderRadiusSm,
                          border: Border(left: BorderSide(color: t.fgDisabled, width: 2)),
                        ),
                        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                        listBullet: baseStyle.copyWith(color: t.fgTertiary),
                        strong: baseStyle.copyWith(fontWeight: FontWeight.bold),
                        em: baseStyle.copyWith(fontStyle: FontStyle.italic),
                        a: baseStyle.copyWith(
                          color: t.accentPrimary,
                          decoration: TextDecoration.underline,
                          decorationColor: t.accentPrimaryMuted,
                        ),
                        tableHead: baseStyle.copyWith(fontWeight: FontWeight.bold),
                        tableBorder: TableBorder.all(color: t.border, width: 0.5),
                        tableHeadAlign: TextAlign.left,
                        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.border, width: 0.5)),
                        ),
                      ),
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          Clipboard.setData(ClipboardData(text: href));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _formatCopilotTimestamp(widget.message.createdAt),
                        style: TextStyle(fontSize: 9, color: t.fgMuted),
                      ),
                      const Spacer(),
                      if (_hovering)
                        GestureDetector(
                          onTap: _copy,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _copied ? Icons.check : Icons.copy,
                                  size: 12,
                                  color: _copied ? t.accentPrimary : t.fgMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _copied ? 'copied' : 'copy',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _copied ? t.accentPrimary : t.fgMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyableCodeBlockBuilder extends MarkdownElementBuilder {
  final ShellTokens tokens;
  final TextStyle baseStyle;

  _CopyableCodeBlockBuilder(this.tokens, this.baseStyle);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.trimRight();
    if (code.isEmpty) return const SizedBox.shrink();
    return _CopilotCodeBlock(
      code: code,
      tokens: tokens,
      baseStyle: baseStyle,
    );
  }
}

class _CopilotCodeBlock extends StatefulWidget {
  final String code;
  final ShellTokens tokens;
  final TextStyle baseStyle;

  const _CopilotCodeBlock({
    required this.code,
    required this.tokens,
    required this.baseStyle,
  });

  @override
  State<_CopilotCodeBlock> createState() => _CopilotCodeBlockState();
}

class _CopilotCodeBlockState extends State<_CopilotCodeBlock> {
  bool _copied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code)).then((_) {
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: BoxDecoration(
        borderRadius: kShellBorderRadiusSm,
        color: t.surfaceBase,
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(
                  'code',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.fgMuted,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _copyCode,
                  child: Text(
                    _copied ? 'copied' : 'copy',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _copied ? t.accentPrimary : t.fgMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SelectableText(
              widget.code,
              style: widget.baseStyle.copyWith(
                color: t.accentPrimary,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thinking indicator -- same pulsing dots as main chat _StreamingIndicator
// ---------------------------------------------------------------------------

class _CopilotThinkingIndicator extends StatefulWidget {
  @override
  State<_CopilotThinkingIndicator> createState() => _CopilotThinkingIndicatorState();
}

class _CopilotThinkingIndicatorState extends State<_CopilotThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4, right: 80),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadius,
              color: t.surfaceCard,
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final phase = _controller.value;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (index) {
                        final offset = (phase - (index * 0.2)) % 1.0;
                        final pulse = (1.0 - (offset - 0.5).abs() * 2.0).clamp(0.0, 1.0);
                        final opacity = 0.25 + (pulse * 0.55);
                        return Padding(
                          padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: t.accentPrimary.withOpacity(opacity),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'thinking',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.fgTertiary,
                    fontSize: 11,
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
