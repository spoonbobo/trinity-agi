'use client';

import { useState, useEffect, useCallback, useRef } from 'react';

/**
 * AppUpdateGate — 1:1 port of core/app_update_gate.dart
 *
 * Polls /trinity-version.json every 90s. Shows reload banner when version changes.
 */
export function AppUpdateGate({ children }: { children: React.ReactNode }) {
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const initialVersionRef = useRef<string | null>(null);

  const fetchVersionToken = useCallback(async (): Promise<string | null> => {
    for (const path of ['/trinity-version.json', '/version.json']) {
      try {
        const res = await fetch(`${path}?t=${Date.now()}`, {
          cache: 'no-store',
          headers: { 'Cache-Control': 'no-cache' },
        });
        if (!res.ok) continue;
        const data = await res.json();
        const token = data.version ?? data.build ?? data.buildNumber ?? '';
        if (token) return String(token);
      } catch {
        continue;
      }
    }
    return null;
  }, []);

  const checkForUpdates = useCallback(async () => {
    const latest = await fetchVersionToken();
    if (!latest) return;

    if (initialVersionRef.current === null) {
      initialVersionRef.current = latest;
      return;
    }

    if (latest !== initialVersionRef.current) {
      setUpdateAvailable(true);
    }

    // Also check service worker
    if ('serviceWorker' in navigator) {
      try {
        const reg = await navigator.serviceWorker.getRegistration();
        if (reg?.waiting) {
          setUpdateAvailable(true);
        }
      } catch {
        // Ignore
      }
    }
  }, [fetchVersionToken]);

  const applyUpdate = useCallback(async () => {
    if ('serviceWorker' in navigator) {
      try {
        const reg = await navigator.serviceWorker.getRegistration();
        if (reg?.waiting) {
          reg.waiting.postMessage({ type: 'SKIP_WAITING' });
          await new Promise((r) => setTimeout(r, 700));
        }
      } catch {
        // Ignore
      }
    }
    window.location.reload();
  }, []);

  useEffect(() => {
    checkForUpdates();
    const timer = setInterval(checkForUpdates, 90000);
    return () => clearInterval(timer);
  }, [checkForUpdates]);

  return (
    <div className="relative flex h-full w-full flex-col">
      {updateAvailable && (
        <div
          className="flex h-8 shrink-0 items-center justify-center gap-3 border-b text-xs"
          style={{
            background: '#141414',
            borderColor: '#2A2A2A',
            color: 'var(--fg-secondary)',
          }}
        >
          <span>A newer Trinity version is available.</span>
          <button
            onClick={applyUpdate}
            className="text-accent-primary hover:underline"
          >
            reload now
          </button>
        </div>
      )}
      <div className="flex-1 overflow-hidden">{children}</div>
    </div>
  );
}
