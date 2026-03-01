import 'package:flutter/material.dart';

/// Centralized dialog manager that prevents duplicate dialogs from stacking.
///
/// Usage:
///   DialogService.instance.showUnique(
///     context: context,
///     id: 'settings',
///     builder: (_) => const SettingsDialog(),
///   );
///
/// If a dialog with the same [id] is already open, the call is a no-op.
/// When the dialog closes (by any means), the id is automatically released.
class DialogService {
  DialogService._();
  static final instance = DialogService._();

  final Set<String> _openDialogs = {};

  /// Whether a dialog with [id] is currently open.
  bool isOpen(String id) => _openDialogs.contains(id);

  /// Show a dialog if one with the same [id] isn't already open.
  ///
  /// Returns the dialog result, or `null` if the call was suppressed or
  /// the context was invalid.
  Future<T?> showUnique<T>({
    required BuildContext context,
    required String id,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color? barrierColor,
  }) {
    if (_openDialogs.contains(id)) return Future.value(null);
    // Guard against deactivated/unmounted context
    if (!context.mounted) return Future.value(null);
    _openDialogs.add(id);
    try {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierColor: barrierColor,
        builder: builder,
      ).whenComplete(() => _openDialogs.remove(id));
    } catch (e) {
      // If showDialog throws synchronously (e.g., no Navigator ancestor),
      // release the ID so the dialog type isn't permanently disabled.
      _openDialogs.remove(id);
      return Future.value(null);
    }
  }

  /// Force-clear all tracked dialogs (useful on logout / hot-restart).
  void reset() => _openDialogs.clear();
}
