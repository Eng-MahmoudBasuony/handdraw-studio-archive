import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/domain/auto_path_result_summary.dart';
import 'package:handdraw_studio/features/editor/domain/path_node_editor.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_project_view_cache.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_animation_guidance.dart';

EditorState testEditorState({
  required HandDrawProject project,
  EditorTool tool = EditorTool.select,
  ui.Image? drawingImage,
  ui.Image? drawingRevealBaseImage,
  SvgRevealLayers? svgRevealLayers,
  ArtworkAnimationGuidance artworkAnimationGuidance =
      ArtworkAnimationGuidance.unknown,
  ui.Image? handImage,
  List<Offset> activeStroke = const [],
  int? selectedStrokeIndex,
  int? hoveredStrokeIndex,
  PathNodeReference? selectedPathNode,
  Set<PathNodeReference> selectedPathNodes = const {},
  double maskBrushWidth = 54,
  double maskFeather = 8,
  bool maskOverlayVisible = true,
  bool maskComparisonBefore = false,
  bool maskClipToLayer = true,
  bool nodeSnapEnabled = false,
  String? selectedTimingSectionKey,
  List<SmartPathSection> smartSections = const [],
  AutoPathResultSummary? autoPathResult,
  String? selectedSmartSectionId,
  Set<String> selectedTimelineSectionIds = const {},
  String? selectedTimelineSceneId,
  bool isAnalyzingSmartPaths = false,
  SmartPathProgress? smartPathProgress,
  Duration smartPathAnalysisElapsed = Duration.zero,
  bool isDrawingImporting = false,
  List<HandPreset> handPresets = BuiltInHands.all,
  String? selectedHandPresetId = BuiltInHands.defaultPresetId,
  bool isHandLibraryLoading = false,
  bool isVoiceGuideLoading = false,
  bool isVoiceGuideMissing = false,
  int canvasRevision = 0,
  String statusMessage = 'Import a drawing to begin',
}) => EditorState(
  documentState: EditorDocumentState(document: testDocumentFromLegacy(project)),
  tool: tool,
  drawingImage: drawingImage,
  drawingAnalysisEncoded:
      project.drawingSourceBase64 ?? project.drawingImageBase64,
  drawingRevealBaseImage: drawingRevealBaseImage,
  svgRevealLayers: svgRevealLayers,
  artworkAnimationGuidance: artworkAnimationGuidance,
  handImage: handImage,
  activeStroke: activeStroke,
  selectedStrokeIndex: selectedStrokeIndex,
  hoveredStrokeIndex: hoveredStrokeIndex,
  selectedPathNode: selectedPathNode,
  selectedPathNodes: selectedPathNodes,
  maskBrushWidth: maskBrushWidth,
  maskFeather: maskFeather,
  maskOverlayVisible: maskOverlayVisible,
  maskComparisonBefore: maskComparisonBefore,
  maskClipToLayer: maskClipToLayer,
  nodeSnapEnabled: nodeSnapEnabled,
  selectedTimingSectionKey: selectedTimingSectionKey,
  smartSections: smartSections,
  autoPathResult: autoPathResult,
  selectedSmartSectionId: selectedSmartSectionId,
  selectedTimelineSectionIds: selectedTimelineSectionIds,
  selectedTimelineSceneId: selectedTimelineSceneId,
  isAnalyzingSmartPaths: isAnalyzingSmartPaths,
  smartPathProgress: smartPathProgress,
  smartPathAnalysisElapsed: smartPathAnalysisElapsed,
  isDrawingImporting: isDrawingImporting,
  handPresets: handPresets,
  selectedHandPresetId: selectedHandPresetId,
  isHandLibraryLoading: isHandLibraryLoading,
  isVoiceGuideLoading: isVoiceGuideLoading,
  isVoiceGuideMissing: isVoiceGuideMissing,
  canvasRevision: canvasRevision,
  statusMessage: statusMessage,
);

ProjectDocument testDocumentFromLegacy(HandDrawProject project) {
  TimelineDuration duration(double seconds) =>
      TimelineDuration.fromMicroseconds(
        (seconds * Duration.microsecondsPerSecond).round(),
      );
  final sectionOrder = <SectionId>[];
  final hasArtwork =
      project.drawingImagePath != null ||
      project.drawingImageBase64 != null ||
      project.drawingSourceBase64 != null;
  final hasHand =
      project.handImagePath != null || project.handImageBase64 != null;
  final artworkAssetId = hasArtwork ? ProjectAssetId('test-artwork') : null;
  final handAssetId = hasHand ? ProjectAssetId('test-hand') : null;
  final sectionStrokes = <SectionId, List<StrokeId>>{};
  final strokes = <ProjectStroke>[];
  for (final stroke in project.strokes) {
    final sectionId = SectionId(stroke.sectionId ?? 'stroke:${stroke.id}');
    sectionStrokes.putIfAbsent(sectionId, () {
      sectionOrder.add(sectionId);
      return <StrokeId>[];
    });
    final strokeId = StrokeId(stroke.id);
    sectionStrokes[sectionId]!.add(strokeId);
    strokes.add(
      ProjectStroke(
        id: strokeId,
        sectionId: sectionId,
        name: stroke.name,
        assetId: artworkAssetId,
        points: [
          for (final point in stroke.points) DocumentPoint(point.dx, point.dy),
        ],
        geometry: stroke.geometry,
        animationGeometry: stroke.animationGeometry,
        isPaintStroke: stroke.isPaintStroke,
        paintRegion: stroke.paintRegion,
        isFilledShape: stroke.isFilledShape,
        isTextShape: stroke.isTextShape,
        isGlobalDecoration: stroke.isGlobalDecoration,
        fillColorValue: stroke.fillColorValue,
        hidden: stroke.hidden,
        reversed: stroke.reversed,
        revealOnly: stroke.revealOnly,
        revealStyle: stroke.revealStyle == RevealMaskStyle.directionalWipe
            ? DocumentRevealStyle.directionalWipe
            : DocumentRevealStyle.brush,
        clipBounds: stroke.clipBounds == null
            ? null
            : DocumentRect(
                left: stroke.clipBounds!.left,
                top: stroke.clipBounds!.top,
                right: stroke.clipBounds!.right,
                bottom: stroke.clipBounds!.bottom,
              ),
        exclusionBounds: [
          for (final rect in stroke.exclusionBounds)
            DocumentRect(
              left: rect.left,
              top: rect.top,
              right: rect.right,
              bottom: rect.bottom,
            ),
        ],
        revealWidth: stroke.revealWidth,
        pausePoints: [
          for (final pause in stroke.pausePoints)
            DocumentStrokePause(
              id: StrokePauseId(pause.id),
              progress: pause.progress,
              duration: duration(pause.durationSeconds),
              keepHandVisible: pause.keepHandVisible,
            ),
        ],
        vectorMaskStrokes: [
          for (final mask in stroke.vectorMaskStrokes)
            DocumentVectorMaskStroke(
              geometry: mask.geometry,
              width: mask.widthFraction,
              erase: mask.operation == VectorMaskOperation.erase,
              feather: mask.featherFraction,
              clipToLayer: mask.clipToLayer,
            ),
        ],
      ),
    );
  }
  final sections = [
    for (final id in sectionOrder)
      ProjectSection(
        id: id,
        name: id.value,
        strokeIds: sectionStrokes[id]!,
        assetId: artworkAssetId,
        timing: _timing(
          project.sectionTimings[id.value] ??
              project.sectionTimings['section:${id.value}'],
        ),
      ),
  ];
  final ordered = <SectionId>[];
  final byValue = {for (final id in sectionOrder) id.value: id};
  for (final value in project.timelineSectionOrder) {
    final id = byValue[value];
    if (id != null && !ordered.contains(id)) ordered.add(id);
  }
  ordered.addAll(sectionOrder.where((id) => !ordered.contains(id)));
  final voiceAssetId = project.voiceGuide == null
      ? null
      : ProjectAssetId('test-voice-asset');
  final voiceTrackId = project.voiceGuide == null
      ? null
      : AudioTrackId('test-voice-track');
  const testHash =
      'sha256:0000000000000000000000000000000000000000000000000000000000000000';
  return ProjectDocument(
    id: ProjectId('test-project'),
    title: 'Test Project',
    canvas: ProjectCanvas(
      width: project.canvasWidth,
      height: project.canvasHeight,
      background: project.canvasBackground,
    ),
    frameRate: FrameRate(numerator: project.frameRate),
    duration: duration(
      project.voiceGuide == null
          ? project.durationSeconds
          : project.durationSeconds > project.voiceGuide!.durationSeconds
          ? project.durationSeconds
          : project.voiceGuide!.durationSeconds,
    ),
    exportConfiguration: ProjectExportConfiguration(
      presetId: project.exportPresetId,
      alphaMode: project.exportAlphaMode,
      renderQuality: project.exportRenderQuality,
    ),
    motionConfiguration: ProjectMotionConfiguration(
      imageAnimationEffect: project.imageAnimationEffect,
      showDrawingHand: project.showDrawingHand,
      drawingDuration: duration(project.drawingDurationSeconds),
      drawingSpeed: project.drawingSpeed,
      penTravelSpeed: project.penTravelSpeed,
      startDelay: duration(project.startDelaySeconds),
      endHold: duration(project.endHoldSeconds),
      revealWidth: project.revealWidth,
    ),
    handConfiguration: ProjectHandConfiguration(
      assetId: handAssetId,
      presetId: project.handPresetId,
      scale: project.handScale,
      rotationDegrees: project.handRotationDegrees,
      flipX: project.handFlipX,
      penTip: DocumentPoint(project.penTip.dx, project.penTip.dy),
    ),
    writingSoundConfiguration: ProjectWritingSoundConfiguration(
      enabled: project.writingSoundEnabled,
      preset: project.writingSoundPreset,
      volume: project.writingSoundVolume,
    ),
    artworkAssetId: artworkAssetId,
    assets: [
      if (artworkAssetId != null)
        ProjectAsset(
          id: artworkAssetId,
          kind: ProjectAssetKind.artwork,
          originalFileName: 'artwork.png',
          storagePolicy: ProjectAssetStoragePolicy.external,
          contentHash: testHash,
          artworkSourceType:
              project.drawingSourceKind.name == ArtworkSourceType.svg.name
              ? ArtworkSourceType.svg
              : ArtworkSourceType.raster,
          externalLocator: ExternalAssetLocator(
            pathHint: project.drawingImagePath ?? '/tmp/test-artwork.png',
          ),
        ),
      if (handAssetId != null)
        ProjectAsset(
          id: handAssetId,
          kind: ProjectAssetKind.hand,
          originalFileName: 'hand.png',
          storagePolicy: ProjectAssetStoragePolicy.external,
          contentHash: testHash,
          externalLocator: ExternalAssetLocator(
            pathHint: project.handImagePath ?? '/tmp/test-hand.png',
          ),
        ),
      if (voiceAssetId != null)
        ProjectAsset(
          id: voiceAssetId,
          kind: ProjectAssetKind.audio,
          originalFileName: 'voice.wav',
          storagePolicy: ProjectAssetStoragePolicy.external,
          contentHash: testHash,
          mediaDuration: duration(project.voiceGuide!.durationSeconds),
          externalLocator: ExternalAssetLocator(
            pathHint: project.voiceGuide!.path,
            securityBookmark: project.voiceGuide!.securityBookmark,
          ),
        ),
    ],
    strokes: strokes,
    sections: sections,
    sectionOrder: ordered,
    scenes: [
      for (final scene in project.sceneGroups)
        ProjectScene(
          id: SceneId(scene.id),
          name: scene.name,
          sectionIds: [for (final id in scene.sectionIds) ?byValue[id]],
          locked: scene.locked,
        ),
    ],
    audioTracks: [
      if (voiceTrackId != null && voiceAssetId != null)
        ProjectAudioTrack(
          id: voiceTrackId,
          assetId: voiceAssetId,
          start: TimelineTime.zero,
          duration: duration(project.voiceGuide!.durationSeconds),
          exportPolicy: AudioExportPolicy.referenceOnly,
        ),
    ],
    voiceGuide: voiceTrackId == null
        ? null
        : ProjectVoiceGuide(
            audioTrackId: voiceTrackId,
            displayName: project.voiceGuide!.name,
            originalFileName: 'voice.wav',
          ),
  );
}

HandDrawProject testLegacyProject(EditorState state) =>
    LegacyProjectViewCache().resolve(state.documentState);

DocumentSectionTiming _timing(SectionTiming? value) {
  if (value == null) return const DocumentSectionTiming();
  TimelineDuration duration(double seconds) =>
      TimelineDuration.fromMicroseconds(
        (seconds * Duration.microsecondsPerSecond).round(),
      );
  return DocumentSectionTiming(
    animationDuration: value.animationDurationSeconds == null
        ? null
        : duration(value.animationDurationSeconds!),
    pauseBefore: duration(value.pauseBeforeSeconds),
    pauseAfter: duration(value.pauseAfterSeconds),
    transitionAfter: duration(value.transitionAfterSeconds ?? 0),
    speedMultiplier: value.speedMultiplier,
    pauseHandBehavior: value.pauseHandBehavior == PauseHandBehavior.hide
        ? DocumentPauseHandBehavior.hide
        : DocumentPauseHandBehavior.keepVisible,
  );
}
