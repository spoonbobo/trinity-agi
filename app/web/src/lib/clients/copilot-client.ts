/**
 * CopilotClient — 1:1 port of core/copilot_client.dart
 *
 * Pure HTTP client for the /copilot/* REST API.
 */

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

export interface CopilotAction {
  type: string;
  label: string;
  channelId?: string;
  focus?: string;
  filter?: string;
  command?: string;
  recommended?: boolean;
}

export interface CopilotMessage {
  id: string;
  role: string;
  content: string;
  createdAt: string;
  actions: CopilotAction[];
}

export interface CopilotMessagesResponse {
  sessionId: string;
  messages: CopilotMessage[];
}

export interface CopilotModelsResponse {
  current: string;
  available: string[];
}

export interface CopilotStatus {
  workspace: string;
  desiredDefaultModel: string;
  desiredDefaultAvailable: boolean;
  actualModel: string;
  defaults: Record<string, any>;
  connectedProviders: string[];
  user: Record<string, any>;
  openclaw: Record<string, any>;
}

/* ------------------------------------------------------------------ */
/*  CopilotClient                                                      */
/* ------------------------------------------------------------------ */

export class CopilotClient {
  private _baseUrl: string;

  constructor() {
    this._baseUrl = typeof window !== 'undefined' ? window.location.origin : '';
  }

  private async _request(
    method: string,
    path: string,
    token: string,
    options?: { openclawId?: string; body?: any },
  ): Promise<any> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    if (options?.openclawId) {
      headers['X-OpenClaw-Id'] = options.openclawId;
    }

    const res = await fetch(`${this._baseUrl}${path}`, {
      method,
      headers,
      body: options?.body ? JSON.stringify(options.body) : undefined,
    });

    if (!res.ok) throw new Error(`Copilot API error: ${res.status}`);
    return res.json();
  }

  async fetchMessages(token: string, openclawId?: string): Promise<CopilotMessagesResponse> {
    const data = await this._request('GET', '/copilot/messages', token, { openclawId });
    return {
      sessionId: data.sessionId ?? '',
      messages: (data.messages ?? []).map((m: any) => ({
        id: m.id ?? '',
        role: m.role ?? 'assistant',
        content: m.content ?? '',
        createdAt: m.createdAt ?? '',
        actions: (m.actions ?? []).map((a: any) => ({
          type: a.type ?? '',
          label: a.label ?? '',
          channelId: a.channelId,
          focus: a.focus,
          filter: a.filter,
          command: a.command,
          recommended: a.recommended,
        })),
      })),
    };
  }

  async fetchStatus(token: string, openclawId?: string): Promise<CopilotStatus> {
    return this._request('GET', '/copilot/status', token, { openclawId });
  }

  async sendPrompt(token: string, message: string, openclawId?: string): Promise<any> {
    return this._request('POST', '/copilot/prompt', token, {
      openclawId,
      body: { message },
    });
  }

  async resetSession(token: string, openclawId?: string): Promise<any> {
    return this._request('POST', '/copilot/session/reset', token, { openclawId });
  }

  async fetchModels(token: string, openclawId?: string): Promise<CopilotModelsResponse> {
    const data = await this._request('GET', '/copilot/models', token, { openclawId });
    return {
      current: data.current ?? '',
      available: data.available ?? [],
    };
  }

  async setModel(token: string, model: string, openclawId?: string): Promise<any> {
    return this._request('POST', '/copilot/model', token, {
      openclawId,
      body: { model },
    });
  }
}
