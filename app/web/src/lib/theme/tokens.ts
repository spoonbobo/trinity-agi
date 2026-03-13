/**
 * Shell Design Tokens — 1:1 port from Flutter ShellTokens (core/theme.dart)
 *
 * 18 named semantic colors across 4 categories:
 *   Surfaces, Borders, Foreground gray ramp (7 levels), Accent/status
 *
 * Two token sets: dark (default) and light.
 * Exposed as CSS custom properties via globals.css.
 */

export interface ShellTokens {
  // Surfaces
  surfaceBase: string;
  surfaceCard: string;
  surfaceCodeInline: string;
  surfaceElevated: string;

  // Borders
  border: string;
  borderPrimarySubtle: string;

  // Foreground gray ramp (7 levels: primary > secondary > ... > hint)
  fgPrimary: string;
  fgSecondary: string;
  fgTertiary: string;
  fgMuted: string;
  fgDisabled: string;
  fgPlaceholder: string;
  fgHint: string;

  // Accent / status
  accentPrimary: string;
  accentPrimaryMuted: string;
  accentSecondary: string;
  statusWarning: string;
  statusError: string;
}

/** Dark theme tokens — matches Flutter darkTokens exactly */
export const darkTokens: ShellTokens = {
  surfaceBase: '#0A0A0A',
  surfaceCard: '#141414',
  surfaceCodeInline: '#1E1E1E',
  surfaceElevated: '#1A1A1A',

  border: '#2A2A2A',
  borderPrimarySubtle: '#1A3A2A',

  fgPrimary: '#D4D4D4',
  fgSecondary: '#A3A3A3',
  fgTertiary: '#737373',
  fgMuted: '#525252',
  fgDisabled: '#404040',
  fgPlaceholder: '#525252',
  fgHint: '#404040',

  accentPrimary: '#6EE7B7',
  accentPrimaryMuted: '#1A3A2A',
  accentSecondary: '#7DD3FC',
  statusWarning: '#FCD34D',
  statusError: '#F87171',
};

/** Light theme tokens — matches Flutter lightTokens exactly */
export const lightTokens: ShellTokens = {
  surfaceBase: '#F5F5F5',
  surfaceCard: '#FFFFFF',
  surfaceCodeInline: '#F0F0F0',
  surfaceElevated: '#FFFFFF',

  border: '#E5E5E5',
  borderPrimarySubtle: '#D1FAE5',

  fgPrimary: '#1A1A1A',
  fgSecondary: '#525252',
  fgTertiary: '#737373',
  fgMuted: '#A3A3A3',
  fgDisabled: '#D4D4D4',
  fgPlaceholder: '#A3A3A3',
  fgHint: '#D4D4D4',

  accentPrimary: '#059669',
  accentPrimaryMuted: '#D1FAE5',
  accentSecondary: '#0284C7',
  statusWarning: '#D97706',
  statusError: '#DC2626',
};

/** Geometry constants — matches Flutter kShellRadius / kShellRadiusSm */
export const SHELL_RADIUS = 6;
export const SHELL_RADIUS_SM = 4;

/**
 * Convert a ShellTokens object to CSS custom property declarations.
 * Used to inject tokens into :root or [data-theme] selectors.
 */
export function tokensToCssVars(tokens: ShellTokens): Record<string, string> {
  return {
    '--surface-base': tokens.surfaceBase,
    '--surface-card': tokens.surfaceCard,
    '--surface-code-inline': tokens.surfaceCodeInline,
    '--surface-elevated': tokens.surfaceElevated,
    '--border': tokens.border,
    '--border-primary-subtle': tokens.borderPrimarySubtle,
    '--fg-primary': tokens.fgPrimary,
    '--fg-secondary': tokens.fgSecondary,
    '--fg-tertiary': tokens.fgTertiary,
    '--fg-muted': tokens.fgMuted,
    '--fg-disabled': tokens.fgDisabled,
    '--fg-placeholder': tokens.fgPlaceholder,
    '--fg-hint': tokens.fgHint,
    '--accent-primary': tokens.accentPrimary,
    '--accent-primary-muted': tokens.accentPrimaryMuted,
    '--accent-secondary': tokens.accentSecondary,
    '--status-warning': tokens.statusWarning,
    '--status-error': tokens.statusError,
  };
}
