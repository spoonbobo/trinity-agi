'use client';

import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  Users,
  FileText,
  HeartPulse,
  ShieldCheck,
  MonitorDot,
  Server,
  Variable,
  Radio,
  Bot,
  ChevronDown,
  ChevronRight,
  Plus,
  Trash2,
  Download,
  RefreshCw,
  Check,
  X,
  Search,
  Filter,
  Terminal,
  AlertCircle,
  Loader2,
} from 'lucide-react';
import { useAuthStore } from '@/lib/stores/auth-store';
import { useTerminalStore } from '@/lib/stores/terminal-store';
import { useGatewayStore } from '@/lib/stores/gateway-store';
import { useThemeStore } from '@/lib/stores/theme-store';
import { Permissions } from '@/lib/utils/rbac-constants';
import { tr } from '@/lib/i18n/translations';
import { Dialog, DialogService } from '@/components/ui/Dialog';
import { ToastService } from '@/components/ui/Toast';
import type { AuthRole, AuditLogResult } from '@/lib/clients/auth-client';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

type AdminTab =
  | 'users'
  | 'audit'
  | 'health'
  | 'rbac'
  | 'sessions'
  | 'openclaws'
  | 'env'
  | 'channels'
  | 'copilot';

interface TabDef {
  id: AdminTab;
  label: string;
  icon: React.ReactNode;
  superadminOnly?: boolean;
}

/* ------------------------------------------------------------------ */
/*  AdminDialog                                                        */
/* ------------------------------------------------------------------ */

export function AdminDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const language = useThemeStore((s) => s.language);
  const role = useAuthStore((s) => s.role);
  const isSuperadmin = role === 'superadmin';

  const [activeTab, setActiveTab] = useState<AdminTab>('users');

  const tabs: TabDef[] = useMemo(
    () => [
      { id: 'users', label: tr(language, 'users'), icon: <Users size={12} /> },
      { id: 'audit', label: tr(language, 'audit'), icon: <FileText size={12} /> },
      { id: 'health', label: tr(language, 'health'), icon: <HeartPulse size={12} /> },
      { id: 'rbac', label: tr(language, 'rbac'), icon: <ShieldCheck size={12} /> },
      { id: 'sessions', label: tr(language, 'sessions'), icon: <MonitorDot size={12} /> },
      { id: 'openclaws', label: tr(language, 'openclaws'), icon: <Server size={12} />, superadminOnly: true },
      { id: 'env', label: tr(language, 'environment'), icon: <Variable size={12} /> },
      { id: 'channels', label: tr(language, 'channels'), icon: <Radio size={12} /> },
      { id: 'copilot', label: tr(language, 'copilot'), icon: <Bot size={12} /> },
    ],
    [language],
  );

  const visibleTabs = useMemo(
    () => tabs.filter((t) => !t.superadminOnly || isSuperadmin),
    [tabs, isSuperadmin],
  );

  return (
    <Dialog
      id="admin"
      open={open}
      onClose={onClose}
      title="ADMIN"
      width="86%"
      height="84%"
      maxWidth="1060px"
      maxHeight="780px"
    >
      <div className="flex h-full flex-col">
        {/* Tab bar */}
        <div className="flex shrink-0 items-center gap-1 overflow-x-auto border-b border-border-shell px-3 py-1">
          {visibleTabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-1.5 px-2.5 py-1 text-[11px] transition-colors ${
                activeTab === tab.id
                  ? 'text-accent-primary'
                  : 'text-fg-muted hover:text-fg-secondary'
              }`}
            >
              {tab.icon}
              <span className="uppercase tracking-wide">{tab.label}</span>
            </button>
          ))}
        </div>

        {/* Tab content */}
        <div className="flex-1 overflow-auto p-4">
          {activeTab === 'users' && <UsersTab />}
          {activeTab === 'audit' && <AuditTab />}
          {activeTab === 'health' && <HealthTab />}
          {activeTab === 'rbac' && <RBACTab />}
          {activeTab === 'sessions' && <SessionsTab />}
          {activeTab === 'openclaws' && <OpenClawsTab />}
          {activeTab === 'env' && <EnvTab />}
          {activeTab === 'channels' && <ChannelsTab />}
          {activeTab === 'copilot' && <CopilotTab />}
        </div>
      </div>
    </Dialog>
  );
}

/* ================================================================== */
/*  USERS TAB                                                          */
/* ================================================================== */

interface UserRow {
  id: string;
  email: string;
  role: string;
  created_at?: string;
  granted_at?: string;
}

function UsersTab() {
  const authClient = useAuthStore((s) => s.client);
  const currentRole = useAuthStore((s) => s.role);
  const [users, setUsers] = useState<UserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [assigning, setAssigning] = useState<string | null>(null);

  const fetchUsers = useCallback(async () => {
    setLoading(true);
    try {
      const data = await authClient.fetchUsers();
      setUsers(data);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to fetch users');
    } finally {
      setLoading(false);
    }
  }, [authClient]);

  useEffect(() => {
    fetchUsers();
  }, [fetchUsers]);

  const assignRole = useCallback(
    async (userId: string, role: string) => {
      setAssigning(userId);
      try {
        await authClient.assignUserRole(userId, role);
        ToastService.showInfo(`Role updated to ${role}`);
        await fetchUsers();
      } catch (err: any) {
        ToastService.showError(err.message ?? 'Failed to assign role');
      } finally {
        setAssigning(null);
      }
    },
    [authClient, fetchUsers],
  );

  const assignableRoles: AuthRole[] =
    currentRole === 'superadmin' ? ['guest', 'user', 'admin', 'superadmin'] : ['guest', 'user', 'admin'];

  if (loading) return <LoadingSpinner />;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-fg-secondary">
          {users.length} user{users.length !== 1 ? 's' : ''}
        </span>
        <button
          onClick={fetchUsers}
          className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
        >
          <RefreshCw size={10} />
          refresh
        </button>
      </div>

      <div className="border border-border-shell">
        {/* Header */}
        <div className="grid grid-cols-[1fr_120px_140px_160px] gap-2 border-b border-border-shell bg-surface-base px-3 py-1.5">
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">email</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">role</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">date</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">assign</span>
        </div>

        {/* Rows */}
        {users.map((user) => (
          <div
            key={user.id}
            className="grid grid-cols-[1fr_120px_140px_160px] gap-2 border-b border-border-shell px-3 py-1.5 last:border-b-0 hover:bg-surface-elevated"
          >
            <span className="truncate text-xs text-fg-primary">{user.email ?? user.id}</span>
            <span
              className={`text-xs ${
                user.role === 'superadmin'
                  ? 'text-status-warning'
                  : user.role === 'admin'
                    ? 'text-accent-primary'
                    : 'text-fg-secondary'
              }`}
            >
              {user.role}
            </span>
            <span className="text-[10px] text-fg-muted">
              {user.granted_at ?? user.created_at
                ? new Date(user.granted_at ?? user.created_at!).toLocaleDateString()
                : '-'}
            </span>
            <div className="flex items-center gap-1">
              {assignableRoles
                .filter((r) => r !== user.role)
                .map((r) => (
                  <button
                    key={r}
                    onClick={() => assignRole(user.id, r)}
                    disabled={assigning === user.id}
                    className="border border-border-shell px-1.5 py-0.5 text-[9px] text-fg-muted hover:text-accent-primary hover:border-accent-primary disabled:opacity-40"
                  >
                    {r}
                  </button>
                ))}
            </div>
          </div>
        ))}

        {users.length === 0 && (
          <div className="p-6 text-center text-xs text-fg-muted">No users found</div>
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  AUDIT TAB                                                          */
/* ================================================================== */

interface AuditFilters {
  action: string;
  userId: string;
  resource: string;
  ip: string;
  from: string;
  to: string;
}

const AUDIT_PAGE_SIZE = 50;

function AuditTab() {
  const authClient = useAuthStore((s) => s.client);
  const [logs, setLogs] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [showFilters, setShowFilters] = useState(false);
  const [expandedRow, setExpandedRow] = useState<string | null>(null);
  const [filters, setFilters] = useState<AuditFilters>({
    action: '',
    userId: '',
    resource: '',
    ip: '',
    from: '',
    to: '',
  });

  const fetchLogs = useCallback(async () => {
    setLoading(true);
    try {
      const params: Record<string, any> = {
        limit: AUDIT_PAGE_SIZE,
        offset: page * AUDIT_PAGE_SIZE,
      };
      if (filters.action) params.action = filters.action;
      if (filters.userId) params.userId = filters.userId;
      if (filters.resource) params.resource = filters.resource;
      if (filters.ip) params.ip = filters.ip;
      if (filters.from) params.from = filters.from;
      if (filters.to) params.to = filters.to;

      const result = await authClient.fetchAuditLog(params);
      setLogs(result.logs);
      setTotal(result.total);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to fetch audit logs');
    } finally {
      setLoading(false);
    }
  }, [authClient, page, filters]);

  useEffect(() => {
    fetchLogs();
  }, [fetchLogs]);

  const totalPages = Math.max(1, Math.ceil(total / AUDIT_PAGE_SIZE));

  const activeFilterParams = useMemo(() => {
    const params: Record<string, string> = {};
    if (filters.action) params.action = filters.action;
    if (filters.userId) params.user_id = filters.userId;
    if (filters.resource) params.resource = filters.resource;
    if (filters.ip) params.ip = filters.ip;
    if (filters.from) params.from = filters.from;
    if (filters.to) params.to = filters.to;
    return params;
  }, [filters]);

  const exportCsvUrl = authClient.getAuditExportUrl('csv', activeFilterParams);
  const exportJsonUrl = authClient.getAuditExportUrl('json', activeFilterParams);

  return (
    <div className="flex flex-col gap-3">
      {/* Header row */}
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-fg-secondary">
          {total} log{total !== 1 ? 's' : ''}
        </span>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowFilters(!showFilters)}
            className={`flex items-center gap-1 text-[10px] ${showFilters ? 'text-accent-primary' : 'text-fg-muted hover:text-fg-secondary'}`}
          >
            <Filter size={10} />
            filters
          </button>
          <a
            href={exportCsvUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
          >
            <Download size={10} />
            csv
          </a>
          <a
            href={exportJsonUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
          >
            <Download size={10} />
            json
          </a>
          <button
            onClick={fetchLogs}
            className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
          >
            <RefreshCw size={10} />
          </button>
        </div>
      </div>

      {/* Filters panel */}
      {showFilters && (
        <div className="grid grid-cols-3 gap-2 border border-border-shell bg-surface-base p-3">
          {(['action', 'userId', 'resource', 'ip', 'from', 'to'] as const).map((key) => (
            <div key={key} className="flex flex-col gap-0.5">
              <label className="text-[9px] uppercase tracking-wide text-fg-muted">{key}</label>
              <input
                type={key === 'from' || key === 'to' ? 'date' : 'text'}
                value={filters[key]}
                onChange={(e) => {
                  setFilters((f) => ({ ...f, [key]: e.target.value }));
                  setPage(0);
                }}
                className="border border-border-shell bg-surface-card px-2 py-1 text-[11px] text-fg-primary outline-none focus:border-accent-primary"
                placeholder={key}
              />
            </div>
          ))}
        </div>
      )}

      {/* Table */}
      {loading ? (
        <LoadingSpinner />
      ) : (
        <div className="border border-border-shell">
          <div className="grid grid-cols-[140px_100px_1fr_120px_120px] gap-2 border-b border-border-shell bg-surface-base px-3 py-1.5">
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">timestamp</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">action</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">resource</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">user</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">ip</span>
          </div>
          {logs.map((log, i) => {
            const rowId = log.id ?? `${i}`;
            const isExpanded = expandedRow === rowId;
            return (
              <div key={rowId}>
                <div
                  onClick={() => setExpandedRow(isExpanded ? null : rowId)}
                  className="grid cursor-pointer grid-cols-[140px_100px_1fr_120px_120px] gap-2 border-b border-border-shell px-3 py-1.5 last:border-b-0 hover:bg-surface-elevated"
                >
                  <span className="text-[10px] text-fg-tertiary">
                    {log.created_at ? new Date(log.created_at).toLocaleString() : '-'}
                  </span>
                  <span className="truncate text-xs text-accent-primary">{log.action}</span>
                  <span className="truncate text-xs text-fg-secondary">{log.resource ?? '-'}</span>
                  <span className="truncate text-[10px] text-fg-muted">
                    {log.user_id?.slice(0, 8) ?? '-'}
                  </span>
                  <span className="text-[10px] text-fg-muted">{log.ip ?? '-'}</span>
                </div>
                {isExpanded && (
                  <div className="border-b border-border-shell bg-surface-base px-4 py-2">
                    <pre className="whitespace-pre-wrap text-[10px] text-fg-tertiary font-mono">
                      {JSON.stringify(log.metadata ?? log, null, 2)}
                    </pre>
                  </div>
                )}
              </div>
            );
          })}
          {logs.length === 0 && (
            <div className="p-6 text-center text-xs text-fg-muted">No audit logs found</div>
          )}
        </div>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-2">
          <button
            disabled={page === 0}
            onClick={() => setPage((p) => Math.max(0, p - 1))}
            className="text-[10px] text-fg-muted hover:text-fg-secondary disabled:opacity-30"
          >
            prev
          </button>
          <span className="text-[10px] text-fg-tertiary">
            {page + 1} / {totalPages}
          </span>
          <button
            disabled={page >= totalPages - 1}
            onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
            className="text-[10px] text-fg-muted hover:text-fg-secondary disabled:opacity-30"
          >
            next
          </button>
        </div>
      )}
    </div>
  );
}

/* ================================================================== */
/*  HEALTH TAB                                                         */
/* ================================================================== */

interface ClawHealth {
  name: string;
  pod: string;
  ready: boolean;
  model: string;
  sessions: number;
}

function HealthTab() {
  const terminalClient = useTerminalStore((s) => s.client);
  const [fleetData, setFleetData] = useState<ClawHealth[]>([]);
  const [loading, setLoading] = useState(true);
  const [drillDown, setDrillDown] = useState<string | null>(null);
  const [drillOutput, setDrillOutput] = useState('');
  const [drillLoading, setDrillLoading] = useState(false);

  const fetchHealth = useCallback(async () => {
    setLoading(true);
    try {
      await terminalClient.connect();
      const statusRaw = await terminalClient.executeCommandForOutput('status --json', 15000);
      const healthRaw = await terminalClient.executeCommandForOutput('health --json', 15000);

      let statusData: any = null;
      let healthData: any = null;

      try {
        statusData = JSON.parse(statusRaw);
      } catch { /* ignore */ }
      try {
        healthData = JSON.parse(healthRaw);
      } catch { /* ignore */ }

      const fleet: ClawHealth[] = [];

      if (healthData?.instances && Array.isArray(healthData.instances)) {
        for (const inst of healthData.instances) {
          fleet.push({
            name: inst.name ?? inst.id ?? 'unknown',
            pod: inst.pod ?? inst.container ?? '-',
            ready: inst.ready === true || inst.status === 'running',
            model: inst.model ?? inst.activeModel ?? '-',
            sessions: inst.sessions ?? inst.sessionCount ?? 0,
          });
        }
      } else if (statusData) {
        fleet.push({
          name: statusData.name ?? 'primary',
          pod: statusData.container ?? statusData.pod ?? '-',
          ready: statusData.ready !== false,
          model: statusData.model ?? statusData.activeModel ?? '-',
          sessions: statusData.sessions ?? statusData.sessionCount ?? 0,
        });
      }

      setFleetData(fleet);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to fetch health');
    } finally {
      setLoading(false);
    }
  }, [terminalClient]);

  useEffect(() => {
    fetchHealth();
  }, [fetchHealth]);

  const handleDrillDown = useCallback(
    async (name: string) => {
      setDrillDown(name);
      setDrillLoading(true);
      try {
        await terminalClient.connect();
        const output = await terminalClient.executeCommandForOutput(
          `health --json --instance ${name}`,
          15000,
        );
        setDrillOutput(output);
      } catch (err: any) {
        setDrillOutput(`Error: ${err.message}`);
      } finally {
        setDrillLoading(false);
      }
    },
    [terminalClient],
  );

  if (loading) return <LoadingSpinner />;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-fg-secondary">
          fleet ({fleetData.length})
        </span>
        <button
          onClick={fetchHealth}
          className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
        >
          <RefreshCw size={10} />
          refresh
        </button>
      </div>

      <div className="border border-border-shell">
        <div className="grid grid-cols-[1fr_120px_80px_120px_80px] gap-2 border-b border-border-shell bg-surface-base px-3 py-1.5">
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">name</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">pod</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">ready</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">model</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">sessions</span>
        </div>
        {fleetData.map((claw) => (
          <div
            key={claw.name}
            onClick={() => handleDrillDown(claw.name)}
            className="grid cursor-pointer grid-cols-[1fr_120px_80px_120px_80px] gap-2 border-b border-border-shell px-3 py-1.5 last:border-b-0 hover:bg-surface-elevated"
          >
            <span className="text-xs text-fg-primary">{claw.name}</span>
            <span className="truncate text-[10px] text-fg-muted font-mono">{claw.pod}</span>
            <span className={`text-xs ${claw.ready ? 'text-accent-primary' : 'text-status-error'}`}>
              {claw.ready ? 'ready' : 'down'}
            </span>
            <span className="truncate text-[10px] text-fg-secondary">{claw.model}</span>
            <span className="text-xs text-fg-secondary">{claw.sessions}</span>
          </div>
        ))}
        {fleetData.length === 0 && (
          <div className="p-6 text-center text-xs text-fg-muted">No instances found</div>
        )}
      </div>

      {/* Drill-down panel */}
      {drillDown && (
        <div className="border border-border-shell bg-surface-base">
          <div className="flex items-center justify-between border-b border-border-shell px-3 py-1.5">
            <span className="flex items-center gap-1.5 text-xs text-fg-secondary">
              <Terminal size={12} />
              {drillDown}
            </span>
            <button
              onClick={() => setDrillDown(null)}
              className="text-fg-muted hover:text-fg-secondary"
            >
              <X size={12} />
            </button>
          </div>
          <div className="max-h-60 overflow-auto p-3">
            {drillLoading ? (
              <LoadingSpinner />
            ) : (
              <pre className="whitespace-pre-wrap text-[10px] text-fg-tertiary font-mono">
                {drillOutput || 'No output'}
              </pre>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

/* ================================================================== */
/*  RBAC TAB                                                           */
/* ================================================================== */

const ALL_PERMISSIONS = [
  'chat.read',
  'chat.send',
  'canvas.view',
  'memory.read',
  'memory.write',
  'skills.list',
  'skills.install',
  'skills.manage',
  'crons.list',
  'crons.manage',
  'terminal.exec.safe',
  'terminal.exec.standard',
  'terminal.exec.privileged',
  'settings.read',
  'settings.admin',
  'governance.view',
  'governance.resolve',
  'acp.spawn',
  'acp.manage',
  'users.list',
  'users.manage',
  'audit.read',
];

const ROLE_COLUMNS = ['guest', 'user', 'admin', 'superadmin'];

function RBACTab() {
  const authClient = useAuthStore((s) => s.client);
  const [matrix, setMatrix] = useState<Record<string, string[]>>({});
  const [draft, setDraft] = useState<Record<string, string[]>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);

  const fetchMatrix = useCallback(async () => {
    setLoading(true);
    try {
      const data = await authClient.fetchRolePermissionMatrix();
      setMatrix(data);
      setDraft(JSON.parse(JSON.stringify(data)));
      setDirty(false);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to fetch RBAC matrix');
    } finally {
      setLoading(false);
    }
  }, [authClient]);

  useEffect(() => {
    fetchMatrix();
  }, [fetchMatrix]);

  const togglePermission = useCallback(
    (role: string, permission: string) => {
      setDraft((prev) => {
        const perms = prev[role] ?? [];
        const next = perms.includes(permission)
          ? perms.filter((p) => p !== permission)
          : [...perms, permission];
        const updated = { ...prev, [role]: next };
        setDirty(JSON.stringify(updated) !== JSON.stringify(matrix));
        return updated;
      });
    },
    [matrix],
  );

  const handleSave = useCallback(async () => {
    setSaving(true);
    try {
      for (const role of ROLE_COLUMNS) {
        if (JSON.stringify(draft[role] ?? []) !== JSON.stringify(matrix[role] ?? [])) {
          await authClient.updateRolePermissions(role, draft[role] ?? []);
        }
      }
      ToastService.showInfo('RBAC permissions saved');
      await fetchMatrix();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to save');
    } finally {
      setSaving(false);
    }
  }, [authClient, draft, matrix, fetchMatrix]);

  const handleDiscard = useCallback(() => {
    setDraft(JSON.parse(JSON.stringify(matrix)));
    setDirty(false);
  }, [matrix]);

  if (loading) return <LoadingSpinner />;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-fg-secondary">permission matrix</span>
        <div className="flex items-center gap-2">
          {dirty && (
            <>
              <button
                onClick={handleDiscard}
                className="text-[10px] text-fg-muted hover:text-status-error"
              >
                discard
              </button>
              <button
                onClick={handleSave}
                disabled={saving}
                className="flex items-center gap-1 text-[10px] text-accent-primary hover:text-accent-secondary disabled:opacity-50"
              >
                {saving ? <Loader2 size={10} className="animate-spin" /> : <Check size={10} />}
                save
              </button>
            </>
          )}
          <button
            onClick={fetchMatrix}
            className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
          >
            <RefreshCw size={10} />
          </button>
        </div>
      </div>

      <div className="overflow-auto border border-border-shell">
        <table className="w-full">
          <thead>
            <tr className="border-b border-border-shell bg-surface-base">
              <th className="px-3 py-1.5 text-left text-[10px] uppercase tracking-wide text-fg-muted">
                permission
              </th>
              {ROLE_COLUMNS.map((role) => (
                <th
                  key={role}
                  className="px-3 py-1.5 text-center text-[10px] uppercase tracking-wide text-fg-muted"
                >
                  {role}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {ALL_PERMISSIONS.map((perm) => (
              <tr key={perm} className="border-b border-border-shell last:border-b-0 hover:bg-surface-elevated">
                <td className="px-3 py-1 text-[11px] text-fg-secondary font-mono">{perm}</td>
                {ROLE_COLUMNS.map((role) => {
                  const active = (draft[role] ?? []).includes(perm);
                  return (
                    <td key={role} className="px-3 py-1 text-center">
                      <button
                        onClick={() => togglePermission(role, perm)}
                        className={`inline-flex h-4 w-4 items-center justify-center border ${
                          active
                            ? 'border-accent-primary bg-accent-primary-muted text-accent-primary'
                            : 'border-border-shell text-transparent hover:border-fg-muted'
                        }`}
                      >
                        {active && <Check size={10} />}
                      </button>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  SESSIONS TAB                                                       */
/* ================================================================== */

interface SessionInfo {
  key: string;
  title?: string;
  model?: string;
  messageCount?: number;
  lastActive?: string;
}

function SessionsTab() {
  const gwClient = useGatewayStore((s) => s.client);
  const [sessions, setSessions] = useState<SessionInfo[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchSessions = useCallback(async () => {
    setLoading(true);
    try {
      const res = await gwClient.listSessions();
      if (res.ok && res.payload?.sessions) {
        setSessions(
          (res.payload.sessions as any[]).map((s: any) => ({
            key: s.key ?? s.sessionKey ?? s.id,
            title: s.title ?? s.name,
            model: s.model ?? s.activeModel,
            messageCount: s.messageCount ?? s.messages,
            lastActive: s.lastActive ?? s.updatedAt,
          })),
        );
      }
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to fetch sessions');
    } finally {
      setLoading(false);
    }
  }, [gwClient]);

  useEffect(() => {
    fetchSessions();
  }, [fetchSessions]);

  if (loading) return <LoadingSpinner />;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-fg-secondary">
          {sessions.length} session{sessions.length !== 1 ? 's' : ''}
        </span>
        <button
          onClick={fetchSessions}
          className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
        >
          <RefreshCw size={10} />
          refresh
        </button>
      </div>

      <div className="border border-border-shell">
        <div className="grid grid-cols-[1fr_120px_100px_140px] gap-2 border-b border-border-shell bg-surface-base px-3 py-1.5">
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">session</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">model</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">messages</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">last active</span>
        </div>
        {sessions.map((session) => (
          <div
            key={session.key}
            className="grid grid-cols-[1fr_120px_100px_140px] gap-2 border-b border-border-shell px-3 py-1.5 last:border-b-0 hover:bg-surface-elevated"
          >
            <div className="flex flex-col">
              <span className="text-xs text-fg-primary">{session.title ?? session.key}</span>
              <span className="text-[9px] text-fg-muted font-mono">{session.key}</span>
            </div>
            <span className="truncate text-[10px] text-fg-secondary">{session.model ?? '-'}</span>
            <span className="text-xs text-fg-secondary">{session.messageCount ?? '-'}</span>
            <span className="text-[10px] text-fg-muted">
              {session.lastActive ? new Date(session.lastActive).toLocaleString() : '-'}
            </span>
          </div>
        ))}
        {sessions.length === 0 && (
          <div className="p-6 text-center text-xs text-fg-muted">No active sessions</div>
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  OPENCLAWS TAB                                                      */
/* ================================================================== */

function OpenClawsTab() {
  const authClient = useAuthStore((s) => s.client);
  const openclaws = useAuthStore((s) => s.openclaws);
  const [loading, setLoading] = useState(false);
  const [createName, setCreateName] = useState('');
  const [createDesc, setCreateDesc] = useState('');
  const [creating, setCreating] = useState(false);
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      await authClient.fetchUserOpenClaws();
    } finally {
      setLoading(false);
    }
  }, [authClient]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const handleCreate = useCallback(async () => {
    if (!createName.trim()) return;
    setCreating(true);
    try {
      const res = await fetch(`${window.location.origin}/auth/openclaws`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${authClient.state.token}`,
        },
        body: JSON.stringify({ name: createName.trim(), description: createDesc.trim() }),
      });
      if (!res.ok) throw new Error('Failed to create instance');
      ToastService.showInfo('OpenClaw instance created');
      setCreateName('');
      setCreateDesc('');
      setShowCreate(false);
      await refresh();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to create');
    } finally {
      setCreating(false);
    }
  }, [authClient, createName, createDesc, refresh]);

  const handleDelete = useCallback(
    async (id: string) => {
      setDeleting(id);
      try {
        const res = await fetch(`${window.location.origin}/auth/openclaws/${id}`, {
          method: 'DELETE',
          headers: {
            Authorization: `Bearer ${authClient.state.token}`,
          },
        });
        if (!res.ok) throw new Error('Failed to delete instance');
        ToastService.showInfo('OpenClaw instance deleted');
        setDeleteConfirm(null);
        await refresh();
      } catch (err: any) {
        ToastService.showError(err.message ?? 'Failed to delete');
      } finally {
        setDeleting(null);
      }
    },
    [authClient, refresh],
  );

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-fg-secondary">
          {openclaws.length} instance{openclaws.length !== 1 ? 's' : ''}
        </span>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowCreate(!showCreate)}
            className="flex items-center gap-1 text-[10px] text-accent-primary hover:text-accent-secondary"
          >
            <Plus size={10} />
            create
          </button>
          <button
            onClick={refresh}
            className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
          >
            <RefreshCw size={10} />
          </button>
        </div>
      </div>

      {/* Create form */}
      {showCreate && (
        <div className="flex flex-col gap-2 border border-border-shell bg-surface-base p-3">
          <input
            type="text"
            placeholder="Instance name"
            value={createName}
            onChange={(e) => setCreateName(e.target.value)}
            className="border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none focus:border-accent-primary"
          />
          <input
            type="text"
            placeholder="Description (optional)"
            value={createDesc}
            onChange={(e) => setCreateDesc(e.target.value)}
            className="border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary outline-none focus:border-accent-primary"
          />
          <div className="flex items-center gap-2">
            <button
              onClick={handleCreate}
              disabled={creating || !createName.trim()}
              className="flex items-center gap-1 px-2 py-1 text-[10px] text-accent-primary hover:text-accent-secondary disabled:opacity-40"
            >
              {creating ? <Loader2 size={10} className="animate-spin" /> : <Plus size={10} />}
              create
            </button>
            <button
              onClick={() => setShowCreate(false)}
              className="text-[10px] text-fg-muted hover:text-fg-secondary"
            >
              cancel
            </button>
          </div>
        </div>
      )}

      {/* Instances list */}
      {loading ? (
        <LoadingSpinner />
      ) : (
        <div className="border border-border-shell">
          <div className="grid grid-cols-[1fr_120px_80px_60px_80px] gap-2 border-b border-border-shell bg-surface-base px-3 py-1.5">
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">name</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">status</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">ready</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">users</span>
            <span className="text-[10px] uppercase tracking-wide text-fg-muted">actions</span>
          </div>
          {openclaws.map((oc) => (
            <div
              key={oc.id}
              className="grid grid-cols-[1fr_120px_80px_60px_80px] gap-2 border-b border-border-shell px-3 py-1.5 last:border-b-0 hover:bg-surface-elevated"
            >
              <div className="flex flex-col">
                <span className="text-xs text-fg-primary">{oc.name}</span>
                {oc.description && (
                  <span className="text-[9px] text-fg-muted">{oc.description}</span>
                )}
              </div>
              <span className="text-[10px] text-fg-secondary">{oc.status}</span>
              <span className={`text-xs ${oc.ready ? 'text-accent-primary' : 'text-status-error'}`}>
                {oc.ready ? 'yes' : 'no'}
              </span>
              <span className="text-xs text-fg-secondary">{oc.userCount}</span>
              <div className="flex items-center gap-1">
                {deleteConfirm === oc.id ? (
                  <>
                    <button
                      onClick={() => handleDelete(oc.id)}
                      disabled={deleting === oc.id}
                      className="text-[9px] text-status-error hover:underline"
                    >
                      {deleting === oc.id ? '...' : 'confirm'}
                    </button>
                    <button
                      onClick={() => setDeleteConfirm(null)}
                      className="text-[9px] text-fg-muted hover:text-fg-secondary"
                    >
                      cancel
                    </button>
                  </>
                ) : (
                  <button
                    onClick={() => setDeleteConfirm(oc.id)}
                    className="text-fg-muted hover:text-status-error"
                  >
                    <Trash2 size={11} />
                  </button>
                )}
              </div>
            </div>
          ))}
          {openclaws.length === 0 && (
            <div className="p-6 text-center text-xs text-fg-muted">No OpenClaw instances</div>
          )}
        </div>
      )}
    </div>
  );
}

/* ================================================================== */
/*  ENV TAB                                                            */
/* ================================================================== */

function EnvTab() {
  const terminalClient = useTerminalStore((s) => s.client);
  const role = useAuthStore((s) => s.role);
  const isSuperadmin = role === 'superadmin';
  const [envVars, setEnvVars] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [newKey, setNewKey] = useState('');
  const [newValue, setNewValue] = useState('');
  const [saving, setSaving] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [deletingKey, setDeletingKey] = useState<string | null>(null);

  const fetchEnvVars = useCallback(async () => {
    setLoading(true);
    try {
      await terminalClient.connect();
      const vars = await terminalClient.listEnvVars();
      setEnvVars(vars);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to fetch env vars');
    } finally {
      setLoading(false);
    }
  }, [terminalClient]);

  useEffect(() => {
    fetchEnvVars();
  }, [fetchEnvVars]);

  const handleSet = useCallback(async () => {
    if (!newKey.trim()) return;
    setSaving(true);
    try {
      await terminalClient.connect();
      await terminalClient.setEnvVar(newKey.trim(), newValue);
      ToastService.showInfo(`Set ${newKey.trim()}`);
      setNewKey('');
      setNewValue('');
      await fetchEnvVars();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to set env var');
    } finally {
      setSaving(false);
    }
  }, [terminalClient, newKey, newValue, fetchEnvVars]);

  const handleDelete = useCallback(
    async (key: string) => {
      setDeletingKey(key);
      try {
        await terminalClient.connect();
        await terminalClient.deleteEnvVar(key);
        ToastService.showInfo(`Deleted ${key}`);
        await fetchEnvVars();
      } catch (err: any) {
        ToastService.showError(err.message ?? 'Failed to delete env var');
      } finally {
        setDeletingKey(null);
      }
    },
    [terminalClient, fetchEnvVars],
  );

  const handleSync = useCallback(async () => {
    setSyncing(true);
    try {
      await terminalClient.connect();
      const result = await terminalClient.syncEnvToGateway();
      ToastService.showInfo(result.message || `Synced ${result.synced} vars`);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to sync');
    } finally {
      setSyncing(false);
    }
  }, [terminalClient]);

  const entries = Object.entries(envVars);

  if (loading) return <LoadingSpinner />;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide text-fg-secondary">
          {entries.length} variable{entries.length !== 1 ? 's' : ''}
        </span>
        <div className="flex items-center gap-2">
          {isSuperadmin && (
            <button
              onClick={handleSync}
              disabled={syncing}
              className="flex items-center gap-1 text-[10px] text-accent-primary hover:text-accent-secondary disabled:opacity-50"
            >
              {syncing ? <Loader2 size={10} className="animate-spin" /> : <RefreshCw size={10} />}
              sync to gateway
            </button>
          )}
          <button
            onClick={fetchEnvVars}
            className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
          >
            <RefreshCw size={10} />
          </button>
        </div>
      </div>

      {/* Add new */}
      <div className="flex items-end gap-2 border border-border-shell bg-surface-base p-3">
        <div className="flex flex-1 flex-col gap-0.5">
          <label className="text-[9px] uppercase tracking-wide text-fg-muted">key</label>
          <input
            type="text"
            value={newKey}
            onChange={(e) => setNewKey(e.target.value)}
            className="border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary font-mono outline-none focus:border-accent-primary"
            placeholder="ENV_VAR_NAME"
          />
        </div>
        <div className="flex flex-1 flex-col gap-0.5">
          <label className="text-[9px] uppercase tracking-wide text-fg-muted">value</label>
          <input
            type="text"
            value={newValue}
            onChange={(e) => setNewValue(e.target.value)}
            className="border border-border-shell bg-surface-card px-2 py-1 text-xs text-fg-primary font-mono outline-none focus:border-accent-primary"
            placeholder="value"
          />
        </div>
        <button
          onClick={handleSet}
          disabled={saving || !newKey.trim()}
          className="flex items-center gap-1 border border-border-shell px-2 py-1 text-[10px] text-accent-primary hover:border-accent-primary disabled:opacity-40"
        >
          {saving ? <Loader2 size={10} className="animate-spin" /> : <Plus size={10} />}
          set
        </button>
      </div>

      {/* Env list */}
      <div className="border border-border-shell">
        <div className="grid grid-cols-[1fr_1fr_60px] gap-2 border-b border-border-shell bg-surface-base px-3 py-1.5">
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">key</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted">value</span>
          <span className="text-[10px] uppercase tracking-wide text-fg-muted" />
        </div>
        {entries.map(([key, value]) => (
          <div
            key={key}
            className="grid grid-cols-[1fr_1fr_60px] gap-2 border-b border-border-shell px-3 py-1.5 last:border-b-0 hover:bg-surface-elevated"
          >
            <span className="truncate text-xs text-fg-primary font-mono">{key}</span>
            <span className="truncate text-xs text-fg-secondary font-mono">{value}</span>
            <div className="flex items-center justify-end">
              <button
                onClick={() => handleDelete(key)}
                disabled={deletingKey === key}
                className="text-fg-muted hover:text-status-error disabled:opacity-40"
              >
                {deletingKey === key ? (
                  <Loader2 size={11} className="animate-spin" />
                ) : (
                  <Trash2 size={11} />
                )}
              </button>
            </div>
          </div>
        ))}
        {entries.length === 0 && (
          <div className="p-6 text-center text-xs text-fg-muted">No environment variables set</div>
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  CHANNELS TAB (stub)                                                */
/* ================================================================== */

function ChannelsTab() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 py-20">
      <Radio size={24} className="text-fg-muted" />
      <p className="text-xs text-fg-tertiary">Channel configuration — coming in next phase</p>
    </div>
  );
}

/* ================================================================== */
/*  COPILOT TAB (stub)                                                 */
/* ================================================================== */

function CopilotTab() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 py-20">
      <Bot size={24} className="text-fg-muted" />
      <p className="text-xs text-fg-tertiary">Copilot chat — coming in next phase</p>
    </div>
  );
}

/* ================================================================== */
/*  Shared helpers                                                     */
/* ================================================================== */

function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center py-12">
      <Loader2 size={16} className="animate-spin text-fg-muted" />
    </div>
  );
}
