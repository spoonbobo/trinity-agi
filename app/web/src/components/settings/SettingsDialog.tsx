'use client';

import { useCallback } from 'react';
import { LogOut, Moon, Sun, Monitor, Globe } from 'lucide-react';
import { useAuthStore } from '@/lib/stores/auth-store';
import { useThemeStore, type ThemeMode, type AppLanguage } from '@/lib/stores/theme-store';
import { tr, languageLabels } from '@/lib/i18n/translations';
import { Dialog } from '@/components/ui/Dialog';

/* ------------------------------------------------------------------ */
/*  SettingsDialog — port of settings_dialog.dart (~160 lines)         */
/* ------------------------------------------------------------------ */

export function SettingsDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const language = useThemeStore((s) => s.language);
  const themeMode = useThemeStore((s) => s.themeMode);
  const setThemeMode = useThemeStore((s) => s.setThemeMode);
  const setLanguage = useThemeStore((s) => s.setLanguage);

  const authClient = useAuthStore((s) => s.client);
  const email = useAuthStore((s) => s.email);
  const userId = useAuthStore((s) => s.userId);
  const role = useAuthStore((s) => s.role);

  const handleLogout = useCallback(() => {
    authClient.logout();
    onClose();
  }, [authClient, onClose]);

  return (
    <Dialog
      id="settings"
      open={open}
      onClose={onClose}
      title={tr(language, 'settings').toUpperCase()}
      width="520px"
      maxWidth="600px"
    >
      <div className="flex flex-col gap-0 divide-y divide-border-shell">
        {/* ---- Account section ---- */}
        <SettingsSection label={tr(language, 'account')}>
          <div className="flex flex-col gap-2">
            <SettingsRow label={tr(language, 'email')} value={email ?? '-'} />
            <SettingsRow label="user id" value={userId?.slice(0, 12) ?? '-'} mono />
            <SettingsRow
              label="role"
              value={role}
              valueClassName={
                role === 'superadmin'
                  ? 'text-status-warning'
                  : role === 'admin'
                    ? 'text-accent-primary'
                    : 'text-fg-secondary'
              }
            />
            <button
              onClick={handleLogout}
              className="mt-1 flex w-fit items-center gap-1.5 text-[11px] text-fg-muted hover:text-status-error"
            >
              <LogOut size={12} />
              {tr(language, 'logout')}
            </button>
          </div>
        </SettingsSection>

        {/* ---- Theme section ---- */}
        <SettingsSection label={tr(language, 'theme')}>
          <ToggleGroup<ThemeMode>
            options={[
              { value: 'system', label: 'system', icon: <Monitor size={12} /> },
              { value: 'dark', label: 'dark', icon: <Moon size={12} /> },
              { value: 'light', label: 'light', icon: <Sun size={12} /> },
            ]}
            value={themeMode}
            onChange={setThemeMode}
          />
        </SettingsSection>

        {/* ---- Language section ---- */}
        <SettingsSection label={tr(language, 'language')}>
          <ToggleGroup<AppLanguage>
            options={[
              { value: 'en', label: 'en', icon: <Globe size={12} /> },
              { value: 'zh-Hans', label: '简体' },
              { value: 'zh-Hant', label: '繁體' },
            ]}
            value={language}
            onChange={setLanguage}
          />
        </SettingsSection>
      </div>
    </Dialog>
  );
}

/* ------------------------------------------------------------------ */
/*  Sub-components                                                     */
/* ------------------------------------------------------------------ */

function SettingsSection({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2 px-4 py-4">
      <span className="text-[10px] uppercase tracking-wide text-fg-muted">{label}</span>
      {children}
    </div>
  );
}

function SettingsRow({
  label,
  value,
  mono,
  valueClassName,
}: {
  label: string;
  value: string;
  mono?: boolean;
  valueClassName?: string;
}) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-[11px] text-fg-tertiary">{label}</span>
      <span
        className={`text-xs ${valueClassName ?? 'text-fg-primary'} ${mono ? 'font-mono' : ''} select-text`}
      >
        {value}
      </span>
    </div>
  );
}

function ToggleGroup<T extends string>({
  options,
  value,
  onChange,
}: {
  options: Array<{ value: T; label: string; icon?: React.ReactNode }>;
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <div className="flex items-center gap-1">
      {options.map((opt) => {
        const isActive = opt.value === value;
        return (
          <button
            key={opt.value}
            onClick={() => onChange(opt.value)}
            className={`flex items-center gap-1.5 border px-3 py-1 text-[11px] transition-colors ${
              isActive
                ? 'border-accent-primary text-accent-primary'
                : 'border-border-shell text-fg-muted hover:text-fg-secondary hover:border-fg-muted'
            }`}
          >
            {opt.icon}
            {opt.label}
          </button>
        );
      })}
    </div>
  );
}
