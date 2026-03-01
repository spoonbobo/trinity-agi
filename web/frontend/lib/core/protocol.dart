/// Constants for OpenClaw Gateway WebSocket protocol event and method names.

class GatewayMethods {
  static const connect = 'connect';
  static const chatSend = 'chat.send';
  static const chatHistory = 'chat.history';
  static const chatAbort = 'chat.abort';
  static const chatInject = 'chat.inject';
  static const status = 'status';
  static const health = 'health';
  static const systemPresence = 'system-presence';
  static const sessionsList = 'sessions.list';
  static const sessionsDelete = 'sessions.delete';
  static const execApprovalResolve = 'exec.approval.resolve';
  static const toolsCatalog = 'tools.catalog';
}

class GatewayEvents {
  static const connectChallenge = 'connect.challenge';
  static const chat = 'chat';
  static const agent = 'agent';
  static const presence = 'presence';
  static const tick = 'tick';
  static const shutdown = 'shutdown';
  static const execApprovalRequested = 'exec.approval.requested';
}

/// Chat event subtypes within the 'chat' event payload.
class ChatEventType {
  static const message = 'message';
  static const toolCall = 'tool_call';
  static const toolResult = 'tool_result';
  static const thinking = 'thinking';
  static const done = 'done';
  static const error = 'error';
}
