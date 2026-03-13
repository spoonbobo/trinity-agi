/**
 * Shared TypeScript types for the Trinity Shell web frontend.
 */

// Re-export commonly used types
export type { AuthState, AuthRole, OpenClawInfo } from '@/lib/clients/auth-client';
export type { ConnectionState, GatewayAuth } from '@/lib/clients/gateway-client';
export type { TerminalConnectionState, TerminalOutput, EnvSyncResult } from '@/lib/clients/terminal-client';
export type { WsFrame, WsRequest, WsResponse, WsEvent } from '@/lib/protocol/ws-frame';
export type { A2UISurface, A2UIComponent } from '@/lib/protocol/a2ui-models';
export type { AppLanguage } from '@/lib/i18n/translations';
export type { CanvasMode, DrawIOTheme } from '@/lib/stores/canvas-store';
export type { ThemeMode } from '@/lib/stores/theme-store';
export type { Breakpoint } from '@/lib/hooks/use-responsive';
