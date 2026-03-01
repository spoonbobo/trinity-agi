import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/gateway_client.dart' as gw;
import '../../models/ws_frame.dart';
import '../../core/providers.dart';

String _formatTimestamp(DateTime ts) {
  final h = ts.hour.toString().padLeft(2, '0');
  final m = ts.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// A single entry in the chat stream.
class ChatEntry {
  final String role; // 'user', 'assistant', 'tool', 'system'
  final String content;
  final String? toolName;
  final bool isStreaming;
  final DateTime timestamp;
  final List<Map<String, dynamic>>? attachments;

  ChatEntry({
    required this.role,
    required this.content,
    this.toolName,
    this.isStreaming = false,
    this.attachments,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatEntry copyWith({String? content, bool? isStreaming}) => ChatEntry(
        role: role,
        content: content ?? this.content,
        toolName: toolName,
        isStreaming: isStreaming ?? this.isStreaming,
        attachments: attachments,
        timestamp: timestamp,
      );
}

class ChatStreamView extends ConsumerStatefulWidget {
  const ChatStreamView({super.key});

  @override
  ConsumerState<ChatStreamView> createState() => _ChatStreamViewState();
}

class _ChatStreamViewState extends ConsumerState<ChatStreamView> {
  final List<ChatEntry> _entries = [];
  final _scrollController = ScrollController();
  StreamSubscription<WsEvent>? _chatSub;
  bool _agentThinking = false;
  bool _showScrollToBottom = false;
  String _currentSession = 'main';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToChatEvents();
    });
  }

  void _onScrollPositionChanged() {
    final shouldShow = !_isNearBottom && _entries.isNotEmpty;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _subscribeToChatEvents() {
    _scrollController.addListener(_onScrollPositionChanged);
    final client = ref.read(gatewayClientProvider);

    // Listen for user messages sent through the prompt bar
    client.addListener(_onClientChange);

    _chatSub = client.chatEvents.listen((event) {
      _handleChatEvent(event);
    });
  }

  void _onClientChange() {
    // Re-subscribe if reconnected
    if (ref.read(gatewayClientProvider).state == gw.ConnectionState.connected) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final client = ref.read(gatewayClientProvider);
    final sessionKey = ref.read(activeSessionProvider);
    debugPrint('[Chat] _loadHistory sessionKey=$sessionKey');
    try {
      final response = await client.getChatHistory(sessionKey: sessionKey, limit: 50);
      debugPrint('[Chat] history ok=${response.ok} payload keys=${response.payload?.keys.toList()}');
      if (response.ok && response.payload != null) {
        // Try 'messages' first, fall back to 'history' or 'entries'
        final messages = response.payload?['messages']
            ?? response.payload?['history']
            ?? response.payload?['entries'];
        debugPrint('[Chat] messages type=${messages.runtimeType} count=${messages is List ? messages.length : 'N/A'}');
        if (messages is List) {
          setState(() {
            _entries.clear();
            for (final msg in messages) {
              if (msg is! Map<String, dynamic>) continue;
              var content = msg['content'] as String? ?? '';
              // #10: Replace raw A2UI JSONL in history with friendly message
              if (content.startsWith('__A2UI__')) {
                content = 'Canvas updated';
              }
              _entries.add(ChatEntry(
                role: msg['role'] as String? ?? 'system',
                content: content,
              ));
            }
          });
          debugPrint('[Chat] loaded ${_entries.length} entries');
          // Seed _lastCanvasSurface from history so the poll doesn't
          // re-render stale surfaces from previous runs.
          _seedLastCanvasSurface(messages);
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('[Chat] _loadHistory error: $e');
    }
  }

  void _seedLastCanvasSurface(List<dynamic> messages) {
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg is! Map<String, dynamic>) continue;
      final role = msg['role'] as String?;
      if (role != 'tool' && role != 'toolResult') continue;
      final contentList = msg['content'];
      if (contentList is! List) continue;
      for (final block in contentList) {
        if (block is! Map<String, dynamic>) continue;
        final text = block['text'] as String?;
        if (text != null && text.startsWith('__A2UI__')) {
          _lastCanvasSurface = text;
          // Also render it to the canvas so the last surface shows on load
          _handleA2UIToolResult(text);
          return;
        }
      }
    }
  }

  void _handleChatEvent(WsEvent event) {
    try {
      _handleChatEventInner(event);
    } catch (e, st) {
      debugPrint('[Chat] error handling event: $e\n$st');
    }
    // #11: Only auto-scroll if user is near the bottom
    _smartScrollToBottom();
  }

  void _handleChatEventInner(WsEvent event) {
    final payload = event.payload;

    if (event.event == 'chat') {
      final state = payload['state'] as String?;
      final type = payload['type'] as String?;

      if (type == 'message' && payload['role'] == 'user') {
        final content = payload['content'] as String? ?? '';
        final rawAttachments = payload['attachments'];
        List<Map<String, dynamic>>? attachments;
        if (rawAttachments is List) {
          attachments = rawAttachments
              .whereType<Map<String, dynamic>>()
              .toList();
        }
        setState(() {
          _entries.add(ChatEntry(
            role: 'user',
            content: content,
            attachments: attachments,
          ));
        });
      } else if (state == 'delta' || state == 'final') {
        final message = payload['message'];
        if (message is! Map<String, dynamic>) return;
        final contentList = message['content'];
        if (contentList is! List || contentList.isEmpty) return;
        final first = contentList[0];
        if (first is! Map<String, dynamic>) return;
        final text = first['text'] as String? ?? '';
        if (state == 'final') {
          setState(() {
            _agentThinking = false;
            if (_entries.isNotEmpty && _entries.last.role == 'assistant') {
              _entries[_entries.length - 1] = _entries.last.copyWith(
                content: text,
                isStreaming: false,
              );
            } else {
              _entries.add(ChatEntry(role: 'assistant', content: text));
            }
          });
        } else {
          setState(() {
            _agentThinking = false;
            if (_entries.isNotEmpty &&
                _entries.last.role == 'assistant' &&
                _entries.last.isStreaming) {
              _entries[_entries.length - 1] = _entries.last.copyWith(
                content: text,
                isStreaming: true,
              );
            } else {
              _entries.add(ChatEntry(
                role: 'assistant',
                content: text,
                isStreaming: true,
              ));
            }
          });
        }
      }
    } else if (event.event == 'agent') {
      final stream = payload['stream'] as String?;
      final data = payload['data'];
      final dataMap = data is Map<String, dynamic> ? data : null;

      // Detect tool call seq gap: lifecycle start is seq 1.
      // If first assistant event has seq >= 3, tool calls happened in between.
      if (stream == 'assistant' && _currentRunFirstAssistantSeq == null) {
        final seq = payload['seq'];
        if (seq is int) {
          _currentRunFirstAssistantSeq = seq;
          if (seq >= 3) {
            _currentRunHadToolGap = true;
          }
        }
      }

      if (stream == 'lifecycle') {
        final phase = dataMap?['phase'] as String?;
        if (phase == 'start') {
          setState(() => _agentThinking = true);
          _currentRunHadToolGap = false;
          _currentRunFirstAssistantSeq = null;
        } else if (phase == 'end') {
          setState(() {
            _agentThinking = false;
            if (_entries.isNotEmpty && _entries.last.role == 'assistant') {
              _entries[_entries.length - 1] =
                  _entries.last.copyWith(isStreaming: false);
            }
          });
          // Only poll for canvas surface if tool calls were detected (seq gap)
          if (_currentRunHadToolGap) {
            _pollCanvasSurface();
          }
        }
      } else if (stream == 'tool_call' || stream == 'tool') {
        // Handle both tool_call (legacy) and tool (current gateway) stream names
        final toolName = dataMap?['tool'] as String? ??
            dataMap?['name'] as String? ??
            'tool';
        final phase = dataMap?['phase'] as String?;
        final result = dataMap?['result']?.toString() ??
            dataMap?['output']?.toString() ??
            '';

        if (phase == 'end' || phase == 'result') {
          // Tool finished — check for A2UI marker
          if (result.startsWith('__A2UI__')) {
            _handleA2UIToolResult(result);
            setState(() {
              if (_entries.isNotEmpty && _entries.last.role == 'tool') {
                _entries[_entries.length - 1] = _entries.last.copyWith(
                  content: 'Canvas updated',
                  isStreaming: false,
                );
              }
            });
          } else {
            setState(() {
              if (_entries.isNotEmpty && _entries.last.role == 'tool') {
                _entries[_entries.length - 1] = _entries.last.copyWith(
                  content: result.isNotEmpty ? result : 'Done',
                  isStreaming: false,
                );
              }
            });
          }
        } else {
          // Tool started or in progress
          final args = dataMap?['args']?.toString() ?? '';
          setState(() {
            _entries.add(ChatEntry(
              role: 'tool',
              content: args,
              toolName: toolName,
              isStreaming: true,
            ));
          });
        }
      } else if (stream == 'tool_result') {
        final result = dataMap?['result']?.toString() ??
            dataMap?['output']?.toString() ??
            '';
        if (result.startsWith('__A2UI__')) {
          _handleA2UIToolResult(result);
          setState(() {
            if (_entries.isNotEmpty && _entries.last.role == 'tool') {
              _entries[_entries.length - 1] = _entries.last.copyWith(
                content: 'Canvas updated',
                isStreaming: false,
              );
            }
          });
        } else {
          setState(() {
            if (_entries.isNotEmpty && _entries.last.role == 'tool') {
              _entries[_entries.length - 1] = _entries.last.copyWith(
                content: result,
                isStreaming: false,
              );
            }
          });
        }
      }
    }
  }

  String? _lastCanvasSurface;
  bool _currentRunHadToolGap = false;
  int? _currentRunFirstAssistantSeq;

  Future<void> _pollCanvasSurface() async {
    try {
      final client = ref.read(gatewayClientProvider);
      // Fetch recent history and scan for __A2UI__ in tool results
      final response = await client.getChatHistory(limit: 10);
      if (!response.ok || response.payload == null) return;
      final messages = response.payload!['messages'];
      if (messages is! List) return;

      // Walk backwards to find the most recent __A2UI__ tool result
      for (int i = messages.length - 1; i >= 0; i--) {
        final msg = messages[i];
        if (msg is! Map<String, dynamic>) continue;
        final role = msg['role'] as String?;
        if (role != 'tool' && role != 'toolResult') continue;
        final contentList = msg['content'];
        if (contentList is! List) continue;
        for (final block in contentList) {
          if (block is! Map<String, dynamic>) continue;
          final text = block['text'] as String?;
          if (text != null && text.startsWith('__A2UI__') && text != _lastCanvasSurface) {
            _lastCanvasSurface = text;
            debugPrint('[Canvas] Found A2UI in history, rendering surface');
            _handleA2UIToolResult(text);
            setState(() {
              if (_entries.isEmpty || _entries.last.role != 'tool' || !_entries.last.isStreaming) {
                _entries.add(ChatEntry(
                   role: 'tool',
                   content: 'Canvas updated',
                   toolName: 'canvas_ui',
                  isStreaming: false,
                ));
              } else {
                _entries[_entries.length - 1] = _entries.last.copyWith(
                   content: 'Canvas updated',
                  isStreaming: false,
                );
              }
            });
            _scrollToBottom();
            return; // Found and rendered, done
          }
        }
      }
    } catch (e) {
      debugPrint('[Canvas] poll error: $e');
    }
  }

  void _handleA2UIToolResult(String result) {
    final lines = result.split('\n').skip(1);
    final client = ref.read(gatewayClientProvider);
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(line.trim()) as Map<String, dynamic>;
        client.emitCanvasEvent(WsEvent(event: 'a2ui', payload: parsed));
      } catch (_) {}
    }
  }

  // #11: Smart scroll -- only auto-scroll if user is near the bottom
  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 100;
  }

  void _smartScrollToBottom() {
    if (!_isNearBottom) return;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    ref.read(gatewayClientProvider).removeListener(_onClientChange);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);

    // Reload history when session changes
    final sessionKey = ref.watch(activeSessionProvider);
    if (sessionKey != _currentSession) {
      _currentSession = sessionKey;
      _entries.clear();
      _agentThinking = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
    }

    // #14 (chat): Better empty state with hint
    if (_entries.isEmpty && !_agentThinking) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Icon(Icons.chat_outlined, size: 16, color: t.fgMuted),
            ),
            const SizedBox(height: 10),
            Text('start a conversation',
              style: TextStyle(fontSize: 11, color: t.fgMuted, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text('type a message below',
              style: TextStyle(fontSize: 10, color: t.fgPlaceholder)),
          ],
        ),
      );
    }

    // (F) Stack with floating scroll-to-bottom button
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _entries.length + (_agentThinking ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _entries.length && _agentThinking) {
              return _buildThinkingIndicator(theme);
            }
            final entry = _entries[index];
            final prev = index > 0 ? _entries[index - 1] : null;
            final isNewSender = prev == null || prev.role != entry.role;
            return _buildEntry(entry, theme, isNewSender: isNewSender);
          },
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 12,
            bottom: 8,
            child: GestureDetector(
              onTap: () {
                _scrollToBottom();
                setState(() => _showScrollToBottom = false);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: t.surfaceCard,
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Icon(Icons.keyboard_arrow_down,
                    size: 16, color: t.fgMuted),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEntry(ChatEntry entry, ThemeData theme, {bool isNewSender = true}) {
    switch (entry.role) {
      case 'user':
        return _UserBubble(entry: entry, isNewSender: isNewSender);
      case 'assistant':
        return _AssistantBubble(entry: entry, isNewSender: isNewSender);
      case 'tool':
        return _ToolCard(entry: entry);
      default:
        return _SystemMessage(entry: entry);
    }
  }

  Widget _buildThinkingIndicator(ThemeData theme) {
    final t = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4, right: 80),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _StreamingIndicator(),
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

class _UserBubble extends StatelessWidget {
  final ChatEntry entry;
  final bool isNewSender;
  const _UserBubble({required this.entry, this.isNewSender = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(
        top: isNewSender ? 14 : 3,
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
                color: t.accentPrimary.withOpacity(0.08),
                border: Border.all(color: t.accentPrimary.withOpacity(0.18), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (entry.attachments != null && entry.attachments!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        alignment: WrapAlignment.end,
                        children: entry.attachments!.map((a) {
                          final mime = a['mimeType'] as String? ?? '';
                          final name = a['name'] as String? ?? 'file';
                          if (mime.startsWith('image/') && a['base64'] != null) {
                            return Container(
                              constraints: const BoxConstraints(maxWidth: 180, maxHeight: 120),
                              decoration: BoxDecoration(
                                border: Border.all(color: t.border, width: 0.5),
                              ),
                              child: Image.memory(
                                base64Decode(a['base64'] as String),
                                fit: BoxFit.cover,
                              ),
                            );
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: t.surfaceCard,
                              border: Border.all(color: t.border, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mime.startsWith('audio/') ? Icons.audiotrack
                                    : mime.startsWith('video/') ? Icons.videocam
                                    : Icons.insert_drive_file,
                                  size: 10, color: t.fgMuted),
                                const SizedBox(width: 4),
                                Text(name,
                                  style: TextStyle(fontSize: 9, color: t.fgTertiary)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  if (entry.content.isNotEmpty && entry.content != '[attachment]')
                    SelectableText(
                      entry.content,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: t.fgPrimary,
                        height: 1.5,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(entry.timestamp),
                    style: TextStyle(fontSize: 9, color: t.fgMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatefulWidget {
  final ChatEntry entry;
  final bool isNewSender;
  const _AssistantBubble({required this.entry, this.isNewSender = true});

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _hovering = false;
  bool _copied = false;

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: widget.entry.content));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
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
                  'trinity',
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
                color: t.surfaceCard,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: widget.entry.content,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: baseStyle,
                      h1: baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: t.fgPrimary),
                      h2: baseStyle.copyWith(fontSize: 15, fontWeight: FontWeight.bold, color: t.fgPrimary),
                      h3: baseStyle.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                      code: baseStyle.copyWith(fontSize: 13, color: t.accentPrimary, backgroundColor: t.surfaceCodeInline),
                      codeblockDecoration: BoxDecoration(
                        color: t.surfaceBase,
                        border: Border(left: BorderSide(color: t.border, width: 2)),
                      ),
                      codeblockPadding: const EdgeInsets.only(left: 12, top: 8, bottom: 8, right: 8),
                      blockquoteDecoration: BoxDecoration(
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
                  if (widget.entry.isStreaming)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _StreamingIndicator(),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _formatTimestamp(widget.entry.timestamp),
                        style: TextStyle(fontSize: 9, color: t.fgMuted),
                      ),
                      const Spacer(),
                      if (_hovering && !widget.entry.isStreaming)
                        GestureDetector(
                          onTap: _copyMessage,
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

class _StreamingIndicator extends StatefulWidget {
  const _StreamingIndicator();

  @override
  State<_StreamingIndicator> createState() => _StreamingIndicatorState();
}

class _StreamingIndicatorState extends State<_StreamingIndicator>
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
    return AnimatedBuilder(
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
    );
  }
}

class _CursorBlink extends StatefulWidget {
  @override
  State<_CursorBlink> createState() => _CursorBlinkState();
}

class _CursorBlinkState extends State<_CursorBlink>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _opacity = _controller.drive(Tween(begin: 0.0, end: 1.0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 7,
        height: 14,
        color: t.accentPrimary.withOpacity(0.6),
      ),
    );
  }
}

// #12: Expandable tool output
class _ToolCard extends StatefulWidget {
  final ChatEntry entry;
  const _ToolCard({required this.entry});

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final toolName = widget.entry.toolName ?? 'tool';
    final content = widget.entry.content;
    final isTruncated = content.length > 300;
    final displayContent = _expanded || !isTruncated
        ? content
        : '${content.substring(0, 300)}...';

    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 3, right: 48),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: t.surfaceBase,
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.entry.isStreaming) ...[
                  SizedBox(
                    width: 12,
                    height: 8,
                    child: const _StreamingIndicator(),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  toolName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: widget.entry.isStreaming ? t.accentPrimary : t.fgTertiary,
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                displayContent,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  color: t.fgTertiary,
                  height: 1.4,
                ),
              ),
              if (isTruncated)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        _expanded ? 'show less' : 'show more',
                        style: TextStyle(
                          fontSize: 10,
                          color: t.accentPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  final ChatEntry entry;
  const _SystemMessage({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          entry.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: t.fgDisabled,
                fontSize: 11,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
