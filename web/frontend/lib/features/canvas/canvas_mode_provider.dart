import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:html' as html;

/// Available canvas rendering modes
enum CanvasMode {
  a2ui,
  drawio,
}

/// DrawIO theme options
enum DrawIOTheme {
  light,
  dark,
}

/// Provider for the current canvas mode
/// Persists the mode selection to localStorage
final canvasModeProvider = StateNotifierProvider<CanvasModeNotifier, CanvasMode>((ref) {
  return CanvasModeNotifier();
});

/// Provider for DrawIO theme (light/dark)
/// Persists to localStorage, defaults to light
final drawIOThemeProvider = StateNotifierProvider<DrawIOThemeNotifier, DrawIOTheme>((ref) {
  return DrawIOThemeNotifier();
});

const _canvasModeKey = 'trinity_canvas_mode_v4';
const _drawIOThemeKey = 'trinity_drawio_theme';

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

class DrawIOThemeNotifier extends StateNotifier<DrawIOTheme> {
  DrawIOThemeNotifier() : super(_loadInitialTheme()) {
    _loadFromStorage();
  }

  static DrawIOTheme _loadInitialTheme() {
    final stored = html.window.localStorage[_drawIOThemeKey];
    return _parseTheme(stored);
  }

  static DrawIOTheme _parseTheme(String? stored) {
    switch (stored) {
      case 'dark':
        return DrawIOTheme.dark;
      case 'light':
      default:
        return DrawIOTheme.light;
    }
  }

  void _loadFromStorage() {
    final stored = html.window.localStorage[_drawIOThemeKey];
    state = _parseTheme(stored);
  }

  void setTheme(DrawIOTheme theme) {
    if (state != theme) {
      state = theme;
      _persistToStorage(theme);
    }
  }

  void toggle() {
    final newTheme = state == DrawIOTheme.light ? DrawIOTheme.dark : DrawIOTheme.light;
    setTheme(newTheme);
  }

  void _persistToStorage(DrawIOTheme theme) {
    html.window.localStorage[_drawIOThemeKey] = theme.name;
  }
}
