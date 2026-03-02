import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/a2ui_models.dart';
import '../../models/ws_frame.dart';
import '../../core/providers.dart';
import 'a2ui_editor.dart';

class A2UIState {
  final Map<String, A2UISurface> surfaces;
  final bool editMode;
  final String? selectedComponentId;
  final String? selectedSurfaceId;
  final UndoRedoManager undoRedo;

  const A2UIState({
    this.surfaces = const {},
    this.editMode = false,
    this.selectedComponentId,
    this.selectedSurfaceId,
    required this.undoRedo,
  });

  A2UIState copyWith({
    Map<String, A2UISurface>? surfaces,
    bool? editMode,
    String? selectedComponentId,
    String? selectedSurfaceId,
    UndoRedoManager? undoRedo,
  }) {
    return A2UIState(
      surfaces: surfaces ?? this.surfaces,
      editMode: editMode ?? this.editMode,
      selectedComponentId: selectedComponentId ?? this.selectedComponentId,
      selectedSurfaceId: selectedSurfaceId ?? this.selectedSurfaceId,
      undoRedo: undoRedo ?? this.undoRedo,
    );
  }
}

class A2UISurfacesNotifier extends StateNotifier<A2UIState> {
  final Ref _ref;
  StreamSubscription<WsEvent>? _chatSub;

  A2UISurfacesNotifier(this._ref)
      : super(A2UIState(undoRedo: UndoRedoManager())) {
    _initWebSocketSubscription();
  }

  void _initWebSocketSubscription() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = _ref.read(gatewayClientProvider);
      _chatSub = client.events
          .where((e) => e.event == 'a2ui' || e.event == 'canvas')
          .listen(_handleEvent);
    });
  }

  void _handleEvent(WsEvent event) {
    try {
      _handleA2UIEvent(event);
    } catch (e, st) {
      debugPrint('[A2UI] error handling event: $e\n$st');
    }
  }

  void _handleA2UIEvent(WsEvent event) {
    final payload = event.payload;
    bool needsRebuild = false;
    final surfaces = Map<String, A2UISurface>.from(state.surfaces);

    if (payload.containsKey('surfaceUpdate')) {
      final raw = payload['surfaceUpdate'];
      if (raw is Map<String, dynamic>) {
        try {
          final update = SurfaceUpdate.fromJson(raw);
          final surface = surfaces.putIfAbsent(
            update.surfaceId,
            () => A2UISurface(surfaceId: update.surfaceId),
          );
          for (final comp in update.components) {
            surface.components[comp.id] = comp;
          }
          needsRebuild = true;
        } catch (e) {
          debugPrint('[A2UI] bad surfaceUpdate: $e');
        }
      }
    }

    if (payload.containsKey('beginRendering')) {
      final raw = payload['beginRendering'];
      if (raw is Map<String, dynamic>) {
        try {
          final begin = BeginRendering.fromJson(raw);
          final surface = surfaces.putIfAbsent(
            begin.surfaceId,
            () => A2UISurface(surfaceId: begin.surfaceId),
          );
          surface.rootId = begin.root;
          if (begin.catalogId != null) {
            surface.catalogId = begin.catalogId;
          }
          needsRebuild = true;
        } catch (e) {
          debugPrint('[A2UI] bad beginRendering: $e');
        }
      }
    }

    if (payload.containsKey('dataModelUpdate')) {
      final raw = payload['dataModelUpdate'];
      if (raw is Map<String, dynamic>) {
        try {
          final update = DataModelUpdate.fromJson(raw);
          final surface = surfaces.putIfAbsent(
            update.surfaceId,
            () => A2UISurface(surfaceId: update.surfaceId),
          );
          surface.mergeContents(update.path, update.contents);
          needsRebuild = true;
        } catch (e) {
          debugPrint('[A2UI] bad dataModelUpdate: $e');
        }
      }
    }

    if (payload.containsKey('deleteSurface')) {
      final raw = payload['deleteSurface'];
      if (raw is Map<String, dynamic>) {
        try {
          final del = DeleteSurface.fromJson(raw);
          if (surfaces.remove(del.surfaceId) != null) {
            needsRebuild = true;
          }
        } catch (e) {
          debugPrint('[A2UI] bad deleteSurface: $e');
        }
      }
    }

    if (needsRebuild) {
      state = state.copyWith(surfaces: surfaces);
    }
  }

  void setEditMode(bool value) {
    state = state.copyWith(editMode: value);
  }

  void selectComponent(String? componentId, String? surfaceId) {
    state = state.copyWith(
      selectedComponentId: componentId,
      selectedSurfaceId: surfaceId,
    );
  }

  void pushUndoSnapshot() {
    state.undoRedo.pushSnapshot(state.surfaces);
  }

  bool undo() {
    return state.undoRedo.undo(state.surfaces);
  }

  bool redo() {
    return state.undoRedo.redo(state.surfaces);
  }

  void updateSurface(String surfaceId, void Function(A2UISurface) update) {
    final surfaces = Map<String, A2UISurface>.from(state.surfaces);
    final surface = surfaces[surfaceId];
    if (surface != null) {
      update(surface);
      state = state.copyWith(surfaces: surfaces);
    }
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    super.dispose();
  }
}

final a2uiSurfacesProvider =
    StateNotifierProvider<A2UISurfacesNotifier, A2UIState>((ref) {
  return A2UISurfacesNotifier(ref);
});
