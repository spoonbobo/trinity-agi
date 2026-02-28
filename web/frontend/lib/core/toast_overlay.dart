import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'toast_provider.dart';
import 'theme.dart';

class ToastOverlay extends ConsumerWidget {
  final Widget child;

  const ToastOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);

    return Stack(
      children: [
        child,
        if (toast.visible && toast.message != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: _ToastWidget(
                message: toast.message!,
                type: toast.type!,
                onDismiss: () => ref.read(toastProvider.notifier).dismiss(),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToastWidget extends StatelessWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final isError = type == ToastType.error;
    final textColor = isError ? t.statusError : t.accentPrimary;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withOpacity(0.95),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isError ? t.statusError.withOpacity(0.5) : t.accentPrimary.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SelectableText(
                message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontFamily: 'monofur',
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onDismiss,
              child: Text(
                'x',
                style: TextStyle(
                  color: t.fgTertiary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
