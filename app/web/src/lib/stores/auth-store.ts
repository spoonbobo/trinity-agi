/**
 * Auth Zustand store — wraps AuthClient, replaces Riverpod authClientProvider
 */

import { create } from 'zustand';
import { AuthClient, type AuthState } from '@/lib/clients/auth-client';

function resolveAuthBaseUrl(): string {
  if (typeof window === 'undefined') return 'http://localhost';
  const env = process.env.NEXT_PUBLIC_AUTH_SERVICE_URL;
  return env || window.location.origin;
}

interface AuthStore extends AuthState {
  client: AuthClient;
  /** Re-sync from client state (called on every client notify) */
  _sync: () => void;
}

export const useAuthStore = create<AuthStore>((set, get) => {
  const client = new AuthClient(resolveAuthBaseUrl());

  // Subscribe to client changes
  client.subscribe(() => {
    get()._sync();
  });

  return {
    ...client.state,
    client,
    _sync: () => {
      set({ ...client.state });
    },
  };
});
