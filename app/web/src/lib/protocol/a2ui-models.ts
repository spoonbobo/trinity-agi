/**
 * A2UI v0.8 data models — 1:1 port of models/a2ui_models.dart
 *
 * Agent-driven UI surfaces with data-bound components.
 */

/* ------------------------------------------------------------------ */
/*  A2UIComponent                                                      */
/* ------------------------------------------------------------------ */

export interface A2UIComponent {
  id: string;
  type: string;
  props: Record<string, any>;
  weight?: number;
}

export function parseA2UIComponent(json: Record<string, any>): A2UIComponent {
  const id = json.id ?? '';
  const weight = json.weight;

  // A2UI v0.8 shape: { id, component: { TypeName: { ...props } } }
  if (json.component && typeof json.component === 'object') {
    const keys = Object.keys(json.component);
    if (keys.length > 0) {
      const typeName = keys[0];
      const props = json.component[typeName] ?? {};
      return { id, type: typeName, props, weight };
    }
  }

  // Legacy fallback: { id, type: "button", ... }
  if (typeof json.type === 'string') {
    const legacyType = json.type;
    let type = 'Unknown';
    const props: Record<string, any> = {};

    if (legacyType === 'button') {
      type = 'Button';
      props.primary = json.primary;
      props.text = json.text ?? json.label;
      props.action = json.action;
    } else if (legacyType === 'text') {
      type = 'Text';
      props.text = json.text;
    } else {
      type = 'Unknown';
    }

    return { id, type, props, weight };
  }

  return { id, type: 'Unknown', props: {}, weight };
}

/* ------------------------------------------------------------------ */
/*  A2UISurface                                                        */
/* ------------------------------------------------------------------ */

export interface A2UISurface {
  surfaceId: string;
  components: Record<string, A2UIComponent>;
  rootId?: string;
  catalogId?: string;
  dataModel: Record<string, any>;
}

export function createSurface(surfaceId: string): A2UISurface {
  return {
    surfaceId,
    components: {},
    dataModel: {},
  };
}

/** Navigate the data model by slash-delimited path */
export function getPath(surface: A2UISurface, path: string): any {
  const parts = path.split('/').filter(Boolean);
  let current: any = surface.dataModel;
  for (const part of parts) {
    if (current == null || typeof current !== 'object') return undefined;
    current = current[part];
  }
  return current;
}

/** Set a value in the data model by slash-delimited path, creating intermediates */
export function setPath(surface: A2UISurface, path: string, value: any): void {
  const parts = path.split('/').filter(Boolean);
  if (parts.length === 0) return;
  let current: any = surface.dataModel;
  for (let i = 0; i < parts.length - 1; i++) {
    if (current[parts[i]] == null || typeof current[parts[i]] !== 'object') {
      current[parts[i]] = {};
    }
    current = current[parts[i]];
  }
  current[parts[parts.length - 1]] = value;
}

/** Merge adjacency-list contents into the data model */
export function mergeContents(
  surface: A2UISurface,
  path: string | null | undefined,
  contents: any[],
): void {
  const target =
    path && path.trim()
      ? (() => {
          const parts = path.split('/').filter(Boolean);
          let current: any = surface.dataModel;
          for (const part of parts) {
            if (current[part] == null || typeof current[part] !== 'object') {
              current[part] = {};
            }
            current = current[part];
          }
          return current;
        })()
      : surface.dataModel;

  parseContents(contents, target);
}

function parseContents(contents: any[], target: Record<string, any>): void {
  for (const entry of contents) {
    const key = entry.key;
    if (!key) continue;

    if (entry.valueString != null) target[key] = entry.valueString;
    else if (entry.valueNumber != null) target[key] = entry.valueNumber;
    else if (entry.valueBoolean != null) target[key] = entry.valueBoolean;
    else if (entry.valueArray != null) target[key] = entry.valueArray;
    else if (entry.valueMap != null) {
      if (target[key] == null || typeof target[key] !== 'object') {
        target[key] = {};
      }
      parseContents(entry.valueMap, target[key]);
    }
  }
}

/* ------------------------------------------------------------------ */
/*  Protocol message types                                             */
/* ------------------------------------------------------------------ */

export interface SurfaceUpdate {
  surfaceId: string;
  components: A2UIComponent[];
}

export interface BeginRendering {
  surfaceId: string;
  root: string;
  catalogId?: string;
}

export interface DataModelUpdate {
  surfaceId: string;
  path?: string;
  contents: any[];
}

export interface DeleteSurface {
  surfaceId: string;
}

export interface UserAction {
  name: string;
  surfaceId: string;
  sourceComponentId: string;
  timestamp: string;
  context: Record<string, any>;
}

export function encodeUserAction(action: UserAction): Record<string, any> {
  return { userAction: action };
}

/* ------------------------------------------------------------------ */
/*  BoundValue resolution                                              */
/* ------------------------------------------------------------------ */

/**
 * Resolve a bound value prop against the surface's data model.
 * Handles: primitives, {path}, {literalString/Number/Boolean/Array}, {path + literal init}.
 */
export function resolveBoundValue(prop: any, surface: A2UISurface): any {
  if (prop == null) return undefined;

  // Primitives
  if (typeof prop === 'string' || typeof prop === 'number' || typeof prop === 'boolean') {
    return prop;
  }

  if (typeof prop === 'object' && !Array.isArray(prop)) {
    // Path binding
    if (prop.path) {
      const val = getPath(surface, prop.path);
      // Initialization shorthand: if both path and literal, write literal on first access
      if (val === undefined) {
        if (prop.literalString != null) {
          setPath(surface, prop.path, prop.literalString);
          return prop.literalString;
        }
        if (prop.literalNumber != null) {
          setPath(surface, prop.path, prop.literalNumber);
          return prop.literalNumber;
        }
        if (prop.literalBoolean != null) {
          setPath(surface, prop.path, prop.literalBoolean);
          return prop.literalBoolean;
        }
      }
      return val;
    }

    // Static literals
    if (prop.literalString != null) return prop.literalString;
    if (prop.literalNumber != null) return prop.literalNumber;
    if (prop.literalBoolean != null) return prop.literalBoolean;
    if (prop.literalArray != null) return prop.literalArray;

    // Legacy fallback
    if (prop.value != null) return prop.value;
  }

  return prop;
}

export function resolveBoundString(prop: any, surface: A2UISurface): string {
  const val = resolveBoundValue(prop, surface);
  return val != null ? String(val) : '';
}

export function resolveBoundNum(prop: any, surface: A2UISurface): number | undefined {
  const val = resolveBoundValue(prop, surface);
  if (typeof val === 'number') return val;
  if (typeof val === 'string') {
    const n = parseFloat(val);
    return isNaN(n) ? undefined : n;
  }
  return undefined;
}

export function resolveBoundBool(prop: any, surface: A2UISurface): boolean {
  const val = resolveBoundValue(prop, surface);
  if (typeof val === 'boolean') return val;
  if (typeof val === 'string') return val === 'true';
  return false;
}

/* ------------------------------------------------------------------ */
/*  JSONL parser helpers                                               */
/* ------------------------------------------------------------------ */

export function parseSurfaceUpdate(json: Record<string, any>): SurfaceUpdate | null {
  const su = json.surfaceUpdate;
  if (!su) return null;
  return {
    surfaceId: su.surfaceId ?? '',
    components: (su.components ?? []).map(parseA2UIComponent),
  };
}

export function parseBeginRendering(json: Record<string, any>): BeginRendering | null {
  const br = json.beginRendering;
  if (!br) return null;
  return {
    surfaceId: br.surfaceId ?? '',
    root: br.root ?? '',
    catalogId: br.catalogId,
  };
}

export function parseDataModelUpdate(json: Record<string, any>): DataModelUpdate | null {
  const dm = json.dataModelUpdate;
  if (!dm) return null;
  return {
    surfaceId: dm.surfaceId ?? '',
    path: dm.path,
    contents: dm.contents ?? [],
  };
}

export function parseDeleteSurface(json: Record<string, any>): DeleteSurface | null {
  const ds = json.deleteSurface;
  if (!ds) return null;
  return { surfaceId: ds.surfaceId ?? '' };
}
