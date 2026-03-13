'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  X,
  RefreshCw,
  Clock,
  Webhook,
  Zap,
  BarChart3,
  Plus,
  Trash2,
  Play,
  ToggleLeft,
  ToggleRight,
  ChevronLeft,
  ChevronRight,
  Info,
} from 'lucide-react';
import { Dialog, DialogService } from '@/components/ui/Dialog';
import { ToastService } from '@/components/ui/Toast';
import { useTerminalStore } from '@/lib/stores/terminal-store';
import {
  type ScheduleFrequency,
  frequencyLabels,
  dayNames,
  buildCronExpression,
  describeCron,
  validateCron,
} from '@/lib/utils/cron-utils';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

interface CronJob {
  id: string;
  name: string;
  schedule: string;
  command: string;
  enabled: boolean;
  session?: string;
  deleteAfterRun?: boolean;
  lastRun?: string;
  nextRun?: string;
}

interface CronTemplate {
  name: string;
  description: string;
  schedule: string;
  command: string;
  emoji?: string;
}

interface Hook {
  id: string;
  name: string;
  emoji?: string;
  description: string;
  events: string[];
  enabled: boolean;
  source?: string;
}

type AutoTab = 'crons' | 'hooks' | 'webhooks' | 'polls';

const PAGE_SIZE = 14;

/* ------------------------------------------------------------------ */
/*  AutomationsDialog                                                  */
/* ------------------------------------------------------------------ */

interface AutomationsDialogProps {
  open: boolean;
  onClose: () => void;
}

export function AutomationsDialog({ open, onClose }: AutomationsDialogProps) {
  const client = useTerminalStore((s) => s.client);
  const [activeTab, setActiveTab] = useState<AutoTab>('crons');

  const handleClose = useCallback(() => {
    DialogService.close('automations');
    onClose();
  }, [onClose]);

  return (
    <Dialog
      id="automations"
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
              automations
            </span>
            <div className="flex items-center gap-1">
              {(['crons', 'hooks', 'webhooks', 'polls'] as AutoTab[]).map((tab) => {
                const Icon = { crons: Clock, hooks: Zap, webhooks: Webhook, polls: BarChart3 }[tab];
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
          <button onClick={handleClose} className="text-fg-muted hover:text-fg-primary">
            <X size={14} />
          </button>
        </div>
      }
    >
      <div className="flex h-full flex-col overflow-hidden">
        {activeTab === 'crons' && <CronsTab client={client} />}
        {activeTab === 'hooks' && <HooksTab client={client} />}
        {activeTab === 'webhooks' && <WebhooksTab />}
        {activeTab === 'polls' && <PollsTab client={client} />}
      </div>
    </Dialog>
  );
}

/* ================================================================== */
/*  Crons Tab                                                          */
/* ================================================================== */

function CronsTab({ client }: { client: any }) {
  const [crons, setCrons] = useState<CronJob[]>([]);
  const [templates, setTemplates] = useState<CronTemplate[]>([]);
  const [loading, setLoading] = useState(false);
  const [page, setPage] = useState(0);
  const [showAdd, setShowAdd] = useState(false);
  const [addMode, setAddMode] = useState<'simple' | 'cron'>('simple');

  // Simple mode state
  const [frequency, setFrequency] = useState<ScheduleFrequency>('dailyAt');
  const [interval, setInterval_] = useState(5);
  const [hour, setHour] = useState(9);
  const [minute, setMinute] = useState(0);
  const [selectedDays, setSelectedDays] = useState<boolean[]>(Array(7).fill(false));
  const [dayOfMonth, setDayOfMonth] = useState(1);

  // Cron mode state
  const [rawExpr, setRawExpr] = useState('');

  // Shared
  const [cronCommand, setCronCommand] = useState('');
  const [cronName, setCronName] = useState('');
  const [cronSession, setCronSession] = useState<'main' | 'isolated'>('main');
  const [deleteAfterRun, setDeleteAfterRun] = useState(false);

  /* ---------------------------------------------------------------- */
  /*  Fetch                                                            */
  /* ---------------------------------------------------------------- */

  const fetchCrons = useCallback(async () => {
    setLoading(true);
    try {
      await client.connect();
      const output = await client.executeCommandForOutput('cron list --json');
      try {
        const data = JSON.parse(output.trim());
        const list: CronJob[] = (Array.isArray(data) ? data : data.crons ?? []).map((c: any) => ({
          id: c.id,
          name: c.name ?? c.id,
          schedule: c.schedule ?? c.cron ?? '',
          command: c.command ?? '',
          enabled: c.enabled !== false,
          session: c.session,
          deleteAfterRun: c.deleteAfterRun ?? c.delete_after_run ?? false,
          lastRun: c.lastRun ?? c.last_run,
          nextRun: c.nextRun ?? c.next_run,
        }));
        setCrons(list);
      } catch {
        setCrons([]);
      }
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to load crons');
    } finally {
      setLoading(false);
    }
  }, [client]);

  const fetchTemplates = useCallback(async () => {
    try {
      await client.connect();
      const output = await client.executeCommandForOutput(
        'cat /home/node/.openclaw/cron-templates/*.json 2>/dev/null || echo "[]"',
      );
      try {
        // Multiple JSON files concatenated — try to parse as array
        const clean = '[' + output.replace(/\]\s*\[/g, ',').replace(/^\[/, '').replace(/\]$/, '') + ']';
        const data = JSON.parse(clean.trim() || '[]');
        const list: CronTemplate[] = (Array.isArray(data) ? data : []).map((t: any) => ({
          name: t.name ?? 'Unnamed',
          description: t.description ?? '',
          schedule: t.schedule ?? t.cron ?? '',
          command: t.command ?? '',
          emoji: t.emoji,
        }));
        setTemplates(list);
      } catch {
        setTemplates([]);
      }
    } catch {
      setTemplates([]);
    }
  }, [client]);

  useEffect(() => {
    fetchCrons();
    fetchTemplates();
  }, [fetchCrons, fetchTemplates]);

  /* ---------------------------------------------------------------- */
  /*  Actions                                                          */
  /* ---------------------------------------------------------------- */

  const addCron = useCallback(async () => {
    const schedule = addMode === 'simple'
      ? buildCronExpression({ frequency, interval, hour, minute, selectedDays, dayOfMonth })
      : rawExpr.trim();

    if (!schedule) {
      ToastService.showError('Schedule is required');
      return;
    }
    if (!cronCommand.trim()) {
      ToastService.showError('Command is required');
      return;
    }

    const validation = validateCron(schedule);
    if (validation) {
      ToastService.showError(validation);
      return;
    }

    let cmd = `cron add "${schedule}" "${cronCommand.trim()}"`;
    if (cronSession === 'isolated') cmd += ' --session isolated';
    if (deleteAfterRun) cmd += ' --delete-after-run';
    if (cronName.trim()) cmd += ` --name "${cronName.trim()}"`;

    try {
      await client.connect();
      await client.executeCommandForOutput(cmd);
      ToastService.showInfo('Cron added');
      setShowAdd(false);
      setCronCommand('');
      setCronName('');
      setRawExpr('');
      fetchCrons();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to add cron');
    }
  }, [
    addMode, frequency, interval, hour, minute, selectedDays, dayOfMonth,
    rawExpr, cronCommand, cronName, cronSession, deleteAfterRun, client, fetchCrons,
  ]);

  const toggleCron = useCallback(async (id: string, enabled: boolean) => {
    try {
      await client.connect();
      await client.executeCommandForOutput(`cron ${enabled ? 'disable' : 'enable'} ${id}`);
      fetchCrons();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to toggle cron');
    }
  }, [client, fetchCrons]);

  const deleteCron = useCallback(async (id: string) => {
    try {
      await client.connect();
      await client.executeCommandForOutput(`cron delete ${id}`);
      ToastService.showInfo('Cron deleted');
      fetchCrons();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to delete cron');
    }
  }, [client, fetchCrons]);

  const runCron = useCallback(async (id: string) => {
    try {
      await client.connect();
      await client.executeCommandForOutput(`cron run ${id}`);
      ToastService.showInfo('Cron triggered');
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to run cron');
    }
  }, [client]);

  const applyTemplate = useCallback((t: CronTemplate) => {
    setCronCommand(t.command);
    setCronName(t.name);
    setAddMode('cron');
    setRawExpr(t.schedule);
    setShowAdd(true);
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Pagination                                                       */
  /* ---------------------------------------------------------------- */

  const allItems = useMemo(() => [...crons], [crons]);
  const totalPages = Math.max(1, Math.ceil(allItems.length / PAGE_SIZE));
  const pageItems = allItems.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);

  /* ---------------------------------------------------------------- */
  /*  Live preview                                                     */
  /* ---------------------------------------------------------------- */

  const previewExpr = addMode === 'simple'
    ? buildCronExpression({ frequency, interval, hour, minute, selectedDays, dayOfMonth })
    : rawExpr.trim();
  const previewDesc = previewExpr ? describeCron(previewExpr) : '';

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  return (
    <div className="flex h-full flex-col">
      {/* Toolbar */}
      <div className="flex items-center gap-2 border-b border-border-shell px-4 py-2">
        <button
          onClick={() => setShowAdd(!showAdd)}
          className="flex items-center gap-1 border border-border-shell px-2 py-1 text-[10px] text-fg-muted hover:text-accent-primary"
        >
          <Plus size={10} />
          add cron
        </button>
        <button
          onClick={fetchCrons}
          className="text-fg-muted hover:text-fg-secondary"
          title="Refresh"
        >
          <RefreshCw size={12} className={loading ? 'animate-spin' : ''} />
        </button>
        <div className="flex-1" />
        <span className="text-[10px] text-fg-muted">
          {crons.length} cron{crons.length !== 1 ? 's' : ''}
        </span>
      </div>

      {/* Add cron form */}
      {showAdd && (
        <div className="border-b border-border-shell bg-surface-elevated px-4 py-3">
          <div className="flex items-center gap-3 mb-3">
            <span className="text-[10px] font-medium text-fg-secondary uppercase">new cron</span>
            <div className="flex items-center gap-1">
              <button
                onClick={() => setAddMode('simple')}
                className={`px-2 py-0.5 text-[10px] border border-border-shell ${
                  addMode === 'simple' ? 'bg-accent-primary-muted text-accent-primary' : 'text-fg-muted'
                }`}
              >
                simple
              </button>
              <button
                onClick={() => setAddMode('cron')}
                className={`px-2 py-0.5 text-[10px] border border-border-shell ${
                  addMode === 'cron' ? 'bg-accent-primary-muted text-accent-primary' : 'text-fg-muted'
                }`}
              >
                cron
              </button>
            </div>
          </div>

          {addMode === 'simple' ? (
            <div className="flex flex-wrap items-start gap-3 mb-3">
              {/* Frequency */}
              <div>
                <label className="mb-1 block text-[9px] text-fg-muted uppercase">frequency</label>
                <select
                  value={frequency}
                  onChange={(e) => setFrequency(e.target.value as ScheduleFrequency)}
                  className="border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                >
                  {Object.entries(frequencyLabels).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
              </div>
              {/* Interval (for everyN*) */}
              {(frequency === 'everyNMinutes' || frequency === 'everyNHours' || frequency === 'inNMinutes') && (
                <div>
                  <label className="mb-1 block text-[9px] text-fg-muted uppercase">interval</label>
                  <input
                    type="number"
                    min={1}
                    max={1440}
                    value={interval}
                    onChange={(e) => setInterval_(parseInt(e.target.value) || 1)}
                    className="w-16 border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                  />
                </div>
              )}
              {/* Time (for daily/weekly/monthly) */}
              {(frequency === 'dailyAt' || frequency === 'weeklyOn' || frequency === 'monthlyOn') && (
                <div className="flex gap-2">
                  <div>
                    <label className="mb-1 block text-[9px] text-fg-muted uppercase">hour</label>
                    <input
                      type="number"
                      min={0}
                      max={23}
                      value={hour}
                      onChange={(e) => setHour(parseInt(e.target.value) || 0)}
                      className="w-14 border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-[9px] text-fg-muted uppercase">minute</label>
                    <input
                      type="number"
                      min={0}
                      max={59}
                      value={minute}
                      onChange={(e) => setMinute(parseInt(e.target.value) || 0)}
                      className="w-14 border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                    />
                  </div>
                </div>
              )}
              {/* Day selector for weekly */}
              {frequency === 'weeklyOn' && (
                <div>
                  <label className="mb-1 block text-[9px] text-fg-muted uppercase">days</label>
                  <div className="flex gap-1">
                    {dayNames.map((d, i) => (
                      <button
                        key={d}
                        onClick={() => {
                          const next = [...selectedDays];
                          next[i] = !next[i];
                          setSelectedDays(next);
                        }}
                        className={`border border-border-shell px-1.5 py-0.5 text-[10px] ${
                          selectedDays[i]
                            ? 'bg-accent-primary-muted text-accent-primary'
                            : 'text-fg-muted'
                        }`}
                      >
                        {d}
                      </button>
                    ))}
                  </div>
                </div>
              )}
              {/* Day of month for monthly */}
              {frequency === 'monthlyOn' && (
                <div>
                  <label className="mb-1 block text-[9px] text-fg-muted uppercase">day of month</label>
                  <input
                    type="number"
                    min={1}
                    max={31}
                    value={dayOfMonth}
                    onChange={(e) => setDayOfMonth(parseInt(e.target.value) || 1)}
                    className="w-14 border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
                  />
                </div>
              )}
            </div>
          ) : (
            <div className="mb-3">
              <label className="mb-1 block text-[9px] text-fg-muted uppercase">cron expression</label>
              <input
                type="text"
                value={rawExpr}
                onChange={(e) => setRawExpr(e.target.value)}
                placeholder="*/5 * * * *"
                className="w-full max-w-xs border border-border-shell bg-surface-card px-2 py-1 text-xs font-mono text-fg-primary placeholder:text-fg-placeholder outline-none"
              />
            </div>
          )}

          {/* Preview */}
          {previewDesc && (
            <div className="mb-3 text-[10px] text-fg-tertiary">
              <span className="text-fg-muted">Schedule:</span> {previewExpr}{' '}
              <span className="text-accent-primary">({previewDesc})</span>
            </div>
          )}

          {/* Command + options */}
          <div className="flex flex-wrap items-end gap-3 mb-3">
            <div className="flex-1 min-w-[200px]">
              <label className="mb-1 block text-[9px] text-fg-muted uppercase">command</label>
              <input
                type="text"
                value={cronCommand}
                onChange={(e) => setCronCommand(e.target.value)}
                placeholder="e.g. check my email and summarize"
                className="w-full border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
              />
            </div>
            <div>
              <label className="mb-1 block text-[9px] text-fg-muted uppercase">name</label>
              <input
                type="text"
                value={cronName}
                onChange={(e) => setCronName(e.target.value)}
                placeholder="optional"
                className="w-32 border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
              />
            </div>
            <div>
              <label className="mb-1 block text-[9px] text-fg-muted uppercase">session</label>
              <select
                value={cronSession}
                onChange={(e) => setCronSession(e.target.value as 'main' | 'isolated')}
                className="border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none"
              >
                <option value="main">main</option>
                <option value="isolated">isolated</option>
              </select>
            </div>
            <label className="flex items-center gap-1 text-[10px] text-fg-muted cursor-pointer">
              <input
                type="checkbox"
                checked={deleteAfterRun}
                onChange={(e) => setDeleteAfterRun(e.target.checked)}
                className="accent-[var(--accent-primary)]"
              />
              delete after run
            </label>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={addCron}
              className="border border-accent-primary px-3 py-1 text-[10px] text-accent-primary hover:bg-accent-primary-muted"
            >
              add
            </button>
            <button
              onClick={() => setShowAdd(false)}
              className="px-3 py-1 text-[10px] text-fg-muted hover:text-fg-secondary"
            >
              cancel
            </button>
          </div>
        </div>
      )}

      {/* Cron list */}
      <div className="flex-1 overflow-y-auto">
        {/* Header */}
        <div className="sticky top-0 flex items-center gap-2 border-b border-border-shell bg-surface-card px-4 py-1.5 text-[10px] font-medium text-fg-muted uppercase">
          <span className="w-8" />
          <span className="w-[20%]">name</span>
          <span className="w-[20%]">schedule</span>
          <span className="flex-1">command</span>
          <span className="w-24 text-right">actions</span>
        </div>

        {loading && pageItems.length === 0 ? (
          <div className="p-8 text-center text-xs text-fg-muted">Loading...</div>
        ) : pageItems.length === 0 ? (
          <div className="p-8 text-center text-xs text-fg-muted">No crons configured</div>
        ) : (
          pageItems.map((cron) => (
            <div
              key={cron.id}
              className="flex items-center gap-2 border-b border-border-shell px-4 py-2 hover:bg-surface-elevated"
            >
              <div className="w-8">
                <button
                  onClick={() => toggleCron(cron.id, cron.enabled)}
                  className={cron.enabled ? 'text-accent-primary' : 'text-fg-disabled'}
                  title={cron.enabled ? 'Disable' : 'Enable'}
                >
                  {cron.enabled ? <ToggleRight size={14} /> : <ToggleLeft size={14} />}
                </button>
              </div>
              <span className="w-[20%] truncate text-xs text-fg-primary">{cron.name}</span>
              <div className="w-[20%]">
                <span className="block truncate text-xs font-mono text-fg-secondary">
                  {cron.schedule}
                </span>
                <span className="block truncate text-[9px] text-fg-muted">
                  {describeCron(cron.schedule)}
                </span>
              </div>
              <span className="flex-1 truncate text-xs text-fg-tertiary">{cron.command}</span>
              <div className="flex w-24 items-center justify-end gap-2">
                <button
                  onClick={() => runCron(cron.id)}
                  className="text-fg-muted hover:text-accent-primary"
                  title="Run now"
                >
                  <Play size={11} />
                </button>
                <button
                  onClick={() => deleteCron(cron.id)}
                  className="text-fg-muted hover:text-status-error"
                  title="Delete"
                >
                  <Trash2 size={11} />
                </button>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Templates section */}
      {templates.length > 0 && (
        <div className="border-t border-border-shell">
          <div className="px-4 py-1.5 text-[10px] font-medium text-fg-muted uppercase">
            templates
          </div>
          <div className="max-h-32 overflow-y-auto">
            {templates.map((t, i) => (
              <button
                key={i}
                onClick={() => applyTemplate(t)}
                className="flex w-full items-center gap-2 px-4 py-1.5 text-left hover:bg-surface-elevated"
              >
                <span className="text-sm">{t.emoji ?? '⏰'}</span>
                <div className="flex-1 min-w-0">
                  <span className="block truncate text-xs text-fg-primary">{t.name}</span>
                  <span className="block truncate text-[10px] text-fg-muted">{t.description}</span>
                </div>
                <span className="text-[9px] font-mono text-fg-muted">{t.schedule}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-2 border-t border-border-shell py-1.5">
          <button
            onClick={() => setPage((p) => Math.max(0, p - 1))}
            disabled={page === 0}
            className="text-fg-muted hover:text-fg-secondary disabled:text-fg-disabled"
          >
            <ChevronLeft size={12} />
          </button>
          <span className="text-[10px] text-fg-muted">
            {page + 1} / {totalPages}
          </span>
          <button
            onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
            disabled={page >= totalPages - 1}
            className="text-fg-muted hover:text-fg-secondary disabled:text-fg-disabled"
          >
            <ChevronRight size={12} />
          </button>
        </div>
      )}
    </div>
  );
}

/* ================================================================== */
/*  Hooks Tab                                                          */
/* ================================================================== */

function HooksTab({ client }: { client: any }) {
  const [hooks, setHooks] = useState<Hook[]>([]);
  const [loading, setLoading] = useState(false);

  const fetchHooks = useCallback(async () => {
    setLoading(true);
    try {
      await client.connect();
      const output = await client.executeCommandForOutput('hooks list --json');
      try {
        const data = JSON.parse(output.trim());
        const list: Hook[] = (Array.isArray(data) ? data : data.hooks ?? []).map((h: any) => ({
          id: h.id,
          name: h.name ?? h.id,
          emoji: h.emoji,
          description: h.description ?? '',
          events: h.events ?? h.triggerEvents ?? [],
          enabled: h.enabled !== false,
          source: h.source,
        }));
        setHooks(list);
      } catch {
        setHooks([]);
      }
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to load hooks');
    } finally {
      setLoading(false);
    }
  }, [client]);

  useEffect(() => {
    fetchHooks();
  }, [fetchHooks]);

  const toggleHook = useCallback(async (id: string, enabled: boolean) => {
    try {
      await client.connect();
      await client.executeCommandForOutput(`hooks ${enabled ? 'disable' : 'enable'} ${id}`);
      fetchHooks();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to toggle hook');
    }
  }, [client, fetchHooks]);

  return (
    <div className="flex h-full flex-col">
      {/* Toolbar */}
      <div className="flex items-center gap-2 border-b border-border-shell px-4 py-2">
        <button
          onClick={fetchHooks}
          className="text-fg-muted hover:text-fg-secondary"
          title="Refresh"
        >
          <RefreshCw size={12} className={loading ? 'animate-spin' : ''} />
        </button>
        <div className="flex-1" />
        <span className="text-[10px] text-fg-muted">
          {hooks.length} hook{hooks.length !== 1 ? 's' : ''}
        </span>
      </div>

      {/* Table */}
      <div className="flex-1 overflow-y-auto">
        <div className="sticky top-0 flex items-center gap-2 border-b border-border-shell bg-surface-card px-4 py-1.5 text-[10px] font-medium text-fg-muted uppercase">
          <span className="w-8" />
          <span className="w-8" />
          <span className="w-[20%]">name</span>
          <span className="flex-1">description</span>
          <span className="w-[25%]">events</span>
          <span className="w-16 text-right">toggle</span>
        </div>

        {loading && hooks.length === 0 ? (
          <div className="p-8 text-center text-xs text-fg-muted">Loading...</div>
        ) : hooks.length === 0 ? (
          <div className="p-8 text-center text-xs text-fg-muted">No hooks configured</div>
        ) : (
          hooks.map((hook) => (
            <div
              key={hook.id}
              className="flex items-center gap-2 border-b border-border-shell px-4 py-2 hover:bg-surface-elevated"
            >
              <div className="w-8">
                <button
                  onClick={() => toggleHook(hook.id, hook.enabled)}
                  className={hook.enabled ? 'text-accent-primary' : 'text-fg-disabled'}
                >
                  {hook.enabled ? <ToggleRight size={14} /> : <ToggleLeft size={14} />}
                </button>
              </div>
              <span className="w-8 text-center text-sm">{hook.emoji ?? '⚡'}</span>
              <span className="w-[20%] truncate text-xs text-fg-primary">{hook.name}</span>
              <span className="flex-1 truncate text-xs text-fg-tertiary">{hook.description}</span>
              <div className="flex w-[25%] flex-wrap gap-1">
                {hook.events.map((ev, i) => (
                  <span
                    key={i}
                    className="bg-surface-elevated px-1 py-0.5 text-[9px] text-fg-muted"
                  >
                    {ev}
                  </span>
                ))}
              </div>
              <div className="w-16 text-right">
                <span className={`text-[10px] ${hook.enabled ? 'text-accent-primary' : 'text-fg-disabled'}`}>
                  {hook.enabled ? 'on' : 'off'}
                </span>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Webhooks Tab (static docs)                                         */
/* ================================================================== */

function WebhooksTab() {
  const endpoints = [
    {
      name: 'Wake',
      method: 'POST',
      path: '/__openclaw__/webhook/wake',
      description: 'Wakes the agent with a message. Body: { "message": "..." }',
    },
    {
      name: 'Agent',
      method: 'POST',
      path: '/__openclaw__/webhook/agent',
      description: 'Sends directly to the agent. Body: { "message": "...", "sessionKey": "..." }',
    },
    {
      name: 'Mapped',
      method: 'POST',
      path: '/__openclaw__/webhook/<name>',
      description: 'Custom webhooks mapped to specific commands or sessions. Configure in agent settings.',
    },
  ];

  return (
    <div className="flex h-full flex-col">
      <div className="border-b border-border-shell px-4 py-2 text-[10px] text-fg-muted">
        HTTP endpoints that external services can call to trigger agent actions.
      </div>
      <div className="flex-1 overflow-y-auto p-4">
        <div className="flex flex-col gap-4">
          {endpoints.map((ep) => (
            <div key={ep.name} className="border border-border-shell p-3">
              <div className="mb-2 flex items-center gap-2">
                <span className="bg-accent-primary-muted px-1.5 py-0.5 text-[10px] font-medium text-accent-primary">
                  {ep.method}
                </span>
                <span className="text-xs font-mono text-fg-primary">{ep.path}</span>
              </div>
              <p className="text-xs text-fg-tertiary">{ep.description}</p>
            </div>
          ))}
        </div>

        <div className="mt-6 border border-border-shell p-3">
          <div className="mb-2 text-xs font-medium text-fg-secondary">Authentication</div>
          <p className="text-xs text-fg-tertiary">
            Include the gateway token in the <code className="bg-surface-code-inline px-1 text-fg-primary">Authorization</code> header
            as <code className="bg-surface-code-inline px-1 text-fg-primary">Bearer &lt;token&gt;</code>.
          </p>
        </div>

        <div className="mt-4 border border-border-shell p-3">
          <div className="mb-2 text-xs font-medium text-fg-secondary">Example</div>
          <pre className="overflow-x-auto bg-surface-code-inline p-2 text-[10px] font-mono text-fg-secondary leading-relaxed">
{`curl -X POST /__openclaw__/webhook/wake \\
  -H "Authorization: Bearer <token>" \\
  -H "Content-Type: application/json" \\
  -d '{"message": "Check system health"}'`}
          </pre>
        </div>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Polls Tab                                                          */
/* ================================================================== */

function PollsTab({ client }: { client: any }) {
  const [channel, setChannel] = useState('');
  const [recipient, setRecipient] = useState('');
  const [question, setQuestion] = useState('');
  const [options, setOptions] = useState('');
  const [multiSelect, setMultiSelect] = useState(false);
  const [sending, setSending] = useState(false);

  const sendPoll = useCallback(async () => {
    if (!channel.trim() || !question.trim() || !options.trim()) {
      ToastService.showError('Channel, question, and options are required');
      return;
    }

    let cmd = `message poll --channel "${channel.trim()}" --to "${recipient.trim()}" --question "${question.trim()}" --options "${options.trim()}"`;
    if (multiSelect) cmd += ' --multi-select';

    setSending(true);
    try {
      await client.connect();
      const output = await client.executeCommandForOutput(cmd);
      ToastService.showInfo('Poll sent');
      setQuestion('');
      setOptions('');
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to send poll');
    } finally {
      setSending(false);
    }
  }, [channel, recipient, question, options, multiSelect, client]);

  return (
    <div className="flex h-full flex-col">
      <div className="border-b border-border-shell px-4 py-2 text-[10px] text-fg-muted">
        Send interactive polls via messaging channels (WhatsApp, Telegram, etc.)
      </div>
      <div className="flex-1 overflow-y-auto p-4">
        <div className="mx-auto max-w-md flex flex-col gap-4">
          <div>
            <label className="mb-1 block text-[9px] text-fg-muted uppercase">channel</label>
            <input
              type="text"
              value={channel}
              onChange={(e) => setChannel(e.target.value)}
              placeholder="e.g. whatsapp, telegram"
              className="w-full border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-[9px] text-fg-muted uppercase">recipient</label>
            <input
              type="text"
              value={recipient}
              onChange={(e) => setRecipient(e.target.value)}
              placeholder="phone or username"
              className="w-full border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-[9px] text-fg-muted uppercase">question</label>
            <input
              type="text"
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder="What should we focus on today?"
              className="w-full border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-[9px] text-fg-muted uppercase">
              options (comma-separated)
            </label>
            <input
              type="text"
              value={options}
              onChange={(e) => setOptions(e.target.value)}
              placeholder="Option A, Option B, Option C"
              className="w-full border border-border-shell bg-surface-card px-3 py-2 text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
            />
          </div>
          <label className="flex items-center gap-2 text-[10px] text-fg-muted cursor-pointer">
            <input
              type="checkbox"
              checked={multiSelect}
              onChange={(e) => setMultiSelect(e.target.checked)}
              className="accent-[var(--accent-primary)]"
            />
            allow multi-select
          </label>
          <button
            onClick={sendPoll}
            disabled={sending}
            className="border border-accent-primary px-4 py-2 text-xs text-accent-primary hover:bg-accent-primary-muted disabled:opacity-50"
          >
            {sending ? 'sending...' : 'send poll'}
          </button>
        </div>
      </div>
    </div>
  );
}
