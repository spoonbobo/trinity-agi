import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../core/terminal_client.dart';
import '../../core/theme.dart';

class PtyTerminalView extends StatefulWidget {
  final TerminalProxyClient client;
  final List<String> suggestedCommands;
  final String? initialCommand;
  final int cols;
  final int rows;
  final bool showHeader;

  const PtyTerminalView({
    super.key,
    required this.client,
    this.suggestedCommands = const [],
    this.initialCommand,
    this.cols = 120,
    this.rows = 32,
    this.showHeader = true,
  });

  @override
  State<PtyTerminalView> createState() => _PtyTerminalViewState();
}

class _PtyTerminalViewState extends State<PtyTerminalView> {
  final Terminal _terminal = Terminal(maxLines: 5000);
  StreamSubscription<String>? _shellSubscription;

  int _lastOutputIndex = 0;
  bool _startingShell = false;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (data) {
      if (widget.client.isShellActive) {
        widget.client.shellInput(data);
      }
    };
    _attachClient(widget.client);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startShell());
  }

  @override
  void didUpdateWidget(covariant PtyTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _detachClient(oldWidget.client);
      _attachClient(widget.client);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startShell());
    }
  }

  @override
  void dispose() {
    _detachClient(widget.client);
    widget.client.closeShell();
    super.dispose();
  }

  void _attachClient(TerminalProxyClient client) {
    client.addListener(_onClientUpdate);
    _shellSubscription = client.shellOutput.listen(_terminal.write);
    _lastOutputIndex = client.outputs.length;
    _drainSystemOutputs();
  }

  void _detachClient(TerminalProxyClient client) {
    client.removeListener(_onClientUpdate);
    _shellSubscription?.cancel();
    _shellSubscription = null;
  }

  void _onClientUpdate() {
    _drainSystemOutputs();
    if (widget.client.isShellActive) {
      _startingShell = false;
    }
    if (mounted) setState(() {});
  }

  void _drainSystemOutputs() {
    final outputs = widget.client.outputs;
    if (_lastOutputIndex >= outputs.length) return;
    for (final output in outputs.sublist(_lastOutputIndex)) {
      final text = output.data ?? output.message;
      if (text == null || text.isEmpty) continue;
      if (output.type == 'shell_output') continue;
      _terminal.write('\r\n[$output.type] $text\r\n');
    }
    _lastOutputIndex = outputs.length;
    _startingShell = false;
  }

  Future<void> _startShell() async {
    if (_startingShell || widget.client.isShellActive) return;
    setState(() => _startingShell = true);
    try {
      if (!widget.client.isConnected || !widget.client.isAuthenticated) {
        await widget.client.connect();
      }
      widget.client.startShell(widget.cols, widget.rows);
    } catch (e) {
      _terminal.write('\r\n[error] failed to start interactive shell: $e\r\n');
      if (mounted) setState(() => _startingShell = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final isReady = widget.client.isShellActive;
    final statusText = 'interactive shell';
    final statusColor = isReady
        ? t.accentPrimary
        : (_startingShell ? t.accentSecondary : t.fgMuted);

    return Column(
      children: [
        if (widget.showHeader)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
                ),
                const SizedBox(width: 10),
                Text(
                  _startingShell ? 'starting...' : 'cwd shown in prompt',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
                const Spacer(),
                if (!isReady)
                  GestureDetector(
                    onTap: _startingShell ? null : _startShell,
                    child: Text(
                      'start shell',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _startingShell ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: t.surfaceBase,
            child: TerminalView(
              _terminal,
              autofocus: true,
              padding: const EdgeInsets.all(10),
              backgroundOpacity: 1,
              cursorType: TerminalCursorType.underline,
              textStyle: const TerminalStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
