'use client';

/**
 * A2UIRenderer — 1:1 port of features/canvas/a2ui_renderer.dart (1920 lines)
 *
 * Renders all A2UI v0.8 surfaces from canvas store.
 * 17 component types: Text, Column, Row, Divider, Spacer, Image, Icon,
 * Progress, CodeEditor, Button, TextField, CheckBox, Slider, Toggle,
 * Card, Modal, Tabs, List
 */

import {
  type CSSProperties,
  type ReactNode,
  useCallback,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  Check,
  ChevronRight,
  Copy,
  LayoutGrid,
  Loader2,
  // Material-icon-name imports from lucide mapped below
} from 'lucide-react';
import { useCanvasStore } from '@/lib/stores/canvas-store';
import { useGatewayStore } from '@/lib/stores/gateway-store';
import {
  type A2UIComponent,
  type A2UISurface,
  resolveBoundString,
  resolveBoundNum,
  resolveBoundBool,
  resolveBoundValue,
  getPath,
  setPath,
} from '@/lib/protocol/a2ui-models';

/* ------------------------------------------------------------------ */
/*  Material icon map → lucide-react names                             */
/*  Lucide doesn't have all Material icons; we map common ones.        */
/* ------------------------------------------------------------------ */

import * as LucideIcons from 'lucide-react';

const MATERIAL_ICON_MAP: Record<string, LucideIcons.LucideIcon> = {
  check: LucideIcons.Check,
  close: LucideIcons.X,
  add: LucideIcons.Plus,
  remove: LucideIcons.Minus,
  delete: LucideIcons.Trash2,
  edit: LucideIcons.Pencil,
  search: LucideIcons.Search,
  settings: LucideIcons.Settings,
  home: LucideIcons.Home,
  star: LucideIcons.Star,
  star_border: LucideIcons.Star,
  favorite: LucideIcons.Heart,
  favorite_border: LucideIcons.Heart,
  info: LucideIcons.Info,
  warning: LucideIcons.AlertTriangle,
  error: LucideIcons.AlertCircle,
  help: LucideIcons.HelpCircle,
  visibility: LucideIcons.Eye,
  visibility_off: LucideIcons.EyeOff,
  arrow_back: LucideIcons.ArrowLeft,
  arrow_forward: LucideIcons.ArrowRight,
  arrow_upward: LucideIcons.ArrowUp,
  arrow_downward: LucideIcons.ArrowDown,
  expand_more: LucideIcons.ChevronDown,
  expand_less: LucideIcons.ChevronUp,
  chevron_right: LucideIcons.ChevronRight,
  chevron_left: LucideIcons.ChevronLeft,
  menu: LucideIcons.Menu,
  more_vert: LucideIcons.MoreVertical,
  more_horiz: LucideIcons.MoreHorizontal,
  refresh: LucideIcons.RefreshCw,
  copy: LucideIcons.Copy,
  content_copy: LucideIcons.Copy,
  content_paste: LucideIcons.ClipboardPaste,
  send: LucideIcons.Send,
  download: LucideIcons.Download,
  upload: LucideIcons.Upload,
  share: LucideIcons.Share2,
  link: LucideIcons.Link,
  open_in_new: LucideIcons.ExternalLink,
  play_arrow: LucideIcons.Play,
  pause: LucideIcons.Pause,
  stop: LucideIcons.Square,
  skip_next: LucideIcons.SkipForward,
  skip_previous: LucideIcons.SkipBack,
  person: LucideIcons.User,
  people: LucideIcons.Users,
  group: LucideIcons.Users,
  notifications: LucideIcons.Bell,
  email: LucideIcons.Mail,
  phone: LucideIcons.Phone,
  chat: LucideIcons.MessageSquare,
  message: LucideIcons.MessageCircle,
  calendar_today: LucideIcons.Calendar,
  schedule: LucideIcons.Clock,
  access_time: LucideIcons.Clock,
  location_on: LucideIcons.MapPin,
  map: LucideIcons.Map,
  cloud: LucideIcons.Cloud,
  cloud_upload: LucideIcons.CloudUpload,
  cloud_download: LucideIcons.CloudDownload,
  folder: LucideIcons.Folder,
  file_copy: LucideIcons.Files,
  attach_file: LucideIcons.Paperclip,
  photo: LucideIcons.Image,
  camera: LucideIcons.Camera,
  mic: LucideIcons.Mic,
  volume_up: LucideIcons.Volume2,
  volume_off: LucideIcons.VolumeX,
  brightness_high: LucideIcons.Sun,
  brightness_low: LucideIcons.SunDim,
  wifi: LucideIcons.Wifi,
  bluetooth: LucideIcons.Bluetooth,
  battery_full: LucideIcons.BatteryFull,
  power: LucideIcons.Power,
  lock: LucideIcons.Lock,
  lock_open: LucideIcons.LockOpen,
  vpn_key: LucideIcons.Key,
  security: LucideIcons.Shield,
  verified: LucideIcons.BadgeCheck,
  thumb_up: LucideIcons.ThumbsUp,
  thumb_down: LucideIcons.ThumbsDown,
  code: LucideIcons.Code,
  terminal: LucideIcons.Terminal,
  bug_report: LucideIcons.Bug,
  build: LucideIcons.Wrench,
  dashboard: LucideIcons.LayoutDashboard,
  analytics: LucideIcons.BarChart3,
  bar_chart: LucideIcons.BarChart,
  pie_chart: LucideIcons.PieChart,
  show_chart: LucideIcons.LineChart,
  trending_up: LucideIcons.TrendingUp,
  trending_down: LucideIcons.TrendingDown,
  data_usage: LucideIcons.Activity,
  memory: LucideIcons.Cpu,
  speed: LucideIcons.Gauge,
  grid_view: LucideIcons.LayoutGrid,
  list: LucideIcons.List,
  view_list: LucideIcons.ListOrdered,
  table_chart: LucideIcons.Table,
  check_circle: LucideIcons.CheckCircle2,
  cancel: LucideIcons.XCircle,
  do_not_disturb: LucideIcons.Ban,
  task_alt: LucideIcons.CircleCheckBig,
  pending: LucideIcons.Clock,
  hourglass_empty: LucideIcons.Hourglass,
  sync: LucideIcons.RefreshCcw,
  autorenew: LucideIcons.RotateCw,
  rocket_launch: LucideIcons.Rocket,
  lightbulb: LucideIcons.Lightbulb,
  psychology: LucideIcons.Brain,
  smart_toy: LucideIcons.Bot,
};

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function resolveChildIds(childrenProp: any): string[] {
  if (!childrenProp) return [];
  if (Array.isArray(childrenProp)) return childrenProp.filter(Boolean).map(String);
  if (typeof childrenProp === 'object') {
    const explicit = childrenProp.explicitList;
    if (Array.isArray(explicit)) return explicit.filter(Boolean).map(String);
  }
  return [];
}

function extractPath(prop: any): string | undefined {
  if (prop && typeof prop === 'object' && prop.path) return prop.path;
  return undefined;
}

/** Map CSS flex alignment strings */
function mainAxisAlign(
  dist?: string,
): CSSProperties['justifyContent'] {
  switch (dist) {
    case 'center':
      return 'center';
    case 'end':
      return 'flex-end';
    case 'spaceBetween':
      return 'space-between';
    case 'spaceAround':
      return 'space-around';
    case 'spaceEvenly':
      return 'space-evenly';
    default:
      return 'flex-start';
  }
}

function crossAxisAlign(alignment?: string): CSSProperties['alignItems'] {
  switch (alignment) {
    case 'center':
      return 'center';
    case 'end':
      return 'flex-end';
    case 'stretch':
      return 'stretch';
    default:
      return 'flex-start';
  }
}

/** Deep copy a JSON-like object */
function deepCopy<T>(obj: T): T {
  return JSON.parse(JSON.stringify(obj));
}

/* ------------------------------------------------------------------ */
/*  A2UIRenderer (main panel)                                          */
/* ------------------------------------------------------------------ */

export default function A2UIRenderer() {
  const surfaces = useCanvasStore((s) => s.surfaces);
  const client = useGatewayStore((s) => s.client);

  const hasSurfaces = Object.keys(surfaces).length > 0;
  const hasRenderable = Object.values(surfaces).some(
    (s) => s.rootId && s.components[s.rootId],
  );

  const sendUserAction = useCallback(
    (
      actionName: string,
      surface: A2UISurface,
      sourceComponentId: string,
      actionContext?: Record<string, any>,
    ) => {
      const resolvedContext: Record<string, any> = {};
      if (actionContext) {
        for (const [key, val] of Object.entries(actionContext)) {
          resolvedContext[key] = resolveBoundValue(val, surface) ?? val;
        }
      }

      const action = {
        name: actionName,
        surfaceId: surface.surfaceId,
        sourceComponentId,
        timestamp: new Date().toISOString(),
        context: resolvedContext,
      };

      client.sendChatMessage(`/a2ui-action ${JSON.stringify(action)}`);
    },
    [client],
  );

  // Empty state
  if (!hasSurfaces) {
    return (
      <div className="flex h-full w-full flex-col items-center justify-center gap-1.5">
        <LayoutGrid size={20} style={{ color: 'var(--fg-placeholder)' }} />
        <span
          className="text-[10px] tracking-widest"
          style={{ color: 'var(--fg-placeholder)' }}
        >
          canvas
        </span>
      </div>
    );
  }

  // Non-renderable (loading)
  if (!hasRenderable) {
    return (
      <div className="flex h-full w-full flex-col items-center justify-center gap-2">
        <div className="h-0.5 w-20 overflow-hidden rounded-full" style={{ background: 'var(--surface-elevated)' }}>
          <div className="h-full w-1/2 animate-pulse rounded-full" style={{ background: 'var(--accent-primary)' }} />
        </div>
        <span className="text-[10px]" style={{ color: 'var(--fg-placeholder)' }}>
          non-renderable A2UI payload
        </span>
      </div>
    );
  }

  return (
    <div className="h-full w-full overflow-auto px-3 pb-3 pt-8">
      {Object.values(surfaces).map((surface) => {
        if (!surface.rootId) return null;
        const rootComponent = surface.components[surface.rootId];
        if (!rootComponent) return null;
        return (
          <div key={`surface-${surface.surfaceId}`}>
            <RenderComponent
              component={rootComponent}
              surface={surface}
              onAction={sendUserAction}
            />
          </div>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  RenderComponent — recursive component dispatcher                   */
/* ------------------------------------------------------------------ */

function RenderComponent({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: (
    actionName: string,
    surface: A2UISurface,
    sourceComponentId: string,
    actionContext?: Record<string, any>,
  ) => void;
}) {
  const c = component;

  switch (c.type) {
    case 'Text':
      return <A2UIText component={c} surface={surface} />;
    case 'Column':
      return <A2UIColumn component={c} surface={surface} onAction={onAction} />;
    case 'Row':
      return <A2UIRow component={c} surface={surface} onAction={onAction} />;
    case 'Divider':
      return <A2UIDivider component={c} />;
    case 'Spacer':
      return <A2UISpacer component={c} />;
    case 'Image':
      return <A2UIImage component={c} surface={surface} />;
    case 'Icon':
      return <A2UIIcon component={c} surface={surface} />;
    case 'Progress':
      return <A2UIProgress component={c} surface={surface} />;
    case 'CodeEditor':
      return <A2UICodeEditor component={c} surface={surface} />;
    case 'Button':
      return (
        <A2UIButton component={c} surface={surface} onAction={onAction} />
      );
    case 'TextField':
      return <A2UITextField component={c} surface={surface} />;
    case 'CheckBox':
      return <A2UICheckBox component={c} surface={surface} />;
    case 'Slider':
      return <A2UISlider component={c} surface={surface} />;
    case 'Toggle':
      return <A2UIToggle component={c} surface={surface} />;
    case 'Card':
      return <A2UICard component={c} surface={surface} onAction={onAction} />;
    case 'Modal':
      return <A2UIModal component={c} surface={surface} onAction={onAction} />;
    case 'Tabs':
      return <A2UITabs component={c} surface={surface} onAction={onAction} />;
    case 'List':
      return <A2UIList component={c} surface={surface} onAction={onAction} />;
    default:
      return (
        <span className="py-0.5 text-[11px]" style={{ color: 'var(--fg-muted)' }}>
          [{c.type}]
        </span>
      );
  }
}

/* ------------------------------------------------------------------ */
/*  Text                                                               */
/* ------------------------------------------------------------------ */

function A2UIText({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const text = resolveBoundString(component.props.text, surface);
  const hint = component.props.usageHint as string | undefined;

  let className = 'py-0.5 select-text ';
  let style: CSSProperties = { color: 'var(--fg-primary)' };

  switch (hint) {
    case 'h1':
      className += 'text-xl font-semibold';
      break;
    case 'h2':
      className += 'text-base font-semibold';
      break;
    case 'h3':
      className += 'text-sm font-medium';
      break;
    case 'h4':
      className += 'text-xs font-medium';
      break;
    case 'h5':
      className += 'text-xs font-medium';
      style.color = 'var(--fg-secondary)';
      break;
    case 'caption':
    case 'label':
      className += 'text-[10px]';
      style.color = 'var(--fg-muted)';
      break;
    default:
      className += 'text-sm';
      break;
  }

  return (
    <p className={className} style={style}>
      {text}
    </p>
  );
}

/* ------------------------------------------------------------------ */
/*  Column                                                             */
/* ------------------------------------------------------------------ */

function A2UIColumn({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: any;
}) {
  const childIds = resolveChildIds(component.props.children);
  return (
    <div
      className="flex flex-col"
      style={{
        justifyContent: mainAxisAlign(component.props.distribution),
        alignItems: crossAxisAlign(component.props.alignment),
      }}
    >
      {childIds.map((id) => {
        const child = surface.components[id];
        if (!child) return null;
        return (
          <RenderComponent
            key={id}
            component={child}
            surface={surface}
            onAction={onAction}
          />
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Row                                                                */
/* ------------------------------------------------------------------ */

function A2UIRow({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: any;
}) {
  const childIds = resolveChildIds(component.props.children);
  return (
    <div
      className="flex flex-row"
      style={{
        justifyContent: mainAxisAlign(component.props.distribution),
        alignItems: crossAxisAlign(component.props.alignment),
      }}
    >
      {childIds.map((id) => {
        const child = surface.components[id];
        if (!child) return null;
        const flex = child.weight ?? 1;
        return (
          <div key={id} style={{ flex }}>
            <RenderComponent
              component={child}
              surface={surface}
              onAction={onAction}
            />
          </div>
        );
      })}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Divider                                                            */
/* ------------------------------------------------------------------ */

function A2UIDivider({ component }: { component: A2UIComponent }) {
  const axis = (component.props.axis as string) ?? 'horizontal';
  if (axis === 'vertical') {
    return (
      <div
        className="mx-2 h-10"
        style={{ width: 1, background: 'var(--border)' }}
      />
    );
  }
  return (
    <div
      className="my-2 w-full"
      style={{ height: 1, background: 'var(--border)' }}
    />
  );
}

/* ------------------------------------------------------------------ */
/*  Spacer                                                             */
/* ------------------------------------------------------------------ */

function A2UISpacer({ component }: { component: A2UIComponent }) {
  const height = (component.props.height as number) ?? 16;
  return <div style={{ height }} />;
}

/* ------------------------------------------------------------------ */
/*  Image                                                              */
/* ------------------------------------------------------------------ */

function A2UIImage({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const url = resolveBoundString(
    component.props.url ?? component.props.src,
    surface,
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  if (!url) return null;

  return (
    <div className="relative my-1 max-h-[400px] max-w-[600px]">
      {loading && !error && (
        <div
          className="flex h-20 w-full items-center justify-center"
          style={{ background: 'var(--surface-elevated)' }}
        >
          <Loader2
            size={16}
            className="animate-spin"
            style={{ color: 'var(--accent-primary)' }}
          />
        </div>
      )}
      {error && (
        <div
          className="p-2 text-xs"
          style={{ color: 'var(--fg-muted)', background: 'var(--surface-card)' }}
        >
          [Image failed to load]
        </div>
      )}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={url}
        alt=""
        className={`max-h-[400px] max-w-full object-contain ${loading && !error ? 'hidden' : ''}`}
        onLoad={() => setLoading(false)}
        onError={() => {
          setLoading(false);
          setError(true);
        }}
      />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Icon                                                               */
/* ------------------------------------------------------------------ */

function A2UIIcon({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const name = resolveBoundString(component.props.name, surface);
  const size = (component.props.size as number) ?? 20;
  const LucideIcon = MATERIAL_ICON_MAP[name] ?? LucideIcons.HelpCircle;

  return (
    <div className="py-0.5">
      <LucideIcon size={size} style={{ color: 'var(--fg-primary)' }} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Progress                                                           */
/* ------------------------------------------------------------------ */

function A2UIProgress({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const value = resolveBoundNum(component.props.value, surface);
  const isDeterminate = value != null;

  return (
    <div className="my-2 w-full">
      <div
        className="h-1 w-full overflow-hidden rounded-full"
        style={{ background: 'var(--surface-elevated)' }}
      >
        {isDeterminate ? (
          <div
            className="h-full rounded-full transition-all"
            style={{
              width: `${Math.max(0, Math.min(100, value * 100))}%`,
              background: 'var(--accent-primary)',
            }}
          />
        ) : (
          <div
            className="h-full w-1/3 animate-pulse rounded-full"
            style={{ background: 'var(--accent-primary)' }}
          />
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  CodeEditor                                                         */
/* ------------------------------------------------------------------ */

function A2UICodeEditor({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const code = resolveBoundString(component.props.code, surface);
  const language = resolveBoundString(component.props.language, surface);
  const editable = component.props.editable === true;
  const showLineNumbers = component.props.lineNumbers !== false;
  const codePath = extractPath(component.props.code);

  const [localCode, setLocalCode] = useState(code);
  const [copied, setCopied] = useState(false);

  // Sync from surface if changed externally
  if (!editable && code !== localCode) {
    setLocalCode(code);
  }

  const lines = (editable ? localCode : code).split('\n');

  const handleCopy = () => {
    navigator.clipboard.writeText(editable ? localCode : code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div
      className="my-1 overflow-hidden"
      style={{
        background: 'var(--surface-base)',
        border: '0.5px solid var(--border)',
        borderRadius: 'var(--shell-radius)',
      }}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between px-2.5 py-1"
        style={{
          background: 'var(--surface-card)',
          borderBottom: '0.5px solid var(--border)',
        }}
      >
        {language ? (
          <span
            className="rounded-sm px-1 py-px text-[9px]"
            style={{
              border: '0.5px solid var(--border)',
              color: 'var(--accent-primary)',
            }}
          >
            {language}
          </span>
        ) : (
          <span />
        )}
        <button
          onClick={handleCopy}
          className="flex cursor-pointer items-center gap-1"
        >
          {copied ? (
            <Check size={11} style={{ color: 'var(--accent-primary)' }} />
          ) : (
            <Copy size={11} style={{ color: 'var(--fg-muted)' }} />
          )}
          <span
            className="text-[9px]"
            style={{
              color: copied ? 'var(--accent-primary)' : 'var(--fg-muted)',
            }}
          >
            {copied ? 'copied' : 'copy'}
          </span>
        </button>
      </div>

      {/* Code area */}
      <div className="flex p-2">
        {showLineNumbers && (
          <div className="mr-3 flex flex-col items-end">
            {lines.map((_, i) => (
              <span
                key={i}
                className="font-mono text-xs leading-6"
                style={{ color: 'var(--fg-disabled)' }}
              >
                {i + 1}
              </span>
            ))}
          </div>
        )}
        <div className="flex-1 overflow-x-auto">
          {editable ? (
            <textarea
              value={localCode}
              onChange={(e) => {
                setLocalCode(e.target.value);
                if (codePath) setPath(surface, codePath, e.target.value);
              }}
              className="w-full resize-none bg-transparent font-mono text-xs leading-6 outline-none"
              style={{ color: 'var(--accent-primary)' }}
              rows={lines.length}
              spellCheck={false}
            />
          ) : (
            <pre
              className="whitespace-pre-wrap font-mono text-xs leading-6 select-text"
              style={{ color: 'var(--accent-primary)' }}
            >
              {code}
            </pre>
          )}
        </div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Button (primary / secondary / danger)                              */
/* ------------------------------------------------------------------ */

function A2UIButton({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: any;
}) {
  const actionProp = component.props.action;
  let actionName: string | undefined;
  let actionContext: Record<string, any> | undefined;

  if (typeof actionProp === 'object' && actionProp !== null && !Array.isArray(actionProp)) {
    actionName = actionProp.name;
    const ctxRaw = actionProp.context;
    if (ctxRaw && typeof ctxRaw === 'object' && !Array.isArray(ctxRaw)) {
      actionContext = ctxRaw;
    } else if (Array.isArray(ctxRaw)) {
      actionContext = {};
      for (const entry of ctxRaw) {
        if (entry && typeof entry === 'object' && entry.key) {
          actionContext[entry.key] = entry.value;
        }
      }
    }
  } else if (typeof actionProp === 'string') {
    actionName = actionProp;
  }

  const primary = component.props.primary === true;
  const variantRaw = component.props.variant
    ? String(component.props.variant).toLowerCase()
    : undefined;
  const variant = variantRaw ?? (primary ? 'primary' : 'secondary');

  // Child component for label
  const childId = component.props.child as string | undefined;
  const childComp = childId ? surface.components[childId] : undefined;
  const label = resolveBoundString(
    component.props.label ?? component.props.text,
    surface,
  );

  const bgColor =
    variant === 'danger'
      ? 'var(--status-error)'
      : variant === 'primary'
        ? 'var(--accent-primary)'
        : 'var(--surface-card)';
  const fgColor =
    variant === 'danger' || variant === 'primary'
      ? 'var(--surface-base)'
      : 'var(--fg-primary)';

  return (
    <div className="py-1">
      <button
        onClick={
          actionName
            ? () =>
                onAction(actionName!, surface, component.id, actionContext)
            : undefined
        }
        disabled={!actionName}
        className="cursor-pointer rounded-sm px-5 py-2.5 text-sm font-medium transition-opacity hover:opacity-90 disabled:cursor-default disabled:opacity-50"
        style={{
          background: bgColor,
          color: fgColor,
          border:
            variant === 'secondary'
              ? '0.5px solid var(--border)'
              : 'none',
        }}
      >
        {childComp ? (
          <RenderComponent
            component={childComp}
            surface={surface}
            onAction={onAction}
          />
        ) : (
          label || 'Button'
        )}
      </button>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  TextField (short / long / number / date / obscured)                */
/* ------------------------------------------------------------------ */

function A2UITextField({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const label = resolveBoundString(component.props.label, surface);
  const placeholder = (component.props.placeholder as string) ?? '';
  const textFieldType = (component.props.textFieldType as string) ?? 'shortText';
  const textPath = extractPath(component.props.text);

  const initialValue = resolveBoundString(component.props.text, surface);
  const [value, setValue] = useState(initialValue);

  // Sync if surface changed the value externally
  const surfaceValue = resolveBoundString(component.props.text, surface);
  if (surfaceValue !== value && surfaceValue !== initialValue) {
    // External update
  }

  const isMultiline = textFieldType === 'longText';
  const isObscured = textFieldType === 'obscured';
  const inputType =
    textFieldType === 'number'
      ? 'number'
      : textFieldType === 'date'
        ? 'date'
        : isObscured
          ? 'password'
          : 'text';

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
  ) => {
    setValue(e.target.value);
    if (textPath) setPath(surface, textPath, e.target.value);
  };

  const fieldStyle: CSSProperties = {
    background: 'transparent',
    border: '0.5px solid var(--border)',
    color: 'var(--fg-primary)',
    outline: 'none',
    fontFamily: 'inherit',
  };

  return (
    <div className="flex flex-col gap-1 py-1">
      {label && (
        <label
          className="text-xs"
          style={{ color: 'var(--fg-secondary)' }}
        >
          {label}
        </label>
      )}
      {isMultiline ? (
        <textarea
          value={value}
          onChange={handleChange}
          placeholder={placeholder}
          rows={5}
          className="w-full rounded-sm px-2 py-1.5 text-sm"
          style={fieldStyle}
        />
      ) : (
        <input
          type={inputType}
          value={value}
          onChange={handleChange}
          placeholder={placeholder}
          className="w-full rounded-sm px-2 py-1.5 text-sm"
          style={fieldStyle}
        />
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  CheckBox                                                           */
/* ------------------------------------------------------------------ */

function A2UICheckBox({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const label = resolveBoundString(component.props.label, surface);
  const valuePath = extractPath(component.props.value);
  const initial = resolveBoundBool(component.props.value, surface);
  const [checked, setChecked] = useState(initial);

  return (
    <label className="flex cursor-pointer items-center gap-2 py-1">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => {
          setChecked(e.target.checked);
          if (valuePath) setPath(surface, valuePath, e.target.checked);
        }}
        className="accent-[var(--accent-primary)]"
      />
      <span className="text-sm" style={{ color: 'var(--fg-primary)' }}>
        {label}
      </span>
    </label>
  );
}

/* ------------------------------------------------------------------ */
/*  Slider                                                             */
/* ------------------------------------------------------------------ */

function A2UISlider({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const label = resolveBoundString(component.props.label, surface);
  const min = (component.props.min as number) ?? 0;
  const max = (component.props.max as number) ?? 100;
  const valuePath = extractPath(component.props.value);
  const initial = resolveBoundNum(component.props.value, surface) ?? min;
  const [value, setValue] = useState(Math.max(min, Math.min(max, initial)));

  return (
    <div className="flex flex-col gap-1 py-1">
      {label && (
        <span className="text-xs" style={{ color: 'var(--fg-muted)' }}>
          {label}
        </span>
      )}
      <input
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(e) => {
          const v = Number(e.target.value);
          setValue(v);
          if (valuePath) setPath(surface, valuePath, v);
        }}
        className="w-full accent-[var(--accent-primary)]"
      />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Toggle                                                             */
/* ------------------------------------------------------------------ */

function A2UIToggle({
  component,
  surface,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
}) {
  const label = resolveBoundString(component.props.label, surface);
  const valuePath = extractPath(component.props.value);
  const initial = resolveBoundBool(component.props.value, surface);
  const [on, setOn] = useState(initial);

  return (
    <label className="flex cursor-pointer items-center justify-between py-1">
      <span className="text-sm" style={{ color: 'var(--fg-primary)' }}>
        {label}
      </span>
      <button
        onClick={() => {
          const next = !on;
          setOn(next);
          if (valuePath) setPath(surface, valuePath, next);
        }}
        className="relative h-5 w-9 rounded-full transition-colors"
        style={{
          background: on ? 'var(--accent-primary)' : 'var(--fg-disabled)',
        }}
      >
        <span
          className="absolute top-0.5 h-4 w-4 rounded-full bg-white transition-transform"
          style={{ left: on ? 18 : 2 }}
        />
      </button>
    </label>
  );
}

/* ------------------------------------------------------------------ */
/*  Card                                                               */
/* ------------------------------------------------------------------ */

function A2UICard({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: any;
}) {
  const singleChild = component.props.child as string | undefined;
  const singleChildComp = singleChild
    ? surface.components[singleChild]
    : undefined;
  const childIds = resolveChildIds(component.props.children);

  return (
    <div
      className="my-1.5 p-3"
      style={{
        background: 'var(--surface-card)',
        border: '0.5px solid var(--border)',
        borderRadius: 'var(--shell-radius)',
      }}
    >
      {singleChildComp ? (
        <RenderComponent
          component={singleChildComp}
          surface={surface}
          onAction={onAction}
        />
      ) : (
        childIds.map((id) => {
          const child = surface.components[id];
          if (!child) return null;
          return (
            <RenderComponent
              key={id}
              component={child}
              surface={surface}
              onAction={onAction}
            />
          );
        })
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Modal                                                              */
/* ------------------------------------------------------------------ */

function A2UIModal({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: any;
}) {
  const [open, setOpen] = useState(false);
  const entryPointChildId = component.props.entryPointChild as string | undefined;
  const contentChildId = component.props.contentChild as string | undefined;

  const entryComp = entryPointChildId
    ? surface.components[entryPointChildId]
    : undefined;
  const contentComp = contentChildId
    ? surface.components[contentChildId]
    : undefined;

  return (
    <>
      <div onClick={() => setOpen(true)} className="cursor-pointer">
        {entryComp ? (
          <RenderComponent
            component={entryComp}
            surface={surface}
            onAction={onAction}
          />
        ) : null}
      </div>

      {open && contentComp && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
          onClick={() => setOpen(false)}
        >
          <div
            className="max-h-[80vh] max-w-[600px] overflow-auto p-4"
            onClick={(e) => e.stopPropagation()}
            style={{
              background: 'var(--surface-base)',
              border: '0.5px solid var(--border)',
              borderRadius: 'var(--shell-radius)',
            }}
          >
            <RenderComponent
              component={contentComp}
              surface={surface}
              onAction={onAction}
            />
          </div>
        </div>
      )}
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Tabs                                                               */
/* ------------------------------------------------------------------ */

function A2UITabs({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: any;
}) {
  const tabItems = (component.props.tabItems as any[]) ?? [];
  const [activeIndex, setActiveIndex] = useState(0);

  if (tabItems.length === 0) return null;

  return (
    <div className="flex flex-col">
      {/* Tab headers */}
      <div
        className="flex"
        style={{ borderBottom: '0.5px solid var(--border)' }}
      >
        {tabItems.map((item: any, i: number) => {
          const title = resolveBoundString(item?.title, surface);
          const isActive = i === activeIndex;
          return (
            <button
              key={i}
              onClick={() => setActiveIndex(i)}
              className="cursor-pointer px-3 py-2 text-xs transition-colors"
              style={{
                color: isActive ? 'var(--accent-primary)' : 'var(--fg-muted)',
                borderBottom: isActive
                  ? '2px solid var(--accent-primary)'
                  : '2px solid transparent',
                fontWeight: isActive ? 600 : 400,
              }}
            >
              {title || `Tab ${i + 1}`}
            </button>
          );
        })}
      </div>

      {/* Tab content */}
      <div className="max-h-[400px] overflow-auto p-2">
        {tabItems.map((item: any, i: number) => {
          if (i !== activeIndex) return null;
          const childId = item?.child as string | undefined;
          const childComp = childId
            ? surface.components[childId]
            : undefined;
          if (!childComp) return null;
          return (
            <RenderComponent
              key={childId}
              component={childComp}
              surface={surface}
              onAction={onAction}
            />
          );
        })}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  List (explicit + template with data binding)                       */
/* ------------------------------------------------------------------ */

function A2UIList({
  component,
  surface,
  onAction,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onAction: any;
}) {
  const childrenProp = component.props.children;

  // Template-based list
  if (
    childrenProp &&
    typeof childrenProp === 'object' &&
    !Array.isArray(childrenProp) &&
    childrenProp.template
  ) {
    const template = childrenProp.template;
    const dataBinding = template.dataBinding as string | undefined;
    const templateId = template.componentId as string | undefined;

    if (dataBinding && templateId) {
      const listData = getPath(surface, dataBinding);
      if (Array.isArray(listData)) {
        return (
          <div className="max-h-[400px] overflow-auto">
            {listData.map((item, index) => {
              const templateComp = surface.components[templateId];
              if (!templateComp) return null;

              // Create scoped surface with item data
              const scopedSurface: A2UISurface = {
                ...surface,
                dataModel: {
                  ...deepCopy(surface.dataModel),
                  _current: item,
                  _index: index,
                },
              };

              return (
                <div key={`list-item-${index}`}>
                  <RenderComponent
                    component={templateComp}
                    surface={scopedSurface}
                    onAction={onAction}
                  />
                </div>
              );
            })}
          </div>
        );
      }
    }
    return null;
  }

  // Explicit list
  const childIds = resolveChildIds(childrenProp);
  return (
    <div className="max-h-[400px] overflow-auto">
      {childIds.map((id) => {
        const child = surface.components[id];
        if (!child) return null;
        return (
          <RenderComponent
            key={id}
            component={child}
            surface={surface}
            onAction={onAction}
          />
        );
      })}
    </div>
  );
}
