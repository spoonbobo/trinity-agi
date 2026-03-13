'use client';

/**
 * DrawIORenderer — 1:1 port of features/canvas/drawio_renderer.dart (663 lines)
 *
 * Embeds diagrams.net via iframe + postMessage protocol.
 * - Theme-aware iframe: dark=0|1
 * - PostMessage: init → load, autosave → capture XML, export → PNG/XML
 * - Export: PNG download, copy PNG to clipboard, get XML
 * - Save/load snapshots via auth-service API
 * - Auto-recovery: localStorage every 30s
 * - Exposes methods via forwardRef + useImperativeHandle
 */

import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from 'react';
import { useCanvasStore, type DrawIOTheme } from '@/lib/stores/canvas-store';
import { useAuthStore } from '@/lib/stores/auth-store';

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

const RECOVERY_KEY = 'trinity_drawio_xml_recovery_v1';

/* ------------------------------------------------------------------ */
/*  Snapshot store (HTTP API)                                          */
/* ------------------------------------------------------------------ */

function computeHash(xml: string): string {
  let hash = 2166136261;
  for (let i = 0; i < xml.length; i++) {
    hash ^= xml.charCodeAt(i);
    hash = (hash * 16777619) & 0xffffffff;
  }
  return hash.toString(16).padStart(8, '0');
}

function saveRecovery(xml: string): void {
  try {
    localStorage.setItem(RECOVERY_KEY, xml);
  } catch {
    /* ignore quota errors */
  }
}

function loadRecovery(): string | null {
  try {
    const raw = localStorage.getItem(RECOVERY_KEY);
    return raw && raw.trim() ? raw : null;
  } catch {
    return null;
  }
}

/* ------------------------------------------------------------------ */
/*  Handle type                                                        */
/* ------------------------------------------------------------------ */

export interface DrawIORendererHandle {
  exportPng: () => void;
  copyPng: () => void;
  getXml: () => Promise<string | null>;
  saveXmlSnapshot: () => Promise<boolean>;
  saveXmlSnapshotNamed: (name: string) => Promise<boolean>;
  loadXmlSnapshot: (xml: string) => void;
  reloadWithTheme: () => void;
}

/* ------------------------------------------------------------------ */
/*  Component                                                          */
/* ------------------------------------------------------------------ */

const DrawIORenderer = forwardRef<
  DrawIORendererHandle,
  { dialogIsOpen?: boolean }
>(function DrawIORenderer({ dialogIsOpen = false }, ref) {
  const drawioTheme = useCanvasStore((s) => s.drawioTheme);
  const token = useAuthStore((s) => s.token);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);

  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const lastKnownXml = useRef<string | null>(null);
  const initialized = useRef(false);
  const pendingLoadXml = useRef<string | null>(loadRecovery());
  const lastRecoveryHash = useRef<string | null>(null);
  const autoSnapshotTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  // Callbacks waiting for export responses
  const pendingExportCb = useRef<((format: string, data: string) => void) | null>(null);
  const pendingXmlResolve = useRef<((xml: string | null) => void) | null>(null);

  // Epoch for iframe reloads (changing this remounts iframe)
  const [iframeEpoch, setIframeEpoch] = useState(0);

  /* ---------------------------------------------------------------- */
  /*  Build iframe URL                                                 */
  /* ---------------------------------------------------------------- */

  const iframeUrl = useCallback(
    (theme: DrawIOTheme) => {
      const params = new URLSearchParams({
        embed: '1',
        ui: 'min',
        dark: theme === 'dark' ? '1' : '0',
        lang: 'en',
        proto: 'json',
        spin: '1',
        saveAndExit: '0',
        noSaveBtn: '1',
        noExitBtn: '1',
      });
      return `https://embed.diagrams.net/?${params.toString()}`;
    },
    [],
  );

  /* ---------------------------------------------------------------- */
  /*  Default diagram XML                                              */
  /* ---------------------------------------------------------------- */

  const defaultDiagramXml = useCallback((theme: DrawIOTheme) => {
    const isDark = theme === 'dark';
    const bg = isDark ? '#0A0A0A' : '#F5F5F5';
    const grid = isDark ? '#1F2937' : '#D1D5DB';
    const page = isDark ? '#0F172A' : '#FFFFFF';
    return `<mxfile><diagram id="trinity-default" name="Page-1"><mxGraphModel dx="1426" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0" background="${bg}" gridColor="${grid}" pageBackgroundColor="${page}"><root><mxCell id="0"/><mxCell id="1" parent="0"/></root></mxGraphModel></diagram></mxfile>`;
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Post message to iframe                                           */
  /* ---------------------------------------------------------------- */

  const postToIframe = useCallback((message: Record<string, any>) => {
    iframeRef.current?.contentWindow?.postMessage(
      JSON.stringify(message),
      '*',
    );
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Persist recovery if hash changed                                 */
  /* ---------------------------------------------------------------- */

  const persistRecoveryIfChanged = useCallback(() => {
    const xml = lastKnownXml.current;
    if (!xml || !xml.trim()) return;
    const hash = computeHash(xml);
    if (hash === lastRecoveryHash.current) return;
    lastRecoveryHash.current = hash;
    saveRecovery(xml);
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Handle incoming postMessage                                      */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    const handler = (event: MessageEvent) => {
      let msg: Record<string, any> | null = null;
      try {
        if (typeof event.data === 'string') {
          msg = JSON.parse(event.data);
        } else if (typeof event.data === 'object') {
          msg = event.data;
        }
      } catch {
        return;
      }
      if (!msg) return;

      const evt = msg.event as string | undefined;

      switch (evt) {
        case 'init': {
          const xml =
            pendingLoadXml.current ?? defaultDiagramXml(drawioTheme);
          pendingLoadXml.current = null;
          lastKnownXml.current = xml;
          initialized.current = true;
          postToIframe({ action: 'load', xml, autosave: 1 });
          break;
        }
        case 'autosave': {
          const xml = msg.xml as string | undefined;
          if (xml && xml.trim()) {
            lastKnownXml.current = xml;
            persistRecoveryIfChanged();
          }
          break;
        }
        case 'export': {
          const format = msg.format as string | undefined;
          const data = msg.data as string | undefined;
          if (format && data) {
            pendingExportCb.current?.(format, data);
          }
          break;
        }
        case 'save': {
          const xml = msg.xml as string | undefined;
          if (xml && xml.trim()) {
            lastKnownXml.current = xml;
            persistRecoveryIfChanged();
          }
          if (pendingXmlResolve.current) {
            pendingXmlResolve.current(xml ?? null);
            pendingXmlResolve.current = null;
          }
          break;
        }
      }
    };

    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, [drawioTheme, defaultDiagramXml, postToIframe, persistRecoveryIfChanged]);

  /* ---------------------------------------------------------------- */
  /*  Auto-recovery timer (30s)                                        */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    autoSnapshotTimer.current = setInterval(
      () => persistRecoveryIfChanged(),
      30000,
    );
    return () => {
      if (autoSnapshotTimer.current) clearInterval(autoSnapshotTimer.current);
    };
  }, [persistRecoveryIfChanged]);

  /* ---------------------------------------------------------------- */
  /*  Dialog pointer events                                            */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    if (iframeRef.current) {
      iframeRef.current.style.pointerEvents = dialogIsOpen ? 'none' : 'auto';
    }
  }, [dialogIsOpen]);

  /* ---------------------------------------------------------------- */
  /*  Extract XML from SVG export data                                 */
  /* ---------------------------------------------------------------- */

  function extractXmlFromExport(format: string, data: string): string | null {
    if (format === 'xml' && data.trim().startsWith('<')) return data;

    if (format !== 'xmlsvg' && !data.startsWith('data:image/svg+xml')) {
      return null;
    }

    try {
      const comma = data.indexOf(',');
      if (comma < 0) return null;
      const meta = data.substring(0, comma);
      const payload = data.substring(comma + 1);
      const svgText = meta.includes(';base64')
        ? atob(payload)
        : decodeURIComponent(payload);

      const match = svgText.match(/content=(["'])([\s\S]*?)\1/);
      if (!match) return null;
      return match[2]
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&');
    } catch {
      return null;
    }
  }

  /* ---------------------------------------------------------------- */
  /*  Imperative handle                                                */
  /* ---------------------------------------------------------------- */

  useImperativeHandle(ref, () => ({
    exportPng() {
      pendingExportCb.current = (format, data) => {
        if (format !== 'png') return;
        const a = document.createElement('a');
        a.href = data;
        a.download = `diagram-${Date.now()}.png`;
        a.click();
        pendingExportCb.current = null;
      };
      postToIframe({
        action: 'export',
        format: 'png',
        spin: '1',
        border: '10',
        crop: '1',
      });
    },

    copyPng() {
      pendingExportCb.current = async (format, data) => {
        if (format !== 'png') return;
        try {
          const b64 = data.includes(',') ? data.split(',')[1] : data;
          const binary = atob(b64);
          const bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          const blob = new Blob([bytes], { type: 'image/png' });
          await navigator.clipboard.write([
            new ClipboardItem({ 'image/png': blob }),
          ]);
        } catch (e) {
          console.warn('[DrawIO] clipboard copy failed:', e);
        }
        pendingExportCb.current = null;
      };
      postToIframe({
        action: 'export',
        format: 'png',
        spin: '1',
        border: '10',
        crop: '1',
      });
    },

    async getXml(): Promise<string | null> {
      return new Promise<string | null>((resolve) => {
        const timeout = setTimeout(() => {
          pendingExportCb.current = null;
          pendingXmlResolve.current = null;
          resolve(lastKnownXml.current);
        }, 4000);

        pendingXmlResolve.current = (xml) => {
          clearTimeout(timeout);
          resolve(xml);
        };

        pendingExportCb.current = (format, data) => {
          const xml = extractXmlFromExport(format, data);
          if (xml && xml.trim()) {
            lastKnownXml.current = xml;
            clearTimeout(timeout);
            pendingExportCb.current = null;
            if (pendingXmlResolve.current) {
              pendingXmlResolve.current(xml);
              pendingXmlResolve.current = null;
            }
          }
        };

        postToIframe({ action: 'save', exit: false });
        postToIframe({ action: 'export', format: 'xml', spin: '1' });
        postToIframe({ action: 'export', format: 'xmlsvg', spin: '1' });
      });
    },

    async saveXmlSnapshot(): Promise<boolean> {
      return saveXmlSnapshotImpl('');
    },

    async saveXmlSnapshotNamed(name: string): Promise<boolean> {
      return saveXmlSnapshotImpl(name);
    },

    loadXmlSnapshot(xml: string) {
      if (!xml.trim()) return;
      lastKnownXml.current = xml;
      persistRecoveryIfChanged();
      postToIframe({ action: 'load', xml, autosave: 1 });
    },

    reloadWithTheme() {
      // Capture current XML before recreating iframe
      const cached = lastKnownXml.current;
      if (cached && cached.trim()) {
        pendingLoadXml.current = cached;
      }
      // Bump epoch to remount iframe
      setIframeEpoch((e) => e + 1);
    },
  }));

  async function saveXmlSnapshotImpl(name: string): Promise<boolean> {
    if (!initialized.current) return false;

    let xml = lastKnownXml.current;
    if (!xml || !xml.trim()) {
      // Try to get it
      xml = await new Promise<string | null>((resolve) => {
        pendingExportCb.current = (format, data) => {
          const extracted = extractXmlFromExport(format, data);
          if (extracted) lastKnownXml.current = extracted;
          pendingExportCb.current = null;
          resolve(extracted);
        };
        postToIframe({ action: 'export', format: 'xml', spin: '1' });
        setTimeout(() => resolve(lastKnownXml.current), 3000);
      });
    }

    if (!xml || !xml.trim()) return false;

    try {
      if (!token || !activeOpenClawId) return false;
      const origin = typeof window !== 'undefined' ? window.location.origin : '';
      const safeName =
        name.trim() ||
        `diagram-${new Date().toISOString().replace(/[:.]/g, '').slice(0, 15)}`;

      const res = await fetch(
        `${origin}/auth/openclaws/${activeOpenClawId}/drawio/snapshots`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ name: safeName, xml }),
        },
      );
      return res.ok;
    } catch {
      return false;
    }
  }

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  return (
    <iframe
      key={`drawio-${iframeEpoch}`}
      ref={iframeRef}
      src={iframeUrl(drawioTheme)}
      className="h-full w-full border-none"
      allow="clipboard-read; clipboard-write"
      title="draw.io editor"
    />
  );
});

export default DrawIORenderer;
