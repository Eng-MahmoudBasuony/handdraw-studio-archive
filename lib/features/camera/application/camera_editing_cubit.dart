import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

final class CameraEditingCubit extends Cubit<CameraEditingState> {
  CameraEditingCubit() : super(CameraEditingState());
  void select(
    CameraShotId id, {
    bool toggle = false,
    bool range = false,
    List<CameraShot> shots = const [],
  }) {
    var ids = <CameraShotId>{id};
    if (toggle) {
      ids = {...state.selectedShotIds};
      ids.contains(id) ? ids.remove(id) : ids.add(id);
    } else if (range && state.primaryShotId != null) {
      final a = shots.indexWhere((s) => s.id == state.primaryShotId),
          b = shots.indexWhere((s) => s.id == id);
      if (a >= 0 && b >= 0) {
        ids = {
          for (final shot in shots.sublist(a < b ? a : b, (a > b ? a : b) + 1))
            shot.id,
        };
      }
    }
    emit(
      state.copyWith(
        selectedShotIds: ids,
        primaryShotId: id,
        selectedKeyframeId: toggle || range ? state.selectedKeyframeId : null,
      ),
    );
  }

  void clear() => emit(
    CameraEditingState(
      collapsed: state.collapsed,
      canvasMode: state.canvasMode,
      frameVisibility: state.frameVisibility,
      compositionGrid: state.compositionGrid,
      pinnedKeyframeIds: state.pinnedKeyframeIds,
      followPlayhead: state.followPlayhead,
      canvasViewportOffset: state.canvasViewportOffset,
      editorView: state.editorView,
      savedEditorView: state.savedEditorView,
      shotDefaults: state.shotDefaults,
    ),
  );
  void selectKeyframe(
    CameraShotId shotId,
    CameraKeyframeId keyframeId, {
    bool preserveShotSelection = false,
  }) => emit(
    state.copyWith(
      selectedShotIds: preserveShotSelection ? state.selectedShotIds : {shotId},
      primaryShotId: shotId,
      selectedKeyframeId: keyframeId,
    ),
  );
  void setCanvasMode(CameraCanvasMode mode) =>
      emit(state.copyWith(canvasMode: mode));
  void panCanvasViewport(Offset delta) => emit(
    state.copyWith(canvasViewportOffset: state.canvasViewportOffset + delta),
  );
  void resetCanvasViewport() =>
      emit(state.copyWith(canvasViewportOffset: Offset.zero));
  void setEditorView(CameraView view) => emit(state.copyWith(editorView: view));
  void restoreEditorView(CameraView view) => emit(
    state.copyWith(
      canvasMode: CameraCanvasMode.editCamera,
      editorView: view,
      savedEditorView: view,
    ),
  );
  void markEditorViewSaved() =>
      emit(state.copyWith(savedEditorView: state.editorView));
  void setFrameVisibility(CameraFrameVisibility visibility) =>
      emit(state.copyWith(frameVisibility: visibility));
  void setCompositionGrid(CameraCompositionGrid grid) =>
      emit(state.copyWith(compositionGrid: grid));
  void togglePinned(CameraKeyframeId id) {
    final pinned = {...state.pinnedKeyframeIds};
    pinned.contains(id) ? pinned.remove(id) : pinned.add(id);
    emit(state.copyWith(pinnedKeyframeIds: pinned));
  }

  void setFollowPlayhead(bool value) =>
      emit(state.copyWith(followPlayhead: value));
  void setShotDefaults(CameraShotDefaults defaults) =>
      emit(state.copyWith(shotDefaults: defaults));
  void toggleCollapsed() => emit(
    state.copyWith(
      collapsed: !state.collapsed,
      transientEdit: null,
      transientEdits: const {},
      interactionMode: CameraInteractionMode.idle,
    ),
  );
  void begin(CameraShot shot, CameraInteractionMode mode) => emit(
    state.copyWith(
      interactionMode: mode,
      transientEdit: CameraTransientEdit(
        originalStart: shot.startTime,
        originalDuration: shot.duration,
        previewStart: shot.startTime,
        previewDuration: shot.duration,
      ),
      transientEdits: {
        shot.id: CameraTransientEdit(
          originalStart: shot.startTime,
          originalDuration: shot.duration,
          previewStart: shot.startTime,
          previewDuration: shot.duration,
        ),
      },
    ),
  );
  void beginMoveGroup(Iterable<CameraShot> shots) {
    final edits = {
      for (final shot in shots)
        shot.id: CameraTransientEdit(
          originalStart: shot.startTime,
          originalDuration: shot.duration,
          previewStart: shot.startTime,
          previewDuration: shot.duration,
        ),
    };
    final primary = state.primaryShotId;
    emit(
      state.copyWith(
        interactionMode: CameraInteractionMode.moving,
        transientEdit: primary == null ? null : edits[primary],
        transientEdits: edits,
      ),
    );
  }

  void update(CameraTransientEdit edit) => emit(
    state.copyWith(
      transientEdit: edit,
      transientEdits: state.primaryShotId == null
          ? state.transientEdits
          : {...state.transientEdits, state.primaryShotId!: edit},
    ),
  );
  void updateGroup(Map<CameraShotId, CameraTransientEdit> edits) => emit(
    state.copyWith(
      transientEdits: edits,
      transientEdit: state.primaryShotId == null
          ? null
          : edits[state.primaryShotId],
    ),
  );
  void cancelInteraction() => emit(
    state.copyWith(
      interactionMode: CameraInteractionMode.idle,
      transientEdit: null,
      transientEdits: const {},
    ),
  );
  void reconcile(
    Iterable<CameraShotId> existing, {
    Iterable<CameraKeyframeId> keyframes = const [],
  }) {
    final valid = state.selectedShotIds.intersection(existing.toSet());
    final validKeyframes = keyframes.toSet();
    emit(
      state.copyWith(
        selectedShotIds: valid,
        primaryShotId: valid.contains(state.primaryShotId)
            ? state.primaryShotId
            : null,
        selectedKeyframeId: validKeyframes.contains(state.selectedKeyframeId)
            ? state.selectedKeyframeId
            : null,
        pinnedKeyframeIds: state.pinnedKeyframeIds.intersection(validKeyframes),
        interactionMode: CameraInteractionMode.idle,
        transientEdit: null,
        transientEdits: const {},
      ),
    );
  }
}
