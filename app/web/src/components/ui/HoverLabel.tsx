'use client';

import { useState, useRef, useEffect } from 'react';

/**
 * Tooltip-style hover label — port of Flutter _HoverLabel widget.
 * Shows a small label below/above the wrapped element on hover.
 */
interface HoverLabelProps {
  label: string;
  children: React.ReactNode;
  position?: 'top' | 'bottom';
}

export function HoverLabel({ label, children, position = 'bottom' }: HoverLabelProps) {
  const [show, setShow] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout>>();

  const handleEnter = () => {
    clearTimeout(timeoutRef.current);
    timeoutRef.current = setTimeout(() => setShow(true), 400);
  };

  const handleLeave = () => {
    clearTimeout(timeoutRef.current);
    setShow(false);
  };

  useEffect(() => {
    return () => clearTimeout(timeoutRef.current);
  }, []);

  return (
    <div className="relative inline-flex" onMouseEnter={handleEnter} onMouseLeave={handleLeave}>
      {children}
      {show && (
        <div
          className={`absolute left-1/2 z-50 -translate-x-1/2 whitespace-nowrap rounded-[var(--shell-radius-sm)] border border-border-shell bg-surface-elevated px-2 py-0.5 text-[10px] text-fg-secondary ${
            position === 'bottom' ? 'top-full mt-1' : 'bottom-full mb-1'
          }`}
        >
          {label}
        </div>
      )}
    </div>
  );
}
