import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';

enum ToastType { error, info }

class ToastState {
  final String? message;
  final ToastType? type;
  final bool visible;

  const ToastState({this.message, this.type, this.visible = false});
}

class ToastNotifier extends StateNotifier<ToastState> {
  ToastNotifier() : super(const ToastState());

  Timer? _timer;

  void showError(String message) {
    _timer?.cancel();
    state = ToastState(message: message, type: ToastType.error, visible: true);
    _timer = Timer(const Duration(seconds: 5), dismiss);
  }

  void showInfo(String message) {
    _timer?.cancel();
    state = ToastState(message: message, type: ToastType.info, visible: true);
    _timer = Timer(const Duration(seconds: 5), dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    state = const ToastState(visible: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final toastProvider = StateNotifierProvider<ToastNotifier, ToastState>((ref) {
  return ToastNotifier();
});

class ToastService {
  static OverlayEntry? _overlayEntry;
  static final List<_ToastItem> _toasts = [];
  static int _seed = 0;

  static const Duration _toastDuration = Duration(seconds: 5);
  static const int _maxVisible = 3;
  static const Duration _dedupeWindow = Duration(milliseconds: 1200);

  static void show(BuildContext context, String message, ToastType type) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    final last = _toasts.isNotEmpty ? _toasts.last : null;
    if (last != null &&
        last.message == trimmed &&
        last.type == type &&
        now.difference(last.createdAt) < _dedupeWindow) {
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (ctx) => _ToastStack(
          toasts: List.unmodifiable(_toasts),
          onDismiss: _dismissById,
        ),
      );
      overlay.insert(_overlayEntry!);
    }

    final item = _ToastItem(
      id: 'toast-${++_seed}',
      message: trimmed,
      type: type,
      createdAt: now,
    );
    _toasts.add(item);
    if (_toasts.length > _maxVisible) {
      _toasts.removeRange(0, _toasts.length - _maxVisible);
    }
    _overlayEntry?.markNeedsBuild();

    Future.delayed(_toastDuration, () {
      _dismissById(item.id);
    });
  }

  static void _dismissById(String id) {
    _toasts.removeWhere((item) => item.id == id);
    if (_toasts.isEmpty) {
      try {
        _overlayEntry?.remove();
      } catch (_) {}
      _overlayEntry = null;
      return;
    }
    _overlayEntry?.markNeedsBuild();
  }

  static void showError(BuildContext context, String message) {
    show(context, message, ToastType.error);
  }

  static void showInfo(BuildContext context, String message) {
    show(context, message, ToastType.info);
  }
}

class _ToastItem {
  final String id;
  final String message;
  final ToastType type;
  final DateTime createdAt;

  const _ToastItem({
    required this.id,
    required this.message,
    required this.type,
    required this.createdAt,
  });
}

class _ToastStack extends StatelessWidget {
  final List<_ToastItem> toasts;
  final ValueChanged<String> onDismiss;

  const _ToastStack({
    required this.toasts,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (toasts.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in toasts)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ToastWidget(
                    message: item.message,
                    type: item.type,
                    onDismiss: () => onDismiss(item.id),
                  ),
                ),
            ],
          ),
        ),
      ),
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
    final isError = type == ToastType.error;
    final textColor = isError ? const Color(0xFFEF4444) : const Color(0xFF22C55E);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withOpacity(0.96),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isError
                ? const Color(0xFFEF4444).withOpacity(0.5)
                : const Color(0xFF22C55E).withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 13,
              color: textColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: SelectableText(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onDismiss,
              child: Text(
                'x',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7280),
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
