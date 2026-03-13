'use client';

import { useState, useEffect, useCallback } from 'react';
import { Plus, X, MessageCircle, MessageSquare, Loader2 } from 'lucide-react';
import { v4 as uuidv4 } from 'uuid';
import { useGatewayStore } from '@/lib/stores/gateway-store';
import { useSessionStore } from '@/lib/stores/session-store';
import { useThemeStore } from '@/lib/stores/theme-store';
import { tr } from '@/lib/i18n/translations';

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

/** Strip the `agent:<agentId>:` prefix that OpenClaw stores internally. */
function normalizeKey(key: string): string {
  return key.replace(/^agent:[^:]+:/, '');
}

interface SessionEntry {
  key: string;
  updatedAt: number;
}

/* ------------------------------------------------------------------ */
/*  SessionDrawer                                                      */
/* ------------------------------------------------------------------ */

export function SessionDrawer() {
  const language = useThemeStore((s) => s.language);
  const gatewayClient = useGatewayStore((s) => s.client);
  const activeSession = useSessionStore((s) => s.activeSession);
  const setActiveSession = useSessionStore((s) => s.setActiveSession);
  const incrementRefreshTick = useSessionStore((s) => s.incrementRefreshTick);

  const [sessionKeys, setSessionKeys] = useState<string[]>(['main']);
  const [loading, setLoading] = useState(false);

  /* ---------------------------------------------------------------- */
  /*  Fetch sessions from gateway                                      */
  /* ---------------------------------------------------------------- */

  const fetchSessions = useCallback(async () => {
    setLoading(true);
    try {
      const response = await gatewayClient.listSessions();
      if (response.ok && response.payload) {
        const sessions = response.payload.sessions;
        if (Array.isArray(sessions)) {
          const entries: SessionEntry[] = [];
          for (const s of sessions) {
            if (typeof s === 'object' && s !== null) {
              const raw = (s.key as string) ?? (s.id as string) ?? '';
              const updatedAt = (s.updatedAt as number) ?? 0;
              if (raw) {
                entries.push({ key: normalizeKey(raw), updatedAt });
              }
            } else if (typeof s === 'string' && s) {
              entries.push({ key: normalizeKey(s), updatedAt: 0 });
            }
          }

          // Sort newest first
          entries.sort((a, b) => b.updatedAt - a.updatedAt);

          // Build key list: main pinned at top
          const keys: string[] = ['main'];
          for (const e of entries) {
            if (e.key !== 'main' && !keys.includes(e.key)) {
              keys.push(e.key);
            }
          }

          // Keep active session even if server doesn't know it yet
          if (!keys.includes(activeSession)) {
            keys.splice(1, 0, activeSession);
          }

          setSessionKeys(keys);
        }
      }
    } catch {
      // Silently fail — sessions will show only 'main'
    }
    setLoading(false);
  }, [gatewayClient, activeSession]);

  useEffect(() => {
    fetchSessions();
  }, [fetchSessions]);

  /* ---------------------------------------------------------------- */
  /*  Create new session                                               */
  /* ---------------------------------------------------------------- */

  const createNewSession = useCallback(() => {
    const key = `session-${uuidv4().substring(0, 8)}`;
    setSessionKeys((prev) => {
      const idx = prev.indexOf('main');
      const next = [...prev];
      next.splice(idx + 1, 0, key);
      return next;
    });
    setActiveSession(key);
    incrementRefreshTick();
  }, [setActiveSession, incrementRefreshTick]);

  /* ---------------------------------------------------------------- */
  /*  Select session                                                   */
  /* ---------------------------------------------------------------- */

  const selectSession = useCallback(
    (key: string) => {
      setActiveSession(key);
      incrementRefreshTick();
    },
    [setActiveSession, incrementRefreshTick],
  );

  /* ---------------------------------------------------------------- */
  /*  Delete session                                                   */
  /* ---------------------------------------------------------------- */

  const deleteSession = useCallback(
    (key: string) => {
      if (key === 'main') return;
      setSessionKeys((prev) => prev.filter((k) => k !== key));
      if (activeSession === key) {
        setActiveSession('main');
        incrementRefreshTick();
      }
      gatewayClient.deleteSession(key).catch(() => {});
    },
    [activeSession, setActiveSession, incrementRefreshTick, gatewayClient],
  );

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  return (
    <div
      className="flex shrink-0 flex-col border-r bg-surface-base"
      style={{ width: 240, borderColor: 'var(--border)', borderRightWidth: '0.5px' }}
    >
      {/* Header (28px) */}
      <div
        className="flex h-7 shrink-0 items-center px-3"
        style={{ borderBottom: '0.5px solid var(--border)' }}
      >
        <span className="font-mono text-[11px] text-fg-muted">
          {tr(language, 'sessions')}
        </span>
        <div className="flex-1" />
        <button
          onClick={createNewSession}
          className="cursor-pointer text-fg-muted hover:text-fg-secondary"
        >
          <Plus size={14} />
        </button>
      </div>

      {/* Session list */}
      <div className="flex-1 overflow-y-auto py-1">
        {loading ? (
          <div className="flex h-full items-center justify-center">
            <Loader2 size={16} className="animate-spin text-accent-primary" />
          </div>
        ) : (
          sessionKeys.map((key) => (
            <SessionItem
              key={key}
              name={key}
              isActive={key === activeSession}
              canDelete={key !== 'main'}
              onSelect={() => selectSession(key)}
              onDelete={() => deleteSession(key)}
            />
          ))
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  SessionItem                                                        */
/* ------------------------------------------------------------------ */

interface SessionItemProps {
  name: string;
  isActive: boolean;
  canDelete: boolean;
  onSelect: () => void;
  onDelete: () => void;
}

function SessionItem({ name, isActive, canDelete, onSelect, onDelete }: SessionItemProps) {
  const [hovering, setHovering] = useState(false);

  return (
    <div
      className="flex h-8 cursor-pointer items-center px-3"
      style={{
        background: isActive
          ? 'color-mix(in srgb, var(--accent-primary) 8%, transparent)'
          : hovering
            ? 'var(--surface-card)'
            : 'transparent',
      }}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      onClick={onSelect}
    >
      {isActive ? (
        <MessageSquare size={12} className="shrink-0 text-accent-primary" />
      ) : (
        <MessageCircle size={12} className="shrink-0 text-fg-muted" />
      )}
      <span
        className="ml-2 min-w-0 flex-1 truncate font-mono text-[11px]"
        style={{ color: isActive ? 'var(--accent-primary)' : 'var(--fg-secondary)' }}
      >
        {name}
      </span>
      {canDelete && hovering && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onDelete();
          }}
          className="shrink-0 text-fg-muted hover:text-fg-secondary"
        >
          <X size={12} />
        </button>
      )}
    </div>
  );
}
