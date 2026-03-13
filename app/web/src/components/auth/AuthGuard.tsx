'use client';

import { useEffect } from 'react';
import { useAuthStore } from '@/lib/stores/auth-store';
import { syncGatewayAuth } from '@/lib/stores/gateway-store';
import { syncTerminalAuth } from '@/lib/stores/terminal-store';
import { LoginPage } from './LoginPage';

/**
 * AuthGuard — 1:1 port of features/auth/auth_guard.dart
 *
 * Binary gate: no token -> LoginPage, token -> children (ShellPage).
 * Also syncs auth state to gateway and terminal clients.
 */
export function AuthGuard({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token);
  const role = useAuthStore((s) => s.role);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);

  // Sync auth to gateway + terminal when token/openclaw changes
  useEffect(() => {
    if (token) {
      syncGatewayAuth(token, activeOpenClawId);
      syncTerminalAuth(token, role, activeOpenClawId);
    }
  }, [token, role, activeOpenClawId]);

  if (!token) {
    return <LoginPage />;
  }

  return <>{children}</>;
}
