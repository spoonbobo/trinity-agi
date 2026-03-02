import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:html' as html;

/// Available canvas rendering modes
enum CanvasMode {
  a2ui,
  drawio,
}

/// Provider for the current canvas mode
/// Persists the mode selection to localStorage
final canvasModeProvider = StateNotifierProvider<CanvasModeNotifier, CanvasMode>((ref) {
  return CanvasModeNotifier();
});

const _canvasModeKey = 'trinity_canvas_mode_v4';

class CanvasModeNotifier extends StateNotifier<CanvasMode> {
  CanvasModeNotifier() : super(_loadInitialMode()) {
    _loadFromStorage();
  }

  static CanvasMode _loadInitialMode() {
    final stored = html.window.localStorage[_canvasModeKey];
    return _parseMode(stored);
  }

  static CanvasMode _parseMode(String? stored) {
    switch (stored) {
      case 'drawio':
        return CanvasMode.drawio;
      case 'a2ui':
      default:
        return CanvasMode.a2ui;
    }
  }

  void _loadFromStorage() {
    final stored = html.window.localStorage[_canvasModeKey];
    state = _parseMode(stored);
  }

  void setMode(CanvasMode mode) {
    if (state != mode) {
      state = mode;
      _persistToStorage(mode);
    }
  }

  /// Toggle: a2ui <-> drawio
  void toggle() {
    final newMode = state == CanvasMode.a2ui ? CanvasMode.drawio : CanvasMode.a2ui;
    setMode(newMode);
  }

  void _persistToStorage(CanvasMode mode) {
    html.window.localStorage[_canvasModeKey] = mode.name;
  }
}
