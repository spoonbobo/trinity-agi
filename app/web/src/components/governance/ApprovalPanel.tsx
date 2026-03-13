'use client';

import { useState, useEffect, useCallback } from 'react';
import {
  ShieldCheck,
  ShieldAlert,
  Terminal,
  Sparkles,
  Check,
  X,
  ChevronDown,
  ChevronRight,
  Loader2,
} from 'lucide-react';
import { useGatewayStore, gatewayClient } from '@/lib/stores/gateway-store';
import { useAuthStore } from '@/lib/stores/auth-store';
import { useThemeStore } from '@/lib/stores/theme-store';
import { Permissions } from '@/lib/utils/rbac-constants';
import { tr } from '@/lib/i18n/translations';
import { ToastService } from '@/components/ui/Toast';
import type { WsEvent } from '@/lib/protocol/ws-frame';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

type ApprovalKind = 'exec' | 'lobster';
type ApprovalStatus = 'pending' | 'approved' | 'rejected';

interface ApprovalItem {
  id: string;
  kind: ApprovalKind;
  status: ApprovalStatus;
  timestamp: number;
  // exec fields
  command?: string;
  host?: string;
  // lobster fields
  prompt?: string;
  preview?: string;
  // shared
  requestId?: string;
  sessionKey?: string;
}

/* ------------------------------------------------------------------ */
/*  ApprovalPanel — port of approval_panel.dart (~429 lines)           */
/*  Fixed width right panel, only visible with pending items           */
/* ------------------------------------------------------------------ */

export function ApprovalPanel() {
  const language = useThemeStore((s) => s.language);
  const permissions = useAuthStore((s) => s.permissions);
  const canResolve = permissions.includes(Permissions.governanceResolve);
  const [items, setItems] = useState<ApprovalItem[]>([]);
  const [showResolved, setShowResolved] = useState(false);
  const [resolving, setResolving] = useState<string | null>(null);

  // Subscribe to gateway events
  useEffect(() => {
    const unsub = gatewayClient.onEvent((event: WsEvent) => {
      if (event.event === 'exec.approval.requested') {
        const payload = event.payload;
        const item: ApprovalItem = {
          id: payload.requestId ?? `exec-${Date.now()}`,
          kind: 'exec',
          status: 'pending',
          timestamp: Date.now(),
          command: payload.command,
          host: payload.host ?? payload.container,
          requestId: payload.requestId,
        };
        setItems((prev) => [item, ...prev]);
      }

      // Lobster workflow approvals come via chat events
      if (event.event === 'chat' && event.payload?.type === 'lobster_approval') {
        const payload = event.payload;
        const item: ApprovalItem = {
          id: payload.requestId ?? `lobster-${Date.now()}`,
          kind: 'lobster',
          status: 'pending',
          timestamp: Date.now(),
          prompt: payload.prompt ?? payload.description,
          preview: payload.preview,
          requestId: payload.requestId,
          sessionKey: payload.sessionKey,
        };
        setItems((prev) => [item, ...prev]);
      }
    });

    return unsub;
  }, []);

  const handleResolve = useCallback(
    async (item: ApprovalItem, approve: boolean) => {
      setResolving(item.id);
      try {
        if (item.kind === 'exec' && item.requestId) {
          const res = await gatewayClient.resolveApproval(item.requestId, approve);
          if (!res.ok) throw new Error(res.error?.message ?? 'Failed');
        } else if (item.kind === 'lobster') {
          // Lobster approvals: send /lobster resume or /lobster reject command
          const cmd = approve ? '/lobster resume' : '/lobster reject';
          await gatewayClient.sendChatMessage(cmd, {
            sessionKey: item.sessionKey,
          });
        }

        setItems((prev) =>
          prev.map((i) =>
            i.id === item.id ? { ...i, status: approve ? 'approved' : 'rejected' } : i,
          ),
        );

        ToastService.showInfo(approve ? 'Approved' : 'Rejected');
      } catch (err: any) {
        ToastService.showError(err.message ?? 'Failed to resolve approval');
      } finally {
        setResolving(null);
      }
    },
    [],
  );

  const pendingItems = items.filter((i) => i.status === 'pending');
  const resolvedItems = items.filter((i) => i.status !== 'pending');

  // Only render the panel when there are pending items
  if (pendingItems.length === 0 && resolvedItems.length === 0) return null;

  return (
    <div
      className="flex h-full shrink-0 flex-col border-l border-border-shell bg-surface-card"
      style={{ width: 280 }}
    >
      {/* Header */}
      <div className="flex h-8 shrink-0 items-center justify-between border-b border-border-shell px-3">
        <span className="flex items-center gap-1.5 text-[10px] uppercase tracking-wide text-fg-secondary">
          <ShieldAlert size={12} />
          approvals
        </span>
        <span className="text-[10px] text-accent-primary">
          {pendingItems.length} pending
        </span>
      </div>

      {/* Body */}
      <div className="flex-1 overflow-auto">
        {/* Empty state */}
        {pendingItems.length === 0 && resolvedItems.length === 0 && (
          <div className="flex flex-col items-center gap-3 py-12">
            <ShieldCheck size={28} className="text-fg-muted" />
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">
              {tr(language, 'no_pending_approvals')}
            </span>
          </div>
        )}

        {/* Pending items */}
        {pendingItems.length > 0 && (
          <div className="flex flex-col">
            {pendingItems.map((item) => (
              <ApprovalCard
                key={item.id}
                item={item}
                canResolve={canResolve}
                resolving={resolving === item.id}
                onApprove={() => handleResolve(item, true)}
                onReject={() => handleResolve(item, false)}
              />
            ))}
          </div>
        )}

        {/* Resolved section */}
        {resolvedItems.length > 0 && (
          <div className="border-t border-border-shell">
            <button
              onClick={() => setShowResolved(!showResolved)}
              className="flex w-full items-center gap-1.5 px-3 py-2 text-[10px] text-fg-muted hover:text-fg-secondary"
            >
              {showResolved ? <ChevronDown size={10} /> : <ChevronRight size={10} />}
              Resolved ({resolvedItems.length})
            </button>
            {showResolved && (
              <div className="flex flex-col">
                {resolvedItems.map((item) => (
                  <ApprovalCard
                    key={item.id}
                    item={item}
                    canResolve={false}
                    resolving={false}
                    onApprove={() => {}}
                    onReject={() => {}}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  ApprovalCard                                                       */
/* ------------------------------------------------------------------ */

function ApprovalCard({
  item,
  canResolve,
  resolving,
  onApprove,
  onReject,
}: {
  item: ApprovalItem;
  canResolve: boolean;
  resolving: boolean;
  onApprove: () => void;
  onReject: () => void;
}) {
  const isPending = item.status === 'pending';
  const language = useThemeStore((s) => s.language);

  return (
    <div className="flex flex-col gap-2 border-b border-border-shell px-3 py-2.5 last:border-b-0">
      {/* Kind badge + timestamp */}
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-1 text-[9px] uppercase tracking-wide text-fg-muted">
          {item.kind === 'exec' ? (
            <Terminal size={10} className="text-status-warning" />
          ) : (
            <Sparkles size={10} className="text-accent-secondary" />
          )}
          {item.kind}
        </span>
        <span className="text-[9px] text-fg-hint">{formatTimeAgo(item.timestamp)}</span>
      </div>

      {/* Content */}
      {item.kind === 'exec' && (
        <div className="flex flex-col gap-1">
          <code className="break-all text-[10px] text-fg-primary font-mono leading-tight">
            {item.command ?? '-'}
          </code>
          {item.host && (
            <span className="text-[9px] text-fg-muted">host: {item.host}</span>
          )}
        </div>
      )}

      {item.kind === 'lobster' && (
        <div className="flex flex-col gap-1">
          <span className="text-[10px] text-fg-primary leading-tight">
            {item.prompt ?? '-'}
          </span>
          {item.preview && (
            <span className="text-[9px] text-fg-tertiary italic leading-tight">
              {item.preview}
            </span>
          )}
        </div>
      )}

      {/* Resolution status for resolved items */}
      {!isPending && (
        <span
          className={`text-[9px] uppercase tracking-wide ${
            item.status === 'approved' ? 'text-accent-primary' : 'text-status-error'
          }`}
        >
          {item.status}
        </span>
      )}

      {/* Action buttons for pending items */}
      {isPending && canResolve && (
        <div className="flex items-center gap-2">
          <button
            onClick={onApprove}
            disabled={resolving}
            className="flex flex-1 items-center justify-center gap-1 border border-accent-primary py-1 text-[10px] text-accent-primary hover:bg-accent-primary-muted disabled:opacity-40"
          >
            {resolving ? (
              <Loader2 size={10} className="animate-spin" />
            ) : (
              <Check size={10} />
            )}
            {tr(language, 'approve')}
          </button>
          <button
            onClick={onReject}
            disabled={resolving}
            className="flex flex-1 items-center justify-center gap-1 border border-status-error py-1 text-[10px] text-status-error hover:bg-status-error/10 disabled:opacity-40"
          >
            {resolving ? (
              <Loader2 size={10} className="animate-spin" />
            ) : (
              <X size={10} />
            )}
            {tr(language, 'reject')}
          </button>
        </div>
      )}

      {isPending && !canResolve && (
        <span className="text-[9px] text-fg-muted italic">
          Insufficient permissions to resolve
        </span>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function formatTimeAgo(timestamp: number): string {
  const seconds = Math.floor((Date.now() - timestamp) / 1000);
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}
