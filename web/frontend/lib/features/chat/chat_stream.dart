import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
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
  final String? toolCallId; // e.g. 'functions.read:0' -- used to match results to calls
  final bool isStreaming;
  final DateTime timestamp;
  final List<Map<String, dynamic>>? attachments;

  ChatEntry({
    required this.role,
    required this.content,
    this.toolName,
    this.toolCallId,
    this.isStreaming = false,
    this.attachments,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatEntry copyWith({String? content, bool? isStreaming}) => ChatEntry(
        role: role,
        content: content ?? this.content,
        toolName: toolName,
        toolCallId: toolCallId,
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
  static const int _maxEntries = 500;
  final List<ChatEntry> _entries = [];
  final _scrollController = ScrollController();
  StreamSubscription<WsEvent>? _chatSub;
  bool _agentThinking = false;
  bool _showScrollToBottom = false;
  String _currentSession = 'main';
  bool _historyLoading = false; // Guard against concurrent history fetches

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

    // If the gateway is already connected (e.g. listener registered after
    // the hello-ok notification fired), load history immediately.
    if (client.state == gw.ConnectionState.connected) {
      _loadHistory();
    }
  }

  void _onClientChange() {
    // Re-subscribe if reconnected; guard prevents overlapping fetches.
    if (!_historyLoading &&
        ref.read(gatewayClientProvider).state == gw.ConnectionState.connected) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (_historyLoading) return; // Prevent concurrent fetches
    _historyLoading = true;
    final client = ref.read(gatewayClientProvider);
    final sessionKey = ref.read(activeSessionProvider);
    try {
      final response = await client.getChatHistory(sessionKey: sessionKey, limit: 50);
      if (!mounted) { _historyLoading = false; return; } // Widget disposed during async gap
      if (response.ok && response.payload != null) {
        // Try 'messages' first, fall back to 'history' or 'entries'
        final messages = response.payload?['messages']
            ?? response.payload?['history']
            ?? response.payload?['entries'];
        if (messages is List) {
          setState(() {
            _entries.clear();
            for (final msg in messages) {
              if (msg is! Map<String, dynamic>) continue;
              // Extract displayable text from content (may be String or List of blocks)
              var content = _extractContent(msg['content']);
              // #10: Replace raw A2UI JSONL in history with friendly message
              if (content.startsWith('__A2UI__')) {
                content = 'Canvas updated';
              }
              // Extract timestamp from history (epoch ms or ISO string)
              DateTime? timestamp;
              final ts = msg['timestamp'] ?? msg['createdAt'] ?? msg['ts'];
              if (ts is num) {
                timestamp = DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true);
              } else if (ts is String) {
                timestamp = DateTime.tryParse(ts);
              }
              // Normalize gateway role names for rendering:
              // 'toolResult' (gateway camelCase) -> 'tool' (Flutter card)
              final rawRole = msg['role'] as String? ?? 'system';
              final role = rawRole == 'toolResult' ? 'tool' : rawRole;
              // Extract tool name and toolCallId for tool card labels + matching
              final toolName = msg['toolName'] as String? ??
                  msg['name'] as String? ??
                  (role == 'tool' ? 'tool' : null);
              final toolCallId = role == 'tool'
                  ? (msg['toolCallId'] as String? ?? msg['id'] as String?)
                  : null;
              // Extract image attachments from history content blocks
              final historyAttachments = _extractImageAttachments(msg['content']);
              _entries.add(ChatEntry(
                role: role,
                content: content,
                toolName: toolName,
                toolCallId: toolCallId,
                timestamp: timestamp,
                attachments: historyAttachments.isNotEmpty ? historyAttachments : null,
              ));
            }
          });
          // Seed _lastCanvasSurface from history so the poll doesn't
          // re-render stale surfaces from previous runs.
          _seedLastCanvasSurface(messages);
          _jumpToBottomAfterLayout();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Chat] _loadHistory error: $e');
    } finally {
      _historyLoading = false;
    }
  }

  /// Extract displayable text from a message content field.
  /// Handles both flat String content and the List<block> format
  /// returned by the gateway (e.g. [{type:"text",text:"..."}, ...]).
  static String _extractContent(dynamic rawContent) {
    if (rawContent is String) return rawContent;
    if (rawContent is List) {
      final textParts = <String>[];
      for (final block in rawContent) {
        if (block is! Map<String, dynamic>) continue;
        final type = block['type'] as String?;
        if (type == 'text') {
          final text = block['text'] as String? ?? '';
          if (text.isNotEmpty) textParts.add(text);
        }
        // Skip 'thinking' and 'toolCall' blocks -- not user-visible in history
      }
      return textParts.join('\n').trim();
    }
    return '';
  }

  /// Extract image attachments from history content blocks.
  /// Handles OpenAI-format image_url blocks with data URI base64.
  static List<Map<String, dynamic>> _extractImageAttachments(dynamic rawContent) {
    if (rawContent is! List) return const [];
    final attachments = <Map<String, dynamic>>[];
    for (final block in rawContent) {
      if (block is! Map<String, dynamic>) continue;
      final type = block['type'] as String?;
      if (type == 'image_url') {
        final imageUrl = block['image_url'];
        if (imageUrl is Map<String, dynamic>) {
          final url = imageUrl['url'] as String? ?? '';
          // Parse data URI: data:image/jpeg;base64,<data>
          final match = RegExp(r'^data:(image/[^;]+);base64,(.+)$').firstMatch(url);
          if (match != null) {
            attachments.add({
              'content': match.group(2)!,
              'mimeType': match.group(1)!,
              'fileName': 'image',
              'type': 'image',
            });
          }
        }
      }
    }
    return attachments;
  }

  /// Extract MEDIA: token paths from tool output and convert to media serving URLs.
  /// Returns a list of `/__openclaw__/media/<relative>` URLs for image files.
  static final _mediaTokenExtractRe = RegExp(
    r'MEDIA:\s*(.+)',
    caseSensitive: false,
    multiLine: true,
  );
  static const _workspacePrefix = '/home/node/.openclaw/workspace/';
  static const _imageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp', '.tiff', '.tif'};

  static List<String> _extractMediaUrls(String text) {
    if (text.isEmpty) return const [];
    final urls = <String>[];
    for (final match in _mediaTokenExtractRe.allMatches(text)) {
      var raw = match.group(1)?.trim() ?? '';
      // Strip surrounding backticks/quotes
      while (raw.isNotEmpty && (raw[0] == '`' || raw[0] == '"' || raw[0] == "'")) {
        raw = raw.substring(1);
      }
      while (raw.isNotEmpty && (raw[raw.length - 1] == '`' || raw[raw.length - 1] == '"' || raw[raw.length - 1] == "'")) {
        raw = raw.substring(0, raw.length - 1);
      }
      raw = raw.trim();
      if (raw.isEmpty) continue;
      // Check if it's an image file
      final lower = raw.toLowerCase();
      final isImage = _imageExts.any((ext) => lower.endsWith(ext));
      if (!isImage) continue;
      // Convert absolute workspace path to relative
      String relative;
      if (raw.startsWith(_workspacePrefix)) {
        relative = raw.substring(_workspacePrefix.length);
      } else if (raw.startsWith('/')) {
        // Absolute path outside workspace -- skip (security)
        continue;
      } else {
        relative = raw;
      }
      urls.add('/__openclaw__/media/$relative');
    }
    return urls;
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

  /// Evict oldest entries if we exceed capacity
  void _capEntries() {
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  /// Find the matching tool entry and update its content.
  /// When [toolCallId] is provided, searches for the exact entry with that ID
  /// (required for parallel tool calls like 3 concurrent reads).
  /// Falls back to the most recent tool entry within the current turn if
  /// no ID match is found (backward compat with older gateway versions).
  void _updateLastToolEntry(String content, {
    bool isStreaming = false,
    String? toolCallId,
  }) {
    // First pass: match by toolCallId if available
    if (toolCallId != null && toolCallId.isNotEmpty) {
      for (int i = _entries.length - 1; i >= 0; i--) {
        if (_entries[i].role == 'tool' &&
            _entries[i].toolCallId == toolCallId) {
          _entries[i] = _entries[i].copyWith(
            content: content,
            isStreaming: isStreaming,
          );
          return;
        }
        if (_entries[i].role == 'user') break;
      }
    }
    // Fallback: find the most recent tool entry in the current turn
    for (int i = _entries.length - 1; i >= 0; i--) {
      if (_entries[i].role == 'tool') {
        _entries[i] = _entries[i].copyWith(
          content: content,
          isStreaming: isStreaming,
        );
        return;
      }
      if (_entries[i].role == 'user') break;
    }
  }

  void _handleChatEvent(WsEvent event) {
    try {
      _handleChatEventInner(event);
      _capEntries();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Chat] error handling event: $e\n$st');
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
      } else if (state == 'delta' || state == 'final' || state == 'aborted') {
        final message = payload['message'];
        if (message is! Map<String, dynamic>) return;
        final contentList = message['content'];
        if (contentList is! List || contentList.isEmpty) return;
        // Scan for the first 'text' block instead of blindly taking
        // contentList[0], which may be a 'thinking' block.
        String text = '';
        for (final block in contentList) {
          if (block is Map<String, dynamic> && block['type'] == 'text') {
            text = block['text'] as String? ?? '';
            break;
          }
        }
        if (state == 'final' || state == 'aborted') {
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
            // Clear isStreaming on all entries still marked as streaming
            // (assistant deltas and tool cards that never received a result).
            for (int i = _entries.length - 1; i >= 0; i--) {
              if (_entries[i].isStreaming) {
                _entries[i] = _entries[i].copyWith(isStreaming: false);
              }
              if (_entries[i].role == 'user') break;
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
        final toolCallId = dataMap?['id'] as String? ??
            dataMap?['toolCallId'] as String?;
        final result = dataMap?['result']?.toString() ??
            dataMap?['output']?.toString() ??
            '';

        if (phase == 'end' || phase == 'result') {
          // Tool finished — check for A2UI marker
          if (result.startsWith('__A2UI__')) {
            _handleA2UIToolResult(result);
            setState(() {
              _updateLastToolEntry('Canvas updated', toolCallId: toolCallId);
            });
          } else {
            // Extract MEDIA: tokens from tool result and render as images
            final mediaImages = _extractMediaUrls(result);
            final displayResult = result.isNotEmpty ? result : 'Done';
            setState(() {
              _updateLastToolEntry(displayResult, toolCallId: toolCallId);
              // Add image entries for any MEDIA: tokens found in tool output
              for (final url in mediaImages) {
                _entries.add(ChatEntry(
                  role: 'assistant',
                  content: '![Generated image]($url)',
                ));
              }
              _capEntries();
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
              toolCallId: toolCallId,
              isStreaming: true,
            ));
          });
        }
      } else if (stream == 'tool_result') {
        final toolCallId = dataMap?['id'] as String? ??
            dataMap?['toolCallId'] as String?;
        final result = dataMap?['result']?.toString() ??
            dataMap?['output']?.toString() ??
            '';
        if (result.startsWith('__A2UI__')) {
          _handleA2UIToolResult(result);
          setState(() {
            _updateLastToolEntry('Canvas updated', toolCallId: toolCallId);
          });
        } else {
          setState(() {
            _updateLastToolEntry(result.isNotEmpty ? result : 'Done',
                toolCallId: toolCallId);
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
      final sessionKey = ref.read(activeSessionProvider);
      // Fetch recent history and scan for __A2UI__ in tool results
      final response = await client.getChatHistory(sessionKey: sessionKey, limit: 10);
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
            if (kDebugMode) debugPrint('[Canvas] Found A2UI in history, rendering surface');
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
      if (kDebugMode) debugPrint('[Canvas] poll error: $e');
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
      } catch (e) {
        if (kDebugMode) debugPrint('[A2UI] Failed to parse JSONL line: $e');
      }
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

  /// Jump to bottom without animation -- used after history load where the
  /// ListView content may settle across multiple frames (markdown rendering,
  /// image placeholders, font loading). Two post-frame passes ensure we
  /// catch late layout shifts.
  void _jumpToBottomAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      // Second pass: catch any remaining layout shifts from async content
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
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
                borderRadius: kShellBorderRadius,
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
    // SizeChangedLayoutNotifier fires when the viewport size changes
    // (e.g., PromptBar height changes from attachments, multi-line text, voice).
    // This keeps the chat pinned to the bottom when the user was already there.
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _smartScrollToBottom();
        return false;
      },
      child: SizeChangedLayoutNotifier(
      child: Stack(
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
                    borderRadius: kShellBorderRadius,
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
    ),
      ),
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
              borderRadius: kShellBorderRadius,
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

class _UserBubble extends StatefulWidget {
  final ChatEntry entry;
  final bool isNewSender;
  const _UserBubble({required this.entry, this.isNewSender = true});

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  bool _hovering = false;
  bool _copied = false;

  /// Memoized decoded image bytes to avoid re-decoding base64 on every rebuild.
  /// Key: attachment index, Value: decoded Uint8List.
  late final Map<int, Uint8List> _decodedImages = _decodeImageAttachments();

  Map<int, Uint8List> _decodeImageAttachments() {
    final result = <int, Uint8List>{};
    final attachments = widget.entry.attachments;
    if (attachments == null) return result;
    for (int i = 0; i < attachments.length; i++) {
      final a = attachments[i];
      final mime = a['mimeType'] as String? ?? '';
      // Support both OpenClaw field name (content) and legacy (base64)
      final b64 = a['content'] as String? ?? a['base64'] as String?;
      if (mime.startsWith('image/') && b64 != null) {
        try {
          result[i] = base64Decode(b64);
        } catch (_) {
          // Skip invalid base64
        }
      }
    }
    return result;
  }

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: widget.entry.content)).then((_) {
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
                    if (widget.entry.attachments != null && widget.entry.attachments!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: List.generate(widget.entry.attachments!.length, (i) {
                            final a = widget.entry.attachments![i];
                            final mime = a['mimeType'] as String? ?? '';
                            // Support both OpenClaw (fileName) and legacy (name) field names
                            final name = a['fileName'] as String? ?? a['name'] as String? ?? 'file';
                            final cachedBytes = _decodedImages[i];
                            if (cachedBytes != null) {
                              return Container(
                                constraints: const BoxConstraints(maxWidth: 180, maxHeight: 120),
                                decoration: BoxDecoration(
                                  borderRadius: kShellBorderRadiusSm,
                                  border: Border.all(color: t.border, width: 0.5),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.memory(
                                  cachedBytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                              );
                            }
                            // Pick icon based on file type
                            final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')).toLowerCase() : '';
                            final IconData fileIcon;
                            if (mime.startsWith('audio/')) {
                              fileIcon = Icons.audiotrack;
                            } else if (mime.startsWith('video/')) {
                              fileIcon = Icons.videocam;
                            } else if (mime == 'application/pdf' || ext == '.pdf') {
                              fileIcon = Icons.picture_as_pdf;
                            } else if (const {'.docx', '.doc', '.odt', '.rtf'}.contains(ext) ||
                                       mime.contains('wordprocessingml') || mime == 'application/msword' ||
                                       mime.contains('opendocument.text') || mime == 'application/rtf') {
                              fileIcon = Icons.description;
                            } else if (const {'.xlsx', '.xls', '.ods', '.csv'}.contains(ext) ||
                                       mime.contains('spreadsheetml') || mime == 'application/vnd.ms-excel' ||
                                       mime.contains('opendocument.spreadsheet') || mime == 'text/csv') {
                              fileIcon = Icons.table_chart;
                            } else if (const {'.pptx', '.ppt', '.odp'}.contains(ext) ||
                                       mime.contains('presentationml') || mime == 'application/vnd.ms-powerpoint' ||
                                       mime.contains('opendocument.presentation')) {
                              fileIcon = Icons.slideshow;
                            } else if (mime == 'application/epub+zip' || ext == '.epub') {
                              fileIcon = Icons.menu_book;
                            } else if (const {'.py', '.js', '.ts', '.dart', '.java', '.c', '.cpp', '.go', '.rs', '.rb', '.php', '.kt', '.swift', '.lua', '.sh', '.bash', '.zsh'}.contains(ext) ||
                                       mime.startsWith('text/x-') || mime == 'text/javascript' || mime == 'text/typescript') {
                              fileIcon = Icons.code;
                            } else {
                              fileIcon = Icons.insert_drive_file;
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: kShellBorderRadiusSm,
                                color: t.surfaceCard,
                                border: Border.all(color: t.border, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(fileIcon, size: 10, color: t.fgMuted),
                                  const SizedBox(width: 4),
                                  Text(name,
                                    style: TextStyle(fontSize: 9, color: t.fgTertiary)),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    if (widget.entry.content.isNotEmpty && widget.entry.content != '[attachment]')
                      SelectionArea(
                        child: MarkdownBody(
                          data: widget.entry.content,
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
                            onTap: _copyMessage,
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
                          _formatTimestamp(widget.entry.timestamp),
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

  /// Image file extensions used for detection.
  static const _imgExts = r'\.(?:png|jpe?g|gif|webp|svg|bmp|tiff?)';

  /// 1. Bare /__openclaw__/media/ URLs not already inside markdown image syntax.
  static final _mediaUrlRe = RegExp(
    r'(?<!\]\()' // not preceded by ](
    r'(/__openclaw__/media/[^\s)\]`]+' + _imgExts + ')',
    caseSensitive: false,
  );

  /// 2. Absolute workspace paths:
  ///    /home/node/.openclaw/workspace/<relative-path>.png
  static final _absWorkspaceRe = RegExp(
    r'(?<!\]\()' // not preceded by ](
    r'/home/node/\.openclaw/workspace/([^\s)\]`]+' + _imgExts + ')',
    caseSensitive: false,
  );

  /// 3. MEDIA: token lines (in case gateway didn't strip them).
  static final _mediaTokenRe = RegExp(
    r'MEDIA:\s*([^\s]+' + _imgExts + ')',
    caseSensitive: false,
  );

  /// Pre-process assistant content to ensure workspace images render inline.
  ///
  /// Converts three patterns into markdown ![image](url):
  ///   - /__openclaw__/media/<path>.png  (already correct URL)
  ///   - /home/node/.openclaw/workspace/<path>.png  (absolute -> media URL)
  ///   - MEDIA: <path>.png  (raw token -> media URL)
  ///
  /// Skips matches already inside markdown image syntax `](url)`.
  String _enrichContentWithImages(String content) {
    var result = content;

    // Pass 1: Convert absolute workspace paths to media URLs
    result = result.replaceAllMapped(_absWorkspaceRe, (m) {
      if (m.start > 0 && result[m.start - 1] == '(') return m.group(0)!;
      final relative = m.group(1)!;
      return '![image](/__openclaw__/media/$relative)';
    });

    // Pass 2: Convert MEDIA: tokens to media URLs
    result = result.replaceAllMapped(_mediaTokenRe, (m) {
      final raw = m.group(1)!;
      // Strip workspace prefix if present
      final relative = raw.startsWith('/home/node/.openclaw/workspace/')
          ? raw.substring('/home/node/.openclaw/workspace/'.length)
          : raw;
      return '![image](/__openclaw__/media/$relative)';
    });

    // Pass 3: Convert bare /__openclaw__/media/ URLs
    result = result.replaceAllMapped(_mediaUrlRe, (m) {
      if (m.start > 0 && result[m.start - 1] == '(') return m.group(0)!;
      final url = m.group(1)!;
      return '![image]($url)';
    });

    return result;
  }

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: widget.entry.content)).then((_) {
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
                borderRadius: kShellBorderRadius,
                color: t.surfaceCard,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectionArea(
                    child: MarkdownBody(
                      data: _enrichContentWithImages(widget.entry.content),
                      selectable: false,
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
                      imageBuilder: (uri, title, alt) {
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
                          child: Image.network(
                            uri.toString(),
                            fit: BoxFit.contain,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return SizedBox(
                                height: 80,
                                child: Center(child: SizedBox(
                                  width: 60,
                                  child: LinearProgressIndicator(
                                    value: progress.expectedTotalBytes != null
                                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                      : null,
                                    backgroundColor: t.border,
                                    color: t.accentPrimary,
                                    minHeight: 2,
                                  ),
                                )),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: kShellBorderRadiusSm,
                                color: t.surfaceBase,
                                border: Border.all(color: t.border, width: 0.5),
                              ),
                              child: Text('[image failed to load]',
                                style: TextStyle(fontSize: 11, color: t.fgMuted)),
                            ),
                          ),
                        );
                      },
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          Clipboard.setData(ClipboardData(text: href));
                        }
                      },
                    ),
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

// #12: Expandable tool output
class _ToolCard extends StatefulWidget {
  final ChatEntry entry;
  const _ToolCard({required this.entry});

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  static const int _collapsedLimit = 300;
  static const int _expandedLimit = 1500;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final toolName = widget.entry.toolName ?? 'tool';
    final content = widget.entry.content;
    final canExpand = content.length > _collapsedLimit;
    final hardCapped = content.length > _expandedLimit;

    String displayContent;
    if (!canExpand) {
      displayContent = content;
    } else if (_expanded) {
      displayContent = hardCapped
          ? '${content.substring(0, _expandedLimit)}... (truncated)'
          : content;
    } else {
      displayContent = '${content.substring(0, _collapsedLimit)}...';
    }

    // Only show the toggle when there's content beyond 300 chars to reveal,
    // but hide "show more" if already expanded and hard-capped (nothing more to do).
    final showToggle = canExpand && !(_expanded && hardCapped);

    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 3, right: 48),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: kShellBorderRadiusSm,
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
              if (showToggle)
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
