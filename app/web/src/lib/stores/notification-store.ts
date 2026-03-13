/**
 * Notification Zustand store — port of features/notifications/notification_center.dart
 */

import { create } from 'zustand';
import type { WsEvent } from '@/lib/protocol/ws-frame';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

export type NotificationType = 'cron' | 'hook' | 'webhook' | 'approval' | 'connection' | 'error';

export interface AppNotification {
  id: string;
  type: NotificationType;
  title: string;
  body: string;
  timestamp: number;
  read: boolean;
}

const MAX_NOTIFICATIONS = 100;
const STORAGE_KEY = 'trinity_notifications';

/* ------------------------------------------------------------------ */
/*  Persistence helpers                                                */
/* ------------------------------------------------------------------ */

function loadNotifications(): AppNotification[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveNotifications(notifications: AppNotification[]): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(notifications.slice(0, MAX_NOTIFICATIONS)));
  } catch { /* ignore */ }
}

/* ------------------------------------------------------------------ */
/*  Store                                                              */
/* ------------------------------------------------------------------ */

interface NotificationStore {
  notifications: AppNotification[];
  unreadCount: number;

  add: (n: Omit<AppNotification, 'id' | 'timestamp' | 'read'>) => void;
  markRead: (id: string) => void;
  markAllRead: () => void;
  dismiss: (id: string) => void;
  clearAll: () => void;
  processEvent: (event: WsEvent) => void;
}

export const useNotificationStore = create<NotificationStore>((set, get) => {
  const initial = typeof window !== 'undefined' ? loadNotifications() : [];

  return {
    notifications: initial,
    unreadCount: initial.filter((n) => !n.read).length,

    add: (n) => {
      const notification: AppNotification = {
        ...n,
        id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        timestamp: Date.now(),
        read: false,
      };
      const list = [notification, ...get().notifications].slice(0, MAX_NOTIFICATIONS);
      saveNotifications(list);
      set({ notifications: list, unreadCount: list.filter((x) => !x.read).length });
    },

    markRead: (id) => {
      const list = get().notifications.map((n) => (n.id === id ? { ...n, read: true } : n));
      saveNotifications(list);
      set({ notifications: list, unreadCount: list.filter((x) => !x.read).length });
    },

    markAllRead: () => {
      const list = get().notifications.map((n) => ({ ...n, read: true }));
      saveNotifications(list);
      set({ notifications: list, unreadCount: 0 });
    },

    dismiss: (id) => {
      const list = get().notifications.filter((n) => n.id !== id);
      saveNotifications(list);
      set({ notifications: list, unreadCount: list.filter((x) => !x.read).length });
    },

    clearAll: () => {
      saveNotifications([]);
      set({ notifications: [], unreadCount: 0 });
    },

    processEvent: (event) => {
      if (event.event === 'exec.approval.requested') {
        get().add({
          type: 'approval',
          title: 'Approval Requested',
          body: event.payload.command ?? event.payload.description ?? 'An action requires your approval',
        });
      }
    },
  };
});
