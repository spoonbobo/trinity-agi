/**
 * Terminal Zustand store — wraps TerminalProxyClient
 */

import { create } from 'zustand';
import {
  TerminalProxyClient,
  type TerminalConnectionState,
} from '@/lib/clients/terminal-client';

function resolveTerminalWsUrl(): string {
  if (typeof window === 'undefined') return 'ws://localhost/terminal/';
  const env = process.env.NEXT_PUBLIC_TERMINAL_WS_URL;
  if (env) return env;
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${proto}//${window.location.host}/terminal/`;
}

interface TerminalStore {
  client: TerminalProxyClient;
  connectionState: TerminalConnectionState;
  terminalFocus: boolean;
  setTerminalFocus: (focus: boolean) => void;
}

const terminalClient = new TerminalProxyClient(resolveTerminalWsUrl(), '', '');

export const useTerminalStore = create<TerminalStore>((set) => {
  terminalClient.onStateChange((connectionState) => {
    set({ connectionState });
  });

  return {
    client: terminalClient,
    connectionState: 'disconnected',
    terminalFocus: false,
    setTerminalFocus: (focus: boolean) => set({ terminalFocus: focus }),
  };
});

/**
 * Sync auth from AuthClient to TerminalProxyClient.
 */
export function syncTerminalAuth(token: string, role: string, openClawId: string | null): void {
  terminalClient.token = token;
  terminalClient.openClawId = openClawId;
}

/**
 * Create a scoped terminal client for isolated use (e.g., per-channel terminals).
 */
export function createScopedTerminalClient(
  token: string,
  role: string,
  openClawId: string | null,
): TerminalProxyClient {
  const url = resolveTerminalWsUrl();
  const client = new TerminalProxyClient(url, token, role);
  client.openClawId = openClawId;
  return client;
}

export { terminalClient };
