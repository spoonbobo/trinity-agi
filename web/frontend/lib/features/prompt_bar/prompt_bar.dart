import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import 'voice_input.dart';
import 'prompt_templates.dart';

class PromptBar extends ConsumerStatefulWidget {
  final bool enabled;

  const PromptBar({
    super.key,
    required this.enabled,
  });

  @override
  ConsumerState<PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends ConsumerState<PromptBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _voiceController = VoiceInputController();
  bool _sending = false;
  bool _showTemplates = false;
  List<_AttachmentInfo> _attachments = [];

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
        if (text.startsWith('/') && !_showTemplates) {
          setState(() => _showTemplates = true);
        } else if (!text.startsWith('/') && _showTemplates) {
          setState(() => _showTemplates = false);
        } else {
          setState(() {});
        }
      }
    });
    // (D) Auto-focus prompt bar on page load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _voiceController.dispose();
    super.dispose();
  }

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
        final attachmentData = _attachments.map((a) => {
          'name': a.name,
          'mimeType': a.mimeType,
          'base64': a.base64,
        }).toList();
        await client.sendChatMessageWithAttachments(
          text.isNotEmpty ? text : '[attachment]',
          sessionKey: sessionKey,
          attachments: attachmentData,
        );
        setState(() => _attachments = []);
      } else {
        await client.sendChatMessage(text, sessionKey: sessionKey);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _focusNode.requestFocus();
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

  // File picker
  void _pickFile() {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*,audio/*,video/*,.pdf,.txt,.md,.json,.csv,.py,.js,.ts,.dart,.yaml,.yml'
      ..multiple = true;
    input.click();
    input.onChange.listen((event) {
      final files = input.files;
      if (files == null) return;
      for (final file in files) {
        _readFile(file);
      }
    });
  }

  void _readFile(html.File file) {
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      if (reader.result is String) {
        final dataUrl = reader.result as String;
        // Data URL format: data:mime;base64,<data>
        final commaIndex = dataUrl.indexOf(',');
        if (commaIndex > 0) {
          final base64Data = dataUrl.substring(commaIndex + 1);
          setState(() {
            _attachments.add(_AttachmentInfo(
              name: file.name,
              mimeType: file.type,
              base64: base64Data,
              size: file.size,
            ));
          });
        }
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
    showDialog(
      context: context,
      builder: (ctx) {
        final t = ShellTokens.of(ctx);
        return Dialog(
          shape: const RoundedRectangleBorder(),
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
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
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: t.border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: t.accentPrimary),
                    ),
                  ),
                  onSubmitted: (_) {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      PromptTemplateStore.addCustom(
                        PromptTemplate(name: name, content: text),
                      );
                      Navigator.of(ctx).pop();
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Text('cancel',
                        style: TextStyle(fontSize: 11, color: t.fgMuted)),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        final name = nameController.text.trim();
                        if (name.isNotEmpty) {
                          PromptTemplateStore.addCustom(
                            PromptTemplate(name: name, content: text),
                          );
                          Navigator.of(ctx).pop();
                        }
                      },
                      child: Text('save',
                        style: TextStyle(fontSize: 11, color: t.accentPrimary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // #2: Handle Shift+Enter for multi-line, Enter for send
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Template panel (above prompt bar)
          if (_showTemplates)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: PromptTemplatePanel(
                filter: _controller.text.startsWith('/')
                    ? _controller.text.substring(1)
                    : '',
                onSelect: (content) {
                  _controller.text = content;
                  _controller.selection = TextSelection.collapsed(
                    offset: content.length);
                  setState(() => _showTemplates = false);
                  _focusNode.requestFocus();
                },
              ),
            ),
          ),
        // Attachment preview row
        if (_attachments.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.border, width: 0.5)),
            ),
            child: SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                itemBuilder: (context, index) {
                  final a = _attachments[index];
                  return _AttachmentChip(
                    name: a.name,
                    mimeType: a.mimeType,
                    size: a.size,
                    tokens: t,
                    theme: theme,
                    onRemove: () => _removeAttachment(index),
                  );
                },
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
                                ? 'type / for templates'
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
