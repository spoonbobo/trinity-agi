import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/auth_client.dart';
import '../../main.dart' show themeModeProvider, fontFamilyProvider, languageProvider, authClientProvider;

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final font = ref.watch(fontFamilyProvider);
    final language = ref.watch(languageProvider);
    final authClient = ref.watch(authClientProvider);
    final authState = authClient.state;

    void setMode(ThemeMode next) {
      ref.read(themeModeProvider.notifier).state = next;
      saveThemeMode(next);
    }

    void setFont(AppFontFamily next) {
      ref.read(fontFamilyProvider.notifier).state = next;
      saveAppFontFamily(next);
    }

    void setLanguage(AppLanguage next) {
      ref.read(languageProvider.notifier).state = next;
      saveAppLanguage(next);
    }

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Text(tr(language, 'settings'), style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text(tr(language, 'close'), style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Account section
                    Text('account', style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          authState.isGuest
                              ? 'guest'
                              : (authState.email ?? authState.userId ?? 'unknown'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          roleToString(authState.role),
                          style: theme.textTheme.labelSmall?.copyWith(color: t.accentPrimary),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            ref.read(authClientProvider).logout();
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            'logout',
                            style: theme.textTheme.labelSmall?.copyWith(color: t.statusError),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Theme
                    Text(tr(language, 'theme'), style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      children: [
                        _toggle(theme, t, tr(language, 'system'), mode == ThemeMode.system, () => setMode(ThemeMode.system)),
                        _toggle(theme, t, tr(language, 'dark'), mode == ThemeMode.dark, () => setMode(ThemeMode.dark)),
                        _toggle(theme, t, tr(language, 'light'), mode == ThemeMode.light, () => setMode(ThemeMode.light)),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Font
                    Text(tr(language, 'font'), style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      children: [
                        for (final f in AppFontFamily.values)
                          _toggle(theme, t, appFontFamilyLabel(f), font == f, () => setFont(f)),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Language
                    Text(tr(language, 'language'), style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      children: [
                        _toggle(theme, t, appLanguageLabel(AppLanguage.en), language == AppLanguage.en, () => setLanguage(AppLanguage.en)),
                        _toggle(theme, t, appLanguageLabel(AppLanguage.zhHans), language == AppLanguage.zhHans, () => setLanguage(AppLanguage.zhHans)),
                        _toggle(theme, t, appLanguageLabel(AppLanguage.zhHant), language == AppLanguage.zhHant, () => setLanguage(AppLanguage.zhHant)),
                      ],
                    ),


                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle(ThemeData theme, ShellTokens t, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: active ? t.accentPrimary : t.fgMuted,
        ),
      ),
    );
  }
}
