/**
 * Copilot Zustand store — wraps CopilotClient
 */

import { create } from 'zustand';
import { CopilotClient, type CopilotMessage, type CopilotStatus } from '@/lib/clients/copilot-client';

interface CopilotStore {
  client: CopilotClient;
  messages: CopilotMessage[];
  status: CopilotStatus | null;
  currentModel: string;
  availableModels: string[];
  loading: boolean;
  sessionId: string;
}

export const useCopilotStore = create<CopilotStore>(() => ({
  client: new CopilotClient(),
  messages: [],
  status: null,
  currentModel: '',
  availableModels: [],
  loading: false,
  sessionId: '',
}));
