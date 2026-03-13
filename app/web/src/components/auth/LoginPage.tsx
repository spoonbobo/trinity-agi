'use client';

import { useState, useRef, useEffect, useCallback } from 'react';
import { useAuthStore } from '@/lib/stores/auth-store';
import { useThemeStore } from '@/lib/stores/theme-store';
import { tr } from '@/lib/i18n/translations';
import { ToastService } from '@/components/ui/Toast';

/**
 * LoginPage — 1:1 port of features/auth/login_page.dart
 *
 * Three auth methods: email/password, Keycloak SSO popup, guest access.
 * Remember email checkbox, login/signup toggle.
 */
export function LoginPage() {
  const client = useAuthStore((s) => s.client);
  const language = useThemeStore((s) => s.language);

  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [rememberEmail, setRememberEmail] = useState(false);

  const passwordRef = useRef<HTMLInputElement>(null);
  const emailRef = useRef<HTMLInputElement>(null);

  // Restore remembered email
  useEffect(() => {
    try {
      const remembered = localStorage.getItem('trinity_remember_email') === 'true';
      setRememberEmail(remembered);
      if (remembered) {
        const saved = localStorage.getItem('trinity_saved_email') ?? '';
        setEmail(saved);
        // Focus password if email is pre-filled
        if (saved) {
          setTimeout(() => passwordRef.current?.focus(), 100);
        }
      }
    } catch {
      // Ignore
    }
  }, []);

  // SSO popup message listener
  useEffect(() => {
    const handler = (e: MessageEvent) => {
      // Validate origin
      const expectedOrigin = window.location.origin;
      if (e.origin !== expectedOrigin) return;

      const data = e.data;
      if (data?.type === 'sso-callback' && data.access_token) {
        client.resolveSessionFromToken(data.access_token).catch((err) => {
          ToastService.showError(err.message ?? 'SSO login failed');
        });
      }
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, [client]);

  const handleSubmit = useCallback(async () => {
    if (!email.trim() || !password.trim()) return;
    setLoading(true);

    try {
      // Save/clear remembered email
      if (rememberEmail) {
        localStorage.setItem('trinity_remember_email', 'true');
        localStorage.setItem('trinity_saved_email', email);
      } else {
        localStorage.removeItem('trinity_remember_email');
        localStorage.removeItem('trinity_saved_email');
      }

      if (isSignUp) {
        await client.signUpWithEmail(email, password);
        ToastService.showInfo('Account created. You can now log in.');
        setIsSignUp(false);
      } else {
        await client.loginWithEmail(email, password);
      }
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Authentication failed');
    } finally {
      setLoading(false);
    }
  }, [email, password, isSignUp, rememberEmail, client]);

  const handleSSO = useCallback(() => {
    const url = client.getKeycloakLoginUrl();
    const popup = window.open(url, 'trinity-sso', 'width=500,height=600,popup=yes');

    // Fallback polling for popup close
    if (popup) {
      const poller = setInterval(() => {
        try {
          if (popup.closed) {
            clearInterval(poller);
          }
        } catch {
          clearInterval(poller);
        }
      }, 500);
    }
  }, [client]);

  const handleGuest = useCallback(async () => {
    setLoading(true);
    try {
      await client.loginAsGuest();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Guest login failed');
    } finally {
      setLoading(false);
    }
  }, [client]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <div className="flex h-full items-center justify-center bg-surface-base">
      <div className="flex w-full max-w-xs flex-col gap-6">
        {/* Title */}
        <div className="text-center">
          <h1 className="text-lg font-light tracking-[0.3em] text-fg-primary">trinity</h1>
        </div>

        {/* Email + Password fields */}
        <div className="flex flex-col gap-3">
          <input
            ref={emailRef}
            type="email"
            autoComplete="email"
            placeholder={tr(language, 'email')}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            onKeyDown={handleKeyDown}
            className="h-9 w-full border-b border-border-shell bg-transparent px-0 text-sm text-fg-primary outline-none placeholder:text-fg-placeholder focus:border-accent-primary"
          />
          <input
            ref={passwordRef}
            type="password"
            autoComplete={isSignUp ? 'new-password' : 'current-password'}
            placeholder={tr(language, 'password')}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={handleKeyDown}
            className="h-9 w-full border-b border-border-shell bg-transparent px-0 text-sm text-fg-primary outline-none placeholder:text-fg-placeholder focus:border-accent-primary"
          />
        </div>

        {/* Remember + Submit */}
        <div className="flex flex-col gap-3">
          <label className="flex cursor-pointer items-center gap-2 text-xs text-fg-tertiary">
            <input
              type="checkbox"
              checked={rememberEmail}
              onChange={(e) => setRememberEmail(e.target.checked)}
              className="accent-accent-primary"
            />
            {tr(language, 'remember_email')}
          </label>

          <button
            onClick={handleSubmit}
            disabled={loading}
            className="text-xs tracking-wide text-accent-primary hover:underline disabled:opacity-50"
          >
            {loading ? tr(language, 'loading') : isSignUp ? tr(language, 'sign_up') : tr(language, 'login')}
          </button>

          <button
            onClick={() => setIsSignUp(!isSignUp)}
            className="text-xs text-fg-muted hover:text-fg-secondary"
          >
            {isSignUp ? tr(language, 'login') : tr(language, 'sign_up')}
          </button>
        </div>

        {/* Divider */}
        <div className="h-px bg-border-shell" />

        {/* SSO + Guest */}
        <div className="flex flex-col items-center gap-2">
          <button
            onClick={handleSSO}
            className="text-xs text-fg-tertiary hover:text-accent-primary"
          >
            {tr(language, 'sso_login')}
          </button>
          <button
            onClick={handleGuest}
            disabled={loading}
            className="text-xs text-fg-muted hover:text-fg-secondary disabled:opacity-50"
          >
            {tr(language, 'guest_access')}
          </button>
        </div>
      </div>
    </div>
  );
}
