import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import 'voice_input.dart';

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

  @override
  void initState() {
    super.initState();
    _voiceController.initialize();
    _voiceController.addListener(() {
      if (mounted) setState(() {});
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
    if (text.isEmpty || !widget.enabled || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      final client = ref.read(gatewayClientProvider);
      await client.sendChatMessage(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _focusNode.requestFocus();
  }

  // #8: Abort the current agent run
  void _abort() {
    final client = ref.read(gatewayClientProvider);
    client.abortChat();
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

    return Container(
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
                      // Remove textInputAction and onSubmitted to let Focus handle it
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: widget.enabled ? '' : 'connecting...',
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
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
    );
  }
}
