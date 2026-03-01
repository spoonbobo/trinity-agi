import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/i18n.dart';
import 'core/providers.dart';
import 'core/dialog_service.dart';
import 'features/shell/shell_page.dart';
import 'features/auth/auth_guard.dart';

export 'core/providers.dart' show authClientProvider;

final themeModeProvider = StateProvider<ThemeMode>((ref) => loadThemeMode());
final fontFamilyProvider = StateProvider<AppFontFamily>((ref) => loadAppFontFamily());
final languageProvider = StateProvider<AppLanguage>((ref) => loadAppLanguage());

void main() {
  // Production error boundary: catch uncaught widget build errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kReleaseMode) {
      // In release mode, log to console instead of crashing
      // ignore: avoid_print
      print('[Trinity] FlutterError: ${details.exceptionAsString()}');
    }
  };

  // Custom error widget for production (replaces red error screen)
  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: const Text(
          'Something went wrong.',
          style: TextStyle(color: Color(0xFF999999), fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    };
  }

  DialogService.instance.reset(); // Clear stale IDs on hot-restart

  // Catch async errors that escape the Flutter framework
  runZonedGuarded(
    () {
      runApp(const ProviderScope(child: TrinityApp()));
    },
    (error, stackTrace) {
      if (kReleaseMode) {
        // ignore: avoid_print
        print('[Trinity] Unhandled async error: $error');
      } else {
        // In debug mode, rethrow so developers see it
        // ignore: avoid_print
        print('[Trinity] Unhandled async error: $error\n$stackTrace');
      }
    },
  );
}

class TrinityApp extends ConsumerWidget {
  const TrinityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final fontFamily = ref.watch(fontFamilyProvider);
    final language = ref.watch(languageProvider);

    return MaterialApp(
      title: 'Trinity',
      debugShowCheckedModeBanner: false,
      locale: appLanguageToLocale(language),
      supportedLocales: const [
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: mode,
      theme: buildTheme(lightTokens, Brightness.light, fontFamily),
      darkTheme: buildTheme(darkTokens, Brightness.dark, fontFamily),
      home: const AuthGuard(child: ShellPage()),
    );
  }
}
