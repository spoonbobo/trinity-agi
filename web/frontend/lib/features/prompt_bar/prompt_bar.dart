import 'package:flutter/material.dart';
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
                  '> ',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: widget.enabled ? t.accentPrimary : t.fgDisabled,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled && !_sending,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: widget.enabled ? '' : 'connecting...',
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                if (_voiceController.isAvailable)
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
