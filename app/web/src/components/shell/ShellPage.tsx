'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import {
  MessageCircle,
  Layout,
  Bell,
  Settings,
  Shield,
  Database,
  Brain,
  Zap,
  Radio,
  Users,
  Wand2,
  LogOut,
} from 'lucide-react';
import { useAuthStore } from '@/lib/stores/auth-store';
import { useGatewayStore, gatewayClient, syncGatewayAuth } from '@/lib/stores/gateway-store';
import { useTerminalStore, terminalClient, syncTerminalAuth } from '@/lib/stores/terminal-store';
import { useSessionStore } from '@/lib/stores/session-store';
import { useNotificationStore } from '@/lib/stores/notification-store';
import { useThemeStore } from '@/lib/stores/theme-store';
import { useBreakpoint } from '@/lib/hooks/use-responsive';
import { useLocalStorage } from '@/lib/hooks/use-local-storage';
import { tr } from '@/lib/i18n/translations';
import { Permissions } from '@/lib/utils/rbac-constants';
import { DialogService, Dialog } from '@/components/ui/Dialog';
import { HoverLabel } from '@/components/ui/HoverLabel';
import { ToastService } from '@/components/ui/Toast';
import { ChatStream } from '@/components/chat/ChatStream';
import { PromptBar } from '@/components/prompt-bar/PromptBar';
import { SessionDrawer } from '@/components/sessions/SessionDrawer';
import { CanvasPanel } from '@/components/canvas/CanvasPanel';
import { ApprovalPanel } from '@/components/governance/ApprovalPanel';
import { NotificationCenter } from '@/components/notifications/NotificationCenter';
import type { ConnectionState } from '@/lib/clients/gateway-client';
import type { WsEvent } from '@/lib/protocol/ws-frame';

/**
 * ShellPage — 1:1 port of features/shell/shell_page.dart
 *
 * Main application shell with status bar, responsive split layout,
 * draggable divider, and prompt bar.
 */
export function ShellPage() {
  const breakpoint = useBreakpoint();
  const language = useThemeStore((s) => s.language);
  const authClient = useAuthStore((s) => s.client);
  const token = useAuthStore((s) => s.token);
  const role = useAuthStore((s) => s.role);
  const permissions = useAuthStore((s) => s.permissions);
  const openclaws = useAuthStore((s) => s.openclaws);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);
  const openClawStatus = useAuthStore((s) => s.openClawStatus);
  const connectionState = useGatewayStore((s) => s.connectionState);
  const unreadCount = useNotificationStore((s) => s.unreadCount);
  const processEvent = useNotificationStore((s) => s.processEvent);

  const [mobileTab, setMobileTab] = useState<'chat' | 'canvas'>('chat');
  const [canvasSplit, setCanvasSplit] = useLocalStorage('trinity_canvas_split', 0.5);
  const [showNotifications, setShowNotifications] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const promptBarRef = useRef<{ addDroppedFiles: (files: File[]) => void }>(null);

  const isMobile = breakpoint === 'mobile';
  const isSuperadmin = role === 'superadmin';
  const hasAdmin = permissions.includes(Permissions.settingsAdmin) || isSuperadmin;
  const activeOpenClaw = openclaws.find((o) => o.id === activeOpenClawId);

  // Connect gateway + terminal on mount
  useEffect(() => {
    if (!token) return;
    syncGatewayAuth(token, activeOpenClawId);
    syncTerminalAuth(token, role, activeOpenClawId);
    gatewayClient.connect();
    terminalClient.connect().catch(() => {});

    return () => {
      gatewayClient.disconnect();
      terminalClient.disconnect();
    };
  }, [token, activeOpenClawId, role]);

  // Subscribe to gateway events for notifications
  useEffect(() => {
    const unsub = gatewayClient.onEvent((event: WsEvent) => {
      processEvent(event);
    });
    return unsub;
  }, [processEvent]);

  // Connection state toasts
  useEffect(() => {
    if (connectionState === 'connected') {
      ToastService.showInfo('Connected to gateway');
    } else if (connectionState === 'error') {
      ToastService.showError('Gateway connection error');
    }
  }, [connectionState]);

  // Drag-and-drop file handling on document.body
  useEffect(() => {
    const handleDragOver = (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
    };
    const handleDrop = (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();
      if (e.dataTransfer?.files.length) {
        promptBarRef.current?.addDroppedFiles(Array.from(e.dataTransfer.files));
      }
    };
    document.body.addEventListener('dragover', handleDragOver);
    document.body.addEventListener('drop', handleDrop);
    return () => {
      document.body.removeEventListener('dragover', handleDragOver);
      document.body.removeEventListener('drop', handleDrop);
    };
  }, []);

  // Draggable divider for canvas split
  const handleDividerMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setIsDragging(true);
      const container = containerRef.current;
      if (!container) return;

      const handleMouseMove = (e: MouseEvent) => {
        const rect = container.getBoundingClientRect();
        const ratio = (e.clientX - rect.left) / rect.width;
        setCanvasSplit(Math.max(0.2, Math.min(0.8, ratio)));
      };
      const handleMouseUp = () => {
        setIsDragging(false);
        document.removeEventListener('mousemove', handleMouseMove);
        document.removeEventListener('mouseup', handleMouseUp);
      };
      document.addEventListener('mousemove', handleMouseMove);
      document.addEventListener('mouseup', handleMouseUp);
    },
    [setCanvasSplit],
  );

  // Dialog openers
  const openDialog = useCallback((id: string) => {
    if (!DialogService.isOpen(id)) {
      DialogService.open(id);
    }
  }, []);

  // No-OpenClaw state
  if (openClawStatus === 'noOpenClaws' && !isSuperadmin) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 bg-surface-base">
        <Users size={32} className="text-fg-muted" />
        <p className="text-sm text-fg-tertiary">You have no assigned OpenClaw instances.</p>
        <button
          onClick={() => authClient.logout()}
          className="text-xs text-fg-muted hover:text-accent-primary"
        >
          {tr(language, 'logout')}
        </button>
      </div>
    );
  }

  const connectionDotColor =
    connectionState === 'connected'
      ? 'var(--accent-primary)'
      : connectionState === 'connecting'
        ? 'var(--status-warning)'
        : 'var(--status-error)';

  return (
    <div className="flex h-full flex-col bg-surface-base">
      {/* ============ Status Bar (28px) ============ */}
      <div className="flex h-7 shrink-0 items-center gap-3 border-b border-border-shell px-3">
        {/* Connection dot */}
        <div
          className="h-1.5 w-1.5 rounded-full"
          style={{ background: connectionDotColor }}
          title={connectionState}
        />

        {/* OpenClaw badge */}
        {activeOpenClaw && (
          <span className="text-[10px] text-fg-tertiary">{activeOpenClaw.name}</span>
        )}

        <div className="flex-1" />

        {/* Action links */}
        <StatusLink label={tr(language, 'knowledge')} onClick={() => openDialog('knowledge')} />
        <StatusLink label={tr(language, 'skills')} onClick={() => openDialog('skills')} />
        <StatusLink label={tr(language, 'automations')} onClick={() => openDialog('automations')} />
        {hasAdmin && (
          <>
            <StatusLink label={tr(language, 'channels')} onClick={() => openDialog('channels')} />
            <StatusLink label={tr(language, 'admin')} onClick={() => openDialog('admin')} />
          </>
        )}
        <StatusLink label={tr(language, 'settings')} onClick={() => openDialog('settings')} />

        {/* Notifications bell */}
        <div className="relative">
          <button
            onClick={() => setShowNotifications(!showNotifications)}
            className="text-fg-muted hover:text-fg-secondary"
          >
            <Bell size={12} />
          </button>
          {unreadCount > 0 && (
            <div
              className="absolute -right-1 -top-1 flex h-3 w-3 items-center justify-center rounded-full text-[7px] font-bold text-surface-base"
              style={{ background: 'var(--accent-primary)' }}
            >
              {unreadCount > 9 ? '9+' : unreadCount}
            </div>
          )}
          {showNotifications && (
            <NotificationCenter onClose={() => setShowNotifications(false)} />
          )}
        </div>
      </div>

      {/* ============ Mobile tab bar ============ */}
      {isMobile && (
        <div className="flex h-8 shrink-0 items-center justify-center gap-4 border-b border-border-shell">
          <button
            onClick={() => setMobileTab('chat')}
            className={`text-xs ${mobileTab === 'chat' ? 'text-accent-primary' : 'text-fg-muted'}`}
          >
            <MessageCircle size={14} />
          </button>
          <button
            onClick={() => setMobileTab('canvas')}
            className={`text-xs ${mobileTab === 'canvas' ? 'text-accent-primary' : 'text-fg-muted'}`}
          >
            <Layout size={14} />
          </button>
        </div>
      )}

      {/* ============ Main content area ============ */}
      <div ref={containerRef} className="flex flex-1 overflow-hidden">
        {/* Session drawer (desktop/tablet only) */}
        {!isMobile && <SessionDrawer />}

        {/* Chat panel */}
        {(!isMobile || mobileTab === 'chat') && (
          <div
            className="flex min-w-0 flex-col"
            style={{ flex: isMobile ? 1 : canvasSplit }}
          >
            <div className="flex-1 overflow-hidden">
              <ChatStream />
            </div>
          </div>
        )}

        {/* Draggable divider (desktop only) */}
        {!isMobile && (
          <div
            className="w-1.5 cursor-col-resize bg-transparent hover:bg-border-shell"
            onMouseDown={handleDividerMouseDown}
            onDoubleClick={() => setCanvasSplit(0.5)}
            style={{ flexShrink: 0 }}
          />
        )}

        {/* Canvas panel */}
        {(!isMobile || mobileTab === 'canvas') && (
          <div
            className="flex min-w-0 flex-col"
            style={{ flex: isMobile ? 1 : 1 - canvasSplit }}
          >
            <CanvasPanel />
          </div>
        )}

        {/* Approval panel */}
        <ApprovalPanel />
      </div>

      {/* ============ Prompt bar ============ */}
      <PromptBar ref={promptBarRef} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Status bar link                                                    */
/* ------------------------------------------------------------------ */

function StatusLink({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="text-[10px] text-fg-muted hover:text-fg-secondary"
    >
      {label}
    </button>
  );
}
