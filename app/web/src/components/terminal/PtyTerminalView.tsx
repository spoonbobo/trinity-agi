'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { ClipboardPaste, RotateCcw } from 'lucide-react';
import type { TerminalProxyClient } from '@/lib/clients/terminal-client';
import { useTerminalStore } from '@/lib/stores/terminal-store';

/* ------------------------------------------------------------------ */
/*  PtyTerminalView — full interactive PTY terminal                    */
/*  1:1 port of features/terminal/pty_terminal_view.dart               */
/* ------------------------------------------------------------------ */

/** Char metrics for JetBrains Mono 12.5px */
const H_PADDING = 20; // xterm padding: all(10) → 10 * 2
const V_PADDING = 20;
const CHAR_WIDTH = 7.5;
const LINE_HEIGHT = 16.25; // 12.5 * 1.3

interface PtyTerminalViewProps {
  client: TerminalProxyClient;
  suggestedCommands?: string[];
  initialCommand?: string;
  cols?: number;
  rows?: number;
  showHeader?: boolean;
}

export function PtyTerminalView({
  client,
  cols: defaultCols = 120,
  rows: defaultRows = 32,
  showHeader = true,
}: PtyTerminalViewProps) {
  const setTerminalFocus = useTerminalStore((s) => s.setTerminalFocus);

  const terminalContainerRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<any>(null); // Terminal instance
  const fitAddonRef = useRef<any>(null);

  const [shellActive, setShellActive] = useState(false);
  const [startingShell, setStartingShell] = useState(false);
  const [loaded, setLoaded] = useState(false);

  const lastColsRef = useRef(0);
  const lastRowsRef = useRef(0);
  const resizeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  /* ---------------------------------------------------------------- */
  /*  Dynamic import xterm (browser-only)                              */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    let cancelled = false;

    async function loadXterm() {
      const [{ Terminal }, { FitAddon }] = await Promise.all([
        import('@xterm/xterm'),
        import('@xterm/addon-fit'),
      ]);

      // Also load xterm CSS
      await import('@xterm/xterm/css/xterm.css');

      if (cancelled || !terminalContainerRef.current) return;

      const fitAddon = new FitAddon();
      const terminal = new Terminal({
        fontFamily: "'JetBrains Mono', monospace",
        fontSize: 12.5,
        lineHeight: 1.3,
        cursorBlink: true,
        cursorStyle: 'block',
        allowTransparency: false,
        scrollback: 5000,
        theme: {
          background: '#0A0A0A',
          foreground: '#D4D4D4',
          cursor: '#6EE7B7',
          cursorAccent: '#0A0A0A',
          selectionBackground: '#1A3A2A',
          selectionForeground: '#6EE7B7',
          black: '#0A0A0A',
          red: '#F87171',
          green: '#6EE7B7',
          yellow: '#FCD34D',
          blue: '#7DD3FC',
          magenta: '#C084FC',
          cyan: '#67E8F9',
          white: '#D4D4D4',
          brightBlack: '#525252',
          brightRed: '#FCA5A5',
          brightGreen: '#A7F3D0',
          brightYellow: '#FDE68A',
          brightBlue: '#BAE6FD',
          brightMagenta: '#D8B4FE',
          brightCyan: '#A5F3FC',
          brightWhite: '#F5F5F5',
        },
      });

      terminal.loadAddon(fitAddon);
      terminal.open(terminalContainerRef.current);

      // Fit to container
      try {
        fitAddon.fit();
      } catch {
        // Container might not be visible yet
      }

      xtermRef.current = terminal;
      fitAddonRef.current = fitAddon;

      // Terminal keyboard input → shell
      terminal.onData((data: string) => {
        if (client.shellActive) {
          client.shellInput(data);
        }
      });

      // Focus tracking via xterm disposable events
      terminal.onFocus(() => setTerminalFocus(true));
      terminal.onBlur(() => setTerminalFocus(false));

      setLoaded(true);
    }

    loadXterm();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Shell output listener                                            */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    if (!loaded) return;

    const unsub = client.onShellOutput((data: string) => {
      xtermRef.current?.write(data);
    });

    return unsub;
  }, [client, loaded]);

  /* ---------------------------------------------------------------- */
  /*  Shell lifecycle tracking                                         */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    if (!loaded) return;

    const unsub = client.onStateChange(() => {
      setShellActive(client.shellActive);
      if (client.shellActive) {
        setStartingShell(false);
      }
    });

    // Also listen to outputs for shell_started / shell_closed
    const unsubOutput = client.onOutput((output) => {
      // The client already updates shellActive internally;
      // we re-sync our local state
      setShellActive(client.shellActive);
      if (client.shellActive) setStartingShell(false);

      // Write non-shell system messages to terminal
      if (output.type !== 'stdout' && output.type !== 'stderr') return;
      // These are exec outputs, not shell — skip
    });

    return () => {
      unsub();
      unsubOutput();
    };
  }, [client, loaded]);

  /* ---------------------------------------------------------------- */
  /*  Start shell                                                      */
  /* ---------------------------------------------------------------- */

  const startShell = useCallback(async () => {
    if (startingShell || client.shellActive) return;
    setStartingShell(true);
    try {
      if (client.connectionState !== 'connected') {
        await client.connect();
      }
      const cols = lastColsRef.current > 0 ? lastColsRef.current : defaultCols;
      const rows = lastRowsRef.current > 0 ? lastRowsRef.current : defaultRows;
      client.startShell(cols, rows);
    } catch (e) {
      xtermRef.current?.write(`\r\n[error] failed to start interactive shell: ${e}\r\n`);
      setStartingShell(false);
    }
  }, [client, startingShell, defaultCols, defaultRows]);

  /* ---------------------------------------------------------------- */
  /*  Auto-start shell on load                                         */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    if (!loaded) return;
    // Small delay to let container measure
    const timer = setTimeout(() => startShell(), 100);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loaded]);

  /* ---------------------------------------------------------------- */
  /*  Auto-resize: calculate cols/rows from viewport                   */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    if (!loaded || !terminalContainerRef.current) return;

    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        const cols = Math.floor((width - H_PADDING) / CHAR_WIDTH);
        const rows = Math.floor((height - V_PADDING) / LINE_HEIGHT);
        const clampedCols = Math.max(40, Math.min(500, cols));
        const clampedRows = Math.max(10, Math.min(200, rows));

        if (clampedCols === lastColsRef.current && clampedRows === lastRowsRef.current) return;
        lastColsRef.current = clampedCols;
        lastRowsRef.current = clampedRows;

        // Debounce resize
        if (resizeTimerRef.current) clearTimeout(resizeTimerRef.current);
        resizeTimerRef.current = setTimeout(() => {
          try {
            fitAddonRef.current?.fit();
          } catch {
            // ignore
          }
          if (client.shellActive) {
            client.shellResize(clampedCols, clampedRows);
          }
        }, 80);
      }
    });

    observer.observe(terminalContainerRef.current);
    return () => {
      observer.disconnect();
      if (resizeTimerRef.current) clearTimeout(resizeTimerRef.current);
    };
  }, [client, loaded]);

  /* ---------------------------------------------------------------- */
  /*  Cleanup on unmount                                               */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    return () => {
      client.closeShell();
      xtermRef.current?.dispose();
      setTerminalFocus(false);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /* ---------------------------------------------------------------- */
  /*  Actions                                                          */
  /* ---------------------------------------------------------------- */

  const handlePaste = useCallback(async () => {
    try {
      const text = await navigator.clipboard.readText();
      if (text && client.shellActive) {
        client.shellInput(text);
      }
    } catch {
      // Clipboard API may not be available
    }
  }, [client]);

  const handleReset = useCallback(async () => {
    client.closeShell();
    // Clear terminal screen
    xtermRef.current?.write('\x1b[2J\x1b[H');
    await new Promise((r) => setTimeout(r, 80));
    startShell();
  }, [client, startShell]);

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  const statusColor = shellActive
    ? 'var(--accent-primary)'
    : startingShell
      ? 'var(--accent-secondary)'
      : 'var(--fg-muted)';

  return (
    <div className="flex h-full flex-col">
      {/* Header bar */}
      {showHeader && (
        <div
          className="flex h-8 shrink-0 items-center gap-2.5 px-3"
          style={{ borderBottom: '0.5px solid var(--border)' }}
        >
          <span className="font-mono text-[11px]" style={{ color: statusColor }}>
            interactive shell
          </span>
          <span className="font-mono text-[11px] text-fg-tertiary">
            {startingShell ? 'starting...' : 'cwd shown in prompt'}
          </span>

          <div className="flex-1" />

          {shellActive && (
            <>
              <button
                onClick={handlePaste}
                className="cursor-pointer font-mono text-[11px] text-fg-muted hover:text-fg-secondary"
                title="Paste from clipboard"
              >
                paste
              </button>
              <button
                onClick={handleReset}
                className="cursor-pointer font-mono text-[11px] text-status-warning hover:text-status-warning/80"
                title="Reset shell"
              >
                reset
              </button>
            </>
          )}

          {!shellActive && (
            <button
              onClick={startingShell ? undefined : startShell}
              className="cursor-pointer font-mono text-[11px]"
              style={{
                color: startingShell ? 'var(--fg-disabled)' : 'var(--accent-primary)',
              }}
              disabled={startingShell}
            >
              start shell
            </button>
          )}
        </div>
      )}

      {/* Terminal viewport */}
      <div
        ref={terminalContainerRef}
        className="flex-1 overflow-hidden bg-surface-base"
        style={{ minHeight: 0 }}
        onFocus={() => setTerminalFocus(true)}
        onBlur={() => setTerminalFocus(false)}
      />
    </div>
  );
}
