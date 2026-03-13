'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  X,
  Search,
  RefreshCw,
  Download,
  ChevronLeft,
  ChevronRight,
  Eye,
  CheckCircle,
  AlertCircle,
  Package,
  BookOpen,
} from 'lucide-react';
import { Dialog, DialogService } from '@/components/ui/Dialog';
import { ToastService } from '@/components/ui/Toast';
import { useTerminalStore } from '@/lib/stores/terminal-store';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

interface Skill {
  id: string;
  name: string;
  emoji?: string;
  description: string;
  status: 'ready' | 'not_ready' | 'clawhub' | 'template';
  slug?: string;
  version?: string;
  author?: string;
}

type SkillCategory = 'ready' | 'clawhub' | 'templates';

const PAGE_SIZE = 14;

const categoryLabels: Record<SkillCategory, string> = {
  ready: 'ready',
  clawhub: 'clawhub',
  templates: 'templates',
};

/* ------------------------------------------------------------------ */
/*  SkillsCronDialog                                                   */
/* ------------------------------------------------------------------ */

interface SkillsCronDialogProps {
  open: boolean;
  onClose: () => void;
}

export function SkillsCronDialog({ open, onClose }: SkillsCronDialogProps) {
  const client = useTerminalStore((s) => s.client);

  const [category, setCategory] = useState<SkillCategory>('ready');
  const [readySkills, setReadySkills] = useState<Skill[]>([]);
  const [clawHubResults, setClawHubResults] = useState<Skill[]>([]);
  const [templateSkills, setTemplateSkills] = useState<Skill[]>([]);
  const [loading, setLoading] = useState(false);
  const [page, setPage] = useState(0);

  // ClawHub search
  const [hubSearch, setHubSearch] = useState('');
  const [hubSearching, setHubSearching] = useState(false);

  // Inspect
  const [inspecting, setInspecting] = useState<Skill | null>(null);
  const [inspectContent, setInspectContent] = useState<string>('');
  const [inspectLoading, setInspectLoading] = useState(false);

  /* ---------------------------------------------------------------- */
  /*  Fetch ready skills                                               */
  /* ---------------------------------------------------------------- */

  const fetchReady = useCallback(async () => {
    setLoading(true);
    try {
      await client.connect();
      const output = await client.executeCommandForOutput('skills list --json');
      try {
        const data = JSON.parse(output.trim());
        const list: Skill[] = (Array.isArray(data) ? data : data.skills ?? []).map((s: any) => ({
          id: s.id ?? s.slug ?? s.name,
          name: s.name ?? s.id,
          emoji: s.emoji,
          description: s.description ?? '',
          status: s.eligible === true || s.status === 'ready' ? 'ready' : 'not_ready',
          slug: s.slug,
          version: s.version,
          author: s.author,
        }));
        setReadySkills(list);
      } catch {
        setReadySkills([]);
      }
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to load skills');
    } finally {
      setLoading(false);
    }
  }, [client]);

  /* ---------------------------------------------------------------- */
  /*  Fetch templates                                                  */
  /* ---------------------------------------------------------------- */

  const fetchTemplates = useCallback(async () => {
    try {
      await client.connect();
      const output = await client.executeCommandForOutput('skills list --json');
      try {
        const data = JSON.parse(output.trim());
        const allSkills = Array.isArray(data) ? data : data.skills ?? [];
        const list: Skill[] = allSkills
          .filter((s: any) => s.source === 'template' || s.type === 'template' || s.bundled)
          .map((s: any) => ({
            id: s.id ?? s.slug ?? s.name,
            name: s.name ?? s.id,
            emoji: s.emoji,
            description: s.description ?? '',
            status: 'template' as const,
            slug: s.slug,
            version: s.version,
            author: s.author,
          }));
        setTemplateSkills(list);
      } catch {
        setTemplateSkills([]);
      }
    } catch {
      setTemplateSkills([]);
    }
  }, [client]);

  useEffect(() => {
    if (!open) return;
    fetchReady();
    fetchTemplates();
  }, [open, fetchReady, fetchTemplates]);

  /* ---------------------------------------------------------------- */
  /*  ClawHub search                                                   */
  /* ---------------------------------------------------------------- */

  const searchClawHub = useCallback(async () => {
    if (!hubSearch.trim()) return;
    setHubSearching(true);
    try {
      await client.connect();
      const output = await client.executeCommandForOutput(`clawhub search ${hubSearch.trim()}`);
      // Parse terminal output lines: "slug - description"
      const lines = output.split('\n').filter((l: string) => l.trim());
      const results: Skill[] = [];

      for (const line of lines) {
        const trimmed = line.trim();
        // Try JSON parse first
        try {
          const item = JSON.parse(trimmed);
          results.push({
            id: item.slug ?? item.name,
            name: item.name ?? item.slug,
            emoji: item.emoji,
            description: item.description ?? '',
            status: 'clawhub',
            slug: item.slug,
            version: item.version,
            author: item.author,
          });
          continue;
        } catch {
          // Not JSON
        }

        // Parse "slug - description" or "name (slug) - description"
        const match = trimmed.match(/^(.+?)\s*-\s*(.+)$/);
        if (match) {
          results.push({
            id: match[1].trim(),
            name: match[1].trim(),
            description: match[2].trim(),
            status: 'clawhub',
            slug: match[1].trim(),
          });
        }
      }

      setClawHubResults(results);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'ClawHub search failed');
    } finally {
      setHubSearching(false);
    }
  }, [hubSearch, client]);

  /* ---------------------------------------------------------------- */
  /*  Install                                                          */
  /* ---------------------------------------------------------------- */

  const installSkill = useCallback(async (slug: string) => {
    try {
      await client.connect();
      const output = await client.executeCommandForOutput(`clawhub install ${slug}`);
      if (output.toLowerCase().includes('error') || output.toLowerCase().includes('failed')) {
        ToastService.showError(`Install failed: ${output.slice(0, 100)}`);
      } else {
        ToastService.showInfo(`Installed ${slug}`);
        fetchReady();
      }
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Install failed');
    }
  }, [client, fetchReady]);

  /* ---------------------------------------------------------------- */
  /*  Inspect                                                          */
  /* ---------------------------------------------------------------- */

  const handleInspect = useCallback(async (skill: Skill) => {
    setInspecting(skill);
    setInspectLoading(true);
    setInspectContent('');

    try {
      await client.connect();

      if (skill.status === 'clawhub') {
        // For ClawHub: show JSON details
        const output = await client.executeCommandForOutput(
          `clawhub info ${skill.slug ?? skill.id}`,
        );
        // Try to pretty-print JSON
        try {
          const data = JSON.parse(output.trim());
          setInspectContent(JSON.stringify(data, null, 2));
        } catch {
          setInspectContent(output);
        }
      } else {
        // For templates / ready: read SKILL.md
        const slug = skill.slug ?? skill.id;
        const output = await client.executeCommandForOutput(
          `cat /home/node/.openclaw/skills/${slug}/SKILL.md 2>/dev/null || echo "(no SKILL.md found)"`,
        );
        setInspectContent(output);
      }
    } catch (err: any) {
      setInspectContent(`Error: ${err.message ?? 'Failed to load details'}`);
    } finally {
      setInspectLoading(false);
    }
  }, [client]);

  /* ---------------------------------------------------------------- */
  /*  Current category items                                           */
  /* ---------------------------------------------------------------- */

  const currentItems = useMemo(() => {
    switch (category) {
      case 'ready':
        return readySkills.filter((s) => s.status === 'ready');
      case 'clawhub':
        return clawHubResults;
      case 'templates':
        return templateSkills;
    }
  }, [category, readySkills, clawHubResults, templateSkills]);

  const totalPages = Math.max(1, Math.ceil(currentItems.length / PAGE_SIZE));
  const pageItems = currentItems.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE);

  // Reset page on category change
  useEffect(() => {
    setPage(0);
  }, [category]);

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  const handleClose = useCallback(() => {
    DialogService.close('skills');
    onClose();
  }, [onClose]);

  return (
    <Dialog
      id="skills"
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
              skills
            </span>
            <div className="flex items-center gap-1">
              {(['ready', 'clawhub', 'templates'] as SkillCategory[]).map((cat) => {
                const Icon = { ready: CheckCircle, clawhub: Package, templates: BookOpen }[cat];
                return (
                  <button
                    key={cat}
                    onClick={() => setCategory(cat)}
                    className={`flex items-center gap-1 border border-border-shell px-2 py-0.5 text-[10px] ${
                      category === cat
                        ? 'bg-accent-primary-muted text-accent-primary'
                        : 'text-fg-muted hover:text-fg-secondary'
                    }`}
                  >
                    <Icon size={10} />
                    {categoryLabels[cat]}
                  </button>
                );
              })}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => {
                fetchReady();
                fetchTemplates();
              }}
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
      <div className="flex h-full">
        {/* Main list */}
        <div className="flex flex-1 flex-col">
          {/* ClawHub search bar */}
          {category === 'clawhub' && (
            <div className="flex items-center gap-2 border-b border-border-shell px-4 py-2">
              <Search size={12} className="text-fg-muted" />
              <input
                type="text"
                value={hubSearch}
                onChange={(e) => setHubSearch(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') searchClawHub();
                }}
                placeholder="Search ClawHub..."
                className="flex-1 bg-transparent text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
              />
              <button
                onClick={searchClawHub}
                disabled={hubSearching}
                className="border border-border-shell px-2 py-0.5 text-[10px] text-fg-muted hover:text-accent-primary disabled:text-fg-disabled"
              >
                {hubSearching ? 'searching...' : 'search'}
              </button>
            </div>
          )}

          {/* Items list */}
          <div className="flex-1 overflow-y-auto">
            {loading && pageItems.length === 0 ? (
              <div className="p-8 text-center text-xs text-fg-muted">Loading...</div>
            ) : pageItems.length === 0 ? (
              <div className="p-8 text-center text-xs text-fg-muted">
                {category === 'clawhub'
                  ? 'Search ClawHub to discover skills'
                  : 'No skills found'}
              </div>
            ) : (
              pageItems.map((skill) => (
                <div
                  key={skill.id}
                  className={`flex items-center gap-3 border-b border-border-shell px-4 py-2.5 hover:bg-surface-elevated ${
                    inspecting?.id === skill.id ? 'bg-accent-primary-muted' : ''
                  }`}
                >
                  <span className="text-base">{skill.emoji ?? '🧩'}</span>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-xs font-medium text-fg-primary">{skill.name}</span>
                      {skill.version && (
                        <span className="text-[9px] text-fg-muted">v{skill.version}</span>
                      )}
                      {skill.status === 'ready' && (
                        <span className="text-[9px] text-accent-primary">ready</span>
                      )}
                    </div>
                    <span className="block truncate text-[10px] text-fg-tertiary">
                      {skill.description}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleInspect(skill)}
                      className="text-fg-muted hover:text-fg-secondary"
                      title="Inspect"
                    >
                      <Eye size={12} />
                    </button>
                    {(category === 'clawhub' || category === 'templates') && skill.slug && (
                      <button
                        onClick={() => installSkill(skill.slug!)}
                        className="flex items-center gap-1 border border-border-shell px-2 py-0.5 text-[10px] text-fg-muted hover:text-accent-primary"
                        title="Install"
                      >
                        <Download size={10} />
                        install
                      </button>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>

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

        {/* Inspect panel (right) */}
        {inspecting && (
          <div className="flex w-[400px] shrink-0 flex-col border-l border-border-shell">
            {/* Header */}
            <div className="flex items-center justify-between border-b border-border-shell px-3 py-2">
              <div className="flex items-center gap-2">
                <span className="text-sm">{inspecting.emoji ?? '🧩'}</span>
                <span className="text-xs font-medium text-fg-primary">{inspecting.name}</span>
              </div>
              <button
                onClick={() => setInspecting(null)}
                className="text-fg-muted hover:text-fg-primary"
              >
                <X size={12} />
              </button>
            </div>

            {/* Meta */}
            <div className="border-b border-border-shell px-3 py-2">
              <p className="text-[10px] text-fg-tertiary">{inspecting.description}</p>
              {inspecting.author && (
                <p className="mt-1 text-[9px] text-fg-muted">by {inspecting.author}</p>
              )}
              {inspecting.slug && (
                <p className="mt-0.5 text-[9px] font-mono text-fg-muted">{inspecting.slug}</p>
              )}
            </div>

            {/* Content */}
            <div className="flex-1 overflow-y-auto p-3">
              {inspectLoading ? (
                <div className="flex items-center gap-2 text-xs text-fg-muted">
                  <RefreshCw size={12} className="animate-spin" />
                  Loading...
                </div>
              ) : inspecting.status === 'clawhub' ? (
                <pre className="whitespace-pre-wrap text-[10px] font-mono text-fg-secondary leading-relaxed">
                  {inspectContent || '(no details available)'}
                </pre>
              ) : (
                <div className="prose-sm text-xs text-fg-secondary leading-relaxed whitespace-pre-wrap select-text">
                  {inspectContent || '(no SKILL.md found)'}
                </div>
              )}
            </div>

            {/* Actions */}
            {inspecting.slug && (category === 'clawhub' || category === 'templates') && (
              <div className="border-t border-border-shell px-3 py-2">
                <button
                  onClick={() => installSkill(inspecting.slug!)}
                  className="flex items-center gap-1 border border-accent-primary px-3 py-1 text-[10px] text-accent-primary hover:bg-accent-primary-muted"
                >
                  <Download size={10} />
                  install {inspecting.slug}
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </Dialog>
  );
}
