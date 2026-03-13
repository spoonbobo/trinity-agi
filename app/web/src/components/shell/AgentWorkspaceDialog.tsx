'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  X,
  RefreshCw,
  Save,
  Plus,
  Trash2,
  ChevronDown,
  ChevronRight,
  ToggleLeft,
  ToggleRight,
  Users,
  Route,
  Brain,
  Settings,
} from 'lucide-react';
import { Dialog, DialogService } from '@/components/ui/Dialog';
import { ToastService } from '@/components/ui/Toast';
import { useAuthStore } from '@/lib/stores/auth-store';
import { useTerminalStore } from '@/lib/stores/terminal-store';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

interface ACPConfig {
  enabled: boolean;
  dispatch: string;
  backend: string;
  defaultAgent: string;
  allowedAgents: string[];
  maxSessions: number;
  ttl: number;
}

interface AgentDef {
  id: string;
  name: string;
  model: string;
  sandbox?: string;
  description?: string;
  systemPrompt?: string;
  tools?: string[];
}

interface BindingRule {
  id: string;
  agentId: string;
  channel?: string;
  account?: string;
  peer?: string;
}

type WorkspaceTab = 'acp' | 'agents' | 'bindings' | 'memory';

/* ------------------------------------------------------------------ */
/*  AgentWorkspaceDialog                                               */
/* ------------------------------------------------------------------ */

interface AgentWorkspaceDialogProps {
  open: boolean;
  onClose: () => void;
}

export function AgentWorkspaceDialog({ open, onClose }: AgentWorkspaceDialogProps) {
  const token = useAuthStore((s) => s.token);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);
  const client = useTerminalStore((s) => s.client);

  const [activeTab, setActiveTab] = useState<WorkspaceTab>('acp');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);

  // Config data
  const [acpConfig, setACPConfig] = useState<ACPConfig>({
    enabled: false,
    dispatch: 'round-robin',
    backend: 'local',
    defaultAgent: '',
    allowedAgents: [],
    maxSessions: 5,
    ttl: 3600,
  });
  const [agents, setAgents] = useState<AgentDef[]>([]);
  const [bindings, setBindings] = useState<BindingRule[]>([]);

  const baseUrl = typeof window !== 'undefined' ? window.location.origin : '';

  /* ---------------------------------------------------------------- */
  /*  Fetch config                                                     */
  /* ---------------------------------------------------------------- */

  const fetchConfig = useCallback(async () => {
    if (!token || !activeOpenClawId) return;
    setLoading(true);
    try {
      const res = await fetch(
        `${baseUrl}/auth/openclaws/${activeOpenClawId}/config`,
        { headers: { Authorization: `Bearer ${token}` } },
      );
      if (!res.ok) throw new Error('Failed to fetch config');
      const data = await res.json();

      // ACP section
      const acp = data.acp ?? data.agentControlPlane ?? {};
      setACPConfig({
        enabled: acp.enabled === true,
        dispatch: acp.dispatch ?? acp.dispatchStrategy ?? 'round-robin',
        backend: acp.backend ?? 'local',
        defaultAgent: acp.defaultAgent ?? acp.default_agent ?? '',
        allowedAgents: acp.allowedAgents ?? acp.allowed_agents ?? [],
        maxSessions: acp.maxSessions ?? acp.max_sessions ?? 5,
        ttl: acp.ttl ?? 3600,
      });

      // Agents
      const agentList = data.agents ?? data.agentDefinitions ?? [];
      setAgents(
        (Array.isArray(agentList) ? agentList : []).map((a: any) => ({
          id: a.id ?? a.agentId,
          name: a.name ?? a.id,
          model: a.model ?? '',
          sandbox: a.sandbox,
          description: a.description ?? '',
          systemPrompt: a.systemPrompt ?? a.system_prompt,
          tools: a.tools ?? [],
        })),
      );

      // Bindings
      const bindingList = data.bindings ?? data.routeBindings ?? [];
      setBindings(
        (Array.isArray(bindingList) ? bindingList : []).map((b: any, i: number) => ({
          id: b.id ?? `binding-${i}`,
          agentId: b.agentId ?? b.agent_id ?? '',
          channel: b.channel,
          account: b.account,
          peer: b.peer,
        })),
      );

      setDirty(false);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to load agent config');
    } finally {
      setLoading(false);
    }
  }, [token, activeOpenClawId, baseUrl]);

  useEffect(() => {
    if (open) fetchConfig();
  }, [open, fetchConfig]);

  /* ---------------------------------------------------------------- */
  /*  Save config                                                      */
  /* ---------------------------------------------------------------- */

  const saveConfig = useCallback(async () => {
    if (!token || !activeOpenClawId) return;
    setSaving(true);
    try {
      const body = {
        acp: {
          enabled: acpConfig.enabled,
          dispatch: acpConfig.dispatch,
          backend: acpConfig.backend,
          defaultAgent: acpConfig.defaultAgent,
          allowedAgents: acpConfig.allowedAgents,
          maxSessions: acpConfig.maxSessions,
          ttl: acpConfig.ttl,
        },
        agents: agents.map((a) => ({
          id: a.id,
          name: a.name,
          model: a.model,
          sandbox: a.sandbox,
          description: a.description,
          systemPrompt: a.systemPrompt,
          tools: a.tools,
        })),
        bindings: bindings.map((b) => ({
          agentId: b.agentId,
          channel: b.channel || undefined,
          account: b.account || undefined,
          peer: b.peer || undefined,
        })),
      };

      const res = await fetch(
        `${baseUrl}/auth/openclaws/${activeOpenClawId}/config`,
        {
          method: 'PATCH',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(body),
        },
      );
      if (!res.ok) throw new Error('Failed to save config');
      ToastService.showInfo('Config saved');
      setDirty(false);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Save failed');
    } finally {
      setSaving(false);
    }
  }, [token, activeOpenClawId, baseUrl, acpConfig, agents, bindings]);

  /* ---------------------------------------------------------------- */
  /*  ACP mutation helpers                                             */
  /* ---------------------------------------------------------------- */

  const updateACP = useCallback((patch: Partial<ACPConfig>) => {
    setACPConfig((prev) => ({ ...prev, ...patch }));
    setDirty(true);
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Agents mutation helpers                                          */
  /* ---------------------------------------------------------------- */

  const addAgent = useCallback(() => {
    const id = `agent-${Date.now()}`;
    setAgents((prev) => [
      ...prev,
      { id, name: 'New Agent', model: '', description: '' },
    ]);
    setDirty(true);
  }, []);

  const removeAgent = useCallback((id: string) => {
    setAgents((prev) => prev.filter((a) => a.id !== id));
    setDirty(true);
  }, []);

  const updateAgent = useCallback((id: string, patch: Partial<AgentDef>) => {
    setAgents((prev) =>
      prev.map((a) => (a.id === id ? { ...a, ...patch } : a)),
    );
    setDirty(true);
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Bindings mutation helpers                                        */
  /* ---------------------------------------------------------------- */

  const addBinding = useCallback(() => {
    const id = `binding-${Date.now()}`;
    setBindings((prev) => [...prev, { id, agentId: '' }]);
    setDirty(true);
  }, []);

  const removeBinding = useCallback((id: string) => {
    setBindings((prev) => prev.filter((b) => b.id !== id));
    setDirty(true);
  }, []);

  const updateBinding = useCallback((id: string, patch: Partial<BindingRule>) => {
    setBindings((prev) =>
      prev.map((b) => (b.id === id ? { ...b, ...patch } : b)),
    );
    setDirty(true);
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  const handleClose = useCallback(() => {
    DialogService.close('agent-workspace');
    onClose();
  }, [onClose]);

  return (
    <Dialog
      id="agent-workspace"
      open={open}
      onClose={handleClose}
      width="86%"
      height="84%"
      maxWidth="1400px"
      maxHeight="900px"
      header={
        <div className="flex h-10 shrink-0 items-center justify-between border-b border-border-shell px-4">
          <div className="flex items-center gap-3">
            <span className="text-xs font-medium tracking-wide text-fg-secondary uppercase">
              agent workspace
            </span>
            <div className="flex items-center gap-1">
              {(['acp', 'agents', 'bindings', 'memory'] as WorkspaceTab[]).map((tab) => {
                const Icon = { acp: Settings, agents: Users, bindings: Route, memory: Brain }[tab];
                return (
                  <button
                    key={tab}
                    onClick={() => setActiveTab(tab)}
                    className={`flex items-center gap-1 border border-border-shell px-2 py-0.5 text-[10px] ${
                      activeTab === tab
                        ? 'bg-accent-primary-muted text-accent-primary'
                        : 'text-fg-muted hover:text-fg-secondary'
                    }`}
                  >
                    <Icon size={10} />
                    {tab}
                  </button>
                );
              })}
            </div>
          </div>
          <div className="flex items-center gap-2">
            {dirty && (
              <button
                onClick={saveConfig}
                disabled={saving}
                className="flex items-center gap-1 border border-accent-primary px-2 py-0.5 text-[10px] text-accent-primary hover:bg-accent-primary-muted disabled:opacity-50"
              >
                <Save size={10} />
                {saving ? 'saving...' : 'save'}
              </button>
            )}
            <button
              onClick={fetchConfig}
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
      <div className="flex h-full flex-col overflow-hidden">
        {loading ? (
          <div className="flex flex-1 items-center justify-center text-xs text-fg-muted">
            <RefreshCw size={14} className="mr-2 animate-spin" />
            Loading config...
          </div>
        ) : (
          <>
            {activeTab === 'acp' && (
              <ACPSection config={acpConfig} onUpdate={updateACP} agents={agents} />
            )}
            {activeTab === 'agents' && (
              <AgentsSection
                agents={agents}
                onAdd={addAgent}
                onRemove={removeAgent}
                onUpdate={updateAgent}
              />
            )}
            {activeTab === 'bindings' && (
              <BindingsSection
                bindings={bindings}
                agents={agents}
                onAdd={addBinding}
                onRemove={removeBinding}
                onUpdate={updateBinding}
              />
            )}
            {activeTab === 'memory' && (
              <MemorySection agents={agents} client={client} />
            )}
          </>
        )}
      </div>
    </Dialog>
  );
}

/* ================================================================== */
/*  ACP Section                                                        */
/* ================================================================== */

function ACPSection({
  config,
  onUpdate,
  agents,
}: {
  config: ACPConfig;
  onUpdate: (patch: Partial<ACPConfig>) => void;
  agents: AgentDef[];
}) {
  return (
    <div className="flex-1 overflow-y-auto p-4">
      <div className="mx-auto max-w-2xl flex flex-col gap-5">
        {/* Enable toggle */}
        <div className="flex items-center justify-between border border-border-shell p-3">
          <div>
            <div className="text-xs font-medium text-fg-primary">Agent Control Plane</div>
            <div className="text-[10px] text-fg-muted">
              Enable multi-agent orchestration
            </div>
          </div>
          <button
            onClick={() => onUpdate({ enabled: !config.enabled })}
            className={config.enabled ? 'text-accent-primary' : 'text-fg-disabled'}
          >
            {config.enabled ? <ToggleRight size={20} /> : <ToggleLeft size={20} />}
          </button>
        </div>

        {/* Dispatch strategy */}
        <div>
          <label className="mb-1 block text-[9px] text-fg-muted uppercase">dispatch strategy</label>
          <select
            value={config.dispatch}
            onChange={(e) => onUpdate({ dispatch: e.target.value })}
            className="w-full max-w-xs border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary outline-none"
          >
            <option value="round-robin">round-robin</option>
            <option value="least-busy">least-busy</option>
            <option value="random">random</option>
            <option value="sticky">sticky</option>
          </select>
        </div>

        {/* Backend */}
        <div>
          <label className="mb-1 block text-[9px] text-fg-muted uppercase">backend</label>
          <select
            value={config.backend}
            onChange={(e) => onUpdate({ backend: e.target.value })}
            className="w-full max-w-xs border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary outline-none"
          >
            <option value="local">local</option>
            <option value="docker">docker</option>
            <option value="kubernetes">kubernetes</option>
          </select>
        </div>

        {/* Default agent */}
        <div>
          <label className="mb-1 block text-[9px] text-fg-muted uppercase">default agent</label>
          <select
            value={config.defaultAgent}
            onChange={(e) => onUpdate({ defaultAgent: e.target.value })}
            className="w-full max-w-xs border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary outline-none"
          >
            <option value="">-- none --</option>
            {agents.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name} ({a.id})
              </option>
            ))}
          </select>
        </div>

        {/* Allowed agents (multi-select) */}
        <div>
          <label className="mb-1 block text-[9px] text-fg-muted uppercase">allowed agents</label>
          <div className="flex flex-wrap gap-1">
            {agents.map((a) => {
              const isAllowed = config.allowedAgents.includes(a.id);
              return (
                <button
                  key={a.id}
                  onClick={() => {
                    onUpdate({
                      allowedAgents: isAllowed
                        ? config.allowedAgents.filter((id) => id !== a.id)
                        : [...config.allowedAgents, a.id],
                    });
                  }}
                  className={`border border-border-shell px-2 py-0.5 text-[10px] ${
                    isAllowed
                      ? 'bg-accent-primary-muted text-accent-primary'
                      : 'text-fg-muted hover:text-fg-secondary'
                  }`}
                >
                  {a.name}
                </button>
              );
            })}
            {agents.length === 0 && (
              <span className="text-[10px] text-fg-muted">No agents defined</span>
            )}
          </div>
        </div>

        {/* Max sessions */}
        <div>
          <label className="mb-1 block text-[9px] text-fg-muted uppercase">max sessions</label>
          <input
            type="number"
            min={1}
            max={100}
            value={config.maxSessions}
            onChange={(e) => onUpdate({ maxSessions: parseInt(e.target.value) || 1 })}
            className="w-24 border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary outline-none"
          />
        </div>

        {/* TTL */}
        <div>
          <label className="mb-1 block text-[9px] text-fg-muted uppercase">session TTL (seconds)</label>
          <input
            type="number"
            min={60}
            max={86400}
            value={config.ttl}
            onChange={(e) => onUpdate({ ttl: parseInt(e.target.value) || 3600 })}
            className="w-32 border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary outline-none"
          />
        </div>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Agents Section                                                     */
/* ================================================================== */

function AgentsSection({
  agents,
  onAdd,
  onRemove,
  onUpdate,
}: {
  agents: AgentDef[];
  onAdd: () => void;
  onRemove: (id: string) => void;
  onUpdate: (id: string, patch: Partial<AgentDef>) => void;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);

  return (
    <div className="flex h-full flex-col">
      {/* Toolbar */}
      <div className="flex items-center gap-2 border-b border-border-shell px-4 py-2">
        <button
          onClick={onAdd}
          className="flex items-center gap-1 border border-border-shell px-2 py-1 text-[10px] text-fg-muted hover:text-accent-primary"
        >
          <Plus size={10} />
          add agent
        </button>
        <div className="flex-1" />
        <span className="text-[10px] text-fg-muted">
          {agents.length} agent{agents.length !== 1 ? 's' : ''}
        </span>
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto">
        {agents.length === 0 ? (
          <div className="p-8 text-center text-xs text-fg-muted">No agents defined</div>
        ) : (
          agents.map((agent) => {
            const isExpanded = expanded === agent.id;
            return (
              <div key={agent.id} className="border-b border-border-shell">
                {/* Summary row */}
                <div
                  className="flex cursor-pointer items-center gap-3 px-4 py-2.5 hover:bg-surface-elevated"
                  onClick={() => setExpanded(isExpanded ? null : agent.id)}
                >
                  {isExpanded ? (
                    <ChevronDown size={12} className="text-fg-muted" />
                  ) : (
                    <ChevronRight size={12} className="text-fg-muted" />
                  )}
                  <span className="text-xs font-medium text-fg-primary">{agent.name}</span>
                  <span className="text-[10px] font-mono text-fg-muted">{agent.id}</span>
                  {agent.model && (
                    <span className="text-[10px] text-fg-tertiary">{agent.model}</span>
                  )}
                  {agent.sandbox && (
                    <span className="bg-surface-elevated px-1 py-0.5 text-[9px] text-fg-muted">
                      {agent.sandbox}
                    </span>
                  )}
                  <div className="flex-1" />
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onRemove(agent.id);
                    }}
                    className="text-fg-muted hover:text-status-error"
                    title="Remove"
                  >
                    <Trash2 size={11} />
                  </button>
                </div>

                {/* Expanded detail */}
                {isExpanded && (
                  <div className="border-t border-border-shell bg-surface-elevated px-4 py-3">
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="mb-1 block text-[9px] text-fg-muted uppercase">id</label>
                        <input
                          type="text"
                          value={agent.id}
                          onChange={(e) => onUpdate(agent.id, { id: e.target.value })}
                          className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs font-mono text-fg-primary outline-none"
                        />
                      </div>
                      <div>
                        <label className="mb-1 block text-[9px] text-fg-muted uppercase">name</label>
                        <input
                          type="text"
                          value={agent.name}
                          onChange={(e) => onUpdate(agent.id, { name: e.target.value })}
                          className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                        />
                      </div>
                      <div>
                        <label className="mb-1 block text-[9px] text-fg-muted uppercase">model</label>
                        <input
                          type="text"
                          value={agent.model}
                          onChange={(e) => onUpdate(agent.id, { model: e.target.value })}
                          placeholder="e.g. gpt-4o, claude-3-opus"
                          className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
                        />
                      </div>
                      <div>
                        <label className="mb-1 block text-[9px] text-fg-muted uppercase">sandbox</label>
                        <select
                          value={agent.sandbox ?? ''}
                          onChange={(e) => onUpdate(agent.id, { sandbox: e.target.value || undefined })}
                          className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                        >
                          <option value="">none</option>
                          <option value="docker">docker</option>
                          <option value="e2b">e2b</option>
                          <option value="firecracker">firecracker</option>
                        </select>
                      </div>
                    </div>
                    <div className="mt-3">
                      <label className="mb-1 block text-[9px] text-fg-muted uppercase">description</label>
                      <textarea
                        value={agent.description ?? ''}
                        onChange={(e) => onUpdate(agent.id, { description: e.target.value })}
                        rows={2}
                        className="w-full resize-y border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
                      />
                    </div>
                    <div className="mt-3">
                      <label className="mb-1 block text-[9px] text-fg-muted uppercase">
                        system prompt
                      </label>
                      <textarea
                        value={agent.systemPrompt ?? ''}
                        onChange={(e) => onUpdate(agent.id, { systemPrompt: e.target.value })}
                        rows={4}
                        className="w-full resize-y border border-border-shell bg-surface-card px-2 py-1 text-xs font-mono text-fg-primary placeholder:text-fg-placeholder outline-none"
                      />
                    </div>
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Bindings Section                                                   */
/* ================================================================== */

function BindingsSection({
  bindings,
  agents,
  onAdd,
  onRemove,
  onUpdate,
}: {
  bindings: BindingRule[];
  agents: AgentDef[];
  onAdd: () => void;
  onRemove: (id: string) => void;
  onUpdate: (id: string, patch: Partial<BindingRule>) => void;
}) {
  return (
    <div className="flex h-full flex-col">
      {/* Toolbar */}
      <div className="flex items-center gap-2 border-b border-border-shell px-4 py-2">
        <button
          onClick={onAdd}
          className="flex items-center gap-1 border border-border-shell px-2 py-1 text-[10px] text-fg-muted hover:text-accent-primary"
        >
          <Plus size={10} />
          add binding
        </button>
        <div className="flex-1" />
        <span className="text-[10px] text-fg-muted">
          {bindings.length} binding{bindings.length !== 1 ? 's' : ''}
        </span>
      </div>

      {/* Table header */}
      <div className="flex items-center gap-2 border-b border-border-shell bg-surface-card px-4 py-1.5 text-[10px] font-medium text-fg-muted uppercase">
        <span className="w-[25%]">agent</span>
        <span className="w-[20%]">channel</span>
        <span className="w-[20%]">account</span>
        <span className="flex-1">peer</span>
        <span className="w-10" />
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto">
        {bindings.length === 0 ? (
          <div className="p-8 text-center text-xs text-fg-muted">No bindings defined</div>
        ) : (
          bindings.map((binding) => (
            <div
              key={binding.id}
              className="flex items-center gap-2 border-b border-border-shell px-4 py-2 hover:bg-surface-elevated"
            >
              <div className="w-[25%]">
                <select
                  value={binding.agentId}
                  onChange={(e) => onUpdate(binding.id, { agentId: e.target.value })}
                  className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                >
                  <option value="">-- select --</option>
                  {agents.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
              </div>
              <div className="w-[20%]">
                <input
                  type="text"
                  value={binding.channel ?? ''}
                  onChange={(e) => onUpdate(binding.id, { channel: e.target.value })}
                  placeholder="*"
                  className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
                />
              </div>
              <div className="w-[20%]">
                <input
                  type="text"
                  value={binding.account ?? ''}
                  onChange={(e) => onUpdate(binding.id, { account: e.target.value })}
                  placeholder="*"
                  className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
                />
              </div>
              <div className="flex-1">
                <input
                  type="text"
                  value={binding.peer ?? ''}
                  onChange={(e) => onUpdate(binding.id, { peer: e.target.value })}
                  placeholder="*"
                  className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
                />
              </div>
              <div className="w-10 text-right">
                <button
                  onClick={() => onRemove(binding.id)}
                  className="text-fg-muted hover:text-status-error"
                  title="Remove"
                >
                  <Trash2 size={11} />
                </button>
              </div>
            </div>
          ))
        )}
      </div>

      <div className="border-t border-border-shell px-4 py-2 text-[10px] text-fg-muted">
        Route rules match channel, account, and peer patterns. Use * for wildcard. First match wins.
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Memory Section (per-agent MEMORY.md)                               */
/* ================================================================== */

function MemorySection({
  agents,
  client,
}: {
  agents: AgentDef[];
  client: any;
}) {
  const [selectedAgent, setSelectedAgent] = useState<string>(agents[0]?.id ?? '');
  const [content, setContent] = useState<string>('');
  const [loading, setLoading] = useState(false);

  const fetchMemory = useCallback(async (agentId: string) => {
    if (!agentId) {
      setContent('');
      return;
    }
    setLoading(true);
    try {
      await client.connect();
      const output = await client.executeCommandForOutput(
        `cat /home/node/.openclaw/agents/${agentId}/MEMORY.md 2>/dev/null || echo "(no MEMORY.md)"`,
      );
      setContent(output.trim());
    } catch (err: any) {
      setContent(`Error: ${err.message ?? 'Failed to load'}`);
    } finally {
      setLoading(false);
    }
  }, [client]);

  useEffect(() => {
    if (selectedAgent) fetchMemory(selectedAgent);
  }, [selectedAgent, fetchMemory]);

  // Default to first agent
  useEffect(() => {
    if (!selectedAgent && agents.length > 0) {
      setSelectedAgent(agents[0].id);
    }
  }, [agents, selectedAgent]);

  return (
    <div className="flex h-full flex-col">
      {/* Toolbar */}
      <div className="flex items-center gap-3 border-b border-border-shell px-4 py-2">
        <label className="text-[9px] text-fg-muted uppercase">agent</label>
        <select
          value={selectedAgent}
          onChange={(e) => setSelectedAgent(e.target.value)}
          className="border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
        >
          {agents.length === 0 && <option value="">-- no agents --</option>}
          {agents.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name} ({a.id})
            </option>
          ))}
        </select>
        <button
          onClick={() => fetchMemory(selectedAgent)}
          className="text-fg-muted hover:text-fg-secondary"
          title="Refresh"
        >
          <RefreshCw size={12} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {loading ? (
          <div className="flex items-center gap-2 text-xs text-fg-muted">
            <RefreshCw size={12} className="animate-spin" />
            Loading...
          </div>
        ) : !selectedAgent ? (
          <div className="flex h-full items-center justify-center text-xs text-fg-muted">
            Select an agent
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
    </div>
  );
}
