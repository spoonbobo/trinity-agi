/**
 * Theme Zustand store — replaces Riverpod themeModeProvider, fontFamilyProvider, languageProvider
 */

import { create } from 'zustand';

export type ThemeMode = 'system' | 'dark' | 'light';
export type AppLanguage = 'en' | 'zh-Hans' | 'zh-Hant';

function loadThemeMode(): ThemeMode {
  try {
    const raw = localStorage.getItem('trinity_theme_mode');
    if (raw === 'dark' || raw === 'light' || raw === 'system') return raw;
  } catch { /* ignore */ }
  return 'dark';
}

function loadLanguage(): AppLanguage {
  try {
    const raw = localStorage.getItem('trinity_app_language');
    if (raw === 'en' || raw === 'zh-Hans' || raw === 'zh-Hant') return raw;
  } catch { /* ignore */ }
  return 'en';
}

interface ThemeStore {
  themeMode: ThemeMode;
  language: AppLanguage;
  setThemeMode: (mode: ThemeMode) => void;
  setLanguage: (lang: AppLanguage) => void;
  /** Resolved effective theme (accounting for system preference) */
  effectiveTheme: () => 'dark' | 'light';
}

export const useThemeStore = create<ThemeStore>((set, get) => ({
  themeMode: typeof window !== 'undefined' ? loadThemeMode() : 'dark',
  language: typeof window !== 'undefined' ? loadLanguage() : 'en',
  setThemeMode: (mode: ThemeMode) => {
    localStorage.setItem('trinity_theme_mode', mode);
    set({ themeMode: mode });
    // Apply to document
    const effective = mode === 'system'
      ? (window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark')
      : mode;
    document.documentElement.setAttribute('data-theme', effective);
  },
  setLanguage: (lang: AppLanguage) => {
    localStorage.setItem('trinity_app_language', lang);
    set({ language: lang });
  },
  effectiveTheme: () => {
    const mode = get().themeMode;
    if (mode === 'system') {
      return typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: light)').matches
        ? 'light'
        : 'dark';
    }
    return mode;
  },
}));
