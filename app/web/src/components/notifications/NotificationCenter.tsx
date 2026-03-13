'use client';

import { useCallback, useEffect, useRef } from 'react';
import {
  Clock,
  Bell,
  Zap,
  Globe,
  ShieldAlert,
  Wifi,
  AlertCircle,
  CheckCheck,
  Trash2,
  X,
} from 'lucide-react';
import { useNotificationStore, type NotificationType, type AppNotification } from '@/lib/stores/notification-store';

/* ------------------------------------------------------------------ */
/*  NotificationCenter — port of notification_center.dart (~329 lines) */
/*  Dropdown panel positioned below the bell icon                      */
/* ------------------------------------------------------------------ */

export function NotificationCenter({ onClose }: { onClose: () => void }) {
  const notifications = useNotificationStore((s) => s.notifications);
  const markAllRead = useNotificationStore((s) => s.markAllRead);
  const clearAll = useNotificationStore((s) => s.clearAll);
  const panelRef = useRef<HTMLDivElement>(null);

  // Close on click outside
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        onClose();
      }
    };
    // Delay to avoid closing immediately from the bell click
    const timer = setTimeout(() => document.addEventListener('mousedown', handler), 0);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('mousedown', handler);
    };
  }, [onClose]);

  // Close on Escape
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  const handleMarkAllRead = useCallback(() => {
    markAllRead();
  }, [markAllRead]);

  const handleClearAll = useCallback(() => {
    clearAll();
  }, [clearAll]);

  return (
    <div
      ref={panelRef}
      className="absolute right-0 top-full z-50 mt-1 flex w-80 flex-col border border-border-shell bg-surface-card shadow-lg"
    >
      {/* Header */}
      <div className="flex items-center justify-between border-b border-border-shell px-3 py-2">
        <span className="text-[10px] uppercase tracking-wide text-fg-secondary">notifications</span>
        <div className="flex items-center gap-2">
          <button
            onClick={handleMarkAllRead}
            className="flex items-center gap-1 text-[9px] text-fg-muted hover:text-accent-primary"
            title="Mark all read"
          >
            <CheckCheck size={10} />
            mark read
          </button>
          <button
            onClick={handleClearAll}
            className="flex items-center gap-1 text-[9px] text-fg-muted hover:text-status-error"
            title="Clear all"
          >
            <Trash2 size={10} />
            clear
          </button>
        </div>
      </div>

      {/* List */}
      <div className="max-h-80 overflow-auto">
        {notifications.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-8">
            <Bell size={18} className="text-fg-muted" />
            <span className="text-[10px] text-fg-muted">No notifications</span>
          </div>
        ) : (
          notifications.map((n) => <NotificationItem key={n.id} notification={n} />)
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  NotificationItem                                                   */
/* ------------------------------------------------------------------ */

function NotificationItem({ notification }: { notification: AppNotification }) {
  const dismiss = useNotificationStore((s) => s.dismiss);
  const markRead = useNotificationStore((s) => s.markRead);

  const handleClick = useCallback(() => {
    if (!notification.read) {
      markRead(notification.id);
    }
  }, [notification, markRead]);

  const handleDismiss = useCallback(
    (e: React.MouseEvent) => {
      e.stopPropagation();
      dismiss(notification.id);
    },
    [dismiss, notification.id],
  );

  const icon = getNotificationIcon(notification.type);
  const timeAgo = formatTimeAgo(notification.timestamp);

  return (
    <div
      onClick={handleClick}
      className={`group flex cursor-pointer gap-2.5 border-b border-border-shell px-3 py-2 last:border-b-0 hover:bg-surface-elevated ${
        !notification.read ? 'bg-accent-primary-muted' : ''
      }`}
    >
      {/* Icon */}
      <div className="mt-0.5 shrink-0 text-fg-muted">{icon}</div>

      {/* Content */}
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="text-[11px] text-fg-primary">{notification.title}</span>
        <span className="truncate text-[10px] text-fg-tertiary">{notification.body}</span>
        <span className="text-[9px] text-fg-muted">{timeAgo}</span>
      </div>

      {/* Dismiss on hover */}
      <button
        onClick={handleDismiss}
        className="mt-0.5 shrink-0 opacity-0 group-hover:opacity-100 text-fg-muted hover:text-fg-secondary"
      >
        <X size={10} />
      </button>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function getNotificationIcon(type: NotificationType): React.ReactNode {
  switch (type) {
    case 'cron':
      return <Clock size={13} />;
    case 'hook':
      return <Zap size={13} />;
    case 'webhook':
      return <Globe size={13} />;
    case 'approval':
      return <ShieldAlert size={13} />;
    case 'connection':
      return <Wifi size={13} />;
    case 'error':
      return <AlertCircle size={13} />;
    default:
      return <Bell size={13} />;
  }
}

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
