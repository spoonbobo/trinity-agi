/**
 * Gateway Zustand store — wraps GatewayClient, replaces Riverpod gatewayClientProvider
 */

import { create } from 'zustand';
import { v4 as uuidv4 } from 'uuid';
import { GatewayClient, type ConnectionState, type GatewayAuth } from '@/lib/clients/gateway-client';

function resolveGatewayWsUrl(): string {
  if (typeof window === 'undefined') return 'ws://localhost/ws';
  const env = process.env.NEXT_PUBLIC_GATEWAY_WS_URL;
  if (env) return env;
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${proto}//${window.location.host}/ws`;
}

interface GatewayStore {
  client: GatewayClient;
  connectionState: ConnectionState;
  deviceId: string;
}

const deviceId = typeof window !== 'undefined' ? uuidv4() : 'server';

const sharedAuth: GatewayAuth = {
  token: '',
  deviceId,
};

const gatewayClient = new GatewayClient(resolveGatewayWsUrl(), sharedAuth);

export const useGatewayStore = create<GatewayStore>((set) => {
  gatewayClient.onStateChange((connectionState) => {
    set({ connectionState });
  });

  return {
    client: gatewayClient,
    connectionState: 'disconnected',
    deviceId,
  };
});

/**
 * Sync auth token from AuthClient to GatewayClient.
 * Called when auth state changes.
 */
export function syncGatewayAuth(token: string | null, openClawId: string | null): void {
  sharedAuth.token = token ?? '';
  gatewayClient.updateAuth(sharedAuth);
  gatewayClient.openClawId = openClawId;
}

export { gatewayClient };
