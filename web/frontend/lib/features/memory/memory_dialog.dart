import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/toast_provider.dart';
import '../shell/shell_page.dart' show terminalClientProvider;

class MemoryDialog extends ConsumerStatefulWidget {
  const MemoryDialog({super.key});

  @override
  ConsumerState<MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends ConsumerState<MemoryDialog> {
  bool _loading = true;
  String? _error;
  String _content = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMemory();
    });
  }

  Future<void> _loadMemory() async {
    final client = ref.read(terminalClientProvider);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!client.isConnected || !client.isAuthenticated) {
        await client.connect();
        await Future.delayed(const Duration(milliseconds: 400));
      }

      if (!client.isAuthenticated) {
        throw StateError('terminal proxy not connected');
      }

      final raw = await client.executeCommandForOutput(
        'cat /home/node/.openclaw/workspace/MEMORY.md',
        timeout: const Duration(seconds: 20),
      );

      if (!mounted) return;
      setState(() {
        _content = raw.trim().isEmpty ? '(empty)' : raw.trimRight();
      });
    } catch (e) {
      if (!mounted) return;
      final errMsg = '$e';
      ToastService.showError(context, errMsg);
      setState(() {
        _error = errMsg;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Text(
                    'memory.md',
                    style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _loading ? null : _loadMemory,
                    child: Text(
                      _loading ? 'loading...' : 'refresh',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _loading ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _loading
                    ? Text(
                        'loading...',
                        style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                      )
                    : _error != null
                        ? Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
                          )
                        : SelectableText(
                            _content,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: t.fgPrimary,
                              height: 1.6,
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
