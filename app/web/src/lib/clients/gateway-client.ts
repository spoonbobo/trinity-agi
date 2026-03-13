/**
 * GatewayClient — 1:1 port of core/gateway_client.dart
 *
 * WebSocket client for the OpenClaw gateway.
 * Challenge-response handshake, request/response correlation,
 * chat methods, session management, browser HTTP API.
 */

import { v4 as uuidv4 } from 'uuid';
import {
  type WsEvent,
  type WsResponse,
  encodeRequest,
  parseFrame,
} from '@/lib/protocol/ws-frame';
import { GatewayMethods, GatewayEvents } from '@/lib/protocol/protocol';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';

export interface GatewayAuth {
  token: string;
  deviceId: string;
}

export type GatewayEventListener = (event: WsEvent) => void;

interface PendingRequest {
  resolve: (res: WsResponse) => void;
  timer: ReturnType<typeof setTimeout>;
}

/* ------------------------------------------------------------------ */
/*  GatewayClient                                                      */
/* ------------------------------------------------------------------ */

export class GatewayClient {
  private _wsUrl: string;
  private _auth: GatewayAuth;
  private _ws: WebSocket | null = null;
  private _connectionState: ConnectionState = 'disconnected';
  private _connectionEpoch = 0;
  private _pending = new Map<string, PendingRequest>();
  private _eventListeners = new Set<GatewayEventListener>();
  private _stateListeners = new Set<(state: ConnectionState) => void>();
  private _reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private _reconnectAttempt = 0;
  private _handshakeTimer: ReturnType<typeof setTimeout> | null = null;
  private _openClawId: string | null = null;

  constructor(wsUrl: string, auth: GatewayAuth) {
    this._wsUrl = wsUrl;
    this._auth = auth;
  }

  get connectionState(): ConnectionState {
    return this._connectionState;
  }

  get openClawId(): string | null {
    return this._openClawId;
  }

  set openClawId(id: string | null) {
    this._openClawId = id;
  }

  updateAuth(auth: GatewayAuth): void {
    this._auth = auth;
  }

  /* ---------------------------------------------------------------- */
  /*  Subscriptions                                                    */
  /* ---------------------------------------------------------------- */

  onEvent(fn: GatewayEventListener): () => void {
    this._eventListeners.add(fn);
    return () => this._eventListeners.delete(fn);
  }

  onStateChange(fn: (state: ConnectionState) => void): () => void {
    this._stateListeners.add(fn);
    return () => this._stateListeners.delete(fn);
  }

  private _emitEvent(event: WsEvent): void {
    this._eventListeners.forEach((fn) => fn(event));
  }

  private _setConnectionState(state: ConnectionState): void {
    this._connectionState = state;
    this._stateListeners.forEach((fn) => fn(state));
  }

  /* ---------------------------------------------------------------- */
  /*  Connect / disconnect                                             */
  /* ---------------------------------------------------------------- */

  connect(): void {
    if (this._connectionState === 'connecting' || this._connectionState === 'connected') return;

    this._connectionEpoch++;
    const epoch = this._connectionEpoch;
    this._setConnectionState('connecting');

    let url = this._wsUrl;
    if (this._auth.token) url += `${url.includes('?') ? '&' : '?'}token=${encodeURIComponent(this._auth.token)}`;
    if (this._openClawId) url += `&openclaw=${encodeURIComponent(this._openClawId)}`;

    try {
      this._ws = new WebSocket(url);
    } catch {
      this._setConnectionState('error');
      this._scheduleReconnect();
      return;
    }

    // Handshake timeout (10s)
    this._handshakeTimer = setTimeout(() => {
      if (epoch === this._connectionEpoch && this._connectionState === 'connecting') {
        this._ws?.close();
        this._setConnectionState('error');
        this._scheduleReconnect();
      }
    }, 10000);

    this._ws.onmessage = (e) => {
      if (epoch !== this._connectionEpoch) return;
      this._onMessage(String(e.data));
    };

    this._ws.onclose = (e) => {
      if (epoch !== this._connectionEpoch) return;
      this._clearHandshakeTimer();
      this._setConnectionState('disconnected');
      this._failPendingCompleters('Connection closed');
      // Rate-limited (1008) uses longer backoff
      if (e.code === 1008) {
        this._scheduleReconnect(true);
      } else {
        this._scheduleReconnect();
      }
    };

    this._ws.onerror = () => {
      if (epoch !== this._connectionEpoch) return;
      this._clearHandshakeTimer();
      this._setConnectionState('error');
      this._failPendingCompleters('Connection error');
      this._scheduleReconnect();
    };
  }

  disconnect(): void {
    this._connectionEpoch++;
    this._clearReconnect();
    this._clearHandshakeTimer();
    this._failPendingCompleters('Disconnected');
    if (this._ws) {
      try {
        this._ws.close();
      } catch {
        // Ignore
      }
      this._ws = null;
    }
    this._setConnectionState('disconnected');
  }

  /* ---------------------------------------------------------------- */
  /*  Message handling                                                 */
  /* ---------------------------------------------------------------- */

  private _onMessage(raw: string): void {
    let frame;
    try {
      frame = parseFrame(raw);
    } catch {
      return;
    }

    if (frame.type === 'event') {
      const evt = frame.event;

      if (evt.event === GatewayEvents.connectChallenge) {
        this._handleChallenge(evt.payload.nonce);
        return;
      }

      // Forward known events
      const knownPrefixes = ['chat', 'agent', 'a2ui', 'canvas', 'browser', 'exec.approval', 'tick'];
      if (knownPrefixes.some((p) => evt.event.startsWith(p))) {
        this._emitEvent(evt);
      }
    } else if (frame.type === 'res') {
      const res = frame.response;
      const pending = this._pending.get(res.id);
      if (pending) {
        clearTimeout(pending.timer);
        this._pending.delete(res.id);
        pending.resolve(res);
      }

      // Check for hello-ok
      if (res.ok && res.payload?.status === 'hello-ok') {
        this._clearHandshakeTimer();
        this._reconnectAttempt = 0;
        this._setConnectionState('connected');
      }
    }
  }

  private _handleChallenge(nonce: string): void {
    this._sendConnect(nonce);
  }

  private _sendConnect(nonce: string): void {
    const params = {
      minProtocol: 3,
      maxProtocol: 3,
      client: {
        name: 'openclaw-control-ui',
        version: 'dev',
        platform: 'web',
        mode: 'webchat',
      },
      role: 'operator',
      scopes: ['operator.read', 'operator.write', 'operator.approvals'],
      capabilities: ['tool-events'],
      locale: 'en-US',
      userAgent: 'trinity-shell/0.1.0',
      auth: {
        token: this._auth.token,
        deviceId: this._auth.deviceId,
        publicKey: this._auth.deviceId,
        signature: 'nosig',
        signedAt: new Date().toISOString(),
        nonce,
      },
    };

    this.sendRequest(GatewayMethods.connect, params);
  }

  /* ---------------------------------------------------------------- */
  /*  Request / response                                               */
  /* ---------------------------------------------------------------- */

  sendRequest(method: string, params: Record<string, any> = {}): Promise<WsResponse> {
    return new Promise<WsResponse>((resolve) => {
      const id = uuidv4();
      const raw = encodeRequest({ id, method, params });

      // 30s timeout
      const timer = setTimeout(() => {
        this._pending.delete(id);
        resolve({ id, ok: false, error: { message: 'Request timed out' } });
      }, 30000);

      this._pending.set(id, { resolve, timer });

      if (this._ws?.readyState === WebSocket.OPEN) {
        this._ws.send(raw);
      } else {
        // Will fail via timeout
      }
    });
  }

  /* ---------------------------------------------------------------- */
  /*  Chat methods                                                     */
  /* ---------------------------------------------------------------- */

  sendChatMessage(
    message: string,
    options: { sessionKey?: string; idempotencyKey?: string } = {},
  ): Promise<WsResponse> {
    const idempotencyKey = options.idempotencyKey ?? uuidv4();

    // Emit local echo
    this._emitEvent({
      event: 'chat',
      payload: {
        type: 'message',
        role: 'user',
        content: message,
        localEcho: true,
        idempotencyKey,
      },
    });

    return this.sendRequest(GatewayMethods.chatSend, {
      message,
      sessionKey: options.sessionKey,
      idempotencyKey,
    });
  }

  sendChatMessageWithAttachments(
    message: string,
    options: {
      sessionKey?: string;
      attachments?: Array<{
        content: string;
        mimeType: string;
        fileName: string;
        type: string;
      }>;
    } = {},
  ): Promise<WsResponse> {
    const idempotencyKey = uuidv4();

    this._emitEvent({
      event: 'chat',
      payload: {
        type: 'message',
        role: 'user',
        content: message,
        localEcho: true,
        idempotencyKey,
        attachments: options.attachments,
      },
    });

    return this.sendRequest(GatewayMethods.chatSend, {
      message,
      sessionKey: options.sessionKey,
      idempotencyKey,
      attachments: options.attachments,
    });
  }

  getChatHistory(options: { sessionKey?: string; limit?: number } = {}): Promise<WsResponse> {
    return this.sendRequest(GatewayMethods.chatHistory, {
      sessionKey: options.sessionKey,
      limit: options.limit ?? 100,
    });
  }

  abortChat(options: { sessionKey?: string } = {}): Promise<WsResponse> {
    return this.sendRequest(GatewayMethods.chatAbort, {
      sessionKey: options.sessionKey,
    });
  }

  /* ---------------------------------------------------------------- */
  /*  Governance                                                       */
  /* ---------------------------------------------------------------- */

  resolveApproval(requestId: string, approve: boolean): Promise<WsResponse> {
    return this.sendRequest(GatewayMethods.execApprovalResolve, {
      requestId,
      approved: approve,
    });
  }

  /* ---------------------------------------------------------------- */
  /*  Session management                                               */
  /* ---------------------------------------------------------------- */

  listSessions(): Promise<WsResponse> {
    return this.sendRequest(GatewayMethods.sessionsList);
  }

  deleteSession(key: string): Promise<WsResponse> {
    return this.sendRequest(GatewayMethods.sessionsDelete, { sessionKey: key });
  }

  /* ---------------------------------------------------------------- */
  /*  Reconnection                                                     */
  /* ---------------------------------------------------------------- */

  private _scheduleReconnect(rateLimited = false): void {
    this._clearReconnect();
    const base = rateLimited ? 15000 : 1000;
    const max = rateLimited ? 60000 : 30000;
    const delay = Math.min(base * Math.pow(2, this._reconnectAttempt), max);
    this._reconnectAttempt++;
    this._reconnectTimer = setTimeout(() => this.connect(), delay);
  }

  private _clearReconnect(): void {
    if (this._reconnectTimer) {
      clearTimeout(this._reconnectTimer);
      this._reconnectTimer = null;
    }
  }

  private _clearHandshakeTimer(): void {
    if (this._handshakeTimer) {
      clearTimeout(this._handshakeTimer);
      this._handshakeTimer = null;
    }
  }

  private _failPendingCompleters(reason: string): void {
    this._pending.forEach((p) => {
      clearTimeout(p.timer);
      p.resolve({ id: '', ok: false, error: { message: reason } });
    });
    this._pending.clear();
  }

  /* ---------------------------------------------------------------- */
  /*  Browser control HTTP API                                         */
  /* ---------------------------------------------------------------- */

  private _browserApiUrl(path: string): string {
    const origin = typeof window !== 'undefined' ? window.location.origin : '';
    return `${origin}/__openclaw__/browser${path}`;
  }

  private _browserHeaders(profile?: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (this._auth.token) headers['Authorization'] = `Bearer ${this._auth.token}`;
    if (this._openClawId) headers['X-OpenClaw-Id'] = this._openClawId;
    if (profile) headers['X-Browser-Profile'] = profile;
    return headers;
  }

  async browserApiGet(path: string, profile?: string): Promise<any> {
    const res = await fetch(this._browserApiUrl(path), {
      headers: this._browserHeaders(profile),
    });
    return res.json();
  }

  async browserApiPost(path: string, body?: any, profile?: string): Promise<any> {
    const res = await fetch(this._browserApiUrl(path), {
      method: 'POST',
      headers: this._browserHeaders(profile),
      body: body ? JSON.stringify(body) : undefined,
    });
    return res.json();
  }

  async browserApiDelete(path: string, profile?: string): Promise<any> {
    const res = await fetch(this._browserApiUrl(path), {
      method: 'DELETE',
      headers: this._browserHeaders(profile),
    });
    return res.json();
  }

  browserStatus(profile?: string) { return this.browserApiGet('/status', profile); }
  browserStart(profile?: string) { return this.browserApiPost('/start', undefined, profile); }
  browserStop(profile?: string) { return this.browserApiPost('/stop', undefined, profile); }
  browserTabs(profile?: string) { return this.browserApiGet('/tabs', profile); }
  browserTabOpen(url: string, profile?: string) { return this.browserApiPost('/tabs', { url }, profile); }
  browserTabFocus(targetId: string, profile?: string) { return this.browserApiPost(`/tabs/${targetId}/focus`, undefined, profile); }
  browserTabClose(targetId: string, profile?: string) { return this.browserApiDelete(`/tabs/${targetId}`, profile); }
  browserScreenshot(profile?: string) { return this.browserApiGet('/screenshot', profile); }
  browserSnapshot(profile?: string) { return this.browserApiGet('/snapshot', profile); }
  browserNavigate(url: string, profile?: string) { return this.browserApiPost('/navigate', { url }, profile); }
  browserAct(action: any, profile?: string) { return this.browserApiPost('/act', action, profile); }
  browserResize(width: number, height: number, profile?: string) { return this.browserApiPost('/resize', { width, height }, profile); }

  /* ---------------------------------------------------------------- */
  /*  Emit synthetic event (used by canvas bridge)                     */
  /* ---------------------------------------------------------------- */

  emitCanvasEvent(event: WsEvent): void {
    this._emitEvent(event);
  }
}
