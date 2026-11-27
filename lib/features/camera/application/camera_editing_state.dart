import 'dart:ui';

import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/simple_camera_view_adapter.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum CameraInteractionMode { idle, moving, trimmingStart, trimmingEnd }

enum CameraCanvasMode { browse, editCamera, previewCamera }

enum CameraFrameVisibility { selectedOnly, adjacent, allPinned }

enum CameraCompositionGrid { quarters, ruleOfThirds }

final class CameraShotDefaults {
  const CameraShotDefaults({
    this.movement = SimpleCameraMovement.ease,
    this.movementDuration = const Duration(milliseconds: 600),
    this.holdDuration = const Duration(milliseconds: 1400),
  });

  final SimpleCameraMovement movement;
  final Duration movementDuration;
  final Duration holdDuration;
}

final class CameraTransientEdit {
  const CameraTransientEdit({
    required this.originalStart,
    required this.originalDuration,
    required this.previewStart,
    required this.previewDuration,
    this.invalid = false,
    this.snapGuide,
  });
  final TimelineTime originalStart, previewStart;
  final TimelineDuration originalDuration, previewDuration;
  final bool invalid;
  final TimelineTime? snapGuide;
  CameraTransientEdit copyWith({
    TimelineTime? previewStart,
    TimelineDuration? previewDuration,
    bool? invalid,
    Object? snapGuide = _unset,
  }) => CameraTransientEdit(
    originalStart: originalStart,
    originalDuration: originalDuration,
    previewStart: previewStart ?? this.previewStart,
    previewDuration: previewDuration ?? this.previewDuration,
    invalid: invalid ?? this.invalid,
    snapGuide: identical(snapGuide, _unset)
        ? this.snapGuide
        : snapGuide as TimelineTime?,
  );
}

final class CameraEditingState {
  CameraEditingState({
    Set<CameraShotId> selectedShotIds = const {},
    this.primaryShotId,
    this.selectedKeyframeId,
    this.interactionMode = CameraInteractionMode.idle,
    this.transientEdit,
    Map<CameraShotId, CameraTransientEdit> transientEdits = const {},
    this.collapsed = false,
    this.canvasMode = CameraCanvasMode.editCamera,
    this.frameVisibility = CameraFrameVisibility.adjacent,
    this.compositionGrid = CameraCompositionGrid.quarters,
    Set<CameraKeyframeId> pinnedKeyframeIds = const {},
    this.followPlayhead = false,
    this.canvasViewportOffset = Offset.zero,
    this.editorView = const CameraView.identity(),
    this.savedEditorView,
    this.shotDefaults = const CameraShotDefaults(),
  }) : selectedShotIds = Set.unmodifiable(selectedShotIds),
       transientEdits = Map.unmodifiable(transientEdits),
       pinnedKeyframeIds = Set.unmodifiable(pinnedKeyframeIds);
  final Set<CameraShotId> selectedShotIds;
  final CameraShotId? primaryShotId;
  final CameraKeyframeId? selectedKeyframeId;
  final CameraInteractionMode interactionMode;
  final CameraTransientEdit? transientEdit;
  final Map<CameraShotId, CameraTransientEdit> transientEdits;
  final bool collapsed;
  final CameraCanvasMode canvasMode;
  final CameraFrameVisibility frameVisibility;
  final CameraCompositionGrid compositionGrid;
  final Set<CameraKeyframeId> pinnedKeyframeIds;
  final bool followPlayhead;
  final Offset canvasViewportOffset;

  /// View-only state for composing a shot. It is deliberately not part of the
  /// project document, so panning and zooming never create history entries.
  final CameraView editorView;
  final CameraView? savedEditorView;
  final CameraShotDefaults shotDefaults;
  bool get isEditorViewDirty =>
      savedEditorView != null && editorView != savedEditorView;
  bool cameraOutputEnabled({required bool timelineFrameVisible}) =>
      timelineFrameVisible && canvasMode == CameraCanvasMode.previewCamera;
  CameraEditingState copyWith({
    Set<CameraShotId>? selectedShotIds,
    Object? primaryShotId = _unset,
    Object? selectedKeyframeId = _unset,
    CameraInteractionMode? interactionMode,
    Object? transientEdit = _unset,
    Map<CameraShotId, CameraTransientEdit>? transientEdits,
    bool? collapsed,
    CameraCanvasMode? canvasMode,
    CameraFrameVisibility? frameVisibility,
    CameraCompositionGrid? compositionGrid,
    Set<CameraKeyframeId>? pinnedKeyframeIds,
    bool? followPlayhead,
    Offset? canvasViewportOffset,
    CameraView? editorView,
    Object? savedEditorView = _unset,
    CameraShotDefaults? shotDefaults,
  }) => CameraEditingState(
    selectedShotIds: selectedShotIds ?? this.selectedShotIds,
    primaryShotId: identical(primaryShotId, _unset)
        ? this.primaryShotId
        : primaryShotId as CameraShotId?,
    selectedKeyframeId: identical(selectedKeyframeId, _unset)
        ? this.selectedKeyframeId
        : selectedKeyframeId as CameraKeyframeId?,
    interactionMode: interactionMode ?? this.interactionMode,
    transientEdit: identical(transientEdit, _unset)
        ? this.transientEdit
        : transientEdit as CameraTransientEdit?,
    transientEdits: transientEdits ?? this.transientEdits,
    collapsed: collapsed ?? this.collapsed,
    canvasMode: canvasMode ?? this.canvasMode,
    frameVisibility: frameVisibility ?? this.frameVisibility,
    compositionGrid: compositionGrid ?? this.compositionGrid,
    pinnedKeyframeIds: pinnedKeyframeIds ?? this.pinnedKeyframeIds,
    followPlayhead: followPlayhead ?? this.followPlayhead,
    canvasViewportOffset: canvasViewportOffset ?? this.canvasViewportOffset,
    editorView: editorView ?? this.editorView,
    savedEditorView: identical(savedEditorView, _unset)
        ? this.savedEditorView
        : savedEditorView as CameraView?,
    shotDefaults: shotDefaults ?? this.shotDefaults,
  );
}

const _unset = Object();
