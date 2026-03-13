'use client';

import { useCallback, useEffect, useRef, useSyncExternalStore } from 'react';
import { X, AlertCircle, CheckCircle } from 'lucide-react';

/* ------------------------------------------------------------------ */
/*  ToastService — stacking toast manager                              */
/*  1:1 port of Flutter core/toast_provider.dart (static ToastService) */
/*                                                                     */
/*  Features:                                                          */
/*   - Deduplication within 1200ms window                              */
/*   - Max 3 visible toasts (FIFO eviction)                            */
/*   - 5s auto-dismiss                                                 */
/* ------------------------------------------------------------------ */

type ToastType = 'error' | 'info';

interface ToastItem {
  id: number;
  message: string;
  type: ToastType;
}

let _nextId = 0;
let _toasts: ToastItem[] = [];
const _listeners = new Set<() => void>();
const _recentMessages = new Map<string, number>(); // message -> timestamp

function _notify() {
  _listeners.forEach((fn) => fn());
}

const DEDUP_WINDOW = 1200;
const MAX_VISIBLE = 3;
const AUTO_DISMISS_MS = 5000;

export const ToastService = {
  show(message: string, type: ToastType) {
    // Deduplication
    const key = `${type}:${message}`;
    const now = Date.now();
    const lastSeen = _recentMessages.get(key);
    if (lastSeen && now - lastSeen < DEDUP_WINDOW) return;
    _recentMessages.set(key, now);

    const id = _nextId++;
    _toasts = [..._toasts, { id, message, type }];
    // Evict oldest if over max
    if (_toasts.length > MAX_VISIBLE) {
      _toasts = _toasts.slice(-MAX_VISIBLE);
    }
    _notify();

    // Auto-dismiss
    setTimeout(() => {
      ToastService.dismiss(id);
    }, AUTO_DISMISS_MS);
  },
  showError(message: string) {
    this.show(message, 'error');
  },
  showInfo(message: string) {
    this.show(message, 'info');
  },
  dismiss(id: number) {
    const prev = _toasts;
    _toasts = _toasts.filter((t) => t.id !== id);
    if (prev.length !== _toasts.length) _notify();
  },
  subscribe(fn: () => void) {
    _listeners.add(fn);
    return () => {
      _listeners.delete(fn);
    };
  },
  getSnapshot(): ToastItem[] {
    return _toasts;
  },
};

/* ------------------------------------------------------------------ */
/*  <ToastContainer> — renders the toast stack                         */
/* ------------------------------------------------------------------ */

export function ToastContainer() {
  const toasts = useSyncExternalStore(
    ToastService.subscribe,
    ToastService.getSnapshot,
    () => [] as ToastItem[],
  );

  if (toasts.length === 0) return null;

  return (
    <div className="fixed bottom-6 left-1/2 z-[100] flex -translate-x-1/2 flex-col-reverse gap-2">
      {toasts.map((toast) => (
        <ToastWidget key={toast.id} toast={toast} />
      ))}
    </div>
  );
}

function ToastWidget({ toast }: { toast: ToastItem }) {
  const isError = toast.type === 'error';
  const borderColor = isError ? 'var(--status-error)' : 'var(--accent-primary)';
  const textColor = isError ? 'var(--status-error)' : 'var(--fg-primary)';
  const Icon = isError ? AlertCircle : CheckCircle;

  return (
    <div
      className="flex items-center gap-2 px-4 py-2"
      style={{
        background: '#1E1E1EF2',
        borderRadius: 'var(--shell-radius)',
        border: `0.5px solid ${borderColor}`,
        color: textColor,
        maxWidth: 480,
        minWidth: 240,
      }}
    >
      <Icon size={14} style={{ color: borderColor, flexShrink: 0 }} />
      <span className="flex-1 text-xs select-text">{toast.message}</span>
      <button
        onClick={() => ToastService.dismiss(toast.id)}
        className="ml-2 flex-shrink-0 text-fg-muted hover:text-fg-primary"
      >
        <X size={12} />
      </button>
    </div>
  );
}
