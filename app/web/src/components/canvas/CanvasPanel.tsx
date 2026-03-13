'use client';

/**
 * CanvasPanel — 1:1 port of features/canvas/canvas_panel.dart
 *
 * Stack layout: mode-specific renderer + toolbars + mode toggle (bottom-right).
 * Modes: drawio | browser (beta) | a2ui (beta)
 */

import { useCallback, useRef, useState } from 'react';
import {
  Copy,
  Download,
  RefreshCw,
  RotateCcw,
  Pause,
  Play,
  Square,
  Sun,
  Moon,
  Wrench,
  X,
  Trash2,
} from 'lucide-react';
import { useCanvasStore, type CanvasMode, type DrawIOTheme } from '@/lib/stores/canvas-store';
import { useAuthStore } from '@/lib/stores/auth-store';
import { useGatewayStore } from '@/lib/stores/gateway-store';
import { ToastService } from '@/components/ui/Toast';
import A2UIRenderer from './A2UIRenderer';
import DrawIORenderer, { type DrawIORendererHandle } from './DrawIORenderer';
import BrowserRenderer from './BrowserRenderer';

/* ------------------------------------------------------------------ */
/*  CanvasPanel                                                        */
/* ------------------------------------------------------------------ */

export default function CanvasPanel() {
  const canvasMode = useCanvasStore((s) => s.canvasMode);
  const drawioTheme = useCanvasStore((s) => s.drawioTheme);
  const setCanvasMode = useCanvasStore((s) => s.setCanvasMode);
  const setDrawIOTheme = useCanvasStore((s) => s.setDrawIOTheme);

  const drawioRef = useRef<DrawIORendererHandle>(null);

  // Dialog states
  const [showSaveAsDialog, setShowSaveAsDialog] = useState(false);
  const [showLoadDialog, setShowLoadDialog] = useState(false);
  const [showRefActionsDialog, setShowRefActionsDialog] = useState(false);

  // Disable iframe pointer events while dialogs open
  const dialogOpen = showSaveAsDialog || showLoadDialog || showRefActionsDialog;

  const toggleDrawioTheme = useCallback(() => {
    const next: DrawIOTheme = drawioTheme === 'dark' ? 'light' : 'dark';
    setDrawIOTheme(next);
    drawioRef.current?.reloadWithTheme();
  }, [drawioTheme, setDrawIOTheme]);

  return (
    <div className="relative h-full w-full overflow-hidden">
      {/* Renderer area */}
      <div className="absolute inset-0">
        {canvasMode === 'a2ui' && <A2UIRenderer />}
        {canvasMode === 'drawio' && (
          <DrawIORenderer ref={drawioRef} dialogIsOpen={dialogOpen} />
        )}
        {canvasMode === 'browser' && <BrowserRenderer />}
      </div>

      {/* DrawIO toolbar — bottom-right above mode toggle */}
      {canvasMode === 'drawio' && (
        <div className="absolute bottom-9 right-1 z-10 flex items-center gap-0.5">
          <SmallButton
            icon={<Copy size={12} />}
            tooltip="copy image"
            onClick={() => drawioRef.current?.copyPng()}
          />
          <SmallButton
            icon={<Download size={12} />}
            tooltip="export PNG"
            onClick={() => drawioRef.current?.exportPng()}
          />
          <SmallTextButton
            label="save xml"
            tooltip="save xml snapshot"
            onClick={async () => {
              const handle = drawioRef.current;
              if (!handle) {
                ToastService.showError('drawio not ready (state unavailable)');
                return;
              }
              const ok = await handle.saveXmlSnapshot();
              if (ok) {
                ToastService.showInfo('saved XML snapshot');
              } else {
                ToastService.showError('unable to save XML snapshot');
              }
            }}
          />
          <SmallTextButton
            label="save as"
            tooltip="save xml with custom name"
            onClick={() => setShowSaveAsDialog(true)}
          />
          <SmallTextButton
            label="load xml"
            tooltip="load xml snapshot"
            onClick={() => setShowLoadDialog(true)}
          />
        </div>
      )}

      {/* DrawIO theme toggle — bottom-right */}
      {canvasMode === 'drawio' && (
        <div className="absolute bottom-1 right-[70px] z-10">
          <button
            onClick={toggleDrawioTheme}
            className="flex items-center justify-center rounded-sm p-1 cursor-pointer"
            style={{
              background: 'var(--surface-base)',
              opacity: 0.95,
              border: '0.5px solid var(--border)',
            }}
            title="toggle drawio theme"
          >
            {drawioTheme === 'dark' ? (
              <Sun size={12} style={{ color: 'var(--fg-muted)' }} />
            ) : (
              <Moon size={12} style={{ color: 'var(--fg-muted)' }} />
            )}
          </button>
        </div>
      )}

      {/* Browser toolbar — bottom-right above mode toggle */}
      {canvasMode === 'browser' && <BrowserToolbar />}

      {/* Mode toggle — bottom-right */}
      <div className="absolute bottom-1 right-1 z-10">
        <ModeToggle
          currentMode={canvasMode}
          drawIOTheme={drawioTheme}
          onModeChanged={setCanvasMode}
          onDrawioThemeToggle={toggleDrawioTheme}
        />
      </div>

      {/* Save As Dialog */}
      {showSaveAsDialog && (
        <DrawIOSaveAsDialog
          drawioRef={drawioRef}
          onClose={() => setShowSaveAsDialog(false)}
        />
      )}

      {/* Load Dialog */}
      {showLoadDialog && (
        <DrawIOLoadDialog
          drawioRef={drawioRef}
          onClose={() => setShowLoadDialog(false)}
        />
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  BrowserToolbar (only visible when browser mode + running)           */
/* ------------------------------------------------------------------ */

function BrowserToolbar() {
  // We import browser state from the gateway-backed browser store
  // Lazy-import to avoid circular deps — browser state lives in BrowserRenderer
  // For the toolbar we just need a simple running check
  return null; // Browser toolbar is embedded in BrowserRenderer's StatusBar
}

/* ------------------------------------------------------------------ */
/*  Mode toggle                                                        */
/* ------------------------------------------------------------------ */

function ModeToggle({
  currentMode,
  drawIOTheme,
  onModeChanged,
  onDrawioThemeToggle,
}: {
  currentMode: CanvasMode;
  drawIOTheme: DrawIOTheme;
  onModeChanged: (mode: CanvasMode) => void;
  onDrawioThemeToggle: () => void;
}) {
  return (
    <div
      className="flex items-center gap-0.5 rounded-sm px-0.5 py-0.5"
      style={{
        background: 'var(--surface-base)',
        opacity: 0.95,
        border: '0.5px solid var(--border)',
      }}
    >
      <ModeButton
        label="drawio"
        isSelected={currentMode === 'drawio'}
        onClick={() => onModeChanged('drawio')}
        trailing={
          currentMode === 'drawio' ? (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onDrawioThemeToggle();
              }}
              className="ml-1 cursor-pointer"
            >
              {drawIOTheme === 'dark' ? (
                <Sun size={10} style={{ color: 'var(--fg-muted)' }} />
              ) : (
                <Moon size={10} style={{ color: 'var(--fg-muted)' }} />
              )}
            </button>
          ) : undefined
        }
      />
      <div
        className="mx-0.5 h-3.5"
        style={{ width: 1, background: 'var(--border)' }}
      />
      <ModeButton
        label="browser"
        isSelected={currentMode === 'browser'}
        onClick={() => onModeChanged('browser')}
        badge="beta"
      />
      <div
        className="mx-0.5 h-3.5"
        style={{ width: 1, background: 'var(--border)' }}
      />
      <ModeButton
        label="a2ui"
        isSelected={currentMode === 'a2ui'}
        onClick={() => onModeChanged('a2ui')}
        badge="beta"
      />
    </div>
  );
}

function ModeButton({
  label,
  isSelected,
  onClick,
  badge,
  trailing,
}: {
  label: string;
  isSelected: boolean;
  onClick: () => void;
  badge?: string;
  trailing?: React.ReactNode;
}) {
  return (
    <button
      onClick={isSelected ? undefined : onClick}
      className="flex items-center rounded-sm px-2 py-1"
      style={{
        cursor: isSelected ? 'default' : 'pointer',
        background: isSelected
          ? 'color-mix(in srgb, var(--accent-primary) 15%, transparent)'
          : 'transparent',
      }}
    >
      <span
        className="text-[10px] tracking-wide"
        style={{
          fontWeight: isSelected ? 600 : 400,
          color: isSelected ? 'var(--accent-primary)' : 'var(--fg-muted)',
        }}
      >
        {label}
      </span>
      {badge && (
        <span
          className="ml-1 rounded-sm px-1 py-px text-[8px] tracking-wide"
          style={{
            background: 'color-mix(in srgb, var(--status-warning) 15%, transparent)',
            border: '0.5px solid color-mix(in srgb, var(--status-warning) 45%, transparent)',
            color: 'var(--status-warning)',
          }}
        >
          {badge}
        </span>
      )}
      {trailing}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/*  Small icon button                                                  */
/* ------------------------------------------------------------------ */

function SmallButton({
  icon,
  tooltip,
  onClick,
}: {
  icon: React.ReactNode;
  tooltip: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      title={tooltip}
      className="flex items-center justify-center rounded-sm p-1 cursor-pointer"
      style={{
        background: 'color-mix(in srgb, var(--surface-base) 80%, transparent)',
        border: '0.5px solid var(--border)',
        color: 'var(--fg-muted)',
      }}
    >
      {icon}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/*  Small text button                                                  */
/* ------------------------------------------------------------------ */

function SmallTextButton({
  label,
  tooltip,
  onClick,
}: {
  label: string;
  tooltip: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      title={tooltip}
      className="rounded-sm px-1.5 py-1 text-[10px] tracking-wide cursor-pointer"
      style={{
        background: 'color-mix(in srgb, var(--surface-base) 90%, transparent)',
        border: '0.5px solid var(--border)',
        color: 'var(--fg-muted)',
      }}
    >
      {label}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/*  DrawIO Save As Dialog                                              */
/* ------------------------------------------------------------------ */

function DrawIOSaveAsDialog({
  drawioRef,
  onClose,
}: {
  drawioRef: React.RefObject<DrawIORendererHandle | null>;
  onClose: () => void;
}) {
  const [name, setName] = useState('');

  const save = async () => {
    const handle = drawioRef.current;
    if (!handle) {
      ToastService.showError('drawio not ready');
      return;
    }
    const ok = await handle.saveXmlSnapshotNamed(name);
    if (ok) {
      onClose();
      ToastService.showInfo('saved XML snapshot');
    } else {
      ToastService.showError('unable to save XML snapshot');
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div
        className="flex w-[360px] flex-col gap-2 p-3"
        style={{
          background: 'var(--surface-base)',
          border: '0.5px solid var(--border)',
          borderRadius: 0,
        }}
      >
        <span className="text-[11px]" style={{ color: 'var(--fg-secondary)' }}>
          save xml snapshot as
        </span>
        <input
          autoFocus
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') save();
          }}
          placeholder="diagram name"
          className="w-full rounded-sm px-2 py-1.5 text-[11px] outline-none"
          style={{
            background: 'transparent',
            border: '0.5px solid var(--border)',
            color: 'var(--fg-secondary)',
          }}
        />
        <div className="flex justify-end gap-1.5">
          <DialogTextButton label="cancel" onClick={onClose} />
          <DialogTextButton label="save" onClick={save} primary />
        </div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  DrawIO Load Dialog                                                 */
/* ------------------------------------------------------------------ */

interface DrawIOSnapshot {
  id: string;
  name: string;
  xml: string;
  createdAt: string;
  xmlHash: string;
}

function DrawIOLoadDialog({
  drawioRef,
  onClose,
}: {
  drawioRef: React.RefObject<DrawIORendererHandle | null>;
  onClose: () => void;
}) {
  const [snapshots, setSnapshots] = useState<DrawIOSnapshot[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const token = useAuthStore((s) => s.token);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);

  // Load on mount
  const didLoad = useRef(false);
  if (!didLoad.current) {
    didLoad.current = true;
    loadSnapshots();
  }

  async function loadSnapshots() {
    setLoading(true);
    setError(null);
    try {
      if (!token || !activeOpenClawId) throw new Error('missing auth/openclaw context');
      const origin = typeof window !== 'undefined' ? window.location.origin : '';
      const res = await fetch(
        `${origin}/auth/openclaws/${activeOpenClawId}/drawio/snapshots`,
        { headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' } },
      );
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setSnapshots(data.snapshots ?? []);
    } catch (e: any) {
      setError(e.message ?? String(e));
    } finally {
      setLoading(false);
    }
  }

  async function deleteSnapshot(id: string) {
    try {
      if (!token || !activeOpenClawId) return;
      const origin = typeof window !== 'undefined' ? window.location.origin : '';
      const res = await fetch(
        `${origin}/auth/openclaws/${activeOpenClawId}/drawio/snapshots/${id}`,
        { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } },
      );
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setSnapshots(data.snapshots ?? []);
    } catch (e: any) {
      ToastService.showError(`failed to delete snapshot: ${e.message}`);
    }
  }

  function formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes}B`;
    const kb = bytes / 1024;
    if (kb < 1024) return `${kb.toFixed(1)}KB`;
    return `${(kb / 1024).toFixed(2)}MB`;
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div
        className="flex max-h-[420px] w-[420px] flex-col"
        style={{
          background: 'var(--surface-base)',
          border: '0.5px solid var(--border)',
          borderRadius: 0,
        }}
      >
        {/* Header */}
        <div
          className="flex h-9 shrink-0 items-center justify-between px-3"
          style={{ borderBottom: '0.5px solid var(--border)' }}
        >
          <span className="text-[11px]" style={{ color: 'var(--fg-muted)' }}>
            load drawio snapshot
          </span>
          <button onClick={onClose} className="cursor-pointer">
            <X size={12} style={{ color: 'var(--fg-muted)' }} />
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-auto">
          {loading && (
            <p className="p-5 text-center text-[11px]" style={{ color: 'var(--fg-muted)' }}>
              loading...
            </p>
          )}
          {!loading && error && (
            <p className="p-5 text-center text-[11px]" style={{ color: 'var(--status-error)' }}>
              failed to load snapshots
            </p>
          )}
          {!loading && !error && snapshots.length === 0 && (
            <p className="p-5 text-center text-[11px]" style={{ color: 'var(--fg-muted)' }}>
              no saved snapshots yet
            </p>
          )}
          {!loading &&
            !error &&
            snapshots.map((snap) => (
              <SnapshotRow
                key={snap.id}
                snapshot={snap}
                subtitle={`${snap.createdAt?.slice(0, 19).replace('T', ' ') ?? ''} \u2022 ${formatSize(snap.xml?.length ?? 0)}`}
                onLoad={() => {
                  drawioRef.current?.loadXmlSnapshot(snap.xml);
                  onClose();
                }}
                onDelete={() => deleteSnapshot(snap.id)}
              />
            ))}
        </div>
      </div>
    </div>
  );
}

function SnapshotRow({
  snapshot,
  subtitle,
  onLoad,
  onDelete,
}: {
  snapshot: DrawIOSnapshot;
  subtitle: string;
  onLoad: () => void;
  onDelete: () => void;
}) {
  const [hovering, setHovering] = useState(false);

  return (
    <div
      onClick={onLoad}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      className="flex h-[42px] cursor-pointer items-center px-3"
      style={{
        background: hovering ? 'var(--surface-card)' : 'transparent',
        borderBottom: '0.5px solid var(--border)',
      }}
    >
      <div className="flex min-w-0 flex-1 flex-col justify-center">
        <span
          className="truncate text-[11px]"
          style={{ color: 'var(--fg-secondary)' }}
        >
          {snapshot.name}
        </span>
        <span className="text-[9px]" style={{ color: 'var(--fg-muted)' }}>
          {subtitle}
        </span>
      </div>
      {hovering && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onDelete();
          }}
          className="cursor-pointer"
        >
          <Trash2 size={12} style={{ color: 'var(--fg-muted)' }} />
        </button>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Dialog text button                                                 */
/* ------------------------------------------------------------------ */

function DialogTextButton({
  label,
  onClick,
  primary = false,
}: {
  label: string;
  onClick: () => void;
  primary?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className="cursor-pointer rounded-sm px-2.5 py-1.5 text-[10px]"
      style={{
        background: primary
          ? 'color-mix(in srgb, var(--accent-primary) 15%, transparent)'
          : 'var(--surface-base)',
        border: `0.5px solid ${
          primary
            ? 'color-mix(in srgb, var(--accent-primary) 60%, transparent)'
            : 'var(--border)'
        }`,
        color: primary ? 'var(--accent-primary)' : 'var(--fg-muted)',
      }}
    >
      {label}
    </button>
  );
}
