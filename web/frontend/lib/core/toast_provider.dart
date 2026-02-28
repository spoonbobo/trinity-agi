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

  static void show(BuildContext context, String message, ToastType type) {
    _overlayEntry?.remove();
    
    _overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: type,
        onDismiss: () => _overlayEntry?.remove(),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
    
    Future.delayed(const Duration(seconds: 5), () {
      _overlayEntry?.remove();
    });
  }

  static void showError(BuildContext context, String message) {
    show(context, message, ToastType.error);
  }

  static void showInfo(BuildContext context, String message) {
    show(context, message, ToastType.info);
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

    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withOpacity(0.95),
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
                  child: const Text(
                    'x',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
