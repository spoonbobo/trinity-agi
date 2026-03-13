/**
 * AuthClient — 1:1 port of core/auth_client.dart
 *
 * Manages JWT authentication, login flows, OpenClaw instance management,
 * and admin operations. Persists state to localStorage.
 */

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

export type AuthRole = 'guest' | 'user' | 'admin' | 'superadmin';

export interface OpenClawInfo {
  id: string;
  name: string;
  description?: string;
  status: string;
  ready: boolean;
  userCount: number;
}

export type OpenClawStatus = 'unknown' | 'loading' | 'ready' | 'noOpenClaws' | 'error';

export interface AuthState {
  token: string | null;
  userId: string | null;
  email: string | null;
  role: AuthRole;
  permissions: string[];
  isGuest: boolean;
  openclaws: OpenClawInfo[];
  activeOpenClawId: string | null;
  openClawStatus: OpenClawStatus;
}

export interface AuditLogResult {
  logs: any[];
  total: number;
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function parseRole(s?: string | null): AuthRole {
  switch (s) {
    case 'superadmin':
      return 'superadmin';
    case 'admin':
      return 'admin';
    case 'user':
      return 'user';
    default:
      return 'guest';
  }
}

function parseJwtExpiry(token: string): Date | null {
  try {
    const parts = token.split('.');
    if (parts.length < 2) return null;
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    if (typeof payload.exp === 'number') {
      return new Date(payload.exp * 1000);
    }
    return null;
  } catch {
    return null;
  }
}

function isExpiredToken(token: string): boolean {
  const exp = parseJwtExpiry(token);
  if (!exp) return false;
  return exp.getTime() < Date.now();
}

const STORAGE_PREFIX = 'trinity_auth_';

function storageGet(key: string): string | null {
  try {
    return localStorage.getItem(STORAGE_PREFIX + key);
  } catch {
    return null;
  }
}

function storageSet(key: string, value: string): void {
  try {
    localStorage.setItem(STORAGE_PREFIX + key, value);
  } catch {
    // Ignore storage errors
  }
}

function storageRemove(key: string): void {
  try {
    localStorage.removeItem(STORAGE_PREFIX + key);
  } catch {
    // Ignore storage errors
  }
}

/* ------------------------------------------------------------------ */
/*  AuthClient                                                         */
/* ------------------------------------------------------------------ */

export type AuthListener = (state: AuthState) => void;

export class AuthClient {
  private _state: AuthState;
  private _baseUrl: string;
  private _listeners = new Set<AuthListener>();
  private _openClawFetchSeq = 0;

  constructor(baseUrl: string) {
    this._baseUrl = baseUrl;
    this._state = {
      token: null,
      userId: null,
      email: null,
      role: 'guest',
      permissions: [],
      isGuest: true,
      openclaws: [],
      activeOpenClawId: null,
      openClawStatus: 'unknown',
    };
    this._restoreFromStorage();
  }

  get state(): AuthState {
    return this._state;
  }

  subscribe(fn: AuthListener): () => void {
    this._listeners.add(fn);
    return () => this._listeners.delete(fn);
  }

  private _notify(): void {
    this._listeners.forEach((fn) => fn(this._state));
  }

  private _setState(patch: Partial<AuthState>): void {
    this._state = { ...this._state, ...patch };
    this._notify();
  }

  /* ---------------------------------------------------------------- */
  /*  Storage                                                          */
  /* ---------------------------------------------------------------- */

  private _restoreFromStorage(): void {
    const token = storageGet('token');
    if (!token) return;
    if (isExpiredToken(token)) {
      this.logout();
      return;
    }

    const role = parseRole(storageGet('role'));
    const permissions = (() => {
      try {
        const raw = storageGet('permissions');
        return raw ? JSON.parse(raw) : [];
      } catch {
        return [];
      }
    })();

    this._state = {
      token,
      userId: storageGet('userId'),
      email: storageGet('email'),
      role,
      permissions,
      isGuest: role === 'guest',
      openclaws: [],
      activeOpenClawId: storageGet('activeOpenClawId'),
      openClawStatus: 'loading',
    };

    // Fetch openclaws in background
    if (role !== 'guest') {
      this.fetchUserOpenClaws();
    }
  }

  private _persistState(): void {
    const s = this._state;
    if (s.token) {
      storageSet('token', s.token);
      storageSet('role', s.role);
      storageSet('permissions', JSON.stringify(s.permissions));
      if (s.userId) storageSet('userId', s.userId);
      if (s.email) storageSet('email', s.email);
      if (s.activeOpenClawId) storageSet('activeOpenClawId', s.activeOpenClawId);
    }
  }

  private _clearStorage(): void {
    const keys = ['token', 'role', 'permissions', 'userId', 'email', 'activeOpenClawId'];
    keys.forEach((k) => storageRemove(k));
  }

  /* ---------------------------------------------------------------- */
  /*  Login flows                                                      */
  /* ---------------------------------------------------------------- */

  async loginWithEmail(email: string, password: string): Promise<void> {
    const res = await fetch(`${this._baseUrl}/supabase/auth/token?grant_type=password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.msg ?? body.error_description ?? 'Login failed');
    }
    const data = await res.json();
    await this._resolveSession(data.access_token);
  }

  async signUpWithEmail(email: string, password: string): Promise<void> {
    const res = await fetch(`${this._baseUrl}/supabase/auth/signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.msg ?? body.error_description ?? 'Sign up failed');
    }
  }

  async loginAsGuest(): Promise<void> {
    const res = await fetch(`${this._baseUrl}/auth/guest`, { method: 'POST' });
    if (!res.ok) {
      throw new Error('Guest login failed');
    }
    const data = await res.json();
    await this._resolveSession(data.token ?? data.access_token);
  }

  async resolveSessionFromToken(accessToken: string): Promise<void> {
    await this._resolveSession(accessToken);
  }

  private async _resolveSession(accessToken: string): Promise<void> {
    const ts = Date.now();
    const res = await fetch(`${this._baseUrl}/auth/me?ts=${ts}`, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Cache-Control': 'no-cache',
      },
    });
    if (!res.ok) throw new Error('Failed to resolve session');
    const me = await res.json();

    const role = parseRole(me.role);
    this._setState({
      token: accessToken,
      userId: me.id ?? me.userId,
      email: me.email,
      role,
      permissions: me.permissions ?? [],
      isGuest: me.isGuest === true || role === 'guest',
      openClawStatus: role === 'guest' ? 'ready' : 'loading',
    });
    this._persistState();

    if (role !== 'guest') {
      await this.fetchUserOpenClaws();
    }
  }

  logout(): void {
    this._clearStorage();
    this._state = {
      token: null,
      userId: null,
      email: null,
      role: 'guest',
      permissions: [],
      isGuest: true,
      openclaws: [],
      activeOpenClawId: null,
      openClawStatus: 'unknown',
    };
    this._notify();
  }

  hasPermission(action: string): boolean {
    return this._state.permissions.includes(action);
  }

  /* ---------------------------------------------------------------- */
  /*  OpenClaw management                                              */
  /* ---------------------------------------------------------------- */

  async fetchUserOpenClaws(): Promise<void> {
    const seq = ++this._openClawFetchSeq;
    const token = this._state.token;
    if (!token) return;

    this._setState({ openClawStatus: 'loading' });

    try {
      const res = await fetch(`${this._baseUrl}/auth/openclaws`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error('Failed to fetch openclaws');
      if (seq !== this._openClawFetchSeq) return; // stale

      const data = await res.json();
      const list: OpenClawInfo[] = (Array.isArray(data) ? data : data.openclaws ?? []).map(
        (o: any) => ({
          id: o.id,
          name: o.name ?? o.id,
          description: o.description,
          status: o.status ?? 'unknown',
          ready: o.ready === true,
          userCount: o.userCount ?? o.user_count ?? 0,
        }),
      );

      const savedId = this._state.activeOpenClawId;
      const activeId =
        (savedId && list.find((o) => o.id === savedId)?.id) ??
        list.find((o) => o.ready)?.id ??
        list[0]?.id ??
        null;

      this._setState({
        openclaws: list,
        activeOpenClawId: activeId,
        openClawStatus: list.length === 0 ? 'noOpenClaws' : 'ready',
      });
      if (activeId) storageSet('activeOpenClawId', activeId);
    } catch (err) {
      if (seq !== this._openClawFetchSeq) return;
      // Retry once after 300ms
      await new Promise((r) => setTimeout(r, 300));
      if (seq !== this._openClawFetchSeq) return;

      try {
        const res2 = await fetch(`${this._baseUrl}/auth/openclaws`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (res2.ok && seq === this._openClawFetchSeq) {
          const data = await res2.json();
          const list: OpenClawInfo[] = (Array.isArray(data) ? data : data.openclaws ?? []).map(
            (o: any) => ({
              id: o.id,
              name: o.name ?? o.id,
              description: o.description,
              status: o.status ?? 'unknown',
              ready: o.ready === true,
              userCount: o.userCount ?? o.user_count ?? 0,
            }),
          );
          const activeId = list.find((o) => o.ready)?.id ?? list[0]?.id ?? null;
          this._setState({
            openclaws: list,
            activeOpenClawId: activeId,
            openClawStatus: list.length === 0 ? 'noOpenClaws' : 'ready',
          });
        }
      } catch {
        if (seq === this._openClawFetchSeq) {
          this._setState({ openClawStatus: 'error' });
        }
      }
    }
  }

  selectOpenClaw(id: string): void {
    const found = this._state.openclaws.find((o) => o.id === id);
    if (!found) return;
    this._setState({ activeOpenClawId: id });
    storageSet('activeOpenClawId', id);
  }

  get activeOpenClaw(): OpenClawInfo | undefined {
    return this._state.openclaws.find((o) => o.id === this._state.activeOpenClawId);
  }

  /* ---------------------------------------------------------------- */
  /*  Admin APIs                                                       */
  /* ---------------------------------------------------------------- */

  private async _authedFetch(path: string, options: RequestInit = {}): Promise<Response> {
    return fetch(`${this._baseUrl}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this._state.token}`,
        ...(options.headers ?? {}),
      },
    });
  }

  async fetchUsers(): Promise<any[]> {
    const res = await this._authedFetch('/auth/users');
    if (!res.ok) throw new Error('Failed to fetch users');
    return res.json();
  }

  async assignUserRole(userId: string, role: string): Promise<void> {
    const res = await this._authedFetch(`/auth/users/${userId}/role`, {
      method: 'POST',
      body: JSON.stringify({ role }),
    });
    if (!res.ok) throw new Error('Failed to assign role');
  }

  async fetchAuditLog(params: {
    limit?: number;
    offset?: number;
    action?: string;
    userId?: string;
    resource?: string;
    ip?: string;
    from?: string;
    to?: string;
  }): Promise<AuditLogResult> {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.offset) qs.set('offset', String(params.offset));
    if (params.action) qs.set('action', params.action);
    if (params.userId) qs.set('user_id', params.userId);
    if (params.resource) qs.set('resource', params.resource);
    if (params.ip) qs.set('ip', params.ip);
    if (params.from) qs.set('from', params.from);
    if (params.to) qs.set('to', params.to);

    const res = await this._authedFetch(`/auth/users/audit?${qs}`);
    if (!res.ok) throw new Error('Failed to fetch audit log');
    const data = await res.json();
    return { logs: data.logs ?? data, total: data.total ?? 0 };
  }

  getAuditExportUrl(format: 'csv' | 'json', params: Record<string, string> = {}): string {
    const qs = new URLSearchParams({ format, ...params });
    return `${this._baseUrl}/auth/users/audit/export?${qs}`;
  }

  async fetchRolePermissionMatrix(): Promise<Record<string, string[]>> {
    const res = await this._authedFetch('/auth/users/roles/permissions');
    if (!res.ok) throw new Error('Failed to fetch role permissions');
    return res.json();
  }

  async updateRolePermissions(role: string, permissions: string[]): Promise<void> {
    const res = await this._authedFetch(`/auth/users/roles/${role}/permissions`, {
      method: 'PUT',
      body: JSON.stringify({ permissions }),
    });
    if (!res.ok) throw new Error('Failed to update role permissions');
  }

  getKeycloakLoginUrl(): string {
    return `${this._baseUrl}/supabase/auth/authorize?provider=keycloak`;
  }
}
