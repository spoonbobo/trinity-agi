import 'package:flutter/material.dart';
import 'dart:html' as html;

enum AppFontFamily {
  ibmPlexMono,
  jetBrainsMono,
}

const _themeModeStorageKey = 'trinity_theme_mode';
const _fontFamilyStorageKey = 'trinity_font_family';

String appFontFamilyToStorage(AppFontFamily family) {
  switch (family) {
    case AppFontFamily.ibmPlexMono:
      return 'ibm-plex-mono';
    case AppFontFamily.jetBrainsMono:
      return 'jetbrains-mono';
  }
}

AppFontFamily appFontFamilyFromStorage(String? value) {
  switch (value) {
    case 'jetbrains-mono':
      return AppFontFamily.jetBrainsMono;
    case 'ibm-plex-mono':
    default:
      return AppFontFamily.ibmPlexMono;
  }
}

String appFontFamilyLabel(AppFontFamily family) {
  switch (family) {
    case AppFontFamily.ibmPlexMono:
      return 'IBM Plex Mono';
    case AppFontFamily.jetBrainsMono:
      return 'JetBrains Mono';
  }
}

/// Returns the font family name as declared in pubspec.yaml
String _fontFamilyName(AppFontFamily family) {
  switch (family) {
    case AppFontFamily.ibmPlexMono:
      return 'IBMPlexMono';
    case AppFontFamily.jetBrainsMono:
      return 'JetBrainsMono';
  }
}

TextTheme applyAppFontToTextTheme(AppFontFamily family, TextTheme base) {
  final fontName = _fontFamilyName(family);
  return base.apply(fontFamily: fontName);
}

TextStyle appFontStyle(
  AppFontFamily family, {
  TextStyle? textStyle,
  Color? color,
  double? fontSize,
}) {
  return (textStyle ?? const TextStyle()).copyWith(
    fontFamily: _fontFamilyName(family),
    color: color ?? textStyle?.color,
    fontSize: fontSize ?? textStyle?.fontSize,
  );
}

// ---------------------------------------------------------------------------
// Semantic tokens
// ---------------------------------------------------------------------------

class ShellTokens {
  // surfaces
  final Color surfaceBase;
  final Color surfaceCard;
  final Color surfaceCodeInline;
  final Color surfaceElevated;

  // borders
  final Color border;
  final Color borderPrimarySubtle;

  // foreground gray ramp
  final Color fgPrimary;
  final Color fgSecondary;
  final Color fgTertiary;
  final Color fgMuted;
  final Color fgDisabled;
  final Color fgPlaceholder;
  final Color fgHint;

  // accent / status
  final Color accentPrimary;
  final Color accentPrimaryMuted;
  final Color accentSecondary;
  final Color statusWarning;
  final Color statusError;

  const ShellTokens({
    required this.surfaceBase,
    required this.surfaceCard,
    required this.surfaceCodeInline,
    required this.surfaceElevated,
    required this.border,
    required this.borderPrimarySubtle,
    required this.fgPrimary,
    required this.fgSecondary,
    required this.fgTertiary,
    required this.fgMuted,
    required this.fgDisabled,
    required this.fgPlaceholder,
    required this.fgHint,
    required this.accentPrimary,
    required this.accentPrimaryMuted,
    required this.accentSecondary,
    required this.statusWarning,
    required this.statusError,
  });

  // convenience ----------------------------------------------------------
  static ShellTokens of(BuildContext context) {
    return Theme.of(context).extension<ShellTokensTheme>()!.tokens;
  }
}

// dark -------------------------------------------------------------------
const darkTokens = ShellTokens(
  surfaceBase: Color(0xFF0A0A0A),
  surfaceCard: Color(0xFF0F0F0F),
  surfaceCodeInline: Color(0xFF111111),
  surfaceElevated: Color(0xFF2A2A2A),
  border: Color(0xFF1E1E1E),
  borderPrimarySubtle: Color(0xFF2A3A2A),
  fgPrimary: Color(0xFFD4D4D4),
  fgSecondary: Color(0xFF999999),
  fgTertiary: Color(0xFF555555),
  fgMuted: Color(0xFF444444),
  fgDisabled: Color(0xFF333333),
  fgPlaceholder: Color(0xFF222222),
  fgHint: Color(0xFF3A3A3A),
  accentPrimary: Color(0xFF6EE7B7),
  accentPrimaryMuted: Color(0xFF3A5A4A),
  accentSecondary: Color(0xFF3B82F6),
  statusWarning: Color(0xFFFBBF24),
  statusError: Color(0xFFEF4444),
);

// light ------------------------------------------------------------------
const lightTokens = ShellTokens(
  surfaceBase: Color(0xFFF5F5F5),
  surfaceCard: Color(0xFFFFFFFF),
  surfaceCodeInline: Color(0xFFEBEBEB),
  surfaceElevated: Color(0xFFD9D9D9),
  border: Color(0xFFDCDCDC),
  borderPrimarySubtle: Color(0xFFB8D8C8),
  fgPrimary: Color(0xFF1A1A1A),
  fgSecondary: Color(0xFF555555),
  fgTertiary: Color(0xFF777777),
  fgMuted: Color(0xFF999999),
  fgDisabled: Color(0xFFBBBBBB),
  fgPlaceholder: Color(0xFFCCCCCC),
  fgHint: Color(0xFFAAAAAA),
  accentPrimary: Color(0xFF059669),
  accentPrimaryMuted: Color(0xFF6DA890),
  accentSecondary: Color(0xFF2563EB),
  statusWarning: Color(0xFFD97706),
  statusError: Color(0xFFDC2626),
);

// ---------------------------------------------------------------------------
// ThemeExtension wrapper so tokens ride the ThemeData
// ---------------------------------------------------------------------------

class ShellTokensTheme extends ThemeExtension<ShellTokensTheme> {
  final ShellTokens tokens;
  const ShellTokensTheme(this.tokens);

  @override
  ShellTokensTheme copyWith({ShellTokens? tokens}) =>
      ShellTokensTheme(tokens ?? this.tokens);

  @override
  ShellTokensTheme lerp(covariant ShellTokensTheme? other, double t) =>
      other ?? this;
}

// ---------------------------------------------------------------------------
// Build a ThemeData from tokens
// ---------------------------------------------------------------------------

ThemeData buildTheme(ShellTokens t, Brightness brightness, AppFontFamily fontFamily) {
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: t.surfaceBase,
    colorScheme: ColorScheme(
      brightness: brightness,
      surface: t.surfaceBase,
      onSurface: t.fgPrimary,
      primary: t.accentPrimary,
      onPrimary: t.surfaceBase,
      secondary: t.accentSecondary,
      onSecondary: t.surfaceBase,
      error: t.statusError,
      onError: t.surfaceBase,
      outline: t.border,
    ),
    cardTheme: CardThemeData(
      color: t.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    textTheme: applyAppFontToTextTheme(
      fontFamily,
      TextTheme(
        bodyLarge: TextStyle(
          color: t.fgPrimary,
          fontSize: 14,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: t.fgSecondary,
          fontSize: 13,
          height: 1.5,
        ),
        titleLarge: TextStyle(
          color: t.fgPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          color: t.fgTertiary,
          fontSize: 11,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      hintStyle: appFontStyle(
        fontFamily,
        color: t.fgHint,
        fontSize: 14,
      ),
    ),
    iconTheme: IconThemeData(color: t.accentPrimary, size: 16),
    dividerTheme: DividerThemeData(
      color: t.border, thickness: 0.5, space: 0,
    ),
    extensions: [ShellTokensTheme(t)],
  );
}

// ---------------------------------------------------------------------------
// Theme mode persistence (localStorage)
// ---------------------------------------------------------------------------

ThemeMode loadThemeMode() {
  final stored = html.window.localStorage[_themeModeStorageKey];
  switch (stored) {
    case 'dark':
      return ThemeMode.dark;
    case 'light':
      return ThemeMode.light;
    default:
      return ThemeMode.system;
  }
}

void saveThemeMode(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.dark:
      html.window.localStorage[_themeModeStorageKey] = 'dark';
      break;
    case ThemeMode.light:
      html.window.localStorage[_themeModeStorageKey] = 'light';
      break;
    case ThemeMode.system:
      html.window.localStorage.remove(_themeModeStorageKey);
      break;
  }
}

AppFontFamily loadAppFontFamily() {
  return appFontFamilyFromStorage(html.window.localStorage[_fontFamilyStorageKey]);
}

void saveAppFontFamily(AppFontFamily family) {
  html.window.localStorage[_fontFamilyStorageKey] = appFontFamilyToStorage(family);
}
