'use client';

/**
 * BrowserRenderer — 1:1 port of features/canvas/browser_renderer.dart (1183 lines)
 *                  + browser_provider.dart (653 lines)
 *
 * Chrome-style managed browser viewport:
 * - Toolbar: back/forward/refresh + editable URL bar with lock icon
 * - Tab strip: horizontal scrollable tabs with close + new
 * - Viewport: screenshot image with zoom, loading/error overlays
 * - Status bar: run state, profile, tab count, auto-refresh toggle
 * - State: start/stop, screenshot polling (2s), tabs, navigate, interactive actions
 * - State screens: start, spinner, error with retry
 */

import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react';
import {
  ArrowLeft,
  ArrowRight,
  Globe,
  Loader2,
  Lock,
  Plus,
  RefreshCw,
  RotateCcw,
  X,
  AlertCircle,
} from 'lucide-react';
import { useGatewayStore } from '@/lib/stores/gateway-store';

/* ------------------------------------------------------------------ */
/*  Browser state types                                                */
/* ------------------------------------------------------------------ */

interface BrowserTab {
  targetId: string;
  title: string;
  url: string;
  type: string;
  active: boolean;
}

interface SnapshotRef {
  ref: string;
  role: string;
  name: string;
}

type BrowserRunState = 'unknown' | 'stopped' | 'starting' | 'running' | 'error';

interface BrowserState {
  runState: BrowserRunState;
  tabs: BrowserTab[];
  activeTabId: string | null;
  currentUrl: string | null;
  pageTitle: string | null;
  screenshotUrl: string | null;
  snapshotText: string | null;
  snapshotRefs: SnapshotRef[];
  autoRefresh: boolean;
  error: string | null;
  screenshotError: string | null;
  isLoading: boolean;
  profile: string;
}

const INITIAL_STATE: BrowserState = {
  runState: 'unknown',
  tabs: [],
  activeTabId: null,
  currentUrl: null,
  pageTitle: null,
  screenshotUrl: null,
  snapshotText: null,
  snapshotRefs: [],
  autoRefresh: true,
  error: null,
  screenshotError: null,
  isLoading: false,
  profile: 'openclaw',
};

/* ------------------------------------------------------------------ */
/*  Humanize error helper                                              */
/* ------------------------------------------------------------------ */

function humanizeError(e: any): string {
  const raw = String(e);
  const lower = raw.toLowerCase();
  if (lower.includes('401') || lower.includes('403') || lower.includes('unauthorized'))
    return 'Browser auth failed. Please re-open the session and try again.';
  if (lower.includes('top-level targets'))
    return 'Browser target was not a top-level page. Re-sync tabs and try again.';
  if (lower.includes('network') || lower.includes('failed to fetch'))
    return 'Browser network request failed. Please retry.';
  return raw.length > 200 ? raw.slice(0, 200) + '...' : raw;
}

/* ------------------------------------------------------------------ */
/*  BrowserRenderer                                                    */
/* ------------------------------------------------------------------ */

export default function BrowserRenderer() {
  const client = useGatewayStore((s) => s.client);
  const [state, setState] = useState<BrowserState>(INITIAL_STATE);
  const stateRef = useRef(state);
  stateRef.current = state;

  const [urlEditing, setUrlEditing] = useState(false);
  const [urlText, setUrlText] = useState('');
  const urlInputRef = useRef<HTMLInputElement>(null);

  const [showSnapshot, setShowSnapshot] = useState(false);
  const [showActions, setShowActions] = useState(false);

  const pollTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (pollTimer.current) clearInterval(pollTimer.current);
    };
  }, []);

  /* ---------------------------------------------------------------- */
  /*  State updater                                                    */
  /* ---------------------------------------------------------------- */

  const patch = useCallback(
    (partial: Partial<BrowserState>) => {
      if (!mountedRef.current) return;
      setState((prev) => ({ ...prev, ...partial }));
    },
    [],
  );

  /* ---------------------------------------------------------------- */
  /*  Browser API wrappers                                             */
  /* ---------------------------------------------------------------- */

  const refreshTabs = useCallback(async () => {
    try {
      const result = await client.browserTabs(stateRef.current.profile);
      if (!mountedRef.current) return;
      const rawTabs = (result?.tabs as any[]) ?? [];
      const parsed: BrowserTab[] = rawTabs
        .filter((t: any) => t && typeof t === 'object')
        .map((t: any) => ({
          targetId: t.targetId ?? t.id ?? '',
          title: t.title ?? 'Untitled',
          url: t.url ?? '',
          type: t.type ?? 'page',
          active: t.active ?? false,
        }));
      const tabs = parsed.filter((t) => t.type === 'page');
      const activeTab =
        tabs.find((t) => t.active) ?? (tabs.length > 0 ? tabs[0] : null);
      patch({
        tabs,
        activeTabId: activeTab?.targetId ?? null,
        currentUrl: activeTab?.url || stateRef.current.currentUrl,
        pageTitle: activeTab?.title || stateRef.current.pageTitle,
      });
    } catch (e) {
      if (!mountedRef.current) return;
      console.warn('[Browser] tabs error:', e);
    }
  }, [client, patch]);

  const refreshScreenshot = useCallback(async () => {
    if (!mountedRef.current) return;
    try {
      const result = await client.browserScreenshot(stateRef.current.profile);
      if (!mountedRef.current) return;
      const screenshotPath = result?.path as string;
      if (!screenshotPath) return;

      const filename = screenshotPath.split('/').pop();
      const origin = typeof window !== 'undefined' ? window.location.origin : '';
      const imageUrl = `${origin}/__openclaw__/browser-media/${filename}`;

      patch({
        screenshotUrl: `${imageUrl}?t=${Date.now()}`,
        screenshotError: null,
        error: null,
      });
    } catch (e) {
      if (!mountedRef.current) return;
      console.warn('[Browser] screenshot error:', e);
      patch({ screenshotError: humanizeError(e) });
    }
  }, [client, patch]);

  const refreshSnapshot = useCallback(async (): Promise<number> => {
    try {
      const result = await client.browserSnapshot(stateRef.current.profile);
      if (!mountedRef.current) return 0;
      const text = result?.snapshot ?? result?.content ?? result?.text ?? '';
      const refsObj = result?.refs;
      const refs: SnapshotRef[] = [];
      if (refsObj && typeof refsObj === 'object') {
        for (const [key, value] of Object.entries(refsObj as Record<string, any>)) {
          if (value && typeof value === 'object') {
            refs.push({
              ref: key,
              role: value.role ?? '',
              name: value.name ?? '',
            });
          }
        }
      }
      refs.sort((a, b) => a.ref.localeCompare(b.ref));
      patch({ snapshotText: text, snapshotRefs: refs, error: null });
      return refs.length;
    } catch (e) {
      if (!mountedRef.current) return -1;
      patch({ error: humanizeError(e) });
      return -1;
    }
  }, [client, patch]);

  /* ---------------------------------------------------------------- */
  /*  Polling                                                          */
  /* ---------------------------------------------------------------- */

  const startPolling = useCallback(() => {
    if (pollTimer.current) clearInterval(pollTimer.current);
    patch({ autoRefresh: true });
    pollTimer.current = setInterval(() => {
      if (
        mountedRef.current &&
        stateRef.current.autoRefresh &&
        stateRef.current.runState === 'running'
      ) {
        refreshScreenshot();
      }
    }, 2000);
  }, [patch, refreshScreenshot]);

  const stopPolling = useCallback(() => {
    if (pollTimer.current) clearInterval(pollTimer.current);
    pollTimer.current = null;
    patch({ autoRefresh: false });
  }, [patch]);

  const toggleAutoRefresh = useCallback(() => {
    if (stateRef.current.autoRefresh) {
      stopPolling();
    } else {
      startPolling();
    }
  }, [startPolling, stopPolling]);

  /* ---------------------------------------------------------------- */
  /*  Browser lifecycle                                                */
  /* ---------------------------------------------------------------- */

  const refreshStatus = useCallback(async () => {
    try {
      const result = await client.browserStatus(stateRef.current.profile);
      if (!mountedRef.current) return;
      const running =
        result?.running === true ||
        result?.status === 'running' ||
        result?.status === 'connected';
      patch({
        runState: running ? 'running' : 'stopped',
        error: null,
      });
      if (running) {
        await Promise.all([refreshTabs(), refreshScreenshot()]);
        if (stateRef.current.autoRefresh && !pollTimer.current) startPolling();
      }
    } catch (e) {
      if (!mountedRef.current) return;
      patch({ runState: 'error', error: humanizeError(e) });
    }
  }, [client, patch, refreshTabs, refreshScreenshot, startPolling]);

  const startBrowser = useCallback(async () => {
    patch({ runState: 'starting', isLoading: true, error: null });
    try {
      await client.browserStart(stateRef.current.profile);
      if (!mountedRef.current) return;
      await new Promise((r) => setTimeout(r, 1500));
      if (!mountedRef.current) return;
      patch({ runState: 'running', isLoading: false });
      await Promise.all([refreshTabs(), refreshScreenshot()]);
      startPolling();
    } catch (e) {
      if (!mountedRef.current) return;
      patch({
        runState: 'error',
        isLoading: false,
        error: humanizeError(e),
      });
    }
  }, [client, patch, refreshTabs, refreshScreenshot, startPolling]);

  const stopBrowser = useCallback(async () => {
    stopPolling();
    patch({ isLoading: true });
    try {
      await client.browserStop(stateRef.current.profile);
      if (!mountedRef.current) return;
      patch({
        runState: 'stopped',
        isLoading: false,
        tabs: [],
        screenshotUrl: null,
        snapshotText: null,
        snapshotRefs: [],
        currentUrl: null,
        pageTitle: null,
        activeTabId: null,
      });
    } catch (e) {
      if (!mountedRef.current) return;
      patch({ isLoading: false, error: humanizeError(e) });
    }
  }, [client, patch, stopPolling]);

  const manualRefresh = useCallback(async () => {
    patch({ isLoading: true });
    await Promise.all([refreshTabs(), refreshScreenshot()]);
    if (mountedRef.current) patch({ isLoading: false });
  }, [patch, refreshTabs, refreshScreenshot]);

  const navigate = useCallback(
    async (url: string) => {
      patch({ isLoading: true });
      try {
        const normalized = url.includes('://') ? url : `https://${url}`;
        await client.browserNavigate(normalized, stateRef.current.profile);
        if (!mountedRef.current) return;
        patch({ currentUrl: normalized, isLoading: false });
        await new Promise((r) => setTimeout(r, 800));
        if (mountedRef.current)
          await Promise.all([refreshTabs(), refreshScreenshot()]);
      } catch (e) {
        if (!mountedRef.current) return;
        patch({ isLoading: false, error: humanizeError(e) });
      }
    },
    [client, patch, refreshTabs, refreshScreenshot],
  );

  const clickRef = useCallback(
    async (ref: string) => {
      try {
        await client.browserAct({ kind: 'click', ref }, stateRef.current.profile);
        await new Promise((r) => setTimeout(r, 500));
        if (mountedRef.current)
          await Promise.all([refreshTabs(), refreshScreenshot()]);
      } catch (e) {
        if (!mountedRef.current) return;
        patch({ error: humanizeError(e) });
      }
    },
    [client, patch, refreshTabs, refreshScreenshot],
  );

  const typeText = useCallback(
    async (ref: string, text: string) => {
      try {
        await client.browserAct(
          { kind: 'type', ref, text },
          stateRef.current.profile,
        );
        await new Promise((r) => setTimeout(r, 300));
        if (mountedRef.current) await refreshScreenshot();
      } catch (e) {
        console.warn('[Browser] type error:', e);
      }
    },
    [client, refreshScreenshot],
  );

  const pressKey = useCallback(
    async (key: string) => {
      try {
        await client.browserAct(
          { kind: 'press', text: key },
          stateRef.current.profile,
        );
        await new Promise((r) => setTimeout(r, 300));
        if (mountedRef.current) await refreshScreenshot();
      } catch (e) {
        console.warn('[Browser] press error:', e);
      }
    },
    [client, refreshScreenshot],
  );

  const goBack = useCallback(async () => {
    await pressKey('Alt+ArrowLeft');
    await new Promise((r) => setTimeout(r, 500));
    if (mountedRef.current) await Promise.all([refreshTabs(), refreshScreenshot()]);
  }, [pressKey, refreshTabs, refreshScreenshot]);

  const goForward = useCallback(async () => {
    await pressKey('Alt+ArrowRight');
    await new Promise((r) => setTimeout(r, 500));
    if (mountedRef.current) await Promise.all([refreshTabs(), refreshScreenshot()]);
  }, [pressKey, refreshTabs, refreshScreenshot]);

  const focusTab = useCallback(
    async (targetId: string) => {
      try {
        await client.browserTabFocus(targetId, stateRef.current.profile);
        if (!mountedRef.current) return;
        patch({ activeTabId: targetId });
        await refreshTabs();
        await refreshScreenshot();
      } catch (e) {
        console.warn('[Browser] focusTab error:', e);
      }
    },
    [client, patch, refreshTabs, refreshScreenshot],
  );

  const closeTab = useCallback(
    async (targetId: string) => {
      try {
        await client.browserTabClose(targetId, stateRef.current.profile);
        if (!mountedRef.current) return;
        await refreshTabs();
        await refreshScreenshot();
      } catch (e) {
        console.warn('[Browser] closeTab error:', e);
      }
    },
    [client, refreshTabs, refreshScreenshot],
  );

  const openTab = useCallback(
    async (url = 'about:blank') => {
      try {
        await client.browserTabOpen(url, stateRef.current.profile);
        if (!mountedRef.current) return;
        await refreshTabs();
        await refreshScreenshot();
      } catch (e) {
        console.warn('[Browser] openTab error:', e);
      }
    },
    [client, refreshTabs, refreshScreenshot],
  );

  /* ---------------------------------------------------------------- */
  /*  Initial status check                                             */
  /* ---------------------------------------------------------------- */

  const didInit = useRef(false);
  useEffect(() => {
    if (!didInit.current) {
      didInit.current = true;
      refreshStatus();
    }
  }, [refreshStatus]);

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  const displayUrl = (url: string) =>
    url.replace(/^https?:\/\//, '');

  return (
    <div className="flex h-full w-full flex-col" style={{ background: 'var(--surface-base)' }}>
      {/* ── Chrome toolbar ─────────────────────────────────────── */}
      <div
        className="flex h-8 shrink-0 items-center gap-1 px-1.5"
        style={{
          background: 'var(--surface-card)',
          borderBottom: '0.5px solid var(--border)',
        }}
      >
        <NavButton icon={<ArrowLeft size={14} />} tooltip="Back" onClick={goBack} />
        <NavButton icon={<ArrowRight size={14} />} tooltip="Forward" onClick={goForward} />
        <NavButton
          icon={
            state.isLoading ? (
              <X size={14} />
            ) : (
              <RefreshCw size={14} />
            )
          }
          tooltip={state.isLoading ? 'Stop' : 'Refresh'}
          onClick={manualRefresh}
        />
        <div className="mx-1 flex-1">
          {urlEditing ? (
            <input
              ref={urlInputRef}
              autoFocus
              value={urlText}
              onChange={(e) => setUrlText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && urlText.trim()) {
                  navigate(urlText.trim());
                  setUrlEditing(false);
                }
                if (e.key === 'Escape') setUrlEditing(false);
              }}
              onBlur={() => setUrlEditing(false)}
              className="h-[22px] w-full rounded-sm px-2 text-[11px] outline-none"
              style={{
                background: 'var(--surface-base)',
                border: '0.5px solid color-mix(in srgb, var(--accent-primary) 50%, transparent)',
                color: 'var(--fg-primary)',
              }}
            />
          ) : (
            <div
              onClick={() => {
                setUrlEditing(true);
                setUrlText(state.currentUrl ?? '');
              }}
              className="flex h-[22px] cursor-text items-center rounded-sm px-2"
              style={{
                background: 'var(--surface-base)',
                border: '0.5px solid var(--border)',
              }}
            >
              {state.currentUrl?.startsWith('https://') && (
                <Lock
                  size={10}
                  className="mr-1 shrink-0"
                  style={{ color: 'var(--accent-primary)' }}
                />
              )}
              <span
                className="truncate text-[11px]"
                style={{ color: 'var(--fg-secondary)' }}
              >
                {displayUrl(state.currentUrl ?? '')}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* ── Tab strip ──────────────────────────────────────────── */}
      {state.runState === 'running' && state.tabs.length > 0 && (
        <div
          className="flex h-[26px] shrink-0 items-center"
          style={{
            background: 'var(--surface-card)',
            borderBottom: '0.5px solid var(--border)',
          }}
        >
          <div className="flex flex-1 items-center gap-0.5 overflow-x-auto px-1">
            {state.tabs.map((tab) => (
              <TabChip
                key={tab.targetId}
                tab={tab}
                isActive={tab.targetId === state.activeTabId}
                onTap={() => focusTab(tab.targetId)}
                onClose={() => closeTab(tab.targetId)}
              />
            ))}
          </div>
          <button
            onClick={() => openTab()}
            className="mr-1 cursor-pointer"
          >
            <Plus size={14} style={{ color: 'var(--fg-muted)' }} />
          </button>
        </div>
      )}

      {/* ── Main viewport ──────────────────────────────────────── */}
      <div className="relative flex-1 overflow-hidden">
        {(state.runState === 'unknown' || state.runState === 'stopped') && (
          <StartScreen onStart={startBrowser} error={state.error} />
        )}

        {state.runState === 'starting' && (
          <div className="flex h-full flex-col items-center justify-center gap-3">
            <Loader2
              size={20}
              className="animate-spin"
              style={{ color: 'var(--accent-primary)' }}
            />
            <span className="text-[11px]" style={{ color: 'var(--fg-muted)' }}>
              starting browser...
            </span>
          </div>
        )}

        {state.runState === 'error' && (
          <ErrorScreen
            error={state.error ?? 'Unknown error'}
            onRetry={refreshStatus}
          />
        )}

        {state.runState === 'running' && !state.screenshotUrl && (
          <div className="flex h-full flex-col items-center justify-center gap-2">
            <Globe size={24} style={{ color: 'var(--fg-muted)' }} />
            <span className="text-[11px]" style={{ color: 'var(--fg-muted)' }}>
              waiting for screenshot...
            </span>
            <button
              onClick={manualRefresh}
              className="cursor-pointer rounded-sm px-3 py-1.5 text-[10px]"
              style={{
                border: '0.5px solid var(--border)',
                color: 'var(--accent-primary)',
              }}
            >
              refresh
            </button>
          </div>
        )}

        {state.runState === 'running' && state.screenshotUrl && (
          <>
            {/* Screenshot with zoom */}
            <div className="h-full w-full overflow-auto">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={state.screenshotUrl}
                alt="Browser screenshot"
                className="h-full w-full object-contain"
                draggable={false}
              />
            </div>

            {/* Loading indicator */}
            {state.isLoading && (
              <div className="absolute right-1 top-1">
                <Loader2
                  size={14}
                  className="animate-spin"
                  style={{ color: 'var(--accent-primary)', opacity: 0.5 }}
                />
              </div>
            )}

            {/* Screenshot error banner */}
            {state.screenshotError && (
              <div
                className="absolute left-2 right-2 top-2 rounded-sm px-2 py-1.5"
                style={{
                  background: 'color-mix(in srgb, var(--status-error) 12%, transparent)',
                  border: '0.5px solid color-mix(in srgb, var(--status-error) 35%, transparent)',
                }}
              >
                <span
                  className="line-clamp-2 text-[10px]"
                  style={{ color: 'var(--status-error)' }}
                >
                  {state.screenshotError}
                </span>
              </div>
            )}

            {/* Snapshot text overlay */}
            {showSnapshot && state.snapshotText && (
              <div
                className="absolute inset-0 overflow-auto p-2"
                style={{
                  background: 'color-mix(in srgb, var(--surface-base) 85%, transparent)',
                }}
              >
                <pre
                  className="whitespace-pre-wrap font-mono text-[10px] leading-relaxed select-text"
                  style={{ color: 'var(--fg-secondary)' }}
                >
                  {state.snapshotText}
                </pre>
              </div>
            )}
          </>
        )}
      </div>

      {/* ── Actions panel ──────────────────────────────────────── */}
      {showActions && state.runState === 'running' && (
        <ActionPanel
          state={state}
          onRefreshRefs={refreshSnapshot}
          onClickRef={clickRef}
          onTypeText={typeText}
          onPressKey={pressKey}
        />
      )}

      {/* ── Status bar ─────────────────────────────────────────── */}
      <StatusBar
        state={state}
        showSnapshot={showSnapshot}
        showActions={showActions}
        onToggleSnapshot={() => {
          setShowSnapshot((v) => !v);
          if (!showSnapshot) refreshSnapshot();
        }}
        onToggleActions={() => {
          setShowActions((v) => !v);
          if (!showActions) refreshSnapshot();
        }}
        onToggleAutoRefresh={toggleAutoRefresh}
        onStop={stopBrowser}
      />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  NavButton                                                          */
/* ------------------------------------------------------------------ */

function NavButton({
  icon,
  tooltip,
  onClick,
}: {
  icon: React.ReactNode;
  tooltip: string;
  onClick: () => void;
}) {
  const [hover, setHover] = useState(false);

  return (
    <button
      onClick={onClick}
      title={tooltip}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      className="flex h-6 w-6 cursor-pointer items-center justify-center rounded-sm"
      style={{
        background: hover
          ? 'color-mix(in srgb, var(--surface-elevated) 50%, transparent)'
          : 'transparent',
        color: hover ? 'var(--fg-primary)' : 'var(--fg-muted)',
      }}
    >
      {icon}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/*  TabChip                                                            */
/* ------------------------------------------------------------------ */

function TabChip({
  tab,
  isActive,
  onTap,
  onClose,
}: {
  tab: BrowserTab;
  isActive: boolean;
  onTap: () => void;
  onClose: () => void;
}) {
  const [hover, setHover] = useState(false);

  return (
    <div
      onClick={onTap}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      className="flex min-w-[60px] max-w-[160px] cursor-pointer items-center gap-1 rounded-sm px-2 py-0.5"
      style={{
        background: isActive
          ? 'var(--surface-base)'
          : hover
            ? 'color-mix(in srgb, var(--surface-elevated) 30%, transparent)'
            : 'transparent',
        border: isActive ? '0.5px solid var(--border)' : 'none',
      }}
    >
      <span
        className="flex-1 truncate text-[10px]"
        style={{
          color: isActive ? 'var(--fg-primary)' : 'var(--fg-muted)',
        }}
      >
        {tab.title || 'New Tab'}
      </span>
      {(hover || isActive) && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onClose();
          }}
          className="shrink-0 cursor-pointer"
        >
          <X size={10} style={{ color: 'var(--fg-muted)' }} />
        </button>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Start screen                                                       */
/* ------------------------------------------------------------------ */

function StartScreen({
  onStart,
  error,
}: {
  onStart: () => void;
  error: string | null;
}) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4">
      <div
        className="flex h-12 w-12 items-center justify-center"
        style={{ border: '0.5px solid var(--border)', borderRadius: 'var(--shell-radius)' }}
      >
        <Globe size={24} style={{ color: 'var(--fg-muted)' }} />
      </div>
      <div className="flex flex-col items-center gap-1">
        <span className="text-xs" style={{ color: 'var(--fg-secondary)' }}>
          openclaw managed browser
        </span>
        <span className="text-[10px]" style={{ color: 'var(--fg-muted)' }}>
          isolated chromium instance for agent + human collaboration
        </span>
      </div>
      {error && (
        <div
          className="max-w-[400px] rounded-sm p-2"
          style={{
            background: 'color-mix(in srgb, var(--status-error) 10%, transparent)',
            border: '0.5px solid color-mix(in srgb, var(--status-error) 30%, transparent)',
          }}
        >
          <span
            className="line-clamp-3 text-[9px]"
            style={{ color: 'var(--status-error)' }}
          >
            {error}
          </span>
        </div>
      )}
      <button
        onClick={onStart}
        className="cursor-pointer rounded-sm px-5 py-2 text-[11px] font-semibold"
        style={{
          background: 'color-mix(in srgb, var(--accent-primary) 15%, transparent)',
          border: '0.5px solid color-mix(in srgb, var(--accent-primary) 30%, transparent)',
          color: 'var(--accent-primary)',
        }}
      >
        start browser
      </button>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Error screen                                                       */
/* ------------------------------------------------------------------ */

function ErrorScreen({
  error,
  onRetry,
}: {
  error: string;
  onRetry: () => void;
}) {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3">
      <AlertCircle size={24} style={{ color: 'var(--status-error)' }} />
      <div
        className="max-w-[400px] rounded-sm p-2 text-center"
        style={{
          background: 'color-mix(in srgb, var(--status-error) 10%, transparent)',
          border: '0.5px solid color-mix(in srgb, var(--status-error) 30%, transparent)',
        }}
      >
        <span
          className="line-clamp-5 text-[10px]"
          style={{ color: 'var(--fg-secondary)' }}
        >
          {error}
        </span>
      </div>
      <button
        onClick={onRetry}
        className="cursor-pointer rounded-sm px-4 py-1.5 text-[10px]"
        style={{
          border: '0.5px solid var(--border)',
          color: 'var(--accent-primary)',
        }}
      >
        retry
      </button>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Status bar                                                         */
/* ------------------------------------------------------------------ */

function StatusBar({
  state,
  showSnapshot,
  showActions,
  onToggleSnapshot,
  onToggleActions,
  onToggleAutoRefresh,
  onStop,
}: {
  state: BrowserState;
  showSnapshot: boolean;
  showActions: boolean;
  onToggleSnapshot: () => void;
  onToggleActions: () => void;
  onToggleAutoRefresh: () => void;
  onStop: () => void;
}) {
  const statusColor =
    state.runState === 'running'
      ? 'var(--accent-primary)'
      : state.runState === 'starting'
        ? 'var(--status-warning)'
        : state.runState === 'error'
          ? 'var(--status-error)'
          : 'var(--fg-disabled)';

  const statusLabel =
    state.runState === 'running'
      ? 'running'
      : state.runState === 'starting'
        ? 'starting'
        : state.runState === 'stopped'
          ? 'stopped'
          : state.runState === 'error'
            ? 'error'
            : 'checking...';

  return (
    <div
      className="flex h-[22px] shrink-0 items-center justify-between px-2"
      style={{
        background: 'var(--surface-card)',
        borderTop: '0.5px solid var(--border)',
      }}
    >
      {/* Left side */}
      <div className="flex flex-1 items-center gap-1 overflow-hidden">
        <div
          className="h-1.5 w-1.5 shrink-0 rounded-full"
          style={{ background: statusColor }}
        />
        <span className="text-[9px]" style={{ color: 'var(--fg-muted)' }}>
          {statusLabel}
        </span>
        <span className="ml-2 truncate text-[9px]" style={{ color: 'var(--fg-muted)' }}>
          profile: {state.profile}
          {state.tabs.length > 0 &&
            ` | ${state.tabs.length} tab${state.tabs.length === 1 ? '' : 's'}`}
        </span>
      </div>

      {/* Right side controls */}
      <div className="flex items-center gap-2">
        {state.runState === 'running' && (
          <>
            <button
              onClick={onToggleSnapshot}
              className="cursor-pointer px-1 text-[9px]"
              style={{
                color: showSnapshot ? 'var(--accent-primary)' : 'var(--fg-muted)',
              }}
            >
              {showSnapshot ? 'hide snapshot' : 'snapshot'}
            </button>
            <button
              onClick={onToggleActions}
              className="cursor-pointer px-1 text-[9px]"
              style={{
                color: showActions ? 'var(--accent-primary)' : 'var(--fg-muted)',
              }}
            >
              {showActions ? 'hide actions' : 'actions'}
            </button>
            <button
              onClick={onToggleAutoRefresh}
              className="flex cursor-pointer items-center gap-0.5"
            >
              <RefreshCw
                size={10}
                style={{
                  color: state.autoRefresh
                    ? 'var(--accent-primary)'
                    : 'var(--fg-muted)',
                }}
              />
              <span
                className="text-[9px]"
                style={{
                  color: state.autoRefresh
                    ? 'var(--accent-primary)'
                    : 'var(--fg-muted)',
                }}
              >
                {state.autoRefresh ? 'live' : 'paused'}
              </span>
            </button>
            <button
              onClick={onStop}
              className="cursor-pointer px-1 text-[9px]"
              style={{ color: 'var(--fg-muted)' }}
            >
              stop
            </button>
          </>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Action panel                                                       */
/* ------------------------------------------------------------------ */

function ActionPanel({
  state,
  onRefreshRefs,
  onClickRef,
  onTypeText,
  onPressKey,
}: {
  state: BrowserState;
  onRefreshRefs: () => Promise<number>;
  onClickRef: (ref: string) => void;
  onTypeText: (ref: string, text: string) => void;
  onPressKey: (key: string) => void;
}) {
  const [selectedRef, setSelectedRef] = useState<string | null>(null);
  const [typeValue, setTypeValue] = useState('');
  const [keyValue, setKeyValue] = useState('Enter');

  return (
    <div
      className="flex shrink-0 flex-col gap-1.5 px-2 py-1.5"
      style={{
        height: 88,
        background: 'var(--surface-card)',
        borderTop: '0.5px solid var(--border)',
      }}
    >
      {/* Header row */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-[10px]" style={{ color: 'var(--fg-secondary)' }}>
            interactive actions
          </span>
          <span className="text-[9px]" style={{ color: 'var(--fg-muted)' }}>
            {state.snapshotRefs.length} refs
          </span>
        </div>
        <button
          onClick={() => onRefreshRefs()}
          className="cursor-pointer rounded-sm px-2.5 py-1 text-[10px]"
          style={{
            border: '0.5px solid var(--border)',
            color: 'var(--accent-primary)',
          }}
        >
          sync refs
        </button>
      </div>

      {/* Controls row */}
      <div className="flex flex-1 items-center gap-1.5 overflow-x-auto">
        {/* Ref selector */}
        <select
          value={selectedRef ?? ''}
          onChange={(e) => setSelectedRef(e.target.value || null)}
          className="h-7 w-[230px] shrink-0 rounded-sm px-2 text-[10px] outline-none"
          style={{
            background: 'transparent',
            border: '0.5px solid var(--border)',
            color: 'var(--fg-secondary)',
          }}
        >
          <option value="">
            {state.snapshotRefs.length === 0
              ? 'no refs yet (click sync refs)'
              : 'select ref'}
          </option>
          {state.snapshotRefs.map((r) => (
            <option key={r.ref} value={r.ref}>
              {r.ref} {r.role}
              {r.name ? `: ${r.name}` : ''}
            </option>
          ))}
        </select>

        <button
          onClick={() => selectedRef && onClickRef(selectedRef)}
          className="h-7 shrink-0 cursor-pointer rounded-sm px-2.5 text-[10px]"
          style={{
            border: '0.5px solid var(--border)',
            color: 'var(--accent-primary)',
          }}
        >
          click
        </button>

        {/* Type input */}
        <input
          value={typeValue}
          onChange={(e) => setTypeValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && selectedRef && typeValue.trim()) {
              onTypeText(selectedRef, typeValue.trim());
            }
          }}
          placeholder="text to type"
          className="h-7 w-[260px] shrink-0 rounded-sm px-2 text-[10px] outline-none"
          style={{
            background: 'transparent',
            border: '0.5px solid var(--border)',
            color: 'var(--fg-primary)',
          }}
        />

        <button
          onClick={() => {
            if (selectedRef && typeValue.trim()) onTypeText(selectedRef, typeValue.trim());
          }}
          className="h-7 shrink-0 cursor-pointer rounded-sm px-2.5 text-[10px]"
          style={{
            border: '0.5px solid var(--border)',
            color: 'var(--accent-primary)',
          }}
        >
          type
        </button>

        {/* Key input */}
        <input
          value={keyValue}
          onChange={(e) => setKeyValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && keyValue.trim()) onPressKey(keyValue.trim());
          }}
          className="h-7 w-20 shrink-0 rounded-sm px-2 text-[10px] outline-none"
          style={{
            background: 'transparent',
            border: '0.5px solid var(--border)',
            color: 'var(--fg-primary)',
          }}
        />

        <button
          onClick={() => keyValue.trim() && onPressKey(keyValue.trim())}
          className="h-7 shrink-0 cursor-pointer rounded-sm px-2.5 text-[10px]"
          style={{
            border: '0.5px solid var(--border)',
            color: 'var(--accent-primary)',
          }}
        >
          press
        </button>
      </div>
    </div>
  );
}
