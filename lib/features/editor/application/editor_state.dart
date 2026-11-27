import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/models/document_revision.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_factory.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/editor/domain/path_node_editor.dart';
import 'package:handdraw_studio/features/editor/domain/auto_path_result_summary.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_animation_guidance.dart';

enum EditorTool {
  select,
  drawPath,
  revealText,
  sceneGroup,
  maskReveal,
  maskErase,
}

final class EditorSceneDraft {
  EditorSceneDraft({
    required this.id,
    required this.name,
    required Iterable<String> sectionIds,
    this.locked = true,
  }) : sectionIds = List.unmodifiable(sectionIds);

  final String id;
  final String name;
  final List<String> sectionIds;
  final bool locked;

  EditorSceneDraft copyWith({List<String>? sectionIds}) => EditorSceneDraft(
    id: id,
    name: name,
    sectionIds: sectionIds ?? this.sectionIds,
    locked: locked,
  );
}

const _unset = Object();

class EditorState {
  EditorState({
    required this.documentState,
    this.tool = EditorTool.select,
    this.drawingImage,
    this.drawingAnalysisEncoded,
    this.drawingRevealBaseImage,
    this.svgRevealLayers,
    this.artworkAnimationGuidance = ArtworkAnimationGuidance.unknown,
    this.handImage,
    this.activeStroke = const [],
    this.manualRevealWidth,
    this.selectedStrokeIndex,
    this.transientArtworkDestination,
    this.hoveredStrokeIndex,
    this.selectedPathNode,
    this.selectedPathNodes = const {},
    this.maskBrushWidth = 54,
    this.maskFeather = 8,
    this.maskOverlayVisible = true,
    this.maskComparisonBefore = false,
    this.maskClipToLayer = true,
    this.nodeSnapEnabled = false,
    this.selectedTimingSectionKey,
    this.smartSections = const [],
    this.autoPathResult,
    this.selectedSmartSectionId,
    this.selectedTimelineSectionIds = const {},
    this.selectedTimelineSceneId,
    this.sceneDrafts = const [],
    this.suggestionOrderCustomized = false,
    this.collapsedTimelineSceneIds = const {},
    this.isAnalyzingSmartPaths = false,
    this.smartPathProgress,
    this.smartPathAnalysisElapsed = Duration.zero,
    this.isDrawingImporting = false,
    this.handPresets = BuiltInHands.all,
    this.selectedHandPresetId = BuiltInHands.defaultPresetId,
    this.isHandLibraryLoading = false,
    this.isVoiceGuideLoading = false,
    this.isVoiceGuideMissing = false,
    this.canvasRevision = 0,
    this.editingImagePaths = false,
    this.imageAnimationControlsOpen = false,
    this.statusMessage = 'Import a drawing to begin',
  });

  factory EditorState.initial() {
    final duration = TimelineDuration.fromMicroseconds(
      6 * Duration.microsecondsPerSecond,
    );
    final document = const ProjectDocumentFactory()
        .createEmpty(ids: SecureRandomIdGenerator(), duration: duration)
        .copyWith(
          motionConfiguration: ProjectMotionConfiguration(
            drawingDuration: TimelineDuration.fromMicroseconds(4700000),
            startDelay: TimelineDuration.fromMicroseconds(400000),
            endHold: TimelineDuration.fromMicroseconds(900000),
          ),
        );
    return EditorState(documentState: EditorDocumentState(document: document));
  }

  final EditorDocumentState documentState;
  ProjectDocument get document => documentState.document;
  DocumentRevision get documentRevision => documentState.revision;

  final EditorTool tool;
  final ui.Image? drawingImage;
  final String? drawingAnalysisEncoded;
  final ui.Image? drawingRevealBaseImage;
  final SvgRevealLayers? svgRevealLayers;
  final ArtworkAnimationGuidance artworkAnimationGuidance;
  final ui.Image? handImage;
  final List<Offset> activeStroke;
  final double? manualRevealWidth;
  final int? selectedStrokeIndex;
  final DocumentRect? transientArtworkDestination;
  final int? hoveredStrokeIndex;
  final PathNodeReference? selectedPathNode;
  final Set<PathNodeReference> selectedPathNodes;
  final double maskBrushWidth;
  final double maskFeather;
  final bool maskOverlayVisible;
  final bool maskComparisonBefore;
  final bool maskClipToLayer;
  final bool nodeSnapEnabled;
  final String? selectedTimingSectionKey;
  final List<SmartPathSection> smartSections;
  final AutoPathResultSummary? autoPathResult;
  final String? selectedSmartSectionId;
  final Set<String> selectedTimelineSectionIds;
  final String? selectedTimelineSceneId;
  final List<EditorSceneDraft> sceneDrafts;
  final bool suggestionOrderCustomized;
  final Set<String> collapsedTimelineSceneIds;
  final bool isAnalyzingSmartPaths;
  final SmartPathProgress? smartPathProgress;
  final Duration smartPathAnalysisElapsed;
  final bool isDrawingImporting;
  final List<HandPreset> handPresets;
  final String? selectedHandPresetId;
  final bool isHandLibraryLoading;
  final bool isVoiceGuideLoading;
  final bool isVoiceGuideMissing;

  /// Monotonically identifies the content currently owned by the canvas.
  ///
  /// It is intentionally view-state only (not persisted in project files).
  /// Replacing, clearing, restoring, or opening artwork increments it so
  /// render objects and asynchronous analysis can never retain an older
  /// canvas session.
  final int canvasRevision;
  final bool editingImagePaths;
  final bool imageAnimationControlsOpen;
  final String statusMessage;

  bool get hasDrawing => drawingImage != null;
  bool get hasHand => handImage != null;
  bool get hasSmartSections => smartSections.isNotEmpty;
  bool get canPreview => hasDrawing && document.strokes.isNotEmpty;
  bool get hasCanvasContent =>
      hasDrawing ||
      document.strokes.isNotEmpty ||
      hasSmartSections ||
      activeStroke.isNotEmpty;

  HandPreset? get selectedHandPreset {
    final id = selectedHandPresetId;
    if (id == null) return null;
    for (final preset in handPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  SmartPathSection? get selectedSmartSection {
    final id = selectedSmartSectionId;
    if (id == null) return null;
    for (final section in smartSections) {
      if (section.id == id) return section;
    }
    return null;
  }

  EditorState copyWith({
    EditorDocumentState? documentState,
    EditorTool? tool,
    Object? drawingImage = _unset,
    Object? drawingAnalysisEncoded = _unset,
    Object? drawingRevealBaseImage = _unset,
    Object? svgRevealLayers = _unset,
    ArtworkAnimationGuidance? artworkAnimationGuidance,
    Object? handImage = _unset,
    List<Offset>? activeStroke,
    Object? manualRevealWidth = _unset,
    Object? selectedStrokeIndex = _unset,
    Object? transientArtworkDestination = _unset,
    Object? hoveredStrokeIndex = _unset,
    Object? selectedPathNode = _unset,
    Set<PathNodeReference>? selectedPathNodes,
    double? maskBrushWidth,
    double? maskFeather,
    bool? maskOverlayVisible,
    bool? maskComparisonBefore,
    bool? maskClipToLayer,
    bool? nodeSnapEnabled,
    Object? selectedTimingSectionKey = _unset,
    List<SmartPathSection>? smartSections,
    Object? autoPathResult = _unset,
    Object? selectedSmartSectionId = _unset,
    Set<String>? selectedTimelineSectionIds,
    Object? selectedTimelineSceneId = _unset,
    List<EditorSceneDraft>? sceneDrafts,
    bool? suggestionOrderCustomized,
    Set<String>? collapsedTimelineSceneIds,
    bool? isAnalyzingSmartPaths,
    Object? smartPathProgress = _unset,
    Duration? smartPathAnalysisElapsed,
    bool? isDrawingImporting,
    List<HandPreset>? handPresets,
    Object? selectedHandPresetId = _unset,
    bool? isHandLibraryLoading,
    bool? isVoiceGuideLoading,
    bool? isVoiceGuideMissing,
    int? canvasRevision,
    bool? editingImagePaths,
    bool? imageAnimationControlsOpen,
    String? statusMessage,
  }) {
    return EditorState(
      documentState: documentState ?? this.documentState,
      tool: tool ?? this.tool,
      drawingImage: identical(drawingImage, _unset)
          ? this.drawingImage
          : drawingImage as ui.Image?,
      drawingAnalysisEncoded: identical(drawingAnalysisEncoded, _unset)
          ? this.drawingAnalysisEncoded
          : drawingAnalysisEncoded as String?,
      drawingRevealBaseImage: identical(drawingRevealBaseImage, _unset)
          ? this.drawingRevealBaseImage
          : drawingRevealBaseImage as ui.Image?,
      svgRevealLayers: identical(svgRevealLayers, _unset)
          ? this.svgRevealLayers
          : svgRevealLayers as SvgRevealLayers?,
      artworkAnimationGuidance:
          artworkAnimationGuidance ?? this.artworkAnimationGuidance,
      handImage: identical(handImage, _unset)
          ? this.handImage
          : handImage as ui.Image?,
      activeStroke: List.unmodifiable(activeStroke ?? this.activeStroke),
      manualRevealWidth: identical(manualRevealWidth, _unset)
          ? this.manualRevealWidth
          : manualRevealWidth as double?,
      selectedStrokeIndex: identical(selectedStrokeIndex, _unset)
          ? this.selectedStrokeIndex
          : selectedStrokeIndex as int?,
      transientArtworkDestination:
          identical(transientArtworkDestination, _unset)
          ? this.transientArtworkDestination
          : transientArtworkDestination as DocumentRect?,
      hoveredStrokeIndex: identical(hoveredStrokeIndex, _unset)
          ? this.hoveredStrokeIndex
          : hoveredStrokeIndex as int?,
      selectedPathNode: identical(selectedPathNode, _unset)
          ? this.selectedPathNode
          : selectedPathNode as PathNodeReference?,
      selectedPathNodes: Set.unmodifiable(
        selectedPathNodes ?? this.selectedPathNodes,
      ),
      maskBrushWidth: maskBrushWidth ?? this.maskBrushWidth,
      maskFeather: maskFeather ?? this.maskFeather,
      maskOverlayVisible: maskOverlayVisible ?? this.maskOverlayVisible,
      maskComparisonBefore: maskComparisonBefore ?? this.maskComparisonBefore,
      maskClipToLayer: maskClipToLayer ?? this.maskClipToLayer,
      nodeSnapEnabled: nodeSnapEnabled ?? this.nodeSnapEnabled,
      selectedTimingSectionKey: identical(selectedTimingSectionKey, _unset)
          ? this.selectedTimingSectionKey
          : selectedTimingSectionKey as String?,
      smartSections: List.unmodifiable(smartSections ?? this.smartSections),
      autoPathResult: identical(autoPathResult, _unset)
          ? this.autoPathResult
          : autoPathResult as AutoPathResultSummary?,
      selectedSmartSectionId: identical(selectedSmartSectionId, _unset)
          ? this.selectedSmartSectionId
          : selectedSmartSectionId as String?,
      selectedTimelineSectionIds: Set.unmodifiable(
        selectedTimelineSectionIds ?? this.selectedTimelineSectionIds,
      ),
      selectedTimelineSceneId: identical(selectedTimelineSceneId, _unset)
          ? this.selectedTimelineSceneId
          : selectedTimelineSceneId as String?,
      sceneDrafts: List.unmodifiable(sceneDrafts ?? this.sceneDrafts),
      suggestionOrderCustomized:
          suggestionOrderCustomized ?? this.suggestionOrderCustomized,
      collapsedTimelineSceneIds:
          collapsedTimelineSceneIds ?? this.collapsedTimelineSceneIds,
      isAnalyzingSmartPaths:
          isAnalyzingSmartPaths ?? this.isAnalyzingSmartPaths,
      smartPathProgress: identical(smartPathProgress, _unset)
          ? this.smartPathProgress
          : smartPathProgress as SmartPathProgress?,
      smartPathAnalysisElapsed:
          smartPathAnalysisElapsed ?? this.smartPathAnalysisElapsed,
      isDrawingImporting: isDrawingImporting ?? this.isDrawingImporting,
      handPresets: List.unmodifiable(handPresets ?? this.handPresets),
      selectedHandPresetId: identical(selectedHandPresetId, _unset)
          ? this.selectedHandPresetId
          : selectedHandPresetId as String?,
      isHandLibraryLoading: isHandLibraryLoading ?? this.isHandLibraryLoading,
      isVoiceGuideLoading: isVoiceGuideLoading ?? this.isVoiceGuideLoading,
      isVoiceGuideMissing: isVoiceGuideMissing ?? this.isVoiceGuideMissing,
      canvasRevision: canvasRevision ?? this.canvasRevision,
      editingImagePaths: editingImagePaths ?? this.editingImagePaths,
      imageAnimationControlsOpen:
          imageAnimationControlsOpen ?? this.imageAnimationControlsOpen,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
