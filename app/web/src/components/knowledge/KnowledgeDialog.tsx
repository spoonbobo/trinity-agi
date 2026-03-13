'use client';

import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import {
  X,
  Search,
  RefreshCw,
  FileText,
  Upload,
  Trash2,
  Play,
  ChevronRight,
  Network,
  LayoutList,
} from 'lucide-react';
import { Dialog, DialogService } from '@/components/ui/Dialog';
import { ToastService } from '@/components/ui/Toast';
import { useAuthStore } from '@/lib/stores/auth-store';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

interface GraphNode {
  id: string;
  label: string;
  kind: string;
  edges: GraphEdge[];
}

interface GraphEdge {
  source: string;
  target: string;
  relation: string;
}

interface LightRAGDocument {
  id: string;
  name: string;
  status: string;
  type: string;
  chunks: number;
  createdAt?: string;
}

type ViewMode = 'graph' | 'documents';

/* ------------------------------------------------------------------ */
/*  Force simulation (lightweight, no d3)                              */
/* ------------------------------------------------------------------ */

interface SimNode {
  id: string;
  label: string;
  kind: string;
  x: number;
  y: number;
  fx?: number;
  fy?: number;
  isCenter: boolean;
}

interface SimEdge {
  source: string;
  target: string;
  relation: string;
}

function layoutForceGraph(
  centerNode: GraphNode,
  relatedNodes: GraphNode[],
  width: number,
  height: number,
): { nodes: SimNode[]; edges: SimEdge[] } {
  const cx = width / 2;
  const cy = height / 2;
  const radius = Math.min(width, height) * 0.35;
  const capped = relatedNodes.slice(0, 14);

  const nodes: SimNode[] = [
    { id: centerNode.id, label: centerNode.label, kind: centerNode.kind, x: cx, y: cy, isCenter: true },
  ];

  capped.forEach((n, i) => {
    const angle = (2 * Math.PI * i) / capped.length - Math.PI / 2;
    nodes.push({
      id: n.id,
      label: n.label,
      kind: n.kind,
      x: cx + radius * Math.cos(angle),
      y: cy + radius * Math.sin(angle),
      isCenter: false,
    });
  });

  const edges: SimEdge[] = centerNode.edges
    .filter((e) => capped.some((n) => n.id === e.target || n.id === e.source))
    .map((e) => ({ source: e.source, target: e.target, relation: e.relation }));

  return { nodes, edges };
}

/* ------------------------------------------------------------------ */
/*  Alphabetical bucketing                                             */
/* ------------------------------------------------------------------ */

function bucketNodes(nodes: GraphNode[]): Map<string, GraphNode[]> {
  const map = new Map<string, GraphNode[]>();
  const sorted = [...nodes].sort((a, b) => a.label.localeCompare(b.label));
  for (const n of sorted) {
    const letter = (n.label[0] ?? '#').toUpperCase();
    const key = /[A-Z]/.test(letter) ? letter : '#';
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(n);
  }
  return map;
}

/* ------------------------------------------------------------------ */
/*  Kind color map                                                     */
/* ------------------------------------------------------------------ */

function kindColor(kind: string): string {
  switch (kind.toLowerCase()) {
    case 'entity': return 'var(--accent-primary)';
    case 'concept': return 'var(--accent-secondary)';
    case 'document': return 'var(--status-warning)';
    default: return 'var(--fg-tertiary)';
  }
}

function statusColor(status: string): string {
  switch (status.toLowerCase()) {
    case 'ready':
    case 'indexed':
      return 'var(--accent-primary)';
    case 'processing':
    case 'ingesting':
      return 'var(--status-warning)';
    case 'error':
    case 'failed':
      return 'var(--status-error)';
    default:
      return 'var(--fg-muted)';
  }
}

/* ------------------------------------------------------------------ */
/*  KnowledgeDialog                                                    */
/* ------------------------------------------------------------------ */

interface KnowledgeDialogProps {
  open: boolean;
  onClose: () => void;
}

export function KnowledgeDialog({ open, onClose }: KnowledgeDialogProps) {
  const token = useAuthStore((s) => s.token);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);

  const [viewMode, setViewMode] = useState<ViewMode>('graph');
  const [graphNodes, setGraphNodes] = useState<GraphNode[]>([]);
  const [documents, setDocuments] = useState<LightRAGDocument[]>([]);
  const [loading, setLoading] = useState(false);
  const [selectedNode, setSelectedNode] = useState<GraphNode | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [docSearch, setDocSearch] = useState('');

  const baseUrl = typeof window !== 'undefined' ? window.location.origin : '';

  /* ---------------------------------------------------------------- */
  /*  Data fetching                                                    */
  /* ---------------------------------------------------------------- */

  const fetchGraph = useCallback(async () => {
    if (!token || !activeOpenClawId) return;
    setLoading(true);
    try {
      const res = await fetch(
        `${baseUrl}/auth/openclaws/${activeOpenClawId}/lightrag-graph`,
        { headers: { Authorization: `Bearer ${token}` } },
      );
      if (!res.ok) throw new Error('Failed to fetch graph');
      const data = await res.json();
      const nodes: GraphNode[] = (data.nodes ?? []).map((n: any) => ({
        id: n.id ?? n.label,
        label: n.label ?? n.id,
        kind: n.kind ?? n.type ?? 'entity',
        edges: (n.edges ?? []).map((e: any) => ({
          source: e.source ?? e.from,
          target: e.target ?? e.to,
          relation: e.relation ?? e.label ?? '',
        })),
      }));
      setGraphNodes(nodes);
      if (nodes.length > 0 && !selectedNode) {
        setSelectedNode(nodes[0]);
      }
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to load knowledge graph');
    } finally {
      setLoading(false);
    }
  }, [token, activeOpenClawId, baseUrl, selectedNode]);

  const fetchDocuments = useCallback(async () => {
    if (!token || !activeOpenClawId) return;
    setLoading(true);
    try {
      const res = await fetch(
        `${baseUrl}/auth/openclaws/${activeOpenClawId}/lightrag-documents`,
        { headers: { Authorization: `Bearer ${token}` } },
      );
      if (!res.ok) throw new Error('Failed to fetch documents');
      const data = await res.json();
      const docs: LightRAGDocument[] = (Array.isArray(data) ? data : data.documents ?? []).map((d: any) => ({
        id: d.id,
        name: d.name ?? d.filename ?? d.id,
        status: d.status ?? 'unknown',
        type: d.type ?? d.mimeType ?? 'text',
        chunks: d.chunks ?? d.chunk_count ?? 0,
        createdAt: d.createdAt ?? d.created_at,
      }));
      setDocuments(docs);
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Failed to load documents');
    } finally {
      setLoading(false);
    }
  }, [token, activeOpenClawId, baseUrl]);

  useEffect(() => {
    if (!open) return;
    fetchGraph();
    fetchDocuments();
  }, [open, fetchGraph, fetchDocuments]);

  /* ---------------------------------------------------------------- */
  /*  Upload                                                           */
  /* ---------------------------------------------------------------- */

  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleUpload = useCallback(async (files: FileList | null) => {
    if (!files || files.length === 0 || !token || !activeOpenClawId) return;
    const formData = new FormData();
    Array.from(files).forEach((f) => formData.append('files', f));

    try {
      const res = await fetch(
        `${baseUrl}/auth/openclaws/${activeOpenClawId}/lightrag-documents`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}` },
          body: formData,
        },
      );
      if (!res.ok) throw new Error('Upload failed');
      ToastService.showInfo('Document uploaded');
      fetchDocuments();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Upload failed');
    }
  }, [token, activeOpenClawId, baseUrl, fetchDocuments]);

  /* ---------------------------------------------------------------- */
  /*  Document actions                                                 */
  /* ---------------------------------------------------------------- */

  const ingestDoc = useCallback(async (docId: string) => {
    if (!token || !activeOpenClawId) return;
    try {
      const res = await fetch(
        `${baseUrl}/auth/openclaws/${activeOpenClawId}/lightrag-documents/${docId}/ingest`,
        {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}` },
        },
      );
      if (!res.ok) throw new Error('Ingest failed');
      ToastService.showInfo('Ingest started');
      fetchDocuments();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Ingest failed');
    }
  }, [token, activeOpenClawId, baseUrl, fetchDocuments]);

  const deleteDoc = useCallback(async (docId: string) => {
    if (!token || !activeOpenClawId) return;
    try {
      const res = await fetch(
        `${baseUrl}/auth/openclaws/${activeOpenClawId}/lightrag-documents/${docId}`,
        {
          method: 'DELETE',
          headers: { Authorization: `Bearer ${token}` },
        },
      );
      if (!res.ok) throw new Error('Delete failed');
      ToastService.showInfo('Document deleted');
      fetchDocuments();
    } catch (err: any) {
      ToastService.showError(err.message ?? 'Delete failed');
    }
  }, [token, activeOpenClawId, baseUrl, fetchDocuments]);

  /* ---------------------------------------------------------------- */
  /*  Filtered / bucketed data                                         */
  /* ---------------------------------------------------------------- */

  const filteredNodes = useMemo(() => {
    if (!searchQuery) return graphNodes;
    const q = searchQuery.toLowerCase();
    return graphNodes.filter(
      (n) => n.label.toLowerCase().includes(q) || n.kind.toLowerCase().includes(q),
    );
  }, [graphNodes, searchQuery]);

  const bucketedNodes = useMemo(() => bucketNodes(filteredNodes), [filteredNodes]);

  const filteredDocs = useMemo(() => {
    if (!docSearch) return documents;
    const q = docSearch.toLowerCase();
    return documents.filter(
      (d) => d.name.toLowerCase().includes(q) || d.type.toLowerCase().includes(q),
    );
  }, [documents, docSearch]);

  /* ---------------------------------------------------------------- */
  /*  Graph layout                                                     */
  /* ---------------------------------------------------------------- */

  const graphLayout = useMemo(() => {
    if (!selectedNode) return null;
    const relatedIds = new Set(
      selectedNode.edges.flatMap((e) => [e.source, e.target]),
    );
    relatedIds.delete(selectedNode.id);
    const related = graphNodes.filter((n) => relatedIds.has(n.id));
    return layoutForceGraph(selectedNode, related, 600, 500);
  }, [selectedNode, graphNodes]);

  /* ---------------------------------------------------------------- */
  /*  SVG graph canvas                                                 */
  /* ---------------------------------------------------------------- */

  const renderGraph = () => {
    if (!graphLayout) {
      return (
        <div className="flex h-full items-center justify-center text-xs text-fg-muted">
          Select a node to explore
        </div>
      );
    }

    const { nodes, edges } = graphLayout;
    const nodeMap = new Map(nodes.map((n) => [n.id, n]));

    return (
      <svg width="100%" height="100%" viewBox="0 0 600 500" className="select-none">
        {/* Edges */}
        {edges.map((e, i) => {
          const s = nodeMap.get(e.source);
          const t = nodeMap.get(e.target);
          if (!s || !t) return null;
          const mx = (s.x + t.x) / 2;
          const my = (s.y + t.y) / 2 - 20;
          return (
            <g key={`edge-${i}`}>
              <path
                d={`M${s.x},${s.y} Q${mx},${my} ${t.x},${t.y}`}
                fill="none"
                stroke="var(--border)"
                strokeWidth={1}
                opacity={0.6}
              />
              {e.relation && (
                <text
                  x={mx}
                  y={my + 6}
                  textAnchor="middle"
                  fill="var(--fg-muted)"
                  fontSize={8}
                  fontFamily="var(--font-mono)"
                >
                  {e.relation}
                </text>
              )}
            </g>
          );
        })}
        {/* Nodes */}
        {nodes.map((n) => (
          <g
            key={n.id}
            className="cursor-pointer"
            onClick={() => {
              const full = graphNodes.find((gn) => gn.id === n.id);
              if (full) setSelectedNode(full);
            }}
          >
            <circle
              cx={n.x}
              cy={n.y}
              r={n.isCenter ? 24 : 16}
              fill={n.isCenter ? 'var(--accent-primary-muted)' : 'var(--surface-card)'}
              stroke={kindColor(n.kind)}
              strokeWidth={n.isCenter ? 2 : 1}
            />
            <text
              x={n.x}
              y={n.y + (n.isCenter ? 36 : 28)}
              textAnchor="middle"
              fill="var(--fg-secondary)"
              fontSize={n.isCenter ? 10 : 9}
              fontFamily="var(--font-mono)"
            >
              {n.label.length > 18 ? n.label.slice(0, 16) + '...' : n.label}
            </text>
          </g>
        ))}
      </svg>
    );
  };

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  const handleClose = useCallback(() => {
    DialogService.close('knowledge');
    onClose();
  }, [onClose]);

  return (
    <Dialog
      id="knowledge"
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
              knowledge
            </span>
            <div className="flex items-center gap-1 border border-border-shell">
              <button
                onClick={() => setViewMode('graph')}
                className={`flex items-center gap-1 px-2 py-0.5 text-[10px] ${
                  viewMode === 'graph'
                    ? 'bg-accent-primary-muted text-accent-primary'
                    : 'text-fg-muted hover:text-fg-secondary'
                }`}
              >
                <Network size={10} />
                graph
              </button>
              <button
                onClick={() => setViewMode('documents')}
                className={`flex items-center gap-1 px-2 py-0.5 text-[10px] ${
                  viewMode === 'documents'
                    ? 'bg-accent-primary-muted text-accent-primary'
                    : 'text-fg-muted hover:text-fg-secondary'
                }`}
              >
                <LayoutList size={10} />
                documents
              </button>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => {
                fetchGraph();
                fetchDocuments();
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
      {viewMode === 'graph' ? (
        /* ============ Graph view ============ */
        <div className="flex h-full">
          {/* Wiki index panel (left) */}
          <div className="flex w-[300px] shrink-0 flex-col border-r border-border-shell">
            {/* Search */}
            <div className="flex items-center gap-2 border-b border-border-shell px-3 py-2">
              <Search size={12} className="text-fg-muted" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search nodes..."
                className="flex-1 bg-transparent text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
              />
            </div>
            {/* Bucketed list */}
            <div className="flex-1 overflow-y-auto">
              {filteredNodes.length === 0 && (
                <div className="p-4 text-center text-xs text-fg-muted">
                  {loading ? 'Loading...' : 'No nodes found'}
                </div>
              )}
              {Array.from(bucketedNodes.entries()).map(([letter, nodes]) => (
                <div key={letter}>
                  <div className="sticky top-0 bg-surface-card px-3 py-1 text-[10px] font-medium text-fg-muted">
                    {letter}
                  </div>
                  {nodes.map((node) => (
                    <button
                      key={node.id}
                      onClick={() => setSelectedNode(node)}
                      className={`flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs hover:bg-surface-elevated ${
                        selectedNode?.id === node.id
                          ? 'bg-accent-primary-muted text-accent-primary'
                          : 'text-fg-secondary'
                      }`}
                    >
                      <div
                        className="h-1.5 w-1.5 shrink-0 rounded-full"
                        style={{ background: kindColor(node.kind) }}
                      />
                      <span className="flex-1 truncate">{node.label}</span>
                      <span className="text-[9px] text-fg-muted">{node.kind}</span>
                    </button>
                  ))}
                </div>
              ))}
            </div>
            <div className="border-t border-border-shell px-3 py-1.5 text-[10px] text-fg-muted">
              {filteredNodes.length} node{filteredNodes.length !== 1 ? 's' : ''}
            </div>
          </div>

          {/* Graph canvas + details */}
          <div className="flex flex-1 flex-col">
            {/* Details panel */}
            {selectedNode && (
              <div className="flex shrink-0 items-center gap-4 border-b border-border-shell px-4 py-2">
                <div className="flex items-center gap-2">
                  <div
                    className="h-2 w-2 rounded-full"
                    style={{ background: kindColor(selectedNode.kind) }}
                  />
                  <span className="text-xs font-medium text-fg-primary">
                    {selectedNode.label}
                  </span>
                </div>
                <span className="text-[10px] text-fg-muted">{selectedNode.kind}</span>
                <span className="text-[10px] text-fg-muted">
                  {selectedNode.edges.length} edge{selectedNode.edges.length !== 1 ? 's' : ''}
                </span>
                {selectedNode.edges.length > 0 && (
                  <div className="flex items-center gap-1 overflow-x-auto">
                    {selectedNode.edges.slice(0, 6).map((e, i) => (
                      <span
                        key={i}
                        className="whitespace-nowrap rounded-sm bg-surface-elevated px-1.5 py-0.5 text-[9px] text-fg-tertiary"
                      >
                        {e.relation || 'linked'}{' '}
                        <ChevronRight size={8} className="inline" />{' '}
                        {e.target === selectedNode.id ? e.source : e.target}
                      </span>
                    ))}
                    {selectedNode.edges.length > 6 && (
                      <span className="text-[9px] text-fg-muted">
                        +{selectedNode.edges.length - 6} more
                      </span>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* SVG canvas */}
            <div className="flex-1 overflow-hidden bg-surface-base">
              {renderGraph()}
            </div>
          </div>
        </div>
      ) : (
        /* ============ Documents view ============ */
        <div className="flex h-full flex-col">
          {/* Toolbar */}
          <div className="flex items-center gap-3 border-b border-border-shell px-4 py-2">
            <div className="flex flex-1 items-center gap-2">
              <Search size={12} className="text-fg-muted" />
              <input
                type="text"
                value={docSearch}
                onChange={(e) => setDocSearch(e.target.value)}
                placeholder="Filter documents..."
                className="flex-1 bg-transparent text-xs text-fg-primary placeholder:text-fg-placeholder outline-none"
              />
            </div>
            <input
              ref={fileInputRef}
              type="file"
              multiple
              className="hidden"
              onChange={(e) => handleUpload(e.target.files)}
            />
            <button
              onClick={() => fileInputRef.current?.click()}
              className="flex items-center gap-1 px-2 py-1 text-[10px] text-fg-muted hover:text-accent-primary border border-border-shell"
            >
              <Upload size={10} />
              upload
            </button>
          </div>

          {/* Table */}
          <div className="flex-1 overflow-y-auto">
            {/* Header */}
            <div className="sticky top-0 flex items-center gap-2 border-b border-border-shell bg-surface-card px-4 py-1.5 text-[10px] font-medium text-fg-muted uppercase">
              <span className="w-[40%]">name</span>
              <span className="w-[12%]">status</span>
              <span className="w-[12%]">type</span>
              <span className="w-[10%] text-right">chunks</span>
              <span className="flex-1 text-right">actions</span>
            </div>
            {filteredDocs.length === 0 ? (
              <div className="p-8 text-center text-xs text-fg-muted">
                {loading ? 'Loading...' : 'No documents'}
              </div>
            ) : (
              filteredDocs.map((doc) => (
                <div
                  key={doc.id}
                  className="flex items-center gap-2 border-b border-border-shell px-4 py-2 hover:bg-surface-elevated"
                >
                  <div className="flex w-[40%] items-center gap-2">
                    <FileText size={12} className="shrink-0 text-fg-muted" />
                    <span className="truncate text-xs text-fg-primary">{doc.name}</span>
                  </div>
                  <div className="w-[12%]">
                    <span
                      className="text-[10px]"
                      style={{ color: statusColor(doc.status) }}
                    >
                      {doc.status}
                    </span>
                  </div>
                  <div className="w-[12%]">
                    <span className="text-[10px] text-fg-tertiary">{doc.type}</span>
                  </div>
                  <div className="w-[10%] text-right">
                    <span className="text-[10px] text-fg-tertiary">{doc.chunks}</span>
                  </div>
                  <div className="flex flex-1 items-center justify-end gap-2">
                    <button
                      onClick={() => ingestDoc(doc.id)}
                      className="text-fg-muted hover:text-accent-primary"
                      title="Ingest"
                    >
                      <Play size={11} />
                    </button>
                    <button
                      onClick={() => deleteDoc(doc.id)}
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

          {/* Footer */}
          <div className="border-t border-border-shell px-4 py-1.5 text-[10px] text-fg-muted">
            {filteredDocs.length} document{filteredDocs.length !== 1 ? 's' : ''}
          </div>
        </div>
      )}
    </Dialog>
  );
}
