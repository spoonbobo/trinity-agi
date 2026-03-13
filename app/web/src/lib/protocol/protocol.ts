/**
 * OpenClaw Gateway WebSocket protocol constants
 * 1:1 port of core/protocol.dart
 */

/** Client-to-server request methods */
export const GatewayMethods = {
  connect: 'connect',
  chatSend: 'chat.send',
  chatHistory: 'chat.history',
  chatAbort: 'chat.abort',
  chatInject: 'chat.inject',
  status: 'status',
  health: 'health',
  systemPresence: 'system-presence',
  sessionsList: 'sessions.list',
  sessionsDelete: 'sessions.delete',
  execApprovalResolve: 'exec.approval.resolve',
  toolsCatalog: 'tools.catalog',
} as const;

/** Server-to-client event names */
export const GatewayEvents = {
  connectChallenge: 'connect.challenge',
  chat: 'chat',
  agent: 'agent',
  presence: 'presence',
  tick: 'tick',
  shutdown: 'shutdown',
  execApprovalRequested: 'exec.approval.requested',
} as const;

/** Subtypes within `chat` event payloads */
export const ChatEventType = {
  message: 'message',
  toolCall: 'tool_call',
  toolResult: 'tool_result',
  thinking: 'thinking',
  done: 'done',
  error: 'error',
} as const;
