/**
 * TerminalProxyClient — 1:1 port of core/terminal_client.dart
 *
 * WebSocket client for the terminal proxy service.
 * Auth, command execution, env var management, interactive PTY shell.
 */

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

export type TerminalConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';

export interface TerminalOutput {
  type: 'stdout' | 'stderr' | 'system' | 'error' | 'exit';
  data?: string;
  message?: string;
  exitCode?: number;
  timestamp: number;
}

export interface EnvSyncResult {
  synced: number;
  skipped: number;
  errors: number;
  message: string;
}

export type TerminalEventListener = (output: TerminalOutput) => void;
export type ShellOutputListener = (data: string) => void;

/* ------------------------------------------------------------------ */
/*  TerminalProxyClient                                                */
/* ------------------------------------------------------------------ */

export class TerminalProxyClient {
  private _wsUrl: string;
  private _token: string;
  private _role: string;
  private _openClawId: string | null = null;
  private _ws: WebSocket | null = null;
  private _connectionState: TerminalConnectionState = 'disconnected';
  private _isAuthenticated = false;
  private _authCompleter: { resolve: () => void; reject: (e: Error) => void } | null = null;
  private _connectPromise: Promise<void> | null = null;
  private _reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private _reconnectAttempt = 0;

  // Outputs
  private _outputs: TerminalOutput[] = [];
  private _maxOutputs = 10000;
  private _outputListeners = new Set<TerminalEventListener>();
  private _stateListeners = new Set<(state: TerminalConnectionState) => void>();

  // Shell
  private _shellActive = false;
  private _shellOutputListeners = new Set<ShellOutputListener>();

  // Exec queue
  private _execQueue: Array<{
    command: string;
    resolve: (output: string) => void;
    reject: (err: Error) => void;
    timeout: number;
  }> = [];
  private _execRunning = false;

  // Env completers
  private _envListCompleter: { resolve: (v: Record<string, string>) => void; reject: (e: Error) => void } | null = null;
  private _envSetCompleter: { resolve: () => void; reject: (e: Error) => void } | null = null;
  private _envDeleteCompleter: { resolve: () => void; reject: (e: Error) => void } | null = null;
  private _envSyncCompleter: { resolve: (v: EnvSyncResult) => void; reject: (e: Error) => void } | null = null;

  constructor(wsUrl: string, token: string, role: string) {
    this._wsUrl = wsUrl;
    this._token = token;
    this._role = role;
  }

  get connectionState(): TerminalConnectionState { return this._connectionState; }
  get isAuthenticated(): boolean { return this._isAuthenticated; }
  get outputs(): TerminalOutput[] { return this._outputs; }
  get shellActive(): boolean { return this._shellActive; }

  set openClawId(id: string | null) { this._openClawId = id; }
  set token(t: string) { this._token = t; }

  /* ---------------------------------------------------------------- */
  /*  Subscriptions                                                    */
  /* ---------------------------------------------------------------- */

  onOutput(fn: TerminalEventListener): () => void {
    this._outputListeners.add(fn);
    return () => this._outputListeners.delete(fn);
  }

  onShellOutput(fn: ShellOutputListener): () => void {
    this._shellOutputListeners.add(fn);
    return () => this._shellOutputListeners.delete(fn);
  }

  onStateChange(fn: (state: TerminalConnectionState) => void): () => void {
    this._stateListeners.add(fn);
    return () => this._stateListeners.delete(fn);
  }

  private _setConnectionState(state: TerminalConnectionState): void {
    this._connectionState = state;
    this._stateListeners.forEach((fn) => fn(state));
  }

  private _addOutput(output: TerminalOutput): void {
    this._outputs.push(output);
    if (this._outputs.length > this._maxOutputs) {
      this._outputs = this._outputs.slice(-this._maxOutputs);
    }
    this._outputListeners.forEach((fn) => fn(output));
  }

  /* ---------------------------------------------------------------- */
  /*  Connect / disconnect                                             */
  /* ---------------------------------------------------------------- */

  connect(): Promise<void> {
    if (this._connectPromise) return this._connectPromise;
    if (this._connectionState === 'connected') return Promise.resolve();

    this._setConnectionState('connecting');

    this._connectPromise = new Promise<void>((resolve, reject) => {
      try {
        this._ws = new WebSocket(this._wsUrl);
      } catch {
        this._setConnectionState('error');
        this._connectPromise = null;
        reject(new Error('Failed to create WebSocket'));
        return;
      }

      this._ws.onopen = () => {
        // Send auth message
        this._send({
          type: 'auth',
          jwt: this._token,
          role: this._role,
          openclawId: this._openClawId,
        });

        // Wait for auth response (10s timeout)
        const timer = setTimeout(() => {
          if (!this._isAuthenticated) {
            this._authCompleter?.reject(new Error('Auth timeout'));
            this._authCompleter = null;
            this._connectPromise = null;
            this._ws?.close();
          }
        }, 10000);

        this._authCompleter = {
          resolve: () => {
            clearTimeout(timer);
            this._isAuthenticated = true;
            this._setConnectionState('connected');
            this._reconnectAttempt = 0;
            this._connectPromise = null;
            resolve();
          },
          reject: (e: Error) => {
            clearTimeout(timer);
            this._connectPromise = null;
            reject(e);
          },
        };
      };

      this._ws.onmessage = (e) => this._onMessage(String(e.data));

      this._ws.onclose = () => {
        this._isAuthenticated = false;
        this._shellActive = false;
        this._setConnectionState('disconnected');
        this._connectPromise = null;
        this._scheduleReconnect();
      };

      this._ws.onerror = () => {
        this._setConnectionState('error');
        this._connectPromise = null;
        reject(new Error('WebSocket error'));
      };
    });

    return this._connectPromise;
  }

  disconnect(): void {
    this._clearReconnect();
    this._connectPromise = null;
    if (this._ws) {
      try {
        this._ws.close();
      } catch {
        // Ignore
      }
      this._ws = null;
    }
    this._isAuthenticated = false;
    this._shellActive = false;
    this._setConnectionState('disconnected');
  }

  private _send(data: any): void {
    if (this._ws?.readyState === WebSocket.OPEN) {
      this._ws.send(JSON.stringify(data));
    }
  }

  /* ---------------------------------------------------------------- */
  /*  Message handling                                                 */
  /* ---------------------------------------------------------------- */

  private _onMessage(raw: string): void {
    let msg: any;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }

    switch (msg.type) {
      case 'auth':
        this._authCompleter?.resolve();
        this._authCompleter = null;
        break;

      case 'stdout':
      case 'stderr':
      case 'system':
        this._addOutput({ type: msg.type, data: msg.data ?? msg.message, timestamp: Date.now() });
        break;

      case 'error':
        this._addOutput({ type: 'error', message: msg.message ?? msg.error, timestamp: Date.now() });
        this._envSetCompleter?.reject(new Error(msg.message));
        this._envSetCompleter = null;
        this._envDeleteCompleter?.reject(new Error(msg.message));
        this._envDeleteCompleter = null;
        break;

      case 'exit':
        this._addOutput({ type: 'exit', exitCode: msg.exitCode ?? msg.code, timestamp: Date.now() });
        this._execRunning = false;
        this._processExecQueue();
        break;

      case 'pong':
        break;

      case 'env_list':
        this._envListCompleter?.resolve(msg.vars ?? {});
        this._envListCompleter = null;
        break;

      case 'env_set':
        if (msg.status === 'ok') this._envSetCompleter?.resolve();
        else this._envSetCompleter?.reject(new Error(msg.error ?? 'Failed'));
        this._envSetCompleter = null;
        break;

      case 'env_delete':
        if (msg.status === 'ok') this._envDeleteCompleter?.resolve();
        else this._envDeleteCompleter?.reject(new Error(msg.error ?? 'Failed'));
        this._envDeleteCompleter = null;
        break;

      case 'env_sync_gateway':
        this._envSyncCompleter?.resolve({
          synced: msg.synced ?? 0,
          skipped: msg.skipped ?? 0,
          errors: msg.errors ?? 0,
          message: msg.message ?? '',
        });
        this._envSyncCompleter = null;
        break;

      case 'shell_started':
        this._shellActive = true;
        break;

      case 'shell_output':
        this._shellOutputListeners.forEach((fn) => fn(msg.data ?? ''));
        break;

      case 'shell_closed':
        this._shellActive = false;
        break;
    }
  }

  /* ---------------------------------------------------------------- */
  /*  Command execution                                                */
  /* ---------------------------------------------------------------- */

  executeCommand(command: string): void {
    this._send({ type: 'exec', command });
  }

  executeCommandForOutput(command: string, timeout = 30000): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      this._execQueue.push({ command, resolve, reject, timeout });
      this._processExecQueue();
    });
  }

  private _processExecQueue(): void {
    if (this._execRunning || this._execQueue.length === 0) return;
    const next = this._execQueue.shift()!;
    this._execRunning = true;

    const startIdx = this._outputs.length;
    this.executeCommand(next.command);

    const timer = setTimeout(() => {
      this._execRunning = false;
      next.resolve(this._collectOutput(startIdx));
      this._processExecQueue();
    }, next.timeout);

    // Watch for exit event
    const unsub = this.onOutput((output) => {
      if (output.type === 'exit') {
        clearTimeout(timer);
        unsub();
        // Give a small delay for final output
        setTimeout(() => {
          next.resolve(this._collectOutput(startIdx));
        }, 50);
      }
    });
  }

  private _collectOutput(fromIdx: number): string {
    return this._outputs
      .slice(fromIdx)
      .filter((o) => o.type === 'stdout' || o.type === 'stderr')
      .map((o) => o.data ?? o.message ?? '')
      .join('\n');
  }

  cancelCommand(): void {
    this._send({ type: 'cancel' });
  }

  /* ---------------------------------------------------------------- */
  /*  Env var management                                               */
  /* ---------------------------------------------------------------- */

  listEnvVars(): Promise<Record<string, string>> {
    return new Promise((resolve, reject) => {
      this._envListCompleter = { resolve, reject };
      this._send({ type: 'env_list' });
      setTimeout(() => {
        if (this._envListCompleter) {
          this._envListCompleter.reject(new Error('Timeout'));
          this._envListCompleter = null;
        }
      }, 5000);
    });
  }

  setEnvVar(key: string, value: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this._envSetCompleter = { resolve, reject };
      this._send({ type: 'env_set', key, value });
      setTimeout(() => {
        if (this._envSetCompleter) {
          this._envSetCompleter.reject(new Error('Timeout'));
          this._envSetCompleter = null;
        }
      }, 5000);
    });
  }

  deleteEnvVar(key: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this._envDeleteCompleter = { resolve, reject };
      this._send({ type: 'env_delete', key });
      setTimeout(() => {
        if (this._envDeleteCompleter) {
          this._envDeleteCompleter.reject(new Error('Timeout'));
          this._envDeleteCompleter = null;
        }
      }, 5000);
    });
  }

  syncEnvToGateway(): Promise<EnvSyncResult> {
    return new Promise((resolve, reject) => {
      this._envSyncCompleter = { resolve, reject };
      this._send({ type: 'env_sync_gateway' });
      setTimeout(() => {
        if (this._envSyncCompleter) {
          this._envSyncCompleter.reject(new Error('Timeout'));
          this._envSyncCompleter = null;
        }
      }, 30000);
    });
  }

  /* ---------------------------------------------------------------- */
  /*  Interactive PTY shell                                            */
  /* ---------------------------------------------------------------- */

  startShell(cols: number, rows: number): void {
    this._send({ type: 'shell_start', cols, rows });
  }

  shellInput(data: string): void {
    this._send({ type: 'shell_input', data });
  }

  shellResize(cols: number, rows: number): void {
    this._send({ type: 'shell_resize', cols, rows });
  }

  closeShell(): void {
    this._send({ type: 'shell_close' });
  }

  /* ---------------------------------------------------------------- */
  /*  Reconnection                                                     */
  /* ---------------------------------------------------------------- */

  private _scheduleReconnect(): void {
    this._clearReconnect();
    const delay = Math.min(1000 * Math.pow(2, this._reconnectAttempt), 30000);
    this._reconnectAttempt++;
    this._reconnectTimer = setTimeout(() => this.connect(), delay);
  }

  private _clearReconnect(): void {
    if (this._reconnectTimer) {
      clearTimeout(this._reconnectTimer);
      this._reconnectTimer = null;
    }
  }
}
