/**
 * Canvas Zustand store — replaces A2UISurfacesNotifier, CanvasModeNotifier, DrawIOThemeNotifier
 */

import { create } from 'zustand';
import {
  type A2UISurface,
  type A2UIComponent,
  createSurface,
  mergeContents,
  parseA2UIComponent,
  parseSurfaceUpdate,
  parseBeginRendering,
  parseDataModelUpdate,
  parseDeleteSurface,
} from '@/lib/protocol/a2ui-models';

/* ------------------------------------------------------------------ */
/*  Canvas mode                                                        */
/* ------------------------------------------------------------------ */

export type CanvasMode = 'a2ui' | 'drawio' | 'browser';
export type DrawIOTheme = 'light' | 'dark';

function loadCanvasMode(): CanvasMode {
  try {
    const raw = localStorage.getItem('trinity_canvas_mode_v4');
    if (raw === 'a2ui' || raw === 'drawio' || raw === 'browser') return raw;
  } catch { /* ignore */ }
  return 'drawio';
}

function loadDrawIOTheme(): DrawIOTheme {
  try {
    const raw = localStorage.getItem('trinity_drawio_theme');
    if (raw === 'light' || raw === 'dark') return raw;
  } catch { /* ignore */ }
  return 'dark';
}

/* ------------------------------------------------------------------ */
/*  Undo / redo                                                        */
/* ------------------------------------------------------------------ */

interface UndoRedoState {
  undoStack: string[];
  redoStack: string[];
}

const MAX_UNDO = 50;

/* ------------------------------------------------------------------ */
/*  Store                                                              */
/* ------------------------------------------------------------------ */

interface CanvasStore {
  // A2UI surfaces
  surfaces: Record<string, A2UISurface>;
  editMode: boolean;
  selectedComponentId: string | null;
  selectedSurfaceId: string | null;
  undoRedo: UndoRedoState;

  // Canvas mode
  canvasMode: CanvasMode;
  drawioTheme: DrawIOTheme;

  // Actions
  setCanvasMode: (mode: CanvasMode) => void;
  setDrawIOTheme: (theme: DrawIOTheme) => void;
  toggleCanvasMode: () => void;
  setEditMode: (on: boolean) => void;
  selectComponent: (surfaceId: string | null, componentId: string | null) => void;
  pushUndoSnapshot: () => void;
  undo: () => void;
  redo: () => void;
  updateSurface: (surfaceId: string, surface: A2UISurface) => void;

  // A2UI event processing
  processA2UIEvent: (payload: Record<string, any>) => void;
  processA2UIJsonl: (lines: string) => void;
  clearSurfaces: () => void;
}

export const useCanvasStore = create<CanvasStore>((set, get) => ({
  surfaces: {},
  editMode: false,
  selectedComponentId: null,
  selectedSurfaceId: null,
  undoRedo: { undoStack: [], redoStack: [] },

  canvasMode: typeof window !== 'undefined' ? loadCanvasMode() : 'drawio',
  drawioTheme: typeof window !== 'undefined' ? loadDrawIOTheme() : 'dark',

  setCanvasMode: (mode) => {
    localStorage.setItem('trinity_canvas_mode_v4', mode);
    set({ canvasMode: mode });
  },

  setDrawIOTheme: (theme) => {
    localStorage.setItem('trinity_drawio_theme', theme);
    set({ drawioTheme: theme });
  },

  toggleCanvasMode: () => {
    const modes: CanvasMode[] = ['drawio', 'browser', 'a2ui'];
    const current = get().canvasMode;
    const next = modes[(modes.indexOf(current) + 1) % modes.length];
    get().setCanvasMode(next);
  },

  setEditMode: (on) => set({ editMode: on }),

  selectComponent: (surfaceId, componentId) =>
    set({ selectedSurfaceId: surfaceId, selectedComponentId: componentId }),

  pushUndoSnapshot: () => {
    const { surfaces, undoRedo } = get();
    const snapshot = JSON.stringify(surfaces);
    const stack = [...undoRedo.undoStack, snapshot];
    if (stack.length > MAX_UNDO) stack.shift();
    set({ undoRedo: { undoStack: stack, redoStack: [] } });
  },

  undo: () => {
    const { surfaces, undoRedo } = get();
    if (undoRedo.undoStack.length === 0) return;
    const stack = [...undoRedo.undoStack];
    const snapshot = stack.pop()!;
    const redoStack = [...undoRedo.redoStack, JSON.stringify(surfaces)];
    set({
      surfaces: JSON.parse(snapshot),
      undoRedo: { undoStack: stack, redoStack },
    });
  },

  redo: () => {
    const { surfaces, undoRedo } = get();
    if (undoRedo.redoStack.length === 0) return;
    const stack = [...undoRedo.redoStack];
    const snapshot = stack.pop()!;
    const undoStack = [...undoRedo.undoStack, JSON.stringify(surfaces)];
    set({
      surfaces: JSON.parse(snapshot),
      undoRedo: { undoStack, redoStack: stack },
    });
  },

  updateSurface: (surfaceId, surface) => {
    set((s) => ({ surfaces: { ...s.surfaces, [surfaceId]: surface } }));
  },

  processA2UIEvent: (payload) => {
    const state = get();
    const newSurfaces = { ...state.surfaces };

    // surfaceUpdate
    const su = parseSurfaceUpdate(payload);
    if (su) {
      const sid = su.surfaceId;
      if (!newSurfaces[sid]) newSurfaces[sid] = createSurface(sid);
      const surface = { ...newSurfaces[sid], components: { ...newSurfaces[sid].components } };
      for (const comp of su.components) {
        surface.components[comp.id] = comp;
      }
      newSurfaces[sid] = surface;
      set({ surfaces: newSurfaces });
      return;
    }

    // beginRendering
    const br = parseBeginRendering(payload);
    if (br) {
      const sid = br.surfaceId;
      if (!newSurfaces[sid]) newSurfaces[sid] = createSurface(sid);
      newSurfaces[sid] = { ...newSurfaces[sid], rootId: br.root, catalogId: br.catalogId };
      set({ surfaces: newSurfaces });
      return;
    }

    // dataModelUpdate
    const dm = parseDataModelUpdate(payload);
    if (dm) {
      const sid = dm.surfaceId;
      if (!newSurfaces[sid]) newSurfaces[sid] = createSurface(sid);
      const surface = { ...newSurfaces[sid], dataModel: { ...newSurfaces[sid].dataModel } };
      mergeContents(surface, dm.path, dm.contents);
      newSurfaces[sid] = surface;
      set({ surfaces: newSurfaces });
      return;
    }

    // deleteSurface
    const ds = parseDeleteSurface(payload);
    if (ds) {
      delete newSurfaces[ds.surfaceId];
      set({ surfaces: newSurfaces });
      return;
    }
  },

  processA2UIJsonl: (lines) => {
    for (const line of lines.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        const json = JSON.parse(trimmed);
        get().processA2UIEvent(json);
      } catch {
        // Skip invalid lines
      }
    }
  },

  clearSurfaces: () => set({ surfaces: {}, selectedComponentId: null, selectedSurfaceId: null }),
}));
