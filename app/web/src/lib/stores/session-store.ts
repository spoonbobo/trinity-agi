/**
 * Session Zustand store — replaces Riverpod activeSessionProvider + chatRefreshTickProvider
 */

import { create } from 'zustand';

interface SessionStore {
  activeSession: string;
  chatRefreshTick: number;
  setActiveSession: (key: string) => void;
  incrementRefreshTick: () => void;
}

export const useSessionStore = create<SessionStore>((set) => ({
  activeSession: 'main',
  chatRefreshTick: 0,
  setActiveSession: (key: string) => set({ activeSession: key }),
  incrementRefreshTick: () => set((s) => ({ chatRefreshTick: s.chatRefreshTick + 1 })),
}));
