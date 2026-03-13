'use client';

import {
  useState,
  useEffect,
  useRef,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeRaw from 'rehype-raw';
import {
  Copy,
  Check,
  ChevronDown,
  ChevronUp,
  MessageCircle,
  FileText,
  FileSpreadsheet,
  FileCode,
  File as FileIcon,
  Download,
  Image as ImageIcon,
} from 'lucide-react';
import { gatewayClient } from '@/lib/stores/gateway-store';
import { useSessionStore } from '@/lib/stores/session-store';
import { useCanvasStore } from '@/lib/stores/canvas-store';
import { useAuthStore } from '@/lib/stores/auth-store';
import type { WsEvent } from '@/lib/protocol/ws-frame';

/* ================================================================== */
/*  Types                                                              */
/* ================================================================== */

export interface ChatEntry {
  id: string;
  role: 'user' | 'assistant' | 'tool' | 'system';
  content: string;
  toolName?: string;
  toolCallId?: string;
  attachments?: Array<Record<string, any>>;
  metadata?: Record<string, any>;
  isStreaming?: boolean;
  startedAt?: number; // Date.now() timestamp
  elapsed?: number; // ms
  localEcho?: boolean;
  idempotencyKey?: string;
  timestamp: number; // Date.now()
}

interface PendingUserEcho {
  content: string;
  idempotencyKey?: string;
  createdAt: number;
}

/* ================================================================== */
/*  Constants                                                          */
/* ================================================================== */

const MAX_ENTRIES = 500;
const SCROLL_THRESHOLD = 100; // px from bottom
const WORKSPACE_PREFIX = '/home/node/.openclaw/workspace/';
const IMG_EXTS = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp', '.tiff', '.tif',
]);

/* ================================================================== */
/*  Helpers                                                            */
/* ================================================================== */

let _entryIdCounter = 0;
function nextEntryId(): string {
  return `ce-${Date.now()}-${++_entryIdCounter}`;
}

function formatTimestamp(ts: number): string {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

function formatElapsed(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  const secs = ms / 1000;
  if (secs < 60) return `${secs.toFixed(1)}s`;
  const mins = Math.floor(secs / 60);
  const rem = Math.floor(secs - mins * 60);
  return `${mins}m ${rem}s`;
}

function isImagePath(path: string): boolean {
  const lower = path.toLowerCase();
  return Array.from(IMG_EXTS).some((ext) => lower.endsWith(ext));
}

/** Extract displayable text from a gateway message content field (string or block list). */
function extractContent(rawContent: unknown): string {
  if (typeof rawContent === 'string') return rawContent;
  if (Array.isArray(rawContent)) {
    const parts: string[] = [];
    for (const block of rawContent) {
      if (typeof block !== 'object' || block === null) continue;
      const b = block as Record<string, any>;
      if (b.type === 'text' && typeof b.text === 'string' && b.text) {
        parts.push(b.text);
      }
    }
    return parts.join('\n').trim();
  }
  return '';
}

/** Extract image attachments from OpenAI-format content blocks (data URI base64). */
function extractImageAttachments(rawContent: unknown): Array<Record<string, any>> {
  if (!Array.isArray(rawContent)) return [];
  const attachments: Array<Record<string, any>> = [];
  for (const block of rawContent) {
    if (typeof block !== 'object' || block === null) continue;
    const b = block as Record<string, any>;
    if (b.type === 'image_url' && typeof b.image_url === 'object') {
      const url = b.image_url?.url ?? '';
      const match = url.match(/^data:(image\/[^;]+);base64,(.+)$/);
      if (match) {
        attachments.push({
          content: match[2],
          mimeType: match[1],
          fileName: 'image',
          type: 'image',
        });
      }
    }
  }
  return attachments;
}

/** Parse tool args into structured metadata. */
function parseToolMetadata(
  toolName: string | undefined,
  args: unknown,
): Record<string, any> | undefined {
  if (args === null || args === undefined) return undefined;
  if (typeof args === 'object' && !Array.isArray(args)) {
    return args as Record<string, any>;
  }
  if (typeof args === 'string' && args.length > 0) {
    try {
      const parsed = JSON.parse(args);
      if (typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
    } catch {
      // not JSON
    }
  }
  return undefined;
}

/** Human-readable summary for tool metadata. */
function getMetadataSummary(
  toolName: string | undefined,
  metadata: Record<string, any> | undefined,
): string | undefined {
  if (!metadata) return undefined;
  const name = toolName ?? '';

  if (name === 'exec' || name === 'bash' || name === 'Bash') {
    const cmd = (metadata.command as string) ?? (metadata.cmd as string) ?? '';
    if (cmd) return cmd;
  }
  if (['read', 'Read', 'write', 'Write', 'edit', 'Edit'].includes(name)) {
    const path =
      (metadata.filePath as string) ?? (metadata.path as string) ?? (metadata.file as string) ?? '';
    if (path) return path;
  }
  if (name === 'glob' || name === 'Glob') {
    const pattern = (metadata.pattern as string) ?? '';
    if (pattern) return pattern;
  }
  if (name === 'grep' || name === 'Grep') {
    const pattern = (metadata.pattern as string) ?? '';
    const include = (metadata.include as string) ?? '';
    if (pattern) return include ? `${pattern} (${include})` : pattern;
  }
  if (name === 'canvas_ui') return 'rendering surface';

  const generic =
    (metadata.command as string) ??
    (metadata.description as string) ??
    (metadata.query as string) ??
    (metadata.prompt as string) ??
    '';
  if (generic) return generic;
  return undefined;
}

/** Secondary detail line for tool metadata. */
function getMetadataDetail(
  toolName: string | undefined,
  metadata: Record<string, any> | undefined,
): string | undefined {
  if (!metadata) return undefined;
  const name = toolName ?? '';
  const parts: string[] = [];

  if (name === 'exec' || name === 'bash' || name === 'Bash') {
    const workdir = (metadata.workdir as string) ?? (metadata.cwd as string) ?? '';
    if (workdir) parts.push(workdir);
    const host = (metadata.host as string) ?? '';
    if (host && host !== 'sandbox') parts.push(`host:${host}`);
  }
  if (name === 'read' || name === 'Read') {
    const offset = metadata.offset;
    const limit = metadata.limit;
    if (offset != null || limit != null) {
      parts.push(`lines ${offset ?? 1}-${(offset ?? 1) + (limit ?? 2000)}`);
    }
  }
  if (name === 'grep' || name === 'Grep') {
    const path = (metadata.path as string) ?? '';
    if (path) parts.push(path);
  }
  return parts.length > 0 ? parts.join('  ') : undefined;
}

/** Extract A2UI marker payload from tool result text. */
function extractA2UIText(raw: string): string | null {
  const idx = raw.indexOf('__A2UI__');
  if (idx < 0) return null;
  return raw.substring(idx);
}

/** Process A2UI JSONL into the canvas store. */
function handleA2UIToolResult(result: string): void {
  const lines = result.split('\n').slice(1); // skip __A2UI__ marker line
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const parsed = JSON.parse(trimmed);
      // Emit as canvas event through the gateway client
      gatewayClient.emitCanvasEvent({ event: 'a2ui', payload: parsed });
    } catch {
      // skip invalid lines
    }
  }
}

/** Extract MEDIA: token paths from tool output. */
const MEDIA_TOKEN_RE = /MEDIA:\s*(.+)/gim;
function extractMediaArtifacts(text: string): Array<Record<string, any>> {
  if (!text) return [];
  const artifacts: Array<Record<string, any>> = [];
  let match: RegExpExecArray | null;
  // Reset lastIndex for safety
  MEDIA_TOKEN_RE.lastIndex = 0;
  while ((match = MEDIA_TOKEN_RE.exec(text)) !== null) {
    let raw = (match[1] ?? '').trim();
    // Strip surrounding quotes/backticks
    while (raw.length > 0 && '`"\''.includes(raw[0])) raw = raw.slice(1);
    while (raw.length > 0 && '`"\''.includes(raw[raw.length - 1])) raw = raw.slice(0, -1);
    raw = raw.trim();
    if (!raw) continue;
    // Convert absolute workspace path to relative
    let relative: string;
    if (raw.startsWith(WORKSPACE_PREFIX)) {
      relative = raw.substring(WORKSPACE_PREFIX.length);
    } else if (raw.startsWith('/')) {
      continue; // absolute path outside workspace -- skip
    } else {
      relative = raw;
    }
    if (relative.startsWith('media/')) relative = relative.substring('media/'.length);
    const fileName = relative.includes('/') ? relative.substring(relative.lastIndexOf('/') + 1) : relative;
    artifacts.push({
      url: `/__openclaw__/media/${relative}`,
      fileName,
      isImage: isImagePath(relative),
    });
  }
  return artifacts;
}

/** Resolve media href: deduplicate /media/media/ and append auth query params. */
function resolveMediaHref(
  href: string,
  authToken?: string | null,
  openclawId?: string | null,
): string {
  let base = href.replace('/__openclaw__/media/media/', '/__openclaw__/media/');
  if (!base.startsWith('/__openclaw__/media/')) return base;
  try {
    const url = new URL(base, window.location.origin);
    if (!url.searchParams.has('openclaw') && openclawId) {
      url.searchParams.set('openclaw', openclawId);
    }
    if (!url.searchParams.has('token') && authToken) {
      url.searchParams.set('token', authToken);
    }
    return url.pathname + url.search;
  } catch {
    return base;
  }
}

/* ================================================================== */
/*  Image enrichment regex (6 passes — port of Flutter)               */
/* ================================================================== */

const IMG_EXT_PATTERN = String.raw`\.(?:png|jpe?g|gif|webp|svg|bmp|tiff?)`;
const IMG_EXT_RE = new RegExp(IMG_EXT_PATTERN + '$', 'i');

function normalizeRelative(input: string): string {
  const trimmed = input.replace(/^\/+/, '');
  return trimmed.startsWith('media/') ? trimmed.substring('media/'.length) : trimmed;
}

function enrichContentWithImages(content: string): string {
  let result = content;

  // Pass 0: backticked absolute workspace image paths -> markdown images
  result = result.replace(
    new RegExp('`/home/node/\\.openclaw/workspace/([^`\\s)\\]]+' + IMG_EXT_PATTERN + ')`', 'gi'),
    (_, rel) => `![image](/__openclaw__/media/${normalizeRelative(rel)})`,
  );

  // Pass 0b: backticked absolute workspace non-image paths -> markdown links
  result = result.replace(
    /`\/home\/node\/\.openclaw\/workspace\/([^`\s)\]]+)`/gi,
    (full, rel) => {
      if (IMG_EXT_RE.test(rel)) return full; // already handled by pass 0
      const relative = normalizeRelative(rel);
      const name = relative.includes('/') ? relative.substring(relative.lastIndexOf('/') + 1) : relative;
      return `[${name}](/__openclaw__/media/${relative})`;
    },
  );

  // Pass 0c: backticked media URLs for non-image files -> markdown links
  result = result.replace(
    /`(\/__openclaw__\/media\/[^`\s)\]]+)`/gi,
    (full, url) => {
      if (IMG_EXT_RE.test(url)) return full;
      const name = url.includes('/') ? url.substring(url.lastIndexOf('/') + 1) : url;
      return `[${name}](${url})`;
    },
  );

  // Pass 1: absolute workspace image paths -> markdown images
  result = result.replace(
    new RegExp(
      '(?<!\\]\\()' + '/home/node/\\.openclaw/workspace/([^\\s)\\]`]+' + IMG_EXT_PATTERN + ')',
      'gi',
    ),
    (full, rel, offset) => {
      if (offset > 0 && result[offset - 1] === '(') return full;
      return `![image](/__openclaw__/media/${normalizeRelative(rel)})`;
    },
  );

  // Pass 2: MEDIA: image tokens -> markdown images
  result = result.replace(
    new RegExp('MEDIA:\\s*([^\\s]+' + IMG_EXT_PATTERN + ')', 'gi'),
    (_, raw) => {
      const relativeRaw = raw.startsWith(WORKSPACE_PREFIX) ? raw.substring(WORKSPACE_PREFIX.length) : raw;
      return `![image](/__openclaw__/media/${normalizeRelative(relativeRaw)})`;
    },
  );

  // Pass 2b: MEDIA: non-image tokens -> markdown links
  result = result.replace(
    /MEDIA:\s*([^\s)\]`]+)/gi,
    (full, raw) => {
      if (IMG_EXT_RE.test(raw)) return full;
      const relativeRaw = raw.startsWith(WORKSPACE_PREFIX) ? raw.substring(WORKSPACE_PREFIX.length) : raw;
      if (relativeRaw.startsWith('/')) return full;
      const relative = normalizeRelative(relativeRaw);
      const name = relative.includes('/') ? relative.substring(relative.lastIndexOf('/') + 1) : relative;
      return `[Generated file: ${name}](/__openclaw__/media/${relative})`;
    },
  );

  // Pass 2c: absolute workspace non-image paths -> markdown links
  result = result.replace(
    /(?<!\]\()\/home\/node\/\.openclaw\/workspace\/([^\s)\]`]+)/gi,
    (full, rel, offset) => {
      if (offset > 0 && result[offset - 1] === '(') return full;
      if (IMG_EXT_RE.test(rel)) return full;
      const relative = normalizeRelative(rel);
      const name = relative.includes('/') ? relative.substring(relative.lastIndexOf('/') + 1) : relative;
      return `[${name}](/__openclaw__/media/${relative})`;
    },
  );

  // Pass 3: bare /__openclaw__/media/ image URLs -> markdown images
  result = result.replace(
    new RegExp(
      '(?<!\\]\\()' + '(/__openclaw__/media/[^\\s)\\]`]+' + IMG_EXT_PATTERN + ')',
      'gi',
    ),
    (full, url, offset) => {
      if (offset > 0 && result[offset - 1] === '(') return full;
      return `![image](${url})`;
    },
  );

  // Pass 4: bare /__openclaw__/media/ non-image URLs -> markdown links
  result = result.replace(
    /(?<!\]\()(/__openclaw__\/media\/[^\s)\]`]+)/gi,
    (full, url, offset) => {
      if (offset > 0 && result[offset - 1] === '(') return full;
      if (IMG_EXT_RE.test(url)) return full;
      const name = url.includes('/') ? url.substring(url.lastIndexOf('/') + 1) : url;
      return `[${name}](${url})`;
    },
  );

  return result;
}

/* ================================================================== */
/*  Assistant stream key extraction                                    */
/* ================================================================== */

function assistantStreamKey(
  payload: Record<string, any>,
  message: Record<string, any>,
): string | undefined {
  const candidates = [
    message.id,
    message.messageId,
    payload.messageId,
    payload.id,
    payload.runId,
    message.runId,
    payload.turnId,
    message.turnId,
  ];
  for (const c of candidates) {
    const val = c?.toString();
    if (val) return val;
  }
  return undefined;
}

/* ================================================================== */
/*  File icon helper                                                   */
/* ================================================================== */

function getFileIcon(mime: string, fileName: string): ReactNode {
  const ext = fileName.includes('.') ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase() : '';
  if (mime.startsWith('image/')) return <ImageIcon size={10} />;
  if (mime === 'application/pdf' || ext === '.pdf') return <FileText size={10} />;
  if (['.xlsx', '.xls', '.csv', '.ods'].includes(ext) || mime.includes('spreadsheet') || mime === 'text/csv')
    return <FileSpreadsheet size={10} />;
  if (
    ['.py', '.js', '.ts', '.dart', '.java', '.c', '.cpp', '.go', '.rs', '.rb', '.php', '.sh'].includes(ext) ||
    mime.startsWith('text/x-')
  )
    return <FileCode size={10} />;
  return <FileIcon size={10} />;
}

/* ================================================================== */
/*  ChatStream (main component)                                        */
/* ================================================================== */

export function ChatStream() {
  const [entries, setEntries] = useState<ChatEntry[]>([]);
  const [agentThinking, setAgentThinking] = useState(false);
  const [showScrollBtn, setShowScrollBtn] = useState(false);

  const scrollRef = useRef<HTMLDivElement>(null);
  const pendingEchoesRef = useRef<PendingUserEcho[]>([]);
  const lastCanvasSurfaceRef = useRef<string | null>(null);
  const currentRunHadToolGapRef = useRef(false);
  const currentRunFirstAssistantSeqRef = useRef<number | null>(null);
  const historyLoadingRef = useRef(false);
  const prevSessionRef = useRef<string>('');
  const prevRefreshTickRef = useRef<number>(0);

  const activeSession = useSessionStore((s) => s.activeSession);
  const chatRefreshTick = useSessionStore((s) => s.chatRefreshTick);
  const processA2UIJsonl = useCanvasStore((s) => s.processA2UIJsonl);
  const authToken = useAuthStore((s) => s.token);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);

  /* ---------------------------------------------------------------- */
  /*  Scroll helpers                                                   */
  /* ---------------------------------------------------------------- */

  const isNearBottom = useCallback((): boolean => {
    const el = scrollRef.current;
    if (!el) return true;
    return el.scrollHeight - el.scrollTop - el.clientHeight < SCROLL_THRESHOLD;
  }, []);

  const scrollToBottom = useCallback((smooth = true) => {
    requestAnimationFrame(() => {
      const el = scrollRef.current;
      if (!el) return;
      el.scrollTo({
        top: el.scrollHeight,
        behavior: smooth ? 'smooth' : 'instant',
      });
    });
  }, []);

  const smartScrollToBottom = useCallback(() => {
    if (isNearBottom()) scrollToBottom();
  }, [isNearBottom, scrollToBottom]);

  const jumpToBottom = useCallback(() => {
    requestAnimationFrame(() => {
      const el = scrollRef.current;
      if (!el) return;
      el.scrollTop = el.scrollHeight;
      // Double-pass for late layout shifts
      requestAnimationFrame(() => {
        if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
      });
    });
  }, []);

  const handleScroll = useCallback(() => {
    const shouldShow = !isNearBottom();
    setShowScrollBtn((prev) => (prev !== shouldShow ? shouldShow : prev));
  }, [isNearBottom]);

  /* ---------------------------------------------------------------- */
  /*  Idempotency dedup                                                */
  /* ---------------------------------------------------------------- */

  const recordOptimisticUser = useCallback((content: string, idempotencyKey?: string) => {
    const now = Date.now();
    pendingEchoesRef.current.push({ content, idempotencyKey, createdAt: now });
    pendingEchoesRef.current = pendingEchoesRef.current.filter(
      (e) => now - e.createdAt < 20000,
    );
  }, []);

  const consumeOptimisticUser = useCallback(
    (content: string, idempotencyKey?: string): boolean => {
      const now = Date.now();
      const pending = pendingEchoesRef.current;
      pendingEchoesRef.current = pending.filter((e) => now - e.createdAt < 20000);

      for (let i = 0; i < pendingEchoesRef.current.length; i++) {
        const p = pendingEchoesRef.current[i];
        const sameId = idempotencyKey != null && p.idempotencyKey != null && p.idempotencyKey === idempotencyKey;
        const sameContent = p.content === content;
        if (sameId || sameContent) {
          pendingEchoesRef.current.splice(i, 1);
          return true;
        }
      }
      return false;
    },
    [],
  );

  /* ---------------------------------------------------------------- */
  /*  Tool entry update helper                                         */
  /* ---------------------------------------------------------------- */

  const updateLastToolEntry = useCallback(
    (
      prevEntries: ChatEntry[],
      content: string,
      opts: { isStreaming?: boolean; toolCallId?: string } = {},
    ): ChatEntry[] => {
      const updated = [...prevEntries];
      const { isStreaming = false, toolCallId } = opts;

      // Match by toolCallId
      if (toolCallId) {
        for (let i = updated.length - 1; i >= 0; i--) {
          if (updated[i].role === 'tool' && updated[i].toolCallId === toolCallId) {
            const elapsed = updated[i].startedAt ? Date.now() - updated[i].startedAt! : undefined;
            updated[i] = { ...updated[i], content, isStreaming, elapsed };
            return updated;
          }
          if (updated[i].role === 'user') break;
        }
      }
      // Fallback: most recent tool in current turn
      for (let i = updated.length - 1; i >= 0; i--) {
        if (updated[i].role === 'tool') {
          const elapsed = updated[i].startedAt ? Date.now() - updated[i].startedAt! : undefined;
          updated[i] = { ...updated[i], content, isStreaming, elapsed };
          return updated;
        }
        if (updated[i].role === 'user') break;
      }
      return updated;
    },
    [],
  );

  /* ---------------------------------------------------------------- */
  /*  Cap entries                                                       */
  /* ---------------------------------------------------------------- */

  const capEntries = useCallback((list: ChatEntry[]): ChatEntry[] => {
    if (list.length > MAX_ENTRIES) return list.slice(list.length - MAX_ENTRIES);
    return list;
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Find assistant index by stream key                               */
  /* ---------------------------------------------------------------- */

  const findAssistantByStreamKey = useCallback(
    (list: ChatEntry[], key: string, requireStreaming = false): number => {
      for (let i = list.length - 1; i >= 0; i--) {
        const e = list[i];
        if (e.role !== 'assistant') continue;
        if (requireStreaming && !e.isStreaming) continue;
        if (e.metadata?._streamKey === key) return i;
      }
      return -1;
    },
    [],
  );

  /* ---------------------------------------------------------------- */
  /*  Seed last canvas surface from history                            */
  /* ---------------------------------------------------------------- */

  const seedLastCanvasSurface = useCallback(
    (messages: any[]) => {
      for (let i = messages.length - 1; i >= 0; i--) {
        const msg = messages[i];
        if (typeof msg !== 'object' || msg === null) continue;
        const role = msg.role;
        if (role !== 'tool' && role !== 'toolResult') continue;
        const contentList = msg.content;
        if (!Array.isArray(contentList)) continue;
        for (const block of contentList) {
          if (typeof block !== 'object' || block === null) continue;
          const text = block.text;
          if (typeof text === 'string' && text.includes('__A2UI__')) {
            const payload = extractA2UIText(text);
            if (!payload) continue;
            lastCanvasSurfaceRef.current = payload;
            handleA2UIToolResult(payload);
            return;
          }
        }
      }
    },
    [],
  );

  /* ---------------------------------------------------------------- */
  /*  Load chat history                                                */
  /* ---------------------------------------------------------------- */

  const loadHistory = useCallback(async () => {
    if (historyLoadingRef.current) return;
    historyLoadingRef.current = true;
    try {
      const sessionKey = useSessionStore.getState().activeSession;
      const response = await gatewayClient.getChatHistory({
        sessionKey,
        limit: 50,
      });
      if (response.ok && response.payload) {
        const messages =
          response.payload.messages ?? response.payload.history ?? response.payload.entries;
        if (Array.isArray(messages)) {
          const newEntries: ChatEntry[] = [];
          for (const msg of messages) {
            if (typeof msg !== 'object' || msg === null) continue;
            let content = extractContent(msg.content);
            if (content.includes('__A2UI__')) content = 'Canvas updated';

            let timestamp = Date.now();
            const ts = msg.timestamp ?? msg.createdAt ?? msg.ts;
            if (typeof ts === 'number') timestamp = ts;
            else if (typeof ts === 'string') {
              const parsed = Date.parse(ts);
              if (!isNaN(parsed)) timestamp = parsed;
            }

            const rawRole = (msg.role as string) ?? 'system';
            const role = rawRole === 'toolResult' ? 'tool' : rawRole;
            const toolName = msg.toolName ?? msg.name ?? (role === 'tool' ? 'tool' : undefined);
            const toolCallId = role === 'tool' ? (msg.toolCallId ?? msg.id) : undefined;

            // Skip empty assistant entries
            if (role === 'assistant' && !content) continue;

            const historyAttachments = extractImageAttachments(msg.content);
            let meta: Record<string, any> | undefined;
            if (role === 'tool' && toolName) {
              const argsRaw = msg.args?.toString() ?? msg.input?.toString() ?? '';
              meta = parseToolMetadata(toolName, argsRaw);
            }

            newEntries.push({
              id: nextEntryId(),
              role: role as ChatEntry['role'],
              content,
              toolName,
              toolCallId,
              timestamp,
              metadata: meta,
              attachments: historyAttachments.length > 0 ? historyAttachments : undefined,
            });
          }
          setEntries(newEntries);
          seedLastCanvasSurface(messages);
          // Jump to bottom after history load
          setTimeout(() => jumpToBottom(), 50);
        }
      }
    } catch (e) {
      console.error('[Chat] loadHistory error:', e);
    } finally {
      historyLoadingRef.current = false;
    }
  }, [seedLastCanvasSurface, jumpToBottom]);

  /* ---------------------------------------------------------------- */
  /*  Poll canvas surface (after tool gap detected)                    */
  /* ---------------------------------------------------------------- */

  const pollCanvasSurface = useCallback(async () => {
    try {
      const sessionKey = useSessionStore.getState().activeSession;
      const response = await gatewayClient.getChatHistory({ sessionKey, limit: 10 });
      if (!response.ok || !response.payload) return;
      const messages = response.payload.messages;
      if (!Array.isArray(messages)) return;

      for (let i = messages.length - 1; i >= 0; i--) {
        const msg = messages[i];
        if (typeof msg !== 'object' || msg === null) continue;
        const role = msg.role;
        if (role !== 'tool' && role !== 'toolResult') continue;
        const contentList = msg.content;
        if (!Array.isArray(contentList)) continue;
        for (const block of contentList) {
          if (typeof block !== 'object' || block === null) continue;
          const text = block.text;
          if (typeof text === 'string' && text.includes('__A2UI__')) {
            const payload = extractA2UIText(text);
            if (!payload || payload === lastCanvasSurfaceRef.current) continue;
            lastCanvasSurfaceRef.current = payload;
            handleA2UIToolResult(payload);
            setEntries((prev) => {
              const updated = [...prev];
              const last = updated[updated.length - 1];
              if (last && last.role === 'tool' && last.isStreaming) {
                updated[updated.length - 1] = { ...last, content: 'Canvas updated', isStreaming: false };
              } else {
                updated.push({
                  id: nextEntryId(),
                  role: 'tool',
                  content: 'Canvas updated',
                  toolName: 'canvas_ui',
                  isStreaming: false,
                  timestamp: Date.now(),
                });
              }
              return capEntries(updated);
            });
            scrollToBottom();
            return;
          }
        }
      }
    } catch (e) {
      console.error('[Canvas] poll error:', e);
    }
  }, [capEntries, scrollToBottom]);

  /* ---------------------------------------------------------------- */
  /*  Gateway event handler                                            */
  /* ---------------------------------------------------------------- */

  const handleChatEvent = useCallback(
    (event: WsEvent) => {
      const payload = event.payload;

      if (event.event === 'chat') {
        const state = payload.state as string | undefined;
        const type = payload.type as string | undefined;

        // --- User message ---
        if (type === 'message' && payload.role === 'user') {
          const isLocalEcho = payload.localEcho === true;
          const content = (payload.content as string) ?? '';
          const idempotencyKey = payload.idempotencyKey as string | undefined;
          let attachments: Array<Record<string, any>> | undefined;
          if (Array.isArray(payload.attachments)) {
            attachments = payload.attachments.filter(
              (a: any) => typeof a === 'object' && a !== null,
            );
          }

          if (isLocalEcho) {
            recordOptimisticUser(content, idempotencyKey);
          } else if (consumeOptimisticUser(content, idempotencyKey)) {
            return; // Server echo for already-shown local echo
          }

          setEntries((prev) => {
            // Deduplicate: skip if the last entry is the same user message
            if (
              !isLocalEcho &&
              prev.length > 0 &&
              prev[prev.length - 1].role === 'user' &&
              prev[prev.length - 1].content === content
            ) {
              return prev;
            }
            return capEntries([
              ...prev,
              {
                id: nextEntryId(),
                role: 'user',
                content,
                attachments,
                idempotencyKey,
                localEcho: isLocalEcho,
                timestamp: Date.now(),
              },
            ]);
          });
          smartScrollToBottom();
          return;
        }

        // --- Assistant streaming / final ---
        if (state === 'delta' || state === 'final' || state === 'aborted') {
          const message = payload.message;
          if (typeof message !== 'object' || message === null) return;
          const msgMap = message as Record<string, any>;
          const streamKey = assistantStreamKey(payload, msgMap);
          const contentList = msgMap.content;
          if (!Array.isArray(contentList) || contentList.length === 0) return;

          // Find first text block (skip thinking blocks)
          let text = '';
          for (const block of contentList) {
            if (typeof block === 'object' && block !== null && block.type === 'text') {
              text = (block.text as string) ?? '';
              break;
            }
          }

          if (state === 'final' || state === 'aborted') {
            setEntries((prev) => {
              const updated = [...prev];
              const keyedIdx =
                streamKey != null ? findAssistantByStreamKey(updated, streamKey) : -1;
              const streamingIdx =
                keyedIdx !== -1
                  ? keyedIdx
                  : updated.findLastIndex((e) => e.role === 'assistant' && e.isStreaming);

              if (streamingIdx !== -1) {
                if (!text) {
                  // Remove empty streaming placeholder (tool-only turn)
                  updated.splice(streamingIdx, 1);
                } else {
                  updated[streamingIdx] = { ...updated[streamingIdx], content: text, isStreaming: false };
                }
              } else if (text) {
                // Check for duplicate
                const lastAsstIdx = updated.findLastIndex((e) => e.role === 'assistant');
                if (
                  lastAsstIdx !== -1 &&
                  !updated[lastAsstIdx].isStreaming &&
                  updated[lastAsstIdx].content === text
                ) {
                  return prev; // Already have this exact content
                }
                updated.push({
                  id: nextEntryId(),
                  role: 'assistant',
                  content: text,
                  timestamp: Date.now(),
                });
              }
              setAgentThinking(false);
              return capEntries(updated);
            });
          } else {
            // delta
            setEntries((prev) => {
              const updated = [...prev];
              const keyedStreamingIdx =
                streamKey != null
                  ? findAssistantByStreamKey(updated, streamKey, true)
                  : -1;
              const keyedIdx =
                streamKey != null ? findAssistantByStreamKey(updated, streamKey) : -1;
              const streamingIdx =
                keyedStreamingIdx !== -1
                  ? keyedStreamingIdx
                  : keyedIdx !== -1
                    ? keyedIdx
                    : updated.findLastIndex((e) => e.role === 'assistant' && e.isStreaming);

              if (streamingIdx !== -1) {
                updated[streamingIdx] = { ...updated[streamingIdx], content: text, isStreaming: true };
              } else if (text) {
                updated.push({
                  id: nextEntryId(),
                  role: 'assistant',
                  content: text,
                  isStreaming: true,
                  metadata: streamKey ? { _streamKey: streamKey } : undefined,
                  timestamp: Date.now(),
                });
              }
              setAgentThinking(false);
              return capEntries(updated);
            });
          }
          smartScrollToBottom();
          return;
        }
      }

      // --- Agent events ---
      if (event.event === 'agent') {
        const stream = payload.stream as string | undefined;
        const data = typeof payload.data === 'object' && payload.data !== null
          ? (payload.data as Record<string, any>)
          : undefined;

        // Track assistant seq for tool gap detection
        if (stream === 'assistant' && currentRunFirstAssistantSeqRef.current === null) {
          const seq = payload.seq;
          if (typeof seq === 'number') {
            currentRunFirstAssistantSeqRef.current = seq;
            if (seq >= 3) currentRunHadToolGapRef.current = true;
          }
        }

        if (stream === 'lifecycle') {
          const phase = data?.phase as string | undefined;
          if (phase === 'start') {
            setAgentThinking(true);
            currentRunHadToolGapRef.current = false;
            currentRunFirstAssistantSeqRef.current = null;
          } else if (phase === 'end') {
            setAgentThinking(false);
            // Clear stale streaming state for tool cards only
            setEntries((prev) => {
              let changed = false;
              const updated = prev.map((e) => {
                if (e.isStreaming && e.role === 'tool') {
                  changed = true;
                  return { ...e, isStreaming: false };
                }
                return e;
              });
              return changed ? updated : prev;
            });
            if (currentRunHadToolGapRef.current) {
              pollCanvasSurface();
            }
          }
          smartScrollToBottom();
          return;
        }

        if (stream === 'tool_call' || stream === 'tool') {
          const toolName = (data?.tool as string) ?? (data?.name as string) ?? 'tool';
          const phase = data?.phase as string | undefined;
          const toolCallId = (data?.id as string) ?? (data?.toolCallId as string) ?? undefined;
          const result = data?.result?.toString() ?? data?.output?.toString() ?? '';

          if (phase === 'end' || phase === 'result') {
            // Tool finished
            const a2uiPayload = extractA2UIText(result);
            if (a2uiPayload) {
              handleA2UIToolResult(a2uiPayload);
              setEntries((prev) =>
                capEntries(updateLastToolEntry(prev, 'Canvas updated', { toolCallId })),
              );
            } else {
              const mediaArtifacts = extractMediaArtifacts(result);
              const displayResult = result || 'Done';
              setEntries((prev) => {
                let updated = updateLastToolEntry(prev, displayResult, { toolCallId });
                for (const artifact of mediaArtifacts) {
                  const url = artifact.url ?? '';
                  const name = artifact.fileName ?? 'file';
                  const isImage = artifact.isImage === true;
                  updated.push({
                    id: nextEntryId(),
                    role: 'assistant',
                    content: isImage ? `![Generated image](${url})` : `[Generated file: ${name}](${url})`,
                    attachments: isImage
                      ? undefined
                      : [{ fileName: name, url, type: 'file' }],
                    timestamp: Date.now(),
                  });
                }
                return capEntries(updated);
              });
            }
          } else {
            // Tool started or in progress
            const argsRaw = data?.args;
            const meta = parseToolMetadata(toolName, argsRaw);
            setEntries((prev) =>
              capEntries([
                ...prev,
                {
                  id: nextEntryId(),
                  role: 'tool',
                  content: argsRaw?.toString() ?? '',
                  toolName,
                  toolCallId,
                  isStreaming: true,
                  metadata: meta,
                  startedAt: Date.now(),
                  timestamp: Date.now(),
                },
              ]),
            );
            setAgentThinking(false);
          }
          smartScrollToBottom();
          return;
        }

        if (stream === 'tool_result') {
          const toolCallId = (data?.id as string) ?? (data?.toolCallId as string) ?? undefined;
          const result = data?.result?.toString() ?? data?.output?.toString() ?? '';
          const a2uiPayload = extractA2UIText(result);
          if (a2uiPayload) {
            handleA2UIToolResult(a2uiPayload);
            setEntries((prev) =>
              capEntries(updateLastToolEntry(prev, 'Canvas updated', { toolCallId })),
            );
          } else {
            setEntries((prev) =>
              capEntries(updateLastToolEntry(prev, result || 'Done', { toolCallId })),
            );
          }
          smartScrollToBottom();
          return;
        }
      }
    },
    [
      recordOptimisticUser,
      consumeOptimisticUser,
      capEntries,
      smartScrollToBottom,
      updateLastToolEntry,
      findAssistantByStreamKey,
      pollCanvasSurface,
    ],
  );

  /* ---------------------------------------------------------------- */
  /*  Subscribe to gateway events                                      */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    const unsub = gatewayClient.onEvent(handleChatEvent);
    return unsub;
  }, [handleChatEvent]);

  /* ---------------------------------------------------------------- */
  /*  Load history on connect and session/tick change                   */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    // Load history when gateway becomes connected
    const unsub = gatewayClient.onStateChange((state) => {
      if (state === 'connected') loadHistory();
    });
    // Also load if already connected
    if (gatewayClient.connectionState === 'connected') loadHistory();
    return unsub;
  }, [loadHistory]);

  // Session change -> reload history
  useEffect(() => {
    if (prevSessionRef.current && prevSessionRef.current !== activeSession) {
      setEntries([]);
      setAgentThinking(false);
      loadHistory();
    }
    prevSessionRef.current = activeSession;
  }, [activeSession, loadHistory]);

  // Refresh tick change -> reload history
  useEffect(() => {
    if (prevRefreshTickRef.current !== chatRefreshTick && prevRefreshTickRef.current !== 0) {
      loadHistory();
    }
    prevRefreshTickRef.current = chatRefreshTick;
  }, [chatRefreshTick, loadHistory]);

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  const isEmpty = entries.length === 0 && !agentThinking;

  if (isEmpty) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="flex flex-col items-center gap-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-[var(--shell-radius)] border-[0.5px] border-border-shell">
            <MessageCircle size={16} className="text-fg-muted" />
          </div>
          <span className="text-[11px] tracking-wide text-fg-muted">start a conversation</span>
          <span className="text-[10px] text-fg-placeholder">type a message below</span>
        </div>
      </div>
    );
  }

  return (
    <div className="relative h-full">
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="h-full overflow-y-auto px-4 py-3"
      >
        {entries.map((entry, index) => {
          const prev = index > 0 ? entries[index - 1] : null;
          const isNewSender = !prev || prev.role !== entry.role;

          switch (entry.role) {
            case 'user':
              return <UserBubble key={entry.id} entry={entry} isNewSender={isNewSender} />;
            case 'assistant':
              if (!entry.content && !entry.isStreaming) return null;
              return (
                <AssistantBubble
                  key={entry.id}
                  entry={entry}
                  isNewSender={isNewSender}
                  authToken={authToken}
                  openclawId={activeOpenClawId}
                />
              );
            case 'tool':
              return <ToolCard key={entry.id} entry={entry} />;
            default:
              return <SystemMessage key={entry.id} entry={entry} />;
          }
        })}

        {agentThinking && <ThinkingIndicator />}
      </div>

      {/* Floating scroll-to-bottom button */}
      {showScrollBtn && (
        <button
          onClick={() => {
            scrollToBottom();
            setShowScrollBtn(false);
          }}
          className="absolute bottom-2 right-3 flex h-7 w-7 items-center justify-center rounded-[var(--shell-radius)] border-[0.5px] border-border-shell bg-surface-card text-fg-muted hover:text-fg-secondary"
        >
          <ChevronDown size={16} />
        </button>
      )}
    </div>
  );
}

/* ================================================================== */
/*  UserBubble                                                         */
/* ================================================================== */

function UserBubble({ entry, isNewSender }: { entry: ChatEntry; isNewSender: boolean }) {
  const [hovering, setHovering] = useState(false);
  const [copied, setCopied] = useState(false);

  const copyMessage = useCallback(() => {
    navigator.clipboard.writeText(entry.content).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }).catch(() => {});
  }, [entry.content]);

  const imageAttachments = useMemo(() => {
    if (!entry.attachments) return [];
    return entry.attachments
      .map((a, i) => {
        const mime = (a.mimeType as string) ?? '';
        const b64 = (a.content as string) ?? (a.base64 as string) ?? null;
        if (mime.startsWith('image/') && b64) {
          return { index: i, dataUri: `data:${mime};base64,${b64}` };
        }
        return null;
      })
      .filter(Boolean) as Array<{ index: number; dataUri: string }>;
  }, [entry.attachments]);

  return (
    <div
      className={`flex justify-end ${isNewSender ? 'mt-3.5' : 'mt-0.5'} pl-20`}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      <div className="max-w-full rounded-[var(--shell-radius)] border-[0.5px] border-accent-primary/18 bg-accent-primary/8 px-3.5 py-2.5">
        {/* Image attachment thumbnails */}
        {imageAttachments.length > 0 && (
          <div className="mb-1.5 flex flex-wrap justify-end gap-1">
            {imageAttachments.map((img) => (
              <div
                key={img.index}
                className="max-h-[120px] max-w-[180px] overflow-hidden rounded-[var(--shell-radius-sm)] border-[0.5px] border-border-shell"
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={img.dataUri} alt="attachment" className="h-full w-full object-cover" />
              </div>
            ))}
          </div>
        )}

        {/* File chips for non-image attachments */}
        {entry.attachments && entry.attachments.length > 0 && (
          <div className="mb-1.5 flex flex-wrap justify-end gap-1">
            {entry.attachments.map((a, i) => {
              const mime = (a.mimeType as string) ?? '';
              if (mime.startsWith('image/') && (a.content || a.base64)) return null;
              const name = (a.fileName as string) ?? (a.name as string) ?? 'file';
              const url = a.url as string | undefined;
              const resolvedUrl = url ? resolveMediaHref(url) : undefined;
              return (
                <a
                  key={i}
                  href={resolvedUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={`flex items-center gap-1 rounded-[var(--shell-radius-sm)] border-[0.5px] ${
                    resolvedUrl ? 'border-accent-primary-muted' : 'border-border-shell'
                  } bg-surface-card px-1.5 py-0.5`}
                >
                  <span className={resolvedUrl ? 'text-accent-primary' : 'text-fg-muted'}>
                    {getFileIcon(mime, name)}
                  </span>
                  <span
                    className={`text-[9px] ${
                      resolvedUrl ? 'text-accent-primary underline' : 'text-fg-tertiary'
                    }`}
                  >
                    {name}
                  </span>
                </a>
              );
            })}
          </div>
        )}

        {/* Markdown content */}
        {entry.content && entry.content !== '[attachment]' && (
          <div className="prose-sm text-sm text-fg-primary [&_a]:text-accent-primary [&_a]:underline [&_code]:bg-surface-code-inline [&_code]:text-accent-primary [&_pre]:rounded-[var(--shell-radius-sm)] [&_pre]:border-l-2 [&_pre]:border-border-shell [&_pre]:bg-surface-base [&_pre]:pl-3">
            <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeRaw]}>
              {entry.content}
            </ReactMarkdown>
          </div>
        )}

        {/* Footer: copy + timestamp */}
        <div className="mt-1 flex items-center justify-end gap-2">
          {hovering && (
            <button onClick={copyMessage} className="flex items-center gap-1 text-fg-muted hover:text-fg-secondary">
              {copied ? <Check size={12} className="text-accent-primary" /> : <Copy size={12} />}
              <span className={`text-[9px] ${copied ? 'text-accent-primary' : ''}`}>
                {copied ? 'copied' : 'copy'}
              </span>
            </button>
          )}
          <span className="text-[9px] text-fg-muted">{formatTimestamp(entry.timestamp)}</span>
        </div>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  AssistantBubble                                                    */
/* ================================================================== */

function AssistantBubble({
  entry,
  isNewSender,
  authToken,
  openclawId,
}: {
  entry: ChatEntry;
  isNewSender: boolean;
  authToken?: string | null;
  openclawId?: string | null;
}) {
  const [hovering, setHovering] = useState(false);
  const [copied, setCopied] = useState(false);

  const copyMessage = useCallback(() => {
    navigator.clipboard.writeText(entry.content).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }).catch(() => {});
  }, [entry.content]);

  const enrichedContent = useMemo(() => enrichContentWithImages(entry.content), [entry.content]);

  return (
    <div
      className={`${isNewSender ? 'mt-3.5' : 'mt-0.5'} pr-12`}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      {isNewSender && (
        <div className="mb-1 ml-0.5 text-[10px] tracking-wide text-fg-tertiary">trinity</div>
      )}
      <div className="w-full rounded-[var(--shell-radius)] border-[0.5px] border-border-shell bg-surface-card px-3.5 py-2.5">
        {/* Markdown content with full GFM */}
        <div className="prose-sm max-w-none text-sm text-fg-primary [&_a]:text-accent-primary [&_a]:underline [&_a]:decoration-accent-primary-muted [&_blockquote]:border-l-2 [&_blockquote]:border-fg-disabled [&_blockquote]:pl-3 [&_code]:bg-surface-code-inline [&_code]:text-[13px] [&_code]:text-accent-primary [&_h1]:text-base [&_h1]:font-bold [&_h2]:text-[15px] [&_h2]:font-bold [&_h3]:text-sm [&_h3]:font-bold [&_hr]:border-border-shell [&_img]:max-h-[300px] [&_img]:max-w-[400px] [&_img]:rounded-[var(--shell-radius-sm)] [&_pre]:rounded-[var(--shell-radius-sm)] [&_pre]:border-l-2 [&_pre]:border-border-shell [&_pre]:bg-surface-base [&_pre]:pl-3 [&_table]:border-collapse [&_td]:border [&_td]:border-border-shell [&_td]:px-2 [&_td]:py-1 [&_th]:border [&_th]:border-border-shell [&_th]:px-2 [&_th]:py-1 [&_th]:text-left [&_th]:font-bold">
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            rehypePlugins={[rehypeRaw]}
            components={{
              // Resolve image src for media URLs
              img: ({ src, alt, ...props }) => {
                const resolved = src ? resolveMediaHref(src, authToken, openclawId) : '';
                return (
                  <ChatImage
                    url={resolved}
                    alt={alt ?? 'image'}
                    authToken={authToken}
                    openclawId={openclawId}
                  />
                );
              },
              // Open links in new tab
              a: ({ href, children, ...props }) => (
                <a
                  href={href ? resolveMediaHref(href, authToken, openclawId) : undefined}
                  target="_blank"
                  rel="noopener noreferrer"
                  {...props}
                >
                  {children}
                </a>
              ),
            }}
          >
            {enrichedContent}
          </ReactMarkdown>
        </div>

        {/* Streaming indicator */}
        {entry.isStreaming && (
          <div className="mt-1">
            <StreamingIndicator />
          </div>
        )}

        {/* Footer: timestamp + copy */}
        <div className="mt-1.5 flex items-center">
          <span className="text-[9px] text-fg-muted">{formatTimestamp(entry.timestamp)}</span>
          <div className="flex-1" />
          {hovering && !entry.isStreaming && (
            <button onClick={copyMessage} className="flex items-center gap-1 text-fg-muted hover:text-fg-secondary">
              {copied ? <Check size={12} className="text-accent-primary" /> : <Copy size={12} />}
              <span className={`text-[9px] ${copied ? 'text-accent-primary' : ''}`}>
                {copied ? 'copied' : 'copy'}
              </span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  ChatImage — inline image with hover toolbar                        */
/* ================================================================== */

function ChatImage({
  url,
  alt,
  authToken,
  openclawId,
}: {
  url: string;
  alt: string;
  authToken?: string | null;
  openclawId?: string | null;
}) {
  const [hovering, setHovering] = useState(false);
  const [copied, setCopied] = useState(false);
  const [loadError, setLoadError] = useState(false);

  const resolvedUrl = useMemo(
    () => resolveMediaHref(url, authToken, openclawId),
    [url, authToken, openclawId],
  );

  const copyUrl = useCallback(() => {
    navigator.clipboard.writeText(resolvedUrl).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }).catch(() => {});
  }, [resolvedUrl]);

  const downloadImage = useCallback(() => {
    const a = document.createElement('a');
    a.href = resolvedUrl;
    const filename = resolvedUrl.split('/').pop()?.split('?')[0] ?? 'image.png';
    a.download = filename;
    a.click();
  }, [resolvedUrl]);

  if (loadError) {
    return (
      <div className="inline-block rounded-[var(--shell-radius-sm)] border-[0.5px] border-border-shell bg-surface-base px-2 py-1.5 text-[11px] text-fg-muted">
        [image failed to load]
      </div>
    );
  }

  return (
    <span
      className="relative inline-block"
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={resolvedUrl}
        alt={alt}
        className="max-h-[300px] max-w-[400px] rounded-[var(--shell-radius-sm)] object-contain"
        onError={() => setLoadError(true)}
      />
      {hovering && (
        <span className="absolute right-1 top-1 flex items-center gap-px rounded-[var(--shell-radius-sm)] border-[0.5px] border-border-shell bg-surface-base/85">
          <button onClick={copyUrl} className="flex items-center gap-0.5 px-1.5 py-1">
            {copied ? (
              <Check size={12} className="text-accent-primary" />
            ) : (
              <Copy size={12} className="text-fg-muted" />
            )}
            <span className="text-[10px] text-fg-muted">{copied ? 'copied' : 'copy'}</span>
          </button>
          <span className="h-4 w-px bg-border-shell" />
          <button onClick={downloadImage} className="flex items-center gap-0.5 px-1.5 py-1">
            <Download size={12} className="text-fg-muted" />
            <span className="text-[10px] text-fg-muted">download</span>
          </button>
        </span>
      )}
    </span>
  );
}

/* ================================================================== */
/*  ToolCard                                                           */
/* ================================================================== */

function ToolCard({ entry }: { entry: ChatEntry }) {
  const [expanded, setExpanded] = useState(false);
  const COLLAPSED_LIMIT = 300;
  const EXPANDED_LIMIT = 1500;

  const toolName = entry.toolName ?? 'tool';
  const summary = getMetadataSummary(entry.toolName, entry.metadata);
  const detail = getMetadataDetail(entry.toolName, entry.metadata);
  const isStreaming = entry.isStreaming ?? false;
  const elapsed = entry.elapsed;

  const rawContent = entry.content;
  const showResult = !isStreaming && rawContent.length > 0;
  const canExpand = showResult && rawContent.length > COLLAPSED_LIMIT;
  const hardCapped = showResult && rawContent.length > EXPANDED_LIMIT;

  let displayResult = '';
  if (showResult) {
    if (!canExpand) {
      displayResult = rawContent;
    } else if (expanded) {
      displayResult = hardCapped
        ? `${rawContent.substring(0, EXPANDED_LIMIT)}... (truncated)`
        : rawContent;
    } else {
      displayResult = `${rawContent.substring(0, COLLAPSED_LIMIT)}...`;
    }
  }

  const showToggle = canExpand && !(expanded && hardCapped);

  return (
    <div className="mt-0.5 mb-0.5 pr-12">
      <div className="rounded-[var(--shell-radius-sm)] border-[0.5px] border-border-shell bg-surface-base px-2.5 py-1.5">
        {/* Header: [dots] toolName [elapsed] */}
        <div className="flex items-center gap-1.5">
          {isStreaming && (
            <div className="w-[22px]">
              <StreamingIndicator />
            </div>
          )}
          <span
            className={`text-[10px] tracking-wide ${
              isStreaming ? 'text-accent-primary' : 'text-fg-tertiary'
            }`}
          >
            {toolName}
          </span>
          {elapsed != null && (
            <span className="text-[9px] tracking-wide text-fg-muted">
              {formatElapsed(elapsed)}
            </span>
          )}
        </div>

        {/* Metadata summary line */}
        {summary && (
          <div
            className={`mt-0.5 max-w-full truncate text-[11px] font-medium leading-snug ${
              isStreaming ? 'text-fg-secondary' : 'text-fg-tertiary'
            }`}
            title={summary}
          >
            {summary}
          </div>
        )}

        {/* Detail line */}
        {detail && (
          <div className="mt-px text-[9px] tracking-wide text-fg-muted">{detail}</div>
        )}

        {/* Result content */}
        {showResult && displayResult && (
          <pre className="mt-1 max-w-full overflow-x-auto whitespace-pre-wrap break-words text-[11px] leading-snug text-fg-tertiary">
            {displayResult}
          </pre>
        )}

        {/* Streaming raw args fallback */}
        {isStreaming && !summary && rawContent && (
          <pre className="mt-1 max-w-full overflow-x-auto whitespace-pre-wrap break-words text-[11px] leading-snug text-fg-tertiary">
            {rawContent.length > COLLAPSED_LIMIT
              ? `${rawContent.substring(0, COLLAPSED_LIMIT)}...`
              : rawContent}
          </pre>
        )}

        {/* Expand/collapse toggle */}
        {showToggle && (
          <button
            onClick={() => setExpanded(!expanded)}
            className="mt-0.5 flex items-center gap-0.5 text-[10px] text-accent-primary hover:underline"
          >
            {expanded ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
            {expanded ? 'show less' : 'show more'}
          </button>
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  StreamingIndicator — 3 animated dots                               */
/* ================================================================== */

function StreamingIndicator() {
  return (
    <span className="inline-flex items-center gap-1">
      <span
        className="h-1 w-1 rounded-full bg-accent-primary animate-pulse-dot"
        style={{ animationDelay: '0s' }}
      />
      <span
        className="h-1 w-1 rounded-full bg-accent-primary animate-pulse-dot"
        style={{ animationDelay: '0.2s' }}
      />
      <span
        className="h-1 w-1 rounded-full bg-accent-primary animate-pulse-dot"
        style={{ animationDelay: '0.4s' }}
      />
    </span>
  );
}

/* ================================================================== */
/*  ThinkingIndicator                                                  */
/* ================================================================== */

function ThinkingIndicator() {
  return (
    <div className="mt-3 mb-1 flex items-start pr-20">
      <div className="flex items-center gap-2 rounded-[var(--shell-radius)] border-[0.5px] border-border-shell bg-surface-card px-3.5 py-2.5">
        <StreamingIndicator />
        <span className="text-[11px] text-fg-tertiary">thinking</span>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  SystemMessage                                                      */
/* ================================================================== */

function SystemMessage({ entry }: { entry: ChatEntry }) {
  return (
    <div className="py-2 text-center">
      <span className="text-[11px] text-fg-disabled">{entry.content}</span>
    </div>
  );
}
