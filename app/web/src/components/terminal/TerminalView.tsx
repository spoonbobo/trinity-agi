'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import type { TerminalProxyClient, TerminalOutput } from '@/lib/clients/terminal-client';

/* ------------------------------------------------------------------ */
/*  TerminalView — simple command-response terminal (non-interactive)  */
/*  1:1 port of features/terminal/terminal_view.dart                   */
/* ------------------------------------------------------------------ */

interface TerminalViewProps {
  client: TerminalProxyClient;
  showInput?: boolean;
  suggestedCommands?: string[];
  onCommandExecuted?: () => void;
}

/** Map output type → CSS color variable */
function outputColor(type: TerminalOutput['type']): string {
  switch (type) {
    case 'stdout':
      return 'var(--fg-primary)';
    case 'stderr':
    case 'error':
      return 'var(--status-error)';
    case 'system':
      return 'var(--fg-tertiary)';
    case 'exit':
      return 'var(--accent-primary)';
    default:
      return 'var(--fg-primary)';
  }
}

export function TerminalView({
  client,
  showInput = true,
  suggestedCommands = [],
  onCommandExecuted,
}: TerminalViewProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const [command, setCommand] = useState('');
  const [outputs, setOutputs] = useState<TerminalOutput[]>(() => [...client.outputs]);
  const [executing, setExecuting] = useState(false);

  /* ---------------------------------------------------------------- */
  /*  Subscribe to client outputs                                      */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    // Sync initial state
    setOutputs([...client.outputs]);

    const unsub = client.onOutput(() => {
      setOutputs([...client.outputs]);
    });
    return unsub;
  }, [client]);

  /* ---------------------------------------------------------------- */
  /*  Track executing state from outputs                               */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    const last = outputs[outputs.length - 1];
    if (last?.type === 'exit') {
      setExecuting(false);
    }
  }, [outputs]);

  /* ---------------------------------------------------------------- */
  /*  Auto-scroll to bottom                                            */
  /* ---------------------------------------------------------------- */

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    requestAnimationFrame(() => {
      el.scrollTop = el.scrollHeight;
    });
  }, [outputs]);

  /* ---------------------------------------------------------------- */
  /*  Execute command                                                   */
  /* ---------------------------------------------------------------- */

  const executeCommand = useCallback(
    (cmd: string) => {
      const trimmed = cmd.trim();
      if (!trimmed) return;
      setExecuting(true);
      client.executeCommand(trimmed);
      setCommand('');
      onCommandExecuted?.();
    },
    [client, onCommandExecuted],
  );

  const handleCancel = useCallback(() => {
    client.cancelCommand();
    setExecuting(false);
  }, [client]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === 'Enter') {
        executeCommand(command);
      }
    },
    [command, executeCommand],
  );

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  return (
    <div className="flex h-full flex-col">
      {/* Output area */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto p-3">
        {outputs.map((output, i) => {
          const text = output.data ?? output.message ?? '';
          if (!text) return null;
          return (
            <div
              key={i}
              className="whitespace-pre-wrap font-mono text-[13px] leading-[1.5] select-text"
              style={{ color: outputColor(output.type) }}
            >
              {text}
            </div>
          );
        })}
      </div>

      {/* Suggested commands */}
      {suggestedCommands.length > 0 && (
        <div
          className="flex flex-wrap gap-3 px-3 py-1.5"
          style={{ borderTop: '0.5px solid var(--border)' }}
        >
          {suggestedCommands.map((cmd) => (
            <button
              key={cmd}
              onClick={() => executeCommand(cmd)}
              className="cursor-pointer font-mono text-xs text-fg-muted hover:text-fg-secondary"
            >
              {cmd}
            </button>
          ))}
        </div>
      )}

      {/* Input row */}
      {showInput && (
        <div
          className="flex items-center gap-0 px-3 py-2"
          style={{ borderTop: '0.5px solid var(--border)' }}
        >
          <span
            className="font-mono text-base"
            style={{
              color:
                client.connectionState === 'connected'
                  ? 'var(--accent-primary)'
                  : 'var(--fg-disabled)',
            }}
          >
            {'> '}
          </span>
          <input
            ref={inputRef}
            type="text"
            value={command}
            onChange={(e) => setCommand(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={client.connectionState !== 'connected' || executing}
            className="min-w-0 flex-1 border-none bg-transparent font-mono text-base text-fg-primary outline-none placeholder:text-fg-placeholder disabled:opacity-50"
          />
          {executing && (
            <button
              onClick={handleCancel}
              className="cursor-pointer font-mono text-xs text-status-error hover:text-status-error/80"
            >
              cancel
            </button>
          )}
        </div>
      )}
    </div>
  );
}
