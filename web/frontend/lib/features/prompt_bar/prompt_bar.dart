import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/dialog_service.dart';
import '../../core/attachment_utils.dart';
import 'voice_input.dart';
import 'prompt_templates.dart';

class PromptBar extends ConsumerStatefulWidget {
  final bool enabled;

  const PromptBar({
    super.key,
    required this.enabled,
  });

  /// Key to access the state from shell_page (for drag-and-drop).
  static final globalKey = GlobalKey<_PromptBarState>();

  @override
  ConsumerState<PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends ConsumerState<PromptBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _voiceController = VoiceInputController();
  final _layerLink = LayerLink();
  OverlayEntry? _templateOverlay;
  StreamSubscription? _pasteSub;
  bool _sending = false;
  bool _showTemplates = false;
  String? _dismissedAtText; // Text snapshot when Esc was pressed; overlay reopens on next edit
  int _activeTemplateIndex = 0; // Keyboard navigation index
  List<_AttachmentInfo> _attachments = [];
  String? _attachError;     // Inline error for rejected files
  int _processingCount = 0; // Files currently being read/compressed
  DateTime? _lastDropTime;  // Debounce guard for duplicate drop events

  @override
  void initState() {
    super.initState();
    _voiceController.initialize();
    _voiceController.addListener(() {
      if (mounted) setState(() {});
    });
    _controller.addListener(() {
      if (mounted) {
        final text = _controller.text;
        if (!text.startsWith('/')) {
          // User backspaced past "/" — clear dismiss snapshot
          _dismissedAtText = null;
          if (_showTemplates) {
            _showTemplates = false;
            _removeTemplateOverlay();
          }
          setState(() {});
        } else if (!_showTemplates) {
          // Text starts with "/" and overlay is not showing.
          // Reopen if: never dismissed, OR text changed since Esc was pressed.
          if (_dismissedAtText == null || text != _dismissedAtText) {
            _dismissedAtText = null; // Clear stale snapshot
            _showTemplates = true;
            _activeTemplateIndex = 0;
            _showTemplateOverlay();
            setState(() {});
          }
        } else {
          // Overlay is showing — update filter as user types
          _activeTemplateIndex = 0;
          _templateOverlay?.markNeedsBuild();
          setState(() {});
        }
      }
    });
    // (D) Auto-focus prompt bar on page load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    // Register global paste listener for Ctrl+V image paste
    _pasteSub = html.document.onPaste.listen(_handlePaste);
  }

  @override
  void dispose() {
    _pasteSub?.cancel();
    _removeTemplateOverlay();
    _controller.dispose();
    _focusNode.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  void _dismissAndCleanup() {
    _showTemplates = false;
    _removeTemplateOverlay();
    if (mounted) setState(() {});
  }

  void _showTemplateOverlay() {
    _removeTemplateOverlay();
    _templateOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(12, -4),
          child: Material(
            color: Colors.transparent,
            child: PromptTemplatePanel(
              filter: _controller.text.startsWith('/')
                  ? _controller.text.substring(1)
                  : '',
              activeIndex: _activeTemplateIndex,
              onSelect: (content) {
                _controller.text = content;
                _controller.selection = TextSelection.collapsed(
                  offset: content.length);
                _dismissAndCleanup();
                _focusNode.requestFocus();
              },
              onDismiss: _dismissAndCleanup,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_templateOverlay!);
  }

  void _removeTemplateOverlay() {
    _templateOverlay?.remove();
    _templateOverlay = null;
  }

  static const _gatewayToken = String.fromEnvironment(
    'GATEWAY_TOKEN',
    defaultValue: 'replace-me-with-a-real-token',
  );

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (!widget.enabled || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      final client = ref.read(gatewayClientProvider);
      final sessionKey = ref.read(activeSessionProvider);

      if (_attachments.isNotEmpty) {
        // Split attachments: images go via WebSocket, non-images via HTTP upload
        final imageAttachments = <_AttachmentInfo>[];
        final fileAttachments = <_AttachmentInfo>[];
        for (final a in _attachments) {
          if (a.mimeType.startsWith('image/')) {
            imageAttachments.add(a);
          } else {
            fileAttachments.add(a);
          }
        }

        // Upload non-image files to workspace via HTTP in parallel
        final uploadFutures = fileAttachments.map((a) async {
          try {
            final bytes = base64Decode(a.base64);
            final result = await uploadFileToWorkspace(
              bytes: bytes,
              fileName: a.name,
              mimeType: a.mimeType,
              gatewayToken: _gatewayToken,
            );
            if (result.ok && result.path != null) {
              return result.path!;
            } else {
              if (kDebugMode) debugPrint('[PromptBar] upload failed: ${result.error}');
              return '[Upload failed: ${a.name}]';
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[PromptBar] upload error: $e');
            return '[Upload failed: ${a.name}]';
          }
        }).toList();
        final uploadedPaths = await Future.wait(uploadFutures);

        // Build the message: user text + file references
        final parts = <String>[];
        if (text.isNotEmpty) parts.add(text);
        for (final p in uploadedPaths) {
          if (p.startsWith('[')) {
            parts.add(p); // error placeholder
          } else {
            parts.add('[File: $p]');
          }
        }
        final message = parts.isNotEmpty ? parts.join('\n') : '[attachment]';

        if (imageAttachments.isNotEmpty) {
          // Send images via WebSocket attachments (gateway-native path)
          final attachmentData = imageAttachments.map((a) => {
            'content': a.base64,
            'mimeType': a.mimeType,
            'fileName': a.name,
            'type': 'image',
          }).toList();
          await client.sendChatMessageWithAttachments(
            message,
            sessionKey: sessionKey,
            attachments: attachmentData,
          );
        } else {
          // Non-image only: send as regular message with file path references
          await client.sendChatMessage(message, sessionKey: sessionKey);
        }
        setState(() => _attachments = []);
      } else {
        await client.sendChatMessage(text, sessionKey: sessionKey);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _focusNode.requestFocus();
      }
    }
  }

  // #8: Abort the current agent run
  void _abort() {
    final client = ref.read(gatewayClientProvider);
    final sessionKey = ref.read(activeSessionProvider);
    client.abortChat(sessionKey: sessionKey);
  }

  void _toggleVoice() {
    if (_voiceController.isListening) {
      _voiceController.stopListening();
    } else {
      _voiceController.startListening(
        onResult: (transcript) {
          _controller.text = transcript;
          _send();
        },
      );
    }
  }

  // --- File handling (all phases) ---

  /// Dismiss attachment error after a delay.
  void _showAttachError(String msg) {
    setState(() => _attachError = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _attachError = null);
    });
  }

  /// File picker (enhanced with validation).
  void _pickFile() {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*,audio/*,video/*,'
          '.pdf,.txt,.md,.json,.csv,.yaml,.yml,'
          '.docx,.xlsx,.pptx,.doc,.xls,.ppt,'
          '.odt,.ods,.odp,.rtf,.epub,'
          '.html,.css,.xml,.sql,.toml,.ini,.env,.log,'
          '.py,.js,.ts,.dart,.sh,.bash,.zsh,'
          '.java,.kt,.c,.cpp,.h,.hpp,.rs,.go,.rb,.php,.swift,.lua'
      ..multiple = true;
    input.click();
    input.onChange.first.then((_) {
      final files = input.files;
      if (files == null) return;
      for (final file in files) {
        _processFile(file);
      }
    });
  }

  /// Public: accept files from drag-and-drop (called by shell_page).
  void addDroppedFiles(List<html.File> files) {
    // Debounce duplicate drop events (Flutter Web can dispatch twice within
    // the same frame). Reject calls arriving within 100 ms of the last drop.
    final now = DateTime.now();
    if (_lastDropTime != null &&
        now.difference(_lastDropTime!).inMilliseconds < 100) {
      return;
    }
    _lastDropTime = now;
    for (final file in files) {
      _processFile(file);
    }
  }

  /// Handle clipboard paste events (Ctrl+V for images).
  void _handlePaste(html.ClipboardEvent event) {
    if (!widget.enabled || _sending) return;
    final items = event.clipboardData?.items;
    if (items == null) return;
    final itemCount = items.length ?? 0;
    for (var i = 0; i < itemCount; i++) {
      final item = items[i];
      if (item == null) continue;
      // Only process file/image items, not text
      if (item.type != null && item.type!.startsWith('image/')) {
        final file = item.getAsFile();
        if (file != null) {
          event.preventDefault();
          _processFile(file);
        }
      }
    }
  }

  /// Central file processing: validate → compress (if image) → read → add.
  void _processFile(html.File file) {
    // Check attachment count limit
    if (_attachments.length >= AttachmentLimits.maxAttachments) {
      _showAttachError('Max ${AttachmentLimits.maxAttachments} attachments');
      return;
    }

    // Validate MIME + size
    final error = MimeValidator.validate(file);
    if (error != null) {
      _showAttachError(error);
      return;
    }

    setState(() => _processingCount++);

    // Check if image needs compression
    if (ImageCompressor.shouldCompress(file)) {
      _compressAndAdd(file);
    } else {
      _readFileRaw(file);
    }
  }

  /// Compress an image then add it as an attachment.
  Future<void> _compressAndAdd(html.File file) async {
    try {
      final result = await ImageCompressor.compress(file);
      if (result != null && mounted) {
        setState(() {
          _processingCount--;
          _attachments.add(_AttachmentInfo(
            name: file.name,
            mimeType: result.mimeType,
            base64: result.base64,
            size: result.size,
          ));
        });
        return;
      }
    } catch (_) {
      // Compression failed — fall through to raw read
    }
    // Fallback to raw read
    _readFileRaw(file);
  }

  /// Read a file as raw base64 (no compression).
  void _readFileRaw(html.File file) {
    final reader = html.FileReader();
    reader.onLoadEnd.first.then((_) {
      if (!mounted) return;
      if (reader.result is String) {
        final dataUrl = reader.result as String;
        final commaIndex = dataUrl.indexOf(',');
        if (commaIndex > 0) {
          final base64Data = dataUrl.substring(commaIndex + 1);
          setState(() {
            _processingCount--;
            _attachments.add(_AttachmentInfo(
              name: file.name,
              mimeType: file.type,
              base64: base64Data,
              size: file.size,
            ));
          });
          return;
        }
      }
      // Read failed
      setState(() => _processingCount--);
      _showAttachError('Failed to read ${file.name}');
    });
    reader.onError.first.then((_) {
      if (mounted) {
        setState(() => _processingCount--);
        _showAttachError('Error reading ${file.name}');
      }
    });
    reader.readAsDataUrl(file);
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  void _saveAsTemplate() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final nameController = TextEditingController();
    final contentController = TextEditingController(text: text);
    DialogService.instance.showUnique(
      context: context,
      id: 'save-template',
      builder: (ctx) {
        final t = ShellTokens.of(ctx);
        void doSave() {
          final name = nameController.text.trim();
          final content = contentController.text.trim();
          if (name.isNotEmpty && content.isNotEmpty) {
            PromptTemplateStore.addCustom(
              PromptTemplate(name: name, content: content),
            );
            Navigator.of(ctx).pop();
          }
        }
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: kShellBorderRadius),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadius,
              color: t.surfaceBase,
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('save as template',
                  style: TextStyle(fontSize: 12, color: t.fgPrimary)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'template name',
                    isDense: true,
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: t.accentPrimary),
                    ),
                  ),
                  onSubmitted: (_) => doSave(),
                ),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    borderRadius: kShellBorderRadiusSm,
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: TextField(
                    controller: contentController,
                    maxLines: 6,
                    minLines: 3,
                    style: TextStyle(fontSize: 12, color: t.fgPrimary),
                    decoration: InputDecoration(
                      hintText: 'template content...',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text('cancel',
                          style: TextStyle(fontSize: 11, color: t.fgMuted)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: doSave,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text('save',
                          style: TextStyle(fontSize: 11, color: t.accentPrimary)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      contentController.dispose();
    });
  }

  // #2: Handle Shift+Enter for multi-line, Enter for send
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Template panel keyboard navigation
    if (_showTemplates) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
        final filter = _controller.text.startsWith('/')
            ? _controller.text.substring(1) : '';
        final all = PromptTemplateStore.all();
        final count = filter.isEmpty ? all.length : all.where((t) =>
          t.name.toLowerCase().contains(filter.toLowerCase()) ||
          t.category.toLowerCase().contains(filter.toLowerCase())
        ).length;
        if (count > 0) {
          setState(() {
            if (key == LogicalKeyboardKey.arrowDown) {
              _activeTemplateIndex = (_activeTemplateIndex + 1) % count;
            } else {
              _activeTemplateIndex = (_activeTemplateIndex - 1 + count) % count;
            }
          });
          _templateOverlay?.markNeedsBuild();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _dismissedAtText = _controller.text; // Snapshot text at dismiss
        _dismissAndCleanup();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter) {
        // Select the active template directly
        final filter = _controller.text.startsWith('/')
            ? _controller.text.substring(1) : '';
        final all = PromptTemplateStore.all();
        final filtered = filter.isEmpty ? all : all.where((t) =>
          t.name.toLowerCase().contains(filter.toLowerCase()) ||
          t.category.toLowerCase().contains(filter.toLowerCase())
        ).toList();
        if (filtered.isNotEmpty) {
          final idx = _activeTemplateIndex.clamp(0, filtered.length - 1);
          final content = filtered[idx].content;
          _controller.text = content;
          _controller.selection = TextSelection.collapsed(offset: content.length);
          _dismissAndCleanup();
          _focusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;

    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
    if (isShiftHeld) {
      // Insert newline at cursor
      final text = _controller.text;
      final selection = _controller.selection;
      final newText = text.replaceRange(selection.start, selection.end, '\n');
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + 1),
      );
      return KeyEventResult.handled;
    }

    // Enter without Shift = send
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final isListening = _voiceController.isListening;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attachment preview row (includes error + processing chips inline)
          if (_attachments.isNotEmpty || _processingCount > 0 || _attachError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border, width: 0.5)),
              ),
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // Error chip (inline, same row height)
                    if (_attachError != null)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: kShellBorderRadiusSm,
                          color: t.statusError.withOpacity(0.08),
                          border: Border.all(color: t.statusError.withOpacity(0.3), width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 10, color: t.statusError),
                            const SizedBox(width: 4),
                            Text(_attachError!,
                              style: TextStyle(fontSize: 9, color: t.statusError)),
                          ],
                        ),
                      ),
                    // Attachment chips
                    for (var i = 0; i < _attachments.length; i++)
                      _AttachmentChip(
                        name: _attachments[i].name,
                        mimeType: _attachments[i].mimeType,
                        size: _attachments[i].size,
                        tokens: t,
                        theme: theme,
                        onRemove: () => _removeAttachment(i),
                      ),
                    // Processing indicator chip
                    if (_processingCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: kShellBorderRadiusSm,
                          color: t.surfaceCard,
                          border: Border.all(color: t.border, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 10, height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: t.accentPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('processing${_processingCount > 1 ? ' ($_processingCount)' : ''}',
                              style: TextStyle(fontSize: 9, color: t.fgMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Main prompt bar
          Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.border, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isListening && _voiceController.transcript.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _voiceController.transcript,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: t.fgTertiary,
                        ),
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // File attach button
                    if (!_sending)
                      GestureDetector(
                        onTap: _pickFile,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6, bottom: 2),
                            child: Icon(Icons.attach_file, size: 14, color: t.fgMuted),
                          ),
                        ),
                      ),
                    // Templates button removed -- use '/' to trigger
                    Text(
                      _sending ? '~ ' : '> ',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: widget.enabled
                            ? (_sending ? t.fgTertiary : t.accentPrimary)
                            : t.fgDisabled,
                      ),
                    ),
                    Expanded(
                      // #2: Wrap in Focus to intercept Enter/Shift+Enter
                      child: Focus(
                        onKeyEvent: _handleKeyEvent,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: widget.enabled && !_sending,
                          maxLines: 5,
                          minLines: 1,
                          style: theme.textTheme.bodyLarge,
                          decoration: InputDecoration(
                            hintText: widget.enabled
                                ? 'type / for prompt templates'
                                : 'connecting...',
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    // Save as template
                    if (!_sending && _controller.text.isNotEmpty)
                      GestureDetector(
                        onTap: _saveAsTemplate,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 2),
                            child: Tooltip(
                              message: 'save as template',
                              child: Icon(Icons.bookmark_add_outlined,
                                size: 14, color: t.fgDisabled),
                            ),
                          ),
                        ),
                      ),
                    // (C) Keyboard shortcut hint
                    if (!_sending && _controller.text.isEmpty && widget.enabled)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 3),
                        child: Text('shift+enter for new line',
                          style: TextStyle(fontSize: 9, color: t.fgDisabled)),
                      ),
                    // #8: Abort button (shown when sending)
                    if (_sending)
                      GestureDetector(
                        onTap: _abort,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 2),
                            child: Icon(
                              Icons.stop_rounded,
                              size: 16,
                              color: t.statusError,
                            ),
                          ),
                        ),
                      ),
                    if (_voiceController.isAvailable && !_sending)
                      GestureDetector(
                        onTap: _toggleVoice,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 2),
                          child: Icon(
                            isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                            size: 16,
                            color: isListening ? t.statusError : t.fgMuted,
                          ),
                        ),
                      ),
                    ],
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

class _AttachmentInfo {
  final String name;
  final String mimeType;
  final String base64;
  final int size;

  const _AttachmentInfo({
    required this.name,
    required this.mimeType,
    required this.base64,
    required this.size,
  });
}

class _AttachmentChip extends StatefulWidget {
  final String name;
  final String mimeType;
  final int size;
  final ShellTokens tokens;
  final ThemeData theme;
  final VoidCallback onRemove;

  const _AttachmentChip({
    required this.name,
    required this.mimeType,
    required this.size,
    required this.tokens,
    required this.theme,
    required this.onRemove,
  });

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  bool _hovering = false;

  IconData _iconForMime(String mime) {
    if (mime.startsWith('image/')) return Icons.image;
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime.startsWith('video/')) return Icons.videocam;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: kShellBorderRadiusSm,
          color: t.surfaceCard,
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconForMime(widget.mimeType), size: 12, color: t.fgTertiary),
            const SizedBox(width: 4),
            Text(widget.name,
              style: TextStyle(fontSize: 10, color: t.fgSecondary),
              overflow: TextOverflow.ellipsis),
            const SizedBox(width: 4),
            Text(_formatSize(widget.size),
              style: TextStyle(fontSize: 8, color: t.fgMuted)),
            if (_hovering) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: widget.onRemove,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 10, color: t.fgMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
