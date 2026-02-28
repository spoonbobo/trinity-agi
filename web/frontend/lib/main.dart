import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/i18n.dart';
import 'core/providers.dart';
import 'features/shell/shell_page.dart';
import 'features/auth/auth_guard.dart';

export 'core/providers.dart' show authClientProvider;

final themeModeProvider = StateProvider<ThemeMode>((ref) => loadThemeMode());
final fontFamilyProvider = StateProvider<AppFontFamily>((ref) => loadAppFontFamily());
final languageProvider = StateProvider<AppLanguage>((ref) => loadAppLanguage());

void main() {
  runApp(const ProviderScope(child: TrinityApp()));
}

class TrinityApp extends ConsumerWidget {
  const TrinityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final fontFamily = ref.watch(fontFamilyProvider);
    final language = ref.watch(languageProvider);

    return MaterialApp(
      title: 'Trinity AGI',
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
