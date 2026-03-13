'use client';

/**
 * A2UIEditor — 1:1 port of features/canvas/a2ui_editor.dart (1325 lines)
 *
 * Edit mode infrastructure for the A2UI canvas:
 * - ComponentTemplate catalog (16 types across 4 categories)
 * - ComponentPalette (dropdown overlay for adding components)
 * - EditableComponentWrapper (selection border + ID badge)
 * - PropertyInspector (220px right panel with type-specific editors)
 * - Helper functions (findParent, resolveChildIds, removeComponent, surfacesToJsonl)
 */

import {
  type CSSProperties,
  type ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  ArrowDown,
  ArrowUp,
  ChevronDown,
  ChevronUp,
  Columns,
  Code,
  Grip,
  Image,
  Minus,
  Plus,
  Rows,
  SlidersHorizontal,
  Space,
  Square,
  Star,
  ToggleRight,
  Type,
  X,
  CheckSquare,
  Table,
  CircleEllipsis,
  Sliders,
  LayoutList,
} from 'lucide-react';
import { useCanvasStore } from '@/lib/stores/canvas-store';
import type { A2UIComponent, A2UISurface } from '@/lib/protocol/a2ui-models';

/* ================================================================== */
/*  Component Template Catalog                                         */
/* ================================================================== */

export interface ComponentTemplate {
  type: string;
  label: string;
  icon: ReactNode;
  category: 'Layout' | 'Display' | 'Interactive' | 'Container';
  /** Creates a default component with the given ID. */
  create: (id: string) => A2UIComponent;
}

let _nextId = 0;
export function genComponentId(): string {
  return `user-${_nextId++}`;
}

export const componentTemplates: ComponentTemplate[] = [
  // ---- Layout ----
  {
    type: 'Column',
    label: 'Column',
    icon: <Columns size={12} />,
    category: 'Layout',
    create: (id) => ({
      id,
      type: 'Column',
      props: { children: { explicitList: [] } },
    }),
  },
  {
    type: 'Row',
    label: 'Row',
    icon: <Rows size={12} />,
    category: 'Layout',
    create: (id) => ({
      id,
      type: 'Row',
      props: { children: { explicitList: [] } },
    }),
  },
  {
    type: 'Divider',
    label: 'Divider',
    icon: <Minus size={12} />,
    category: 'Layout',
    create: (id) => ({
      id,
      type: 'Divider',
      props: { axis: 'horizontal' },
    }),
  },
  {
    type: 'Spacer',
    label: 'Spacer',
    icon: <Space size={12} />,
    category: 'Layout',
    create: (id) => ({
      id,
      type: 'Spacer',
      props: { height: 16 },
    }),
  },

  // ---- Display ----
  {
    type: 'Text',
    label: 'Text',
    icon: <Type size={12} />,
    category: 'Display',
    create: (id) => ({
      id,
      type: 'Text',
      props: { text: { literalString: 'New text' }, usageHint: 'body' },
    }),
  },
  {
    type: 'Image',
    label: 'Image',
    icon: <Image size={12} />,
    category: 'Display',
    create: (id) => ({
      id,
      type: 'Image',
      props: { url: { literalString: '' } },
    }),
  },
  {
    type: 'Icon',
    label: 'Icon',
    icon: <Star size={12} />,
    category: 'Display',
    create: (id) => ({
      id,
      type: 'Icon',
      props: { name: { literalString: 'star' } },
    }),
  },
  {
    type: 'Progress',
    label: 'Progress',
    icon: <SlidersHorizontal size={12} />,
    category: 'Display',
    create: (id) => ({
      id,
      type: 'Progress',
      props: { value: 0.5 },
    }),
  },
  {
    type: 'CodeEditor',
    label: 'CodeEditor',
    icon: <Code size={12} />,
    category: 'Display',
    create: (id) => ({
      id,
      type: 'CodeEditor',
      props: {
        code: { literalString: '// your code here' },
        language: { literalString: 'typescript' },
        editable: false,
        lineNumbers: true,
      },
    }),
  },

  // ---- Interactive ----
  {
    type: 'Button',
    label: 'Button',
    icon: <Square size={12} />,
    category: 'Interactive',
    create: (id) => {
      const textId = `${id}-label`;
      return {
        id,
        type: 'Button',
        props: {
          child: textId,
          primary: false,
          action: { name: `click_${id}` },
        },
      };
    },
  },
  {
    type: 'TextField',
    label: 'TextField',
    icon: <Grip size={12} />,
    category: 'Interactive',
    create: (id) => ({
      id,
      type: 'TextField',
      props: {
        label: { literalString: 'Label' },
        placeholder: 'Enter text...',
        textFieldType: 'shortText',
        text: { path: `/user-input/${id}` },
      },
    }),
  },
  {
    type: 'CheckBox',
    label: 'CheckBox',
    icon: <CheckSquare size={12} />,
    category: 'Interactive',
    create: (id) => ({
      id,
      type: 'CheckBox',
      props: {
        label: { literalString: 'Check me' },
        value: { path: `/user-input/${id}` },
      },
    }),
  },
  {
    type: 'Toggle',
    label: 'Toggle',
    icon: <ToggleRight size={12} />,
    category: 'Interactive',
    create: (id) => ({
      id,
      type: 'Toggle',
      props: {
        label: { literalString: 'Toggle' },
        value: { path: `/user-input/${id}` },
      },
    }),
  },
  {
    type: 'Slider',
    label: 'Slider',
    icon: <Sliders size={12} />,
    category: 'Interactive',
    create: (id) => ({
      id,
      type: 'Slider',
      props: {
        min: 0,
        max: 100,
        value: { path: `/user-input/${id}` },
      },
    }),
  },

  // ---- Container ----
  {
    type: 'Card',
    label: 'Card',
    icon: <Square size={12} />,
    category: 'Container',
    create: (id) => ({
      id,
      type: 'Card',
      props: { children: { explicitList: [] } },
    }),
  },
  {
    type: 'Tabs',
    label: 'Tabs',
    icon: <Table size={12} />,
    category: 'Container',
    create: (id) => ({
      id,
      type: 'Tabs',
      props: { tabItems: [] },
    }),
  },
  {
    type: 'List',
    label: 'List',
    icon: <LayoutList size={12} />,
    category: 'Container',
    create: (id) => ({
      id,
      type: 'List',
      props: { children: { explicitList: [] } },
    }),
  },
];

/* ================================================================== */
/*  Helper Functions                                                    */
/* ================================================================== */

/** Get child IDs from a component's children/child prop. */
export function resolveChildIds(comp: A2UIComponent): string[] {
  const childrenProp = comp.props.children;
  if (Array.isArray(childrenProp)) {
    return childrenProp.filter(Boolean).map(String);
  }
  if (childrenProp && typeof childrenProp === 'object') {
    const explicit = childrenProp.explicitList;
    if (Array.isArray(explicit)) {
      return explicit.filter(Boolean).map(String);
    }
  }
  // Single child
  const child = comp.props.child;
  if (typeof child === 'string') return [child];
  return [];
}

/** Find the parent component that contains [childId] in its children list. */
export function findParent(
  childId: string,
  surface: A2UISurface,
): A2UIComponent | null {
  for (const comp of Object.values(surface.components)) {
    const childIds = resolveChildIds(comp);
    if (childIds.includes(childId)) return comp;
  }
  return null;
}

/** Set child IDs on a component (Column, Row, Card, etc.) */
export function setChildIds(comp: A2UIComponent, ids: string[]): void {
  if (comp.props.children && typeof comp.props.children === 'object' && !Array.isArray(comp.props.children)) {
    comp.props.children.explicitList = ids;
  } else {
    comp.props.children = { explicitList: ids };
  }
}

/** Check if a component type is a container (can hold children). */
export function isContainer(type: string): boolean {
  return ['Column', 'Row', 'Card', 'List'].includes(type);
}

/** Cascade remove a component and its descendants. */
function cascadeRemove(id: string, surface: A2UISurface): void {
  const comp = surface.components[id];
  if (!comp) return;
  delete surface.components[id];
  for (const childId of resolveChildIds(comp)) {
    cascadeRemove(childId, surface);
  }
  // Also handle Button child
  const child = comp.props.child;
  if (typeof child === 'string') {
    cascadeRemove(child, surface);
  }
}

/**
 * Remove a component and its descendants from a surface.
 * Also removes it from its parent's child list.
 */
export function removeComponent(
  componentId: string,
  surface: A2UISurface,
): void {
  // Remove from parent
  const parent = findParent(componentId, surface);
  if (parent) {
    const ids = resolveChildIds(parent);
    const filtered = ids.filter((id) => id !== componentId);
    setChildIds(parent, filtered);
  }
  // Cascade remove children
  cascadeRemove(componentId, surface);
}

/** Convert data model map to A2UI contents array. */
function mapToContents(
  map: Record<string, any>,
): Array<Record<string, any>> {
  const contents: Array<Record<string, any>> = [];
  for (const [key, val] of Object.entries(map)) {
    if (typeof val === 'string') {
      contents.push({ key, valueString: val });
    } else if (typeof val === 'number') {
      contents.push({ key, valueNumber: val });
    } else if (typeof val === 'boolean') {
      contents.push({ key, valueBoolean: val });
    } else if (Array.isArray(val)) {
      contents.push({ key, valueArray: val });
    } else if (val && typeof val === 'object') {
      contents.push({ key, valueMap: mapToContents(val) });
    }
  }
  return contents;
}

/** Serialize surfaces to JSONL for sending to agent. */
export function surfacesToJsonl(
  surfaces: Record<string, A2UISurface>,
): string {
  const lines: string[] = [];
  for (const surface of Object.values(surfaces)) {
    if (!surface.rootId) continue;

    // surfaceUpdate with all components
    const components = Object.values(surface.components).map((c) => {
      const compMap: Record<string, any> = {
        id: c.id,
        component: { [c.type]: c.props },
      };
      if (c.weight != null) compMap.weight = c.weight;
      return compMap;
    });
    lines.push(
      JSON.stringify({
        surfaceUpdate: {
          surfaceId: surface.surfaceId,
          components,
        },
      }),
    );

    // beginRendering
    lines.push(
      JSON.stringify({
        beginRendering: {
          surfaceId: surface.surfaceId,
          root: surface.rootId,
        },
      }),
    );

    // dataModelUpdate if non-empty
    if (
      surface.dataModel &&
      Object.keys(surface.dataModel).length > 0
    ) {
      const contents = mapToContents(surface.dataModel);
      lines.push(
        JSON.stringify({
          dataModelUpdate: {
            surfaceId: surface.surfaceId,
            contents,
          },
        }),
      );
    }
  }
  return lines.join('\n');
}

/* ================================================================== */
/*  ComponentPalette                                                    */
/* ================================================================== */

export function ComponentPalette({
  onAdd,
}: {
  onAdd: (template: ComponentTemplate) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const anchorRef = useRef<HTMLDivElement>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!expanded) return;
    function handleClick(e: MouseEvent) {
      if (
        anchorRef.current?.contains(e.target as Node) ||
        dropdownRef.current?.contains(e.target as Node)
      ) {
        return;
      }
      setExpanded(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [expanded]);

  // Group templates by category
  const grouped = useMemo(() => {
    const groups: Record<string, ComponentTemplate[]> = {};
    for (const tmpl of componentTemplates) {
      if (!groups[tmpl.category]) groups[tmpl.category] = [];
      groups[tmpl.category].push(tmpl);
    }
    return groups;
  }, []);

  return (
    <div className="relative" ref={anchorRef}>
      <button
        onClick={() => setExpanded((p) => !p)}
        className="flex cursor-pointer items-center gap-1 rounded-sm px-1.5 py-1"
        style={{
          background: 'color-mix(in srgb, var(--surface-base) 80%, transparent)',
          border: '0.5px solid var(--border)',
        }}
      >
        <Plus size={11} style={{ color: 'var(--accent-primary)' }} />
        <span
          className="text-[10px]"
          style={{ color: 'var(--fg-secondary)' }}
        >
          add
        </span>
        {expanded ? (
          <ChevronUp size={10} style={{ color: 'var(--fg-muted)' }} />
        ) : (
          <ChevronDown size={10} style={{ color: 'var(--fg-muted)' }} />
        )}
      </button>

      {expanded && (
        <div
          ref={dropdownRef}
          className="absolute left-0 top-full z-50 mt-0.5 max-h-80 w-40 overflow-auto"
          style={{
            background: 'var(--surface-base)',
            border: '0.5px solid var(--border)',
            borderRadius: 'var(--shell-radius-sm)',
          }}
        >
          <div className="py-0.5">
            {Object.entries(grouped).map(([category, templates]) => (
              <div key={category}>
                <div
                  className="px-2 pt-1.5 pb-0.5 text-[9px] uppercase tracking-wider"
                  style={{ color: 'var(--fg-muted)' }}
                >
                  {category}
                </div>
                {templates.map((tmpl) => (
                  <PaletteItem
                    key={tmpl.type}
                    template={tmpl}
                    onTap={() => {
                      onAdd(tmpl);
                      setExpanded(false);
                    }}
                  />
                ))}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function PaletteItem({
  template,
  onTap,
}: {
  template: ComponentTemplate;
  onTap: () => void;
}) {
  const [hovering, setHovering] = useState(false);

  return (
    <button
      onClick={onTap}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      className="flex w-full cursor-pointer items-center gap-1.5 px-2 py-1"
      style={{
        background: hovering ? 'var(--surface-card)' : 'transparent',
        color: 'var(--fg-muted)',
      }}
    >
      <span style={{ color: 'var(--fg-muted)' }}>{template.icon}</span>
      <span
        className="text-[10px]"
        style={{ color: 'var(--fg-secondary)' }}
      >
        {template.label}
      </span>
    </button>
  );
}

/* ================================================================== */
/*  EditableComponentWrapper                                            */
/* ================================================================== */

export function EditableComponentWrapper({
  children,
  componentId,
  isSelected,
  onSelect,
}: {
  children: ReactNode;
  componentId: string;
  isSelected: boolean;
  onSelect: () => void;
}) {
  const [hovering, setHovering] = useState(false);
  const showBorder = isSelected || hovering;

  return (
    <div
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      onClick={(e) => {
        e.stopPropagation();
        onSelect();
      }}
      className="relative cursor-pointer"
      style={{
        borderRadius: 'var(--shell-radius-sm)',
        border: showBorder
          ? `${isSelected ? '1px' : '0.5px'} solid ${
              isSelected
                ? 'var(--accent-primary)'
                : 'color-mix(in srgb, var(--accent-primary) 30%, transparent)'
            }`
          : '1px solid transparent',
      }}
    >
      <div className="p-px">{children}</div>

      {/* Component ID badge on hover/select */}
      {showBorder && (
        <div
          className="absolute top-0 right-0 px-1 py-px text-[8px] font-semibold"
          style={{
            background: isSelected
              ? 'var(--accent-primary)'
              : 'color-mix(in srgb, var(--accent-primary) 70%, transparent)',
            color: 'var(--surface-base)',
            borderBottomLeftRadius: 2,
            borderTopRightRadius: 'var(--shell-radius-sm)',
          }}
        >
          {componentId}
        </div>
      )}
    </div>
  );
}

/* ================================================================== */
/*  PropertyInspector                                                   */
/* ================================================================== */

export function PropertyInspector({
  component,
  surface,
  onEdited,
  onDelete,
  onDeselect,
  onReorder,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onEdited: () => void;
  onDelete: () => void;
  onDeselect: () => void;
  onReorder?: (oldIndex: number, newIndex: number) => void;
}) {
  return (
    <div
      className="flex h-full w-[220px] shrink-0 flex-col"
      style={{
        background: 'var(--surface-base)',
        borderLeft: '0.5px solid var(--border)',
      }}
    >
      {/* Header */}
      <div
        className="flex shrink-0 items-center gap-1.5 px-2 py-1.5"
        style={{ borderBottom: '0.5px solid var(--border)' }}
      >
        <SlidersHorizontal
          size={12}
          style={{ color: 'var(--accent-primary)' }}
        />
        <span
          className="flex-1 text-[10px] tracking-wider"
          style={{ color: 'var(--fg-secondary)' }}
        >
          properties
        </span>
        <button
          onClick={onDeselect}
          className="cursor-pointer"
        >
          <X size={12} style={{ color: 'var(--fg-muted)' }} />
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-auto p-2">
        {/* ID (read only) */}
        <ReadOnlyField label="id" value={component.id} />
        <div className="h-1.5" />

        {/* Type (read only) */}
        <ReadOnlyField label="type" value={component.type} />
        <div className="h-1.5" />

        {/* Move up/down buttons */}
        <MoveButtons
          component={component}
          surface={surface}
          onReorder={onReorder}
        />
        <div className="h-2" />

        <div
          className="w-full"
          style={{ height: 1, background: 'var(--border)' }}
        />
        <div className="h-2" />

        {/* Type-specific property editors */}
        <PropEditors
          component={component}
          surface={surface}
          onEdited={onEdited}
        />

        <div className="h-4" />

        {/* Weight editor */}
        <WeightEditor
          component={component}
          surface={surface}
          onEdited={onEdited}
        />

        <div className="h-4" />
        <div
          className="w-full"
          style={{ height: 1, background: 'var(--border)' }}
        />
        <div className="h-2" />

        {/* Delete button */}
        <button
          onClick={onDelete}
          className="w-full cursor-pointer rounded-sm py-1.5 text-center text-[10px]"
          style={{
            border: '0.5px solid color-mix(in srgb, var(--status-error) 30%, transparent)',
            color: 'var(--status-error)',
            background: 'transparent',
          }}
        >
          delete component
        </button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  ReadOnlyField                                                      */
/* ------------------------------------------------------------------ */

function ReadOnlyField({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center">
      <span
        className="w-[50px] shrink-0 text-[9px] tracking-tight"
        style={{ color: 'var(--fg-muted)' }}
      >
        {label}
      </span>
      <span
        className="flex-1 truncate text-[10px]"
        style={{ color: 'var(--fg-secondary)' }}
      >
        {value}
      </span>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  MoveButtons                                                        */
/* ------------------------------------------------------------------ */

function MoveButtons({
  component,
  surface,
  onReorder,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onReorder?: (oldIndex: number, newIndex: number) => void;
}) {
  const parent = findParent(component.id, surface);
  if (!parent) return null;

  const siblings = resolveChildIds(parent);
  const index = siblings.indexOf(component.id);
  if (index < 0) return null;

  const canMoveUp = index > 0;
  const canMoveDown = index < siblings.length - 1;

  return (
    <div className="flex items-center">
      <span
        className="w-[50px] shrink-0 text-[9px] tracking-tight"
        style={{ color: 'var(--fg-muted)' }}
      >
        order
      </span>
      <MoveButton
        enabled={canMoveUp}
        onClick={() => onReorder?.(index, index - 1)}
      >
        <ArrowUp size={10} />
      </MoveButton>
      <div className="w-1" />
      <MoveButton
        enabled={canMoveDown}
        onClick={() => onReorder?.(index, index + 1)}
      >
        <ArrowDown size={10} />
      </MoveButton>
    </div>
  );
}

function MoveButton({
  enabled,
  onClick,
  children,
}: {
  enabled: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      onClick={enabled ? onClick : undefined}
      className="flex items-center justify-center rounded-sm p-0.5"
      style={{
        border: '0.5px solid var(--border)',
        color: enabled ? 'var(--fg-secondary)' : 'var(--fg-disabled)',
        cursor: enabled ? 'pointer' : 'default',
      }}
    >
      {children}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/*  WeightEditor                                                       */
/* ------------------------------------------------------------------ */

function WeightEditor({
  component,
  surface,
  onEdited,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onEdited: () => void;
}) {
  const currentWeight = component.weight ?? 1;

  return (
    <div>
      <span
        className="text-[9px] tracking-tight"
        style={{ color: 'var(--fg-muted)' }}
      >
        flex weight
      </span>
      <div className="mt-1 flex items-center gap-1">
        <input
          type="range"
          min={1}
          max={10}
          step={1}
          value={Math.max(1, Math.min(10, currentWeight))}
          onChange={(e) => {
            const w = parseInt(e.target.value, 10);
            // Replace component in surface with new weight
            const newComp: A2UIComponent = {
              id: component.id,
              type: component.type,
              props: component.props,
              weight: w,
            };
            surface.components[component.id] = newComp;
            onEdited();
          }}
          className="flex-1 accent-[var(--accent-primary)]"
        />
        <span
          className="w-6 text-center text-[10px]"
          style={{ color: 'var(--fg-secondary)' }}
        >
          {currentWeight}
        </span>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  PropEditors — type dispatcher                                      */
/* ------------------------------------------------------------------ */

function PropEditors({
  component,
  surface,
  onEdited,
}: {
  component: A2UIComponent;
  surface: A2UISurface;
  onEdited: () => void;
}) {
  switch (component.type) {
    case 'Text':
      return <TextProps component={component} onEdited={onEdited} />;
    case 'Button':
      return <ButtonProps component={component} onEdited={onEdited} />;
    case 'Image':
      return <ImageProps component={component} onEdited={onEdited} />;
    case 'Icon':
      return <IconProps component={component} onEdited={onEdited} />;
    case 'TextField':
      return <TextFieldProps component={component} onEdited={onEdited} />;
    case 'CheckBox':
    case 'Toggle':
      return <LabelProps component={component} onEdited={onEdited} />;
    case 'Slider':
      return <SliderProps component={component} onEdited={onEdited} />;
    case 'Progress':
      return <ProgressProps component={component} onEdited={onEdited} />;
    case 'Spacer':
      return <SpacerProps component={component} onEdited={onEdited} />;
    case 'Divider':
      return <DividerProps component={component} onEdited={onEdited} />;
    case 'Column':
    case 'Row':
      return <LayoutProps component={component} onEdited={onEdited} />;
    case 'Card':
      return <CardProps />;
    case 'CodeEditor':
      return <CodeEditorProps component={component} onEdited={onEdited} />;
    default:
      return (
        <span className="text-[9px]" style={{ color: 'var(--fg-muted)' }}>
          no editable properties
        </span>
      );
  }
}

/* ------------------------------------------------------------------ */
/*  Text props                                                         */
/* ------------------------------------------------------------------ */

function TextProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const textVal = extractLiteral(component.props.text) ?? '';
  const usageHint = (component.props.usageHint as string) ?? 'body';

  return (
    <>
      <PropLabel label="text" />
      <PropTextField
        key={`text-${component.id}`}
        value={textVal}
        onChange={(v) => {
          component.props.text = { literalString: v };
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="usageHint" />
      <PropDropdown
        value={usageHint}
        options={['h1', 'h2', 'h3', 'h4', 'h5', 'body', 'caption', 'label']}
        onChange={(v) => {
          component.props.usageHint = v;
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Button props                                                       */
/* ------------------------------------------------------------------ */

function ButtonProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const primary = (component.props.primary as boolean) ?? false;
  const actionRaw = component.props.action;
  const actionName =
    actionRaw && typeof actionRaw === 'object'
      ? (actionRaw.name as string) ?? ''
      : typeof actionRaw === 'string'
        ? actionRaw
        : '';

  return (
    <>
      <PropLabel label="primary" />
      <PropToggle
        value={primary}
        onChange={(v) => {
          component.props.primary = v;
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="action name" />
      <PropTextField
        key={`btn-action-${component.id}`}
        value={actionName}
        onChange={(v) => {
          if (component.props.action && typeof component.props.action === 'object') {
            component.props.action.name = v;
          } else {
            component.props.action = { name: v };
          }
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Image props                                                        */
/* ------------------------------------------------------------------ */

function ImageProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const url = extractLiteral(component.props.url) ?? '';

  return (
    <>
      <PropLabel label="url" />
      <PropTextField
        key={`img-url-${component.id}`}
        value={url}
        onChange={(v) => {
          component.props.url = { literalString: v };
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Icon props                                                         */
/* ------------------------------------------------------------------ */

function IconProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const name = extractLiteral(component.props.name) ?? 'star';

  return (
    <>
      <PropLabel label="name" />
      <PropTextField
        key={`icon-name-${component.id}`}
        value={name}
        onChange={(v) => {
          component.props.name = { literalString: v };
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  TextField props                                                    */
/* ------------------------------------------------------------------ */

function TextFieldProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const label = extractLiteral(component.props.label) ?? '';
  const placeholder = (component.props.placeholder as string) ?? '';
  const type = (component.props.textFieldType as string) ?? 'shortText';

  return (
    <>
      <PropLabel label="label" />
      <PropTextField
        key={`tf-label-${component.id}`}
        value={label}
        onChange={(v) => {
          component.props.label = { literalString: v };
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="placeholder" />
      <PropTextField
        key={`tf-ph-${component.id}`}
        value={placeholder}
        onChange={(v) => {
          component.props.placeholder = v;
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="type" />
      <PropDropdown
        value={type}
        options={['shortText', 'longText', 'number', 'date', 'obscured']}
        onChange={(v) => {
          component.props.textFieldType = v;
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  CheckBox / Toggle label props                                      */
/* ------------------------------------------------------------------ */

function LabelProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const label = extractLiteral(component.props.label) ?? '';

  return (
    <>
      <PropLabel label="label" />
      <PropTextField
        key={`lbl-${component.id}`}
        value={label}
        onChange={(v) => {
          component.props.label = { literalString: v };
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Slider props                                                       */
/* ------------------------------------------------------------------ */

function SliderProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const min = (component.props.min as number) ?? 0;
  const max = (component.props.max as number) ?? 100;

  return (
    <>
      <PropLabel label="min" />
      <PropTextField
        key={`sl-min-${component.id}`}
        value={String(min)}
        onChange={(v) => {
          component.props.min = parseFloat(v) || 0;
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="max" />
      <PropTextField
        key={`sl-max-${component.id}`}
        value={String(max)}
        onChange={(v) => {
          component.props.max = parseFloat(v) || 100;
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Progress props                                                     */
/* ------------------------------------------------------------------ */

function ProgressProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const value = (component.props.value as number) ?? 0.5;

  return (
    <>
      <PropLabel label="value (0-1)" />
      <input
        type="range"
        min={0}
        max={1}
        step={0.01}
        value={Math.max(0, Math.min(1, value))}
        onChange={(e) => {
          component.props.value = parseFloat(
            parseFloat(e.target.value).toFixed(2),
          );
          onEdited();
        }}
        className="w-full accent-[var(--accent-primary)]"
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Spacer props                                                       */
/* ------------------------------------------------------------------ */

function SpacerProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const height = (component.props.height as number) ?? 16;

  return (
    <>
      <PropLabel label="height" />
      <PropTextField
        key={`sp-h-${component.id}`}
        value={String(height)}
        onChange={(v) => {
          component.props.height = parseFloat(v) || 16;
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Divider props                                                      */
/* ------------------------------------------------------------------ */

function DividerProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const axis = (component.props.axis as string) ?? 'horizontal';

  return (
    <>
      <PropLabel label="axis" />
      <PropDropdown
        value={axis}
        options={['horizontal', 'vertical']}
        onChange={(v) => {
          component.props.axis = v;
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Column / Row props                                                 */
/* ------------------------------------------------------------------ */

function LayoutProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const distribution =
    (component.props.distribution as string) ?? 'start';
  const alignment = (component.props.alignment as string) ?? 'start';

  return (
    <>
      <PropLabel label="distribution" />
      <PropDropdown
        value={distribution}
        options={[
          'start',
          'center',
          'end',
          'spaceBetween',
          'spaceAround',
          'spaceEvenly',
        ]}
        onChange={(v) => {
          component.props.distribution = v;
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="alignment" />
      <PropDropdown
        value={alignment}
        options={['start', 'center', 'end', 'stretch']}
        onChange={(v) => {
          component.props.alignment = v;
          onEdited();
        }}
      />
    </>
  );
}

/* ------------------------------------------------------------------ */
/*  Card props                                                         */
/* ------------------------------------------------------------------ */

function CardProps() {
  return (
    <span className="text-[9px]" style={{ color: 'var(--fg-muted)' }}>
      children are managed via the canvas
    </span>
  );
}

/* ------------------------------------------------------------------ */
/*  CodeEditor props                                                   */
/* ------------------------------------------------------------------ */

function CodeEditorProps({
  component,
  onEdited,
}: {
  component: A2UIComponent;
  onEdited: () => void;
}) {
  const lang = extractLiteral(component.props.language) ?? 'typescript';
  const editable = component.props.editable === true;
  const lineNumbers = component.props.lineNumbers !== false;

  return (
    <>
      <PropLabel label="language" />
      <PropTextField
        key={`ce-lang-${component.id}`}
        value={lang}
        onChange={(v) => {
          component.props.language = { literalString: v };
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="editable" />
      <PropToggle
        value={editable}
        onChange={(v) => {
          component.props.editable = v;
          onEdited();
        }}
      />
      <div className="h-1.5" />
      <PropLabel label="lineNumbers" />
      <PropToggle
        value={lineNumbers}
        onChange={(v) => {
          component.props.lineNumbers = v;
          onEdited();
        }}
      />
    </>
  );
}

/* ================================================================== */
/*  Generic property editor widgets                                    */
/* ================================================================== */

function PropLabel({ label }: { label: string }) {
  return (
    <div
      className="mb-0.5 text-[9px] tracking-tight"
      style={{ color: 'var(--fg-muted)' }}
    >
      {label}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  PropTextField — controlled text input with stable lifecycle        */
/* ------------------------------------------------------------------ */

function PropTextField({
  value: externalValue,
  onChange,
}: {
  value: string;
  onChange: (v: string) => void;
}) {
  const [localValue, setLocalValue] = useState(externalValue);
  const prevExternalRef = useRef(externalValue);

  // Sync from external when it changes and differs from local
  useEffect(() => {
    if (externalValue !== prevExternalRef.current) {
      setLocalValue(externalValue);
      prevExternalRef.current = externalValue;
    }
  }, [externalValue]);

  return (
    <input
      type="text"
      value={localValue}
      onChange={(e) => {
        setLocalValue(e.target.value);
        prevExternalRef.current = e.target.value;
        onChange(e.target.value);
      }}
      className="h-7 w-full rounded-sm px-1.5 text-[10px] outline-none"
      style={{
        background: 'transparent',
        border: '0.5px solid var(--border)',
        color: 'var(--fg-primary)',
        fontFamily: 'inherit',
      }}
    />
  );
}

/* ------------------------------------------------------------------ */
/*  PropDropdown                                                       */
/* ------------------------------------------------------------------ */

function PropDropdown({
  value,
  options,
  onChange,
}: {
  value: string;
  options: string[];
  onChange: (v: string) => void;
}) {
  // Ensure value is in options
  const safeValue = options.includes(value) ? value : options[0];

  return (
    <select
      value={safeValue}
      onChange={(e) => onChange(e.target.value)}
      className="h-7 w-full cursor-pointer rounded-sm px-1.5 text-[10px] outline-none"
      style={{
        background: 'var(--surface-base)',
        border: '0.5px solid var(--border)',
        color: 'var(--fg-primary)',
        fontFamily: 'inherit',
      }}
    >
      {options.map((o) => (
        <option key={o} value={o}>
          {o}
        </option>
      ))}
    </select>
  );
}

/* ------------------------------------------------------------------ */
/*  PropToggle                                                         */
/* ------------------------------------------------------------------ */

function PropToggle({
  value,
  onChange,
}: {
  value: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <button
      onClick={() => onChange(!value)}
      className="relative h-5 w-9 rounded-full transition-colors"
      style={{
        background: value ? 'var(--accent-primary)' : 'var(--fg-disabled)',
        cursor: 'pointer',
      }}
    >
      <span
        className="absolute top-0.5 h-4 w-4 rounded-full bg-white transition-[left]"
        style={{ left: value ? 18 : 2 }}
      />
    </button>
  );
}

/* ================================================================== */
/*  Internal helpers                                                   */
/* ================================================================== */

/** Extract a string literal from a bound value prop. */
function extractLiteral(prop: any): string | null {
  if (typeof prop === 'string') return prop;
  if (prop && typeof prop === 'object') {
    const lit = prop.literalString ?? prop.value;
    return lit != null ? String(lit) : null;
  }
  return prop != null ? String(prop) : null;
}
