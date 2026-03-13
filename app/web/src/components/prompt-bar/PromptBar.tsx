'use client';

import React, {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  Paperclip,
  Mic,
  MicOff,
  Square,
  Bookmark,
  Send,
  X,
  FileText,
  Image as ImageIcon,
  Music,
  Video,
  FileSpreadsheet,
  Loader2,
  AlertTriangle,
} from 'lucide-react';
import { gatewayClient } from '@/lib/stores/gateway-store';
import { useSessionStore } from '@/lib/stores/session-store';
import { useAuthStore } from '@/lib/stores/auth-store';
import {
  validateFile,
  shouldCompressImage,
  compressImage,
  readFileAsBase64,
  uploadFileToWorkspace,
  AttachmentLimits,
} from '@/lib/utils/attachment-utils';

/* ================================================================== */
/*  PromptTemplate data model                                          */
/* ================================================================== */

export interface PromptTemplate {
  name: string;
  content: string;
  category: 'built-in' | 'custom';
}

/* ================================================================== */
/*  PromptTemplateStore — localStorage persistence                     */
/* ================================================================== */

const STORAGE_KEY = 'trinity_prompt_templates';

const BUILT_IN_TEMPLATES: PromptTemplate[] = [
  {
    name: 'Summarize',
    content: 'Summarize the following in clear, concise bullet points:\n\n',
    category: 'built-in',
  },
  {
    name: 'Explain',
    content: 'Explain this in simple terms that anyone can understand:\n\n',
    category: 'built-in',
  },
  {
    name: 'Rewrite',
    content: 'Rewrite the following to be clearer and more professional:\n\n',
    category: 'built-in',
  },
  {
    name: 'Translate',
    content: 'Translate the following to [language]:\n\n',
    category: 'built-in',
  },
  {
    name: 'Brainstorm',
    content: 'Help me brainstorm ideas for:\n\n',
    category: 'built-in',
  },
  {
    name: 'Draft Email',
    content:
      'Draft a professional email about:\n\nTone: [formal/friendly/casual]\nTo: [recipient]\n\n',
    category: 'built-in',
  },
  {
    name: 'Pros and Cons',
    content: 'List the pros and cons of:\n\n',
    category: 'built-in',
  },
  {
    name: 'Action Items',
    content: 'Extract the action items and next steps from:\n\n',
    category: 'built-in',
  },
  {
    name: 'Canvas Dashboard',
    content: 'Build a dashboard on the canvas showing:\n\n',
    category: 'built-in',
  },
  {
    name: 'Compare',
    content:
      'Compare and contrast the following options:\n\n1. \n2. \n\nConsider: cost, quality, ease of use, and timeline.',
    category: 'built-in',
  },
];

export class PromptTemplateStore {
  static loadCustom(): PromptTemplate[] {
    if (typeof window === 'undefined') return [];
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (!stored) return [];
      const list = JSON.parse(stored) as unknown[];
      return list
        .filter(
          (item): item is Record<string, unknown> =>
            typeof item === 'object' && item !== null,
        )
        .map((j) => ({
          name: (j.name as string) ?? '',
          content: (j.content as string) ?? '',
          category: (j.category as 'custom') ?? 'custom',
        }));
    } catch {
      return [];
    }
  }

  static saveCustom(templates: PromptTemplate[]): void {
    if (typeof window === 'undefined') return;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(templates));
  }

  static all(): PromptTemplate[] {
    return [...BUILT_IN_TEMPLATES, ...this.loadCustom()];
  }

  static addCustom(template: PromptTemplate): void {
    const custom = this.loadCustom();
    custom.push({ ...template, category: 'custom' });
    this.saveCustom(custom);
  }

  static removeCustom(name: string): void {
    const custom = this.loadCustom().filter((t) => t.name !== name);
    this.saveCustom(custom);
  }

  static updateCustom(oldName: string, updated: PromptTemplate): void {
    const custom = this.loadCustom();
    const idx = custom.findIndex((t) => t.name === oldName);
    if (idx >= 0) {
      custom[idx] = updated;
    } else {
      custom.push(updated);
    }
    this.saveCustom(custom);
  }
}

/* ================================================================== */
/*  PromptTemplatePanel — floating overlay                             */
/* ================================================================== */

interface PromptTemplatePanelProps {
  filter: string;
  activeIndex: number;
  onSelect: (content: string) => void;
  onDismiss: () => void;
}

function PromptTemplatePanel({
  filter,
  activeIndex,
  onSelect,
  onDismiss,
}: PromptTemplatePanelProps) {
  const [templates, setTemplates] = useState<PromptTemplate[]>(() =>
    PromptTemplateStore.all(),
  );
  const scrollRef = useRef<HTMLDivElement>(null);

  const filtered = useMemo(() => {
    if (!filter) return templates;
    const q = filter.toLowerCase();
    return templates.filter(
      (t) =>
        t.name.toLowerCase().includes(q) ||
        t.category.toLowerCase().includes(q),
    );
  }, [templates, filter]);

  const clampedIndex = filtered.length > 0
    ? Math.min(Math.max(activeIndex, 0), filtered.length - 1)
    : -1;

  // Auto-scroll to active item
  useEffect(() => {
    if (clampedIndex < 0 || !scrollRef.current) return;
    const row = scrollRef.current.children[clampedIndex] as HTMLElement | undefined;
    row?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }, [clampedIndex]);

  const handleRemoveCustom = useCallback(
    (name: string) => {
      PromptTemplateStore.removeCustom(name);
      setTemplates(PromptTemplateStore.all());
    },
    [],
  );

  return (
    <div
      className="w-80 max-h-[360px] flex flex-col border border-[var(--border)] bg-[var(--surface-base)] shadow-lg font-mono"
      style={{ boxShadow: '0 -4px 12px rgba(0,0,0,0.2)' }}
    >
      {/* Header */}
      <div className="h-8 shrink-0 flex items-center justify-between px-3 border-b border-[var(--border)]">
        <span className="text-[10px] text-[var(--fg-muted)]">
          prompt templates
        </span>
        <button
          type="button"
          className="text-[10px] text-[var(--fg-muted)] hover:text-[var(--fg-secondary)] cursor-pointer bg-transparent border-none"
          onClick={() => {
            onDismiss();
            // TODO: open PromptTemplateManagerDialog
          }}
        >
          manage
        </button>
      </div>

      {/* Template list */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto py-0.5">
        {filtered.length === 0 && (
          <div className="px-3 py-4 text-center text-[10px] text-[var(--fg-disabled)]">
            no templates match
          </div>
        )}
        {filtered.map((tmpl, index) => (
          <TemplateRow
            key={`${tmpl.category}-${tmpl.name}`}
            template={tmpl}
            isActive={index === clampedIndex}
            onSelect={() => onSelect(tmpl.content)}
            onDelete={
              tmpl.category === 'custom'
                ? () => handleRemoveCustom(tmpl.name)
                : undefined
            }
          />
        ))}
      </div>

      {/* Footer: + new */}
      <button
        type="button"
        className="h-[30px] shrink-0 flex items-center justify-center border-t border-[var(--border)] text-[10px] text-[var(--accent-primary)] hover:bg-[var(--surface-card)] cursor-pointer bg-transparent w-full"
        onClick={() => {
          onDismiss();
          // TODO: open PromptTemplateManagerDialog in add mode
        }}
      >
        + new
      </button>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  TemplateRow                                                        */
/* ------------------------------------------------------------------ */

interface TemplateRowProps {
  template: PromptTemplate;
  isActive: boolean;
  onSelect: () => void;
  onDelete?: () => void;
}

function TemplateRow({ template, isActive, onSelect, onDelete }: TemplateRowProps) {
  const [hovering, setHovering] = useState(false);

  return (
    <div
      className={`h-9 flex items-center px-3 cursor-pointer transition-colors ${
        isActive || hovering ? 'bg-[var(--surface-card)]' : ''
      }`}
      style={
        isActive
          ? { borderLeft: '2px solid var(--accent-primary)' }
          : { borderLeft: '2px solid transparent' }
      }
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      onClick={onSelect}
    >
      <div className="flex-1 min-w-0 flex flex-col justify-center">
        <span className="text-[11px] text-[var(--fg-secondary)] leading-tight truncate">
          {template.name}
        </span>
        <span className="text-[9px] text-[var(--fg-muted)] leading-tight truncate">
          {template.content.replace(/\n/g, ' ').trim()}
        </span>
      </div>
      <span className="shrink-0 ml-2 px-1 py-px text-[8px] text-[var(--fg-disabled)] border border-[var(--border)]">
        {template.category}
      </span>
      {onDelete && hovering && (
        <button
          type="button"
          className="shrink-0 ml-1.5 p-0 bg-transparent border-none cursor-pointer text-[var(--fg-muted)] hover:text-[var(--fg-secondary)]"
          onClick={(e) => {
            e.stopPropagation();
            onDelete();
          }}
        >
          <X size={10} />
        </button>
      )}
    </div>
  );
}

/* ================================================================== */
/*  Attachment types + helpers                                         */
/* ================================================================== */

interface AttachmentInfo {
  name: string;
  mimeType: string;
  base64: string;
  size: number;
}

function iconForMime(mime: string) {
  if (mime.startsWith('image/')) return ImageIcon;
  if (mime.startsWith('audio/')) return Music;
  if (mime.startsWith('video/')) return Video;
  if (mime.includes('pdf')) return FileText;
  if (mime.includes('spreadsheet') || mime.includes('excel') || mime.includes('csv'))
    return FileSpreadsheet;
  return FileText;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

/* ------------------------------------------------------------------ */
/*  AttachmentChip                                                     */
/* ------------------------------------------------------------------ */

function AttachmentChip({
  attachment,
  onRemove,
}: {
  attachment: AttachmentInfo;
  onRemove: () => void;
}) {
  const [hovering, setHovering] = useState(false);
  const Icon = iconForMime(attachment.mimeType);

  return (
    <div
      className="shrink-0 mr-1.5 flex items-center gap-1 px-2 py-1 bg-[var(--surface-card)] border border-[var(--border)] max-w-[180px]"
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
    >
      <Icon size={12} className="shrink-0 text-[var(--fg-tertiary)]" />
      <span className="text-[10px] text-[var(--fg-secondary)] truncate">
        {attachment.name}
      </span>
      <span className="text-[8px] text-[var(--fg-muted)] shrink-0">
        {formatSize(attachment.size)}
      </span>
      {hovering && (
        <button
          type="button"
          className="shrink-0 p-0 bg-transparent border-none cursor-pointer text-[var(--fg-muted)] hover:text-[var(--fg-secondary)]"
          onClick={onRemove}
        >
          <X size={10} />
        </button>
      )}
    </div>
  );
}

/* ================================================================== */
/*  SpeechRecognition type shim                                        */
/* ================================================================== */

interface SpeechRecognitionEvent extends Event {
  results: SpeechRecognitionResultList;
  resultIndex: number;
}

interface SpeechRecognitionErrorEvent extends Event {
  error: string;
}

type SpeechRecognitionCtor = new () => SpeechRecognitionInstance;

interface SpeechRecognitionInstance extends EventTarget {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onresult: ((e: SpeechRecognitionEvent) => void) | null;
  onerror: ((e: SpeechRecognitionErrorEvent) => void) | null;
  onend: (() => void) | null;
  start(): void;
  stop(): void;
  abort(): void;
}

function getSpeechRecognition(): SpeechRecognitionCtor | null {
  if (typeof window === 'undefined') return null;
  return (
    (window as any).SpeechRecognition ??
    (window as any).webkitSpeechRecognition ??
    null
  );
}

/* ================================================================== */
/*  SaveTemplateDialog (inline modal)                                  */
/* ================================================================== */

function SaveTemplateDialog({
  initialContent,
  onClose,
}: {
  initialContent: string;
  onClose: () => void;
}) {
  const [name, setName] = useState('');
  const [content, setContent] = useState(initialContent);
  const nameRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    nameRef.current?.focus();
  }, []);

  const handleSave = () => {
    const trimName = name.trim();
    const trimContent = content.trim();
    if (!trimName || !trimContent) return;
    PromptTemplateStore.addCustom({
      name: trimName,
      content: trimContent,
      category: 'custom',
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div
        className="w-[400px] p-4 bg-[var(--surface-base)] border border-[var(--border)] font-mono"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="text-xs text-[var(--fg-primary)] mb-3">
          save as template
        </div>
        <input
          ref={nameRef}
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') handleSave();
          }}
          placeholder="template name"
          className="w-full bg-transparent border-b border-[var(--border)] focus:border-[var(--accent-primary)] text-xs text-[var(--fg-primary)] placeholder:text-[var(--fg-placeholder)] py-1 outline-none mb-2.5"
        />
        <div className="border border-[var(--border)] max-h-[140px]">
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={4}
            className="w-full bg-transparent text-xs text-[var(--fg-primary)] placeholder:text-[var(--fg-placeholder)] p-2 outline-none resize-none"
            placeholder="template content..."
          />
        </div>
        <div className="flex justify-end gap-3 mt-3">
          <button
            type="button"
            onClick={onClose}
            className="text-[11px] text-[var(--fg-muted)] hover:text-[var(--fg-secondary)] cursor-pointer bg-transparent border-none"
          >
            cancel
          </button>
          <button
            type="button"
            onClick={handleSave}
            className="text-[11px] text-[var(--accent-primary)] hover:text-[var(--fg-primary)] cursor-pointer bg-transparent border-none"
          >
            save
          </button>
        </div>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  PromptBar — main component                                         */
/* ================================================================== */

export interface PromptBarHandle {
  addDroppedFiles: (files: File[]) => void;
}

export interface PromptBarProps {
  enabled?: boolean;
}

const PromptBar = forwardRef<PromptBarHandle, PromptBarProps>(
  function PromptBar({ enabled = true }, ref) {
    /* ---------------------------------------------------------------- */
    /*  State                                                            */
    /* ---------------------------------------------------------------- */

    const [text, setText] = useState('');
    const [sending, setSending] = useState(false);
    const [showTemplates, setShowTemplates] = useState(false);
    const [activeTemplateIndex, setActiveTemplateIndex] = useState(0);
    const [dismissedAtText, setDismissedAtText] = useState<string | null>(null);
    const [attachments, setAttachments] = useState<AttachmentInfo[]>([]);
    const [attachError, setAttachError] = useState<string | null>(null);
    const [processingCount, setProcessingCount] = useState(0);
    const [isListening, setIsListening] = useState(false);
    const [voiceAvailable, setVoiceAvailable] = useState(false);
    const [voiceTranscript, setVoiceTranscript] = useState('');
    const [showSaveDialog, setShowSaveDialog] = useState(false);

    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const fileInputRef = useRef<HTMLInputElement>(null);
    const panelAnchorRef = useRef<HTMLDivElement>(null);
    const recognitionRef = useRef<SpeechRecognitionInstance | null>(null);
    const lastDropTimeRef = useRef<number>(0);
    const errorTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

    const activeSession = useSessionStore((s) => s.activeSession);

    /* ---------------------------------------------------------------- */
    /*  Speech Recognition setup                                        */
    /* ---------------------------------------------------------------- */

    useEffect(() => {
      setVoiceAvailable(getSpeechRecognition() !== null);
    }, []);

    /* ---------------------------------------------------------------- */
    /*  Auto-focus on mount                                              */
    /* ---------------------------------------------------------------- */

    useEffect(() => {
      textareaRef.current?.focus();
    }, []);

    /* ---------------------------------------------------------------- */
    /*  Auto-resize textarea                                             */
    /* ---------------------------------------------------------------- */

    useEffect(() => {
      const ta = textareaRef.current;
      if (!ta) return;
      ta.style.height = 'auto';
      // line-height is ~20px; max 5 lines = 100px
      ta.style.height = `${Math.min(ta.scrollHeight, 100)}px`;
    }, [text]);

    /* ---------------------------------------------------------------- */
    /*  Template overlay logic (driven by text changes)                  */
    /* ---------------------------------------------------------------- */

    useEffect(() => {
      if (!text.startsWith('/')) {
        // User backspaced past "/" — close overlay
        if (showTemplates) {
          setShowTemplates(false);
        }
        setDismissedAtText(null);
        return;
      }

      // Text starts with "/"
      if (!showTemplates) {
        // Reopen if never dismissed or text changed since Esc
        if (dismissedAtText === null || text !== dismissedAtText) {
          setDismissedAtText(null);
          setShowTemplates(true);
          setActiveTemplateIndex(0);
        }
      } else {
        // Overlay showing — reset index as user types
        setActiveTemplateIndex(0);
      }
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [text]);

    /* ---------------------------------------------------------------- */
    /*  Clipboard paste handler                                          */
    /* ---------------------------------------------------------------- */

    useEffect(() => {
      function handlePaste(e: ClipboardEvent) {
        if (!enabled || sending) return;
        const items = e.clipboardData?.items;
        if (!items) return;
        for (let i = 0; i < items.length; i++) {
          const item = items[i];
          if (item.type?.startsWith('image/')) {
            const file = item.getAsFile();
            if (file) {
              e.preventDefault();
              processFile(file);
            }
          }
        }
      }
      document.addEventListener('paste', handlePaste);
      return () => document.removeEventListener('paste', handlePaste);
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [enabled, sending, attachments.length]);

    /* ---------------------------------------------------------------- */
    /*  Imperative handle for drag-drop                                  */
    /* ---------------------------------------------------------------- */

    useImperativeHandle(ref, () => ({
      addDroppedFiles(files: File[]) {
        // Debounce duplicate drop events within 100ms
        const now = Date.now();
        if (now - lastDropTimeRef.current < 100) return;
        lastDropTimeRef.current = now;
        for (const file of files) {
          processFile(file);
        }
      },
    }));

    /* ---------------------------------------------------------------- */
    /*  File processing pipeline                                         */
    /* ---------------------------------------------------------------- */

    // eslint-disable-next-line react-hooks/exhaustive-deps
    function showAttachErrorMsg(msg: string) {
      setAttachError(msg);
      if (errorTimerRef.current) clearTimeout(errorTimerRef.current);
      errorTimerRef.current = setTimeout(() => setAttachError(null), 4000);
    }

    // eslint-disable-next-line react-hooks/exhaustive-deps
    function processFile(file: File) {
      // Check count limit
      // Use a ref-like approach via callback form of setState
      setAttachments((prev) => {
        if (prev.length >= AttachmentLimits.maxAttachments) {
          showAttachErrorMsg(`Max ${AttachmentLimits.maxAttachments} attachments`);
          return prev;
        }

        // Validate
        const error = validateFile(file);
        if (error) {
          showAttachErrorMsg(error);
          return prev;
        }

        // Kick off async read
        setProcessingCount((c) => c + 1);

        if (shouldCompressImage(file)) {
          compressAndAdd(file);
        } else {
          readAndAdd(file);
        }

        return prev;
      });
    }

    async function compressAndAdd(file: File) {
      try {
        const result = await compressImage(file);
        setAttachments((prev) => [
          ...prev,
          {
            name: file.name,
            mimeType: result.mimeType,
            base64: result.base64,
            size: result.size,
          },
        ]);
      } catch {
        // Fallback to raw read
        await readAndAdd(file);
        return;
      } finally {
        setProcessingCount((c) => Math.max(0, c - 1));
      }
    }

    async function readAndAdd(file: File) {
      try {
        const base64 = await readFileAsBase64(file);
        setAttachments((prev) => [
          ...prev,
          {
            name: file.name,
            mimeType: file.type || 'application/octet-stream',
            base64,
            size: file.size,
          },
        ]);
      } catch {
        showAttachErrorMsg(`Failed to read ${file.name}`);
      } finally {
        setProcessingCount((c) => Math.max(0, c - 1));
      }
    }

    function removeAttachment(index: number) {
      setAttachments((prev) => prev.filter((_, i) => i !== index));
    }

    /* ---------------------------------------------------------------- */
    /*  Send message                                                     */
    /* ---------------------------------------------------------------- */

    const send = useCallback(async () => {
      const trimmed = text.trim();
      if (trimmed.length === 0 && attachments.length === 0) return;
      if (!enabled || sending) return;

      setSending(true);
      const savedText = text;
      setText('');

      try {
        if (attachments.length > 0) {
          // Split: images via WebSocket, non-images via HTTP upload
          const imageAttachments: AttachmentInfo[] = [];
          const fileAttachments: AttachmentInfo[] = [];
          for (const a of attachments) {
            if (a.mimeType.startsWith('image/')) {
              imageAttachments.push(a);
            } else {
              fileAttachments.push(a);
            }
          }

          // Upload non-image files via HTTP
          const authState = useAuthStore.getState();
          const jwt = authState.token ?? '';
          const openclawId = authState.activeOpenClawId ?? undefined;

          const uploadResults = await Promise.all(
            fileAttachments.map(async (a) => {
              try {
                // Convert base64 back to File for upload
                const binaryStr = atob(a.base64);
                const bytes = new Uint8Array(binaryStr.length);
                for (let i = 0; i < binaryStr.length; i++) {
                  bytes[i] = binaryStr.charCodeAt(i);
                }
                const blob = new Blob([bytes], { type: a.mimeType });
                const file = new File([blob], a.name, { type: a.mimeType });

                const result = await uploadFileToWorkspace(file, jwt, openclawId);
                if (result.ok && result.path) {
                  return result.path;
                }
                return `[Upload failed: ${a.name}]`;
              } catch {
                return `[Upload failed: ${a.name}]`;
              }
            }),
          );

          // Build message with file references
          const parts: string[] = [];
          if (trimmed) parts.push(trimmed);
          for (const p of uploadResults) {
            parts.push(p.startsWith('[') ? p : `[File: ${p}]`);
          }
          const message = parts.length > 0 ? parts.join('\n') : '[attachment]';

          if (imageAttachments.length > 0) {
            const wsAttachments = imageAttachments.map((a) => ({
              content: a.base64,
              mimeType: a.mimeType,
              fileName: a.name,
              type: 'image',
            }));
            await gatewayClient.sendChatMessageWithAttachments(message, {
              sessionKey: activeSession,
              attachments: wsAttachments,
            });
          } else {
            await gatewayClient.sendChatMessage(message, {
              sessionKey: activeSession,
            });
          }
          setAttachments([]);
        } else {
          await gatewayClient.sendChatMessage(trimmed, {
            sessionKey: activeSession,
          });
        }
      } catch {
        // Restore text on failure
        setText((current) => (current === '' ? savedText : current));
      } finally {
        setSending(false);
        textareaRef.current?.focus();
      }
    }, [text, attachments, enabled, sending, activeSession]);

    /* ---------------------------------------------------------------- */
    /*  Abort                                                            */
    /* ---------------------------------------------------------------- */

    const abort = useCallback(() => {
      gatewayClient.abortChat({ sessionKey: activeSession });
    }, [activeSession]);

    /* ---------------------------------------------------------------- */
    /*  Voice input                                                      */
    /* ---------------------------------------------------------------- */

    const toggleVoice = useCallback(() => {
      if (isListening) {
        recognitionRef.current?.stop();
        setIsListening(false);
        setVoiceTranscript('');
        return;
      }

      const SpeechRecognitionCtor = getSpeechRecognition();
      if (!SpeechRecognitionCtor) return;

      const recognition = new SpeechRecognitionCtor();
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = 'en-US';

      recognition.onresult = (e: SpeechRecognitionEvent) => {
        let transcript = '';
        for (let i = e.resultIndex; i < e.results.length; i++) {
          transcript += e.results[i][0].transcript;
        }
        setVoiceTranscript(transcript);

        // Check if final result
        const lastResult = e.results[e.results.length - 1];
        if (lastResult.isFinal) {
          setText(transcript);
          setIsListening(false);
          setVoiceTranscript('');
          recognition.stop();
        }
      };

      recognition.onerror = () => {
        setIsListening(false);
        setVoiceTranscript('');
      };

      recognition.onend = () => {
        setIsListening(false);
      };

      recognitionRef.current = recognition;
      recognition.start();
      setIsListening(true);
    }, [isListening]);

    /* ---------------------------------------------------------------- */
    /*  File picker                                                      */
    /* ---------------------------------------------------------------- */

    const pickFile = useCallback(() => {
      fileInputRef.current?.click();
    }, []);

    const onFileInputChange = useCallback(
      (e: React.ChangeEvent<HTMLInputElement>) => {
        const files = e.target.files;
        if (!files) return;
        for (let i = 0; i < files.length; i++) {
          processFile(files[i]);
        }
        // Reset input so same file can be re-selected
        e.target.value = '';
      },
      // eslint-disable-next-line react-hooks/exhaustive-deps
      [],
    );

    /* ---------------------------------------------------------------- */
    /*  Save as template                                                 */
    /* ---------------------------------------------------------------- */

    const saveAsTemplate = useCallback(() => {
      if (!text.trim()) return;
      setShowSaveDialog(true);
    }, [text]);

    /* ---------------------------------------------------------------- */
    /*  Keyboard handler                                                 */
    /* ---------------------------------------------------------------- */

    const handleKeyDown = useCallback(
      (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
        // Template panel keyboard navigation
        if (showTemplates) {
          if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault();
            const filter = text.startsWith('/') ? text.substring(1) : '';
            const all = PromptTemplateStore.all();
            const filtered = filter
              ? all.filter(
                  (t) =>
                    t.name.toLowerCase().includes(filter.toLowerCase()) ||
                    t.category.toLowerCase().includes(filter.toLowerCase()),
                )
              : all;
            if (filtered.length > 0) {
              setActiveTemplateIndex((prev) => {
                if (e.key === 'ArrowDown') return (prev + 1) % filtered.length;
                return (prev - 1 + filtered.length) % filtered.length;
              });
            }
            return;
          }

          if (e.key === 'Escape') {
            e.preventDefault();
            setDismissedAtText(text);
            setShowTemplates(false);
            return;
          }

          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            const filter = text.startsWith('/') ? text.substring(1) : '';
            const all = PromptTemplateStore.all();
            const filtered = filter
              ? all.filter(
                  (t) =>
                    t.name.toLowerCase().includes(filter.toLowerCase()) ||
                    t.category.toLowerCase().includes(filter.toLowerCase()),
                )
              : all;
            if (filtered.length > 0) {
              const idx = Math.min(
                Math.max(activeTemplateIndex, 0),
                filtered.length - 1,
              );
              const content = filtered[idx].content;
              setText(content);
              setShowTemplates(false);
              textareaRef.current?.focus();
            }
            return;
          }
        }

        // Enter = send, Shift+Enter = newline
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          send();
        }
      },
      [showTemplates, text, activeTemplateIndex, send],
    );

    /* ---------------------------------------------------------------- */
    /*  Template panel dismiss                                           */
    /* ---------------------------------------------------------------- */

    const dismissTemplates = useCallback(() => {
      setShowTemplates(false);
      textareaRef.current?.focus();
    }, []);

    const handleTemplateSelect = useCallback((content: string) => {
      setText(content);
      setShowTemplates(false);
      // Move cursor to end after React re-render
      setTimeout(() => {
        const ta = textareaRef.current;
        if (ta) {
          ta.focus();
          ta.selectionStart = content.length;
          ta.selectionEnd = content.length;
        }
      }, 0);
    }, []);

    /* ---------------------------------------------------------------- */
    /*  Cleanup                                                          */
    /* ---------------------------------------------------------------- */

    useEffect(() => {
      return () => {
        if (errorTimerRef.current) clearTimeout(errorTimerRef.current);
        recognitionRef.current?.abort();
      };
    }, []);

    /* ---------------------------------------------------------------- */
    /*  Click-outside handler for template panel                         */
    /* ---------------------------------------------------------------- */

    useEffect(() => {
      if (!showTemplates) return;
      function handleClickOutside(e: MouseEvent) {
        const anchor = panelAnchorRef.current;
        if (anchor && !anchor.contains(e.target as Node)) {
          setShowTemplates(false);
        }
      }
      // Delay to avoid closing on the same click that opened it
      const timer = setTimeout(() => {
        document.addEventListener('mousedown', handleClickOutside);
      }, 0);
      return () => {
        clearTimeout(timer);
        document.removeEventListener('mousedown', handleClickOutside);
      };
    }, [showTemplates]);

    /* ---------------------------------------------------------------- */
    /*  Template filter                                                  */
    /* ---------------------------------------------------------------- */

    const templateFilter = text.startsWith('/') ? text.substring(1) : '';

    /* ---------------------------------------------------------------- */
    /*  Render                                                           */
    /* ---------------------------------------------------------------- */

    const hasAttachmentRow =
      attachments.length > 0 || processingCount > 0 || attachError !== null;

    return (
      <>
        <div ref={panelAnchorRef} className="relative w-full font-mono">
          {/* ---- Floating template panel ---- */}
          {showTemplates && (
            <div className="absolute bottom-full left-3 mb-1 z-50">
              <PromptTemplatePanel
                filter={templateFilter}
                activeIndex={activeTemplateIndex}
                onSelect={handleTemplateSelect}
                onDismiss={dismissTemplates}
              />
            </div>
          )}

          {/* ---- Attachment preview row ---- */}
          {hasAttachmentRow && (
            <div className="flex items-center h-8 px-3 py-1 border-t border-[var(--border)] overflow-x-auto">
              {/* Error chip */}
              {attachError && (
                <div className="shrink-0 mr-1.5 flex items-center gap-1 px-2 py-1 bg-[var(--status-error)]/[0.08] border border-[var(--status-error)]/30">
                  <AlertTriangle
                    size={10}
                    className="shrink-0 text-[var(--status-error)]"
                  />
                  <span className="text-[9px] text-[var(--status-error)] whitespace-nowrap">
                    {attachError}
                  </span>
                </div>
              )}

              {/* Attachment chips */}
              {attachments.map((a, i) => (
                <AttachmentChip
                  key={`${a.name}-${i}`}
                  attachment={a}
                  onRemove={() => removeAttachment(i)}
                />
              ))}

              {/* Processing indicator */}
              {processingCount > 0 && (
                <div className="shrink-0 mr-1.5 flex items-center gap-1.5 px-2 py-1 bg-[var(--surface-card)] border border-[var(--border)]">
                  <Loader2
                    size={10}
                    className="shrink-0 text-[var(--accent-primary)] animate-spin"
                  />
                  <span className="text-[9px] text-[var(--fg-muted)] whitespace-nowrap">
                    processing{processingCount > 1 ? ` (${processingCount})` : ''}
                  </span>
                </div>
              )}
            </div>
          )}

          {/* ---- Main prompt bar ---- */}
          <div className="border-t border-[var(--border)] px-3 py-2">
            {/* Voice transcript preview */}
            {isListening && voiceTranscript && (
              <div className="mb-1 text-xs text-[var(--fg-tertiary)]">
                {voiceTranscript}
              </div>
            )}

            <div className="flex items-end gap-0">
              {/* File attach button */}
              {!sending && (
                <button
                  type="button"
                  className="shrink-0 p-0 mr-1.5 mb-0.5 bg-transparent border-none cursor-pointer text-[var(--fg-muted)] hover:text-[var(--fg-secondary)]"
                  onClick={pickFile}
                  title="Attach file"
                >
                  <Paperclip size={14} />
                </button>
              )}

              {/* Prompt prefix */}
              <span
                className={`shrink-0 text-base leading-5 mr-0.5 select-none ${
                  !enabled
                    ? 'text-[var(--fg-disabled)]'
                    : sending
                      ? 'text-[var(--fg-tertiary)]'
                      : 'text-[var(--accent-primary)]'
                }`}
              >
                {sending ? '~ ' : '> '}
              </span>

              {/* Textarea */}
              <textarea
                ref={textareaRef}
                value={text}
                onChange={(e) => setText(e.target.value)}
                onKeyDown={handleKeyDown}
                disabled={!enabled || sending}
                rows={1}
                placeholder={enabled ? 'type / for prompt templates' : 'connecting...'}
                className="flex-1 bg-transparent text-sm text-[var(--fg-primary)] placeholder:text-[var(--fg-placeholder)] outline-none resize-none leading-5 py-0 border-none min-h-[20px]"
                style={{ maxHeight: '100px', fontFamily: 'inherit' }}
              />

              {/* Save as template */}
              {!sending && text.trim().length > 0 && (
                <button
                  type="button"
                  className="shrink-0 p-0 ml-1 mb-0.5 bg-transparent border-none cursor-pointer text-[var(--fg-disabled)] hover:text-[var(--fg-muted)]"
                  onClick={saveAsTemplate}
                  title="Save as template"
                >
                  <Bookmark size={14} />
                </button>
              )}

              {/* Shift+Enter hint */}
              {!sending && text.length === 0 && enabled && (
                <span className="shrink-0 ml-1 mb-0.5 text-[9px] text-[var(--fg-disabled)] whitespace-nowrap select-none">
                  shift+enter for new line
                </span>
              )}

              {/* Abort button */}
              {sending && (
                <button
                  type="button"
                  className="shrink-0 p-0 ml-2 mb-0.5 bg-transparent border-none cursor-pointer text-[var(--status-error)] hover:text-[var(--status-error)]"
                  onClick={abort}
                  title="Stop"
                >
                  <Square size={16} />
                </button>
              )}

              {/* Voice button */}
              {voiceAvailable && !sending && (
                <button
                  type="button"
                  className={`shrink-0 p-0 ml-2 mb-0.5 bg-transparent border-none cursor-pointer ${
                    isListening
                      ? 'text-[var(--status-error)]'
                      : 'text-[var(--fg-muted)] hover:text-[var(--fg-secondary)]'
                  }`}
                  onClick={toggleVoice}
                  title={isListening ? 'Stop recording' : 'Voice input'}
                >
                  {isListening ? <MicOff size={16} /> : <Mic size={16} />}
                </button>
              )}

              {/* Send button (visible when there's content and not sending) */}
              {!sending &&
                (text.trim().length > 0 || attachments.length > 0) && (
                  <button
                    type="button"
                    className="shrink-0 p-0 ml-2 mb-0.5 bg-transparent border-none cursor-pointer text-[var(--accent-primary)] hover:text-[var(--fg-primary)]"
                    onClick={() => send()}
                    title="Send"
                  >
                    <Send size={16} />
                  </button>
                )}
            </div>
          </div>

          {/* Hidden file input */}
          <input
            ref={fileInputRef}
            type="file"
            multiple
            className="hidden"
            accept="image/*,audio/*,video/*,.pdf,.txt,.md,.json,.csv,.yaml,.yml,.docx,.xlsx,.pptx,.doc,.xls,.ppt,.odt,.ods,.odp,.rtf,.epub,.html,.css,.xml,.sql,.toml,.ini,.py,.js,.ts,.dart,.sh,.bash,.zsh,.java,.kt,.c,.cpp,.h,.hpp,.rs,.go,.rb,.php,.swift,.lua"
            onChange={onFileInputChange}
          />
        </div>

        {/* Save-as-template dialog */}
        {showSaveDialog && (
          <SaveTemplateDialog
            initialContent={text}
            onClose={() => setShowSaveDialog(false)}
          />
        )}
      </>
    );
  },
);

export default PromptBar;
export { PromptTemplatePanel };
