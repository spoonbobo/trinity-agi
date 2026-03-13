/**
 * Keyboard shortcut hooks
 */

import { useEffect } from 'react';

type KeyHandler = (e: KeyboardEvent) => void;

/**
 * Register a global keyboard shortcut. The handler is called when the key combo matches.
 * Supports modifier keys: ctrl, shift, alt, meta.
 */
export function useKeyboard(key: string, handler: KeyHandler, deps: any[] = []): void {
  useEffect(() => {
    const listener = (e: KeyboardEvent) => {
      if (e.key === key) {
        handler(e);
      }
    };
    document.addEventListener('keydown', listener);
    return () => document.removeEventListener('keydown', listener);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, ...deps]);
}

/**
 * Global Escape key handler — works even when iframes have focus.
 */
export function useEscapeKey(handler: () => void, deps: any[] = []): void {
  useEffect(() => {
    const listener = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        handler();
      }
    };
    // Both window and document level to catch iframe escapes
    document.addEventListener('keydown', listener);
    return () => document.removeEventListener('keydown', listener);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
}
