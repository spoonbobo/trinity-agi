'use client';

import { useCallback, useEffect, useRef } from 'react';
import { X } from 'lucide-react';

/* ------------------------------------------------------------------ */
/*  DialogService — singleton deduplication manager                    */
/*  1:1 port of Flutter core/dialog_service.dart                       */
/* ------------------------------------------------------------------ */

const _openDialogs = new Set<string>();
const _listeners = new Set<() => void>();

function _notify() {
  _listeners.forEach((fn) => fn());
}

export const DialogService = {
  isOpen(id: string) {
    return _openDialogs.has(id);
  },
  get hasOpenDialogs() {
    return _openDialogs.size > 0;
  },
  open(id: string) {
    if (_openDialogs.has(id)) return false;
    _openDialogs.add(id);
    _notify();
    return true;
  },
  close(id: string) {
    _openDialogs.delete(id);
    _notify();
  },
  reset() {
    _openDialogs.clear();
    _notify();
  },
  subscribe(fn: () => void) {
    _listeners.add(fn);
    return () => {
      _listeners.delete(fn);
    };
  },
};

/* ------------------------------------------------------------------ */
/*  <Dialog> component                                                  */
/*  Matches Flutter's custom Dialog widget visual: zero border-radius, */
/*  dark card bg, 0.5px border, no elevation                           */
/* ------------------------------------------------------------------ */

interface DialogProps {
  id: string;
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: string;
  /** CSS width — e.g. '86%' or '520px' */
  width?: string;
  /** CSS height — e.g. '84%' or '600px' */
  height?: string;
  /** CSS max-width */
  maxWidth?: string;
  /** CSS max-height */
  maxHeight?: string;
  /** Whether clicking backdrop closes the dialog */
  barrierDismissible?: boolean;
  /** Hide the default header close button */
  hideClose?: boolean;
  /** Custom header content (replaces default title + close) */
  header?: React.ReactNode;
}

export function Dialog({
  id,
  open,
  onClose,
  children,
  title,
  width = '520px',
  height,
  maxWidth = '1060px',
  maxHeight = '780px',
  barrierDismissible = true,
  hideClose = false,
  header,
}: DialogProps) {
  const backdropRef = useRef<HTMLDivElement>(null);

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [open, onClose]);

  const handleBackdropClick = useCallback(
    (e: React.MouseEvent) => {
      if (barrierDismissible && e.target === backdropRef.current) {
        onClose();
      }
    },
    [barrierDismissible, onClose],
  );

  if (!open) return null;

  return (
    <div
      ref={backdropRef}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
      onClick={handleBackdropClick}
    >
      <div
        className="flex flex-col overflow-hidden border border-border-shell bg-surface-card"
        style={{
          width,
          height,
          maxWidth,
          maxHeight,
          borderRadius: 0,
        }}
      >
        {/* Header */}
        {header ?? (
          <div className="flex h-10 shrink-0 items-center justify-between border-b border-border-shell px-4">
            <span className="text-xs font-medium tracking-wide text-fg-secondary uppercase">
              {title}
            </span>
            {!hideClose && (
              <button
                onClick={onClose}
                className="flex items-center justify-center text-fg-muted hover:text-fg-primary"
              >
                <X size={14} />
              </button>
            )}
          </div>
        )}

        {/* Body */}
        <div className="flex-1 overflow-auto">{children}</div>
      </div>
    </div>
  );
}
