'use client';

import { useState, useEffect, useCallback } from 'react';
import { X, RefreshCw } from 'lucide-react';
import { Dialog, DialogService } from '@/components/ui/Dialog';
import { ToastService } from '@/components/ui/Toast';
import { useTerminalStore } from '@/lib/stores/terminal-store';

/* ------------------------------------------------------------------ */
/*  MemoryDialog — 1:1 port of features/memory/memory_dialog.dart     */
/*  Simple MEMORY.md viewer                                            */
/* ------------------------------------------------------------------ */

interface MemoryDialogProps {
  open: boolean;
  onClose: () => void;
}

export function MemoryDialog({ open, onClose }: MemoryDialogProps) {
  const client = useTerminalStore((s) => s.client);
  const [content, setContent] = useState<string>('');
  const [loading, setLoading] = useState(false);

  /* ---------------------------------------------------------------- */
  /*  Fetch MEMORY.md                                                  */
  /* ---------------------------------------------------------------- */

  const fetchMemory = useCallback(async () => {
    setLoading(true);
    try {
      await client.connect();
      const output = await client.executeCommandForOutput(
        'cat /home/node/.openclaw/workspace/MEMORY.md',
      );
      setContent(output.trim());
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to load MEMORY.md');
      setContent('');
    } finally {
      setLoading(false);
    }
  }, [client]);

  useEffect(() => {
    if (open) fetchMemory();
  }, [open, fetchMemory]);

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  const handleClose = useCallback(() => {
    DialogService.close('memory');
    onClose();
  }, [onClose]);

  return (
    <Dialog
      id="memory"
      open={open}
      onClose={handleClose}
      width="80%"
      height="80%"
      maxWidth="980px"
      maxHeight="760px"
      header={
        <div className="flex h-10 shrink-0 items-center justify-between border-b border-border-shell px-4">
          <span className="text-xs font-medium tracking-wide text-fg-secondary uppercase">
            memory
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={fetchMemory}
              className="text-fg-muted hover:text-fg-secondary"
              title="Refresh"
            >
              <RefreshCw size={12} className={loading ? 'animate-spin' : ''} />
            </button>
            <button onClick={handleClose} className="text-fg-muted hover:text-fg-primary">
              <X size={14} />
            </button>
          </div>
        </div>
      }
    >
      <div className="h-full overflow-y-auto p-4">
        {loading ? (
          <div className="flex items-center gap-2 text-xs text-fg-muted">
            <RefreshCw size={12} className="animate-spin" />
            Loading...
          </div>
        ) : content ? (
          <pre
            className="whitespace-pre-wrap font-mono text-xs text-fg-secondary select-text"
            style={{ lineHeight: 1.6 }}
          >
            {content}
          </pre>
        ) : (
          <div className="flex h-full items-center justify-center text-xs text-fg-muted">
            (empty)
          </div>
        )}
      </div>
    </Dialog>
  );
}
