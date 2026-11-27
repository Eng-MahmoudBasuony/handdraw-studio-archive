import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_polygon_list.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_value_list.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

enum ProjectAssetKind { artwork, hand, audio, other }

enum ArtworkSourceType { svg, raster }

enum ArtworkPlacementMode { fitEntire, fitVisible, originalSize, fillCanvas }

enum ArtworkImportIntent { fullScene, element }

enum ProjectCanvasBackground { transparent, color }

final class ProjectCreationDefaults {
  const ProjectCreationDefaults({
    this.background = ProjectCanvasBackground.transparent,
    this.importIntent = ArtworkImportIntent.fullScene,
  });

  final ProjectCanvasBackground background;
  final ArtworkImportIntent importIntent;
}

/// Identifies the exact analysis configuration that produced accepted artwork
/// paths. Accepted strokes remain authoritative; this record prevents a later
/// feature-flag or algorithm update from silently changing an older project.
final class ProjectPathProcessingMetadata {
  const ProjectPathProcessingMetadata({
    required this.engineId,
    required this.algorithmVersion,
    required this.sourceAssetHash,
    required this.suspectedFrameDetection,
    required this.suspectedFrameConfidenceThreshold,
  });

  final String engineId;
  final int algorithmVersion;
  final String sourceAssetHash;
  final bool suspectedFrameDetection;
  final double suspectedFrameConfidenceThreshold;

  List<String> get featureSet => [
    if (suspectedFrameDetection) 'suspected-frame-detection-v1',
  ];

  Map<String, double> get processingParameters => {
    if (suspectedFrameDetection)
      'suspectedFrameConfidenceThreshold': suspectedFrameConfidenceThreshold,
  };
}

enum ProjectAssetStoragePolicy { embedded, external }

/// Whether an audio track participates in rendered media output. This is
/// deliberately independent from how its source asset is stored in a project.
enum AudioExportPolicy { referenceOnly, embedInOutput }

enum DocumentRevealStyle { brush, directionalWipe }

enum DocumentPauseHandBehavior { keepVisible, hide }

final class ProjectCanvas {
  const ProjectCanvas({
    required this.width,
    required this.height,
    this.background = const CanvasBackground.transparent(),
  });

  final int width;
  final int height;
  final CanvasBackground background;

  ProjectCanvas copyWith({
    int? width,
    int? height,
    CanvasBackground? background,
  }) => ProjectCanvas(
    width: width ?? this.width,
    height: height ?? this.height,
    background: background ?? this.background,
  );
}

final class DocumentPoint {
  const DocumentPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentPoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}

final class DocumentRect {
  const DocumentRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Persistent artwork-to-project mapping. Bounds are expressed in encoded
/// image pixels; [destination] is expressed in project-canvas coordinates.
/// It is deliberately independent from editor viewport and camera transforms.
final class ProjectArtworkPlacement {
  const ProjectArtworkPlacement({
    required this.encodedBounds,
    required this.visibleBounds,
    required this.destination,
    this.mode = ArtworkPlacementMode.fitEntire,
    this.importIntent = ArtworkImportIntent.fullScene,
  });

  final DocumentRect encodedBounds;
  final DocumentRect visibleBounds;
  final DocumentRect destination;
  final ArtworkPlacementMode mode;
  final ArtworkImportIntent importIntent;

  ProjectArtworkPlacement copyWith({
    DocumentRect? encodedBounds,
    DocumentRect? visibleBounds,
    DocumentRect? destination,
    ArtworkPlacementMode? mode,
    ArtworkImportIntent? importIntent,
  }) => ProjectArtworkPlacement(
    encodedBounds: encodedBounds ?? this.encodedBounds,
    visibleBounds: visibleBounds ?? this.visibleBounds,
    destination: destination ?? this.destination,
    mode: mode ?? this.mode,
    importIntent: importIntent ?? this.importIntent,
  );
}

final class DocumentStrokePause {
  const DocumentStrokePause({
    required this.id,
    required this.progress,
    required this.duration,
    this.keepHandVisible = true,
  });

  final StrokePauseId id;
  final double progress;
  final TimelineDuration duration;
  final bool keepHandVisible;
}

final class DocumentVectorMaskStroke {
  const DocumentVectorMaskStroke({
    required this.geometry,
    required this.width,
    required this.erase,
    this.feather = 0,
    this.clipToLayer = true,
  });

  final StrokePathGeometry geometry;
  final double width;
  final bool erase;
  final double feather;
  final bool clipToLayer;
}

final class ProjectExportConfiguration {
  const ProjectExportConfiguration({
    this.presetId = ExportPresetId.presentationHd,
    this.alphaMode = ExportAlphaMode.premultiplied,
    this.renderQuality = ExportRenderQuality.full,
  });

  final ExportPresetId presetId;
  final ExportAlphaMode alphaMode;
  final ExportRenderQuality renderQuality;

  ProjectExportConfiguration copyWith({
    ExportPresetId? presetId,
    ExportAlphaMode? alphaMode,
    ExportRenderQuality? renderQuality,
  }) => ProjectExportConfiguration(
    presetId: presetId ?? this.presetId,
    alphaMode: alphaMode ?? this.alphaMode,
    renderQuality: renderQuality ?? this.renderQuality,
  );
}

final class ProjectMotionConfiguration {
  const ProjectMotionConfiguration({
    required this.drawingDuration,
    this.drawingSpeed = 1,
    this.penTravelSpeed = 1,
    this.startDelay = TimelineDuration.zero,
    this.endHold = TimelineDuration.zero,
    this.revealWidth = 54,
    this.imageAnimationEffect = 'legacy',
    this.showDrawingHand = true,
  });

  final TimelineDuration drawingDuration;
  final double drawingSpeed;
  final double penTravelSpeed;
  final TimelineDuration startDelay;
  final TimelineDuration endHold;
  final double revealWidth;
  final String imageAnimationEffect;
  final bool showDrawingHand;

  ProjectMotionConfiguration copyWith({
    TimelineDuration? drawingDuration,
    double? drawingSpeed,
    double? penTravelSpeed,
    TimelineDuration? startDelay,
    TimelineDuration? endHold,
    double? revealWidth,
    String? imageAnimationEffect,
    bool? showDrawingHand,
  }) => ProjectMotionConfiguration(
    drawingDuration: drawingDuration ?? this.drawingDuration,
    drawingSpeed: drawingSpeed ?? this.drawingSpeed,
    penTravelSpeed: penTravelSpeed ?? this.penTravelSpeed,
    startDelay: startDelay ?? this.startDelay,
    endHold: endHold ?? this.endHold,
    revealWidth: revealWidth ?? this.revealWidth,
    imageAnimationEffect: imageAnimationEffect ?? this.imageAnimationEffect,
    showDrawingHand: showDrawingHand ?? this.showDrawingHand,
  );
}

final class ProjectHandConfiguration {
  const ProjectHandConfiguration({
    this.assetId,
    this.presetId = 'marker-technical-wheat-right',
    this.scale = 0.24,
    this.rotationDegrees = 0,
    this.flipX = false,
    this.penTip = const DocumentPoint(0.114583, 0.485677),
  });

  final ProjectAssetId? assetId;
  final String? presetId;
  final double scale;
  final double rotationDegrees;
  final bool flipX;
  final DocumentPoint penTip;

  ProjectHandConfiguration copyWith({
    Object? assetId = _unsetDocumentValue,
    Object? presetId = _unsetDocumentValue,
    double? scale,
    double? rotationDegrees,
    bool? flipX,
    DocumentPoint? penTip,
  }) => ProjectHandConfiguration(
    assetId: identical(assetId, _unsetDocumentValue)
        ? this.assetId
        : assetId as ProjectAssetId?,
    presetId: identical(presetId, _unsetDocumentValue)
        ? this.presetId
        : presetId as String?,
    scale: scale ?? this.scale,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    flipX: flipX ?? this.flipX,
    penTip: penTip ?? this.penTip,
  );
}

final class ProjectWritingSoundConfiguration {
  const ProjectWritingSoundConfiguration({
    this.enabled = false,
    this.preset = WritingSoundPreset.defaultPreset,
    this.volume = 0.65,
  });

  final bool enabled;
  final WritingSoundPreset preset;
  final double volume;

  ProjectWritingSoundConfiguration copyWith({
    bool? enabled,
    WritingSoundPreset? preset,
    double? volume,
  }) => ProjectWritingSoundConfiguration(
    enabled: enabled ?? this.enabled,
    preset: preset ?? this.preset,
    volume: volume ?? this.volume,
  );
}

/// Platform-specific information used to resolve an external asset.
///
/// [ProjectAsset.contentHash] protects against silently resolving a different
/// file at the same path. Embedded assets deliberately have no locator.
final class ExternalAssetLocator {
  const ExternalAssetLocator({required this.pathHint, this.securityBookmark});

  final String pathHint;
  final String? securityBookmark;
}

final class ProjectAsset {
  const ProjectAsset({
    required this.id,
    required this.kind,
    required this.originalFileName,
    required this.storagePolicy,
    required this.contentHash,
    this.mediaType,
    this.artworkSourceType,
    this.externalLocator,
    this.mediaDuration,
  });

  final ProjectAssetId id;
  final ProjectAssetKind kind;
  final String originalFileName;
  final ProjectAssetStoragePolicy storagePolicy;
  final String contentHash;
  final String? mediaType;
  final ArtworkSourceType? artworkSourceType;

  final ExternalAssetLocator? externalLocator;
  final TimelineDuration? mediaDuration;

  ProjectAsset copyWith({
    ProjectAssetId? id,
    ProjectAssetKind? kind,
    String? originalFileName,
    ProjectAssetStoragePolicy? storagePolicy,
    String? contentHash,
    Object? mediaType = _unsetDocumentValue,
    Object? artworkSourceType = _unsetDocumentValue,
    Object? externalLocator = _unsetDocumentValue,
    Object? mediaDuration = _unsetDocumentValue,
  }) => ProjectAsset(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    originalFileName: originalFileName ?? this.originalFileName,
    storagePolicy: storagePolicy ?? this.storagePolicy,
    contentHash: contentHash ?? this.contentHash,
    mediaType: identical(mediaType, _unsetDocumentValue)
        ? this.mediaType
        : mediaType as String?,
    artworkSourceType: identical(artworkSourceType, _unsetDocumentValue)
        ? this.artworkSourceType
        : artworkSourceType as ArtworkSourceType?,
    externalLocator: identical(externalLocator, _unsetDocumentValue)
        ? this.externalLocator
        : externalLocator as ExternalAssetLocator?,
    mediaDuration: identical(mediaDuration, _unsetDocumentValue)
        ? this.mediaDuration
        : mediaDuration as TimelineDuration?,
  );
}

final class ProjectStroke {
  ProjectStroke({
    required this.id,
    required this.sectionId,
    required this.name,
    required List<DocumentPoint> points,
    this.assetId,
    this.geometry,
    this.animationGeometry,
    this.isFilledShape = false,
    this.isTextShape = false,
    this.isGlobalDecoration = false,
    this.fillColorValue,
    this.hidden = false,
    this.reversed = false,
    this.revealOnly = false,
    this.isPaintStroke = false,
    this.paintRegion = 0,
    this.revealStyle = DocumentRevealStyle.brush,
    this.clipBounds,
    List<List<DocumentPoint>> clipPolygons = const [],
    List<DocumentRect> exclusionBounds = const [],
    this.revealWidth,
    List<DocumentStrokePause> pausePoints = const [],
    List<DocumentVectorMaskStroke> vectorMaskStrokes = const [],
  }) : points = List.unmodifiable(points),
       clipPolygons = ImmutablePolygonList<DocumentPoint>.freeze(clipPolygons),
       exclusionBounds = ImmutableValueList.freeze(exclusionBounds),
       pausePoints = List.unmodifiable(pausePoints),
       vectorMaskStrokes = List.unmodifiable(vectorMaskStrokes);

  final StrokeId id;
  final SectionId sectionId;
  final String name;
  final List<DocumentPoint> points;
  final ProjectAssetId? assetId;
  final StrokePathGeometry? geometry;
  final StrokePathGeometry? animationGeometry;
  final bool isFilledShape;
  final bool isTextShape;
  final bool isGlobalDecoration;
  final int? fillColorValue;
  final bool hidden;
  final bool reversed;
  final bool revealOnly;
  final bool isPaintStroke;
  final int paintRegion;
  final DocumentRevealStyle revealStyle;
  final DocumentRect? clipBounds;
  final List<List<DocumentPoint>> clipPolygons;
  final List<DocumentRect> exclusionBounds;
  final double? revealWidth;
  final List<DocumentStrokePause> pausePoints;
  final List<DocumentVectorMaskStroke> vectorMaskStrokes;

  ProjectStroke copyWith({
    StrokeId? id,
    SectionId? sectionId,
    String? name,
    List<DocumentPoint>? points,
    Object? assetId = _unsetDocumentValue,
    Object? geometry = _unsetDocumentValue,
    Object? animationGeometry = _unsetDocumentValue,
    bool? isFilledShape,
    bool? isTextShape,
    bool? isGlobalDecoration,
    Object? fillColorValue = _unsetDocumentValue,
    bool? hidden,
    bool? reversed,
    bool? revealOnly,
    bool? isPaintStroke,
    int? paintRegion,
    DocumentRevealStyle? revealStyle,
    Object? clipBounds = _unsetDocumentValue,
    List<List<DocumentPoint>>? clipPolygons,
    List<DocumentRect>? exclusionBounds,
    Object? revealWidth = _unsetDocumentValue,
    List<DocumentStrokePause>? pausePoints,
    List<DocumentVectorMaskStroke>? vectorMaskStrokes,
  }) => ProjectStroke(
    id: id ?? this.id,
    sectionId: sectionId ?? this.sectionId,
    name: name ?? this.name,
    points: points ?? this.points,
    assetId: identical(assetId, _unsetDocumentValue)
        ? this.assetId
        : assetId as ProjectAssetId?,
    geometry: identical(geometry, _unsetDocumentValue)
        ? this.geometry
        : geometry as StrokePathGeometry?,
    animationGeometry: identical(animationGeometry, _unsetDocumentValue)
        ? this.animationGeometry
        : animationGeometry as StrokePathGeometry?,
    isFilledShape: isFilledShape ?? this.isFilledShape,
    isTextShape: isTextShape ?? this.isTextShape,
    isGlobalDecoration: isGlobalDecoration ?? this.isGlobalDecoration,
    fillColorValue: identical(fillColorValue, _unsetDocumentValue)
        ? this.fillColorValue
        : fillColorValue as int?,
    hidden: hidden ?? this.hidden,
    reversed: reversed ?? this.reversed,
    revealOnly: revealOnly ?? this.revealOnly,
    isPaintStroke: isPaintStroke ?? this.isPaintStroke,
    paintRegion: paintRegion ?? this.paintRegion,
    revealStyle: revealStyle ?? this.revealStyle,
    clipBounds: identical(clipBounds, _unsetDocumentValue)
        ? this.clipBounds
        : clipBounds as DocumentRect?,
    clipPolygons: clipPolygons ?? this.clipPolygons,
    exclusionBounds: exclusionBounds ?? this.exclusionBounds,
    revealWidth: identical(revealWidth, _unsetDocumentValue)
        ? this.revealWidth
        : revealWidth as double?,
    pausePoints: pausePoints ?? this.pausePoints,
    vectorMaskStrokes: vectorMaskStrokes ?? this.vectorMaskStrokes,
  );
}

final class DocumentSectionTiming {
  const DocumentSectionTiming({
    this.animationDuration,
    this.pauseBefore = TimelineDuration.zero,
    this.pauseBeforeEnabled = false,
    this.pauseAfter = TimelineDuration.zero,
    this.pauseAfterEnabled = false,
    this.transitionAfter = TimelineDuration.zero,
    this.speedMultiplier = 1,
    this.pauseHandBehavior = DocumentPauseHandBehavior.keepVisible,
    this.audioCueAnchor,
    this.handEntranceAnimation = SectionHandEntranceAnimation.none,
    this.handEntranceDuration = TimelineDuration.zero,
    this.handExitAnimation = SectionHandExitAnimation.none,
    this.handExitDuration = TimelineDuration.zero,
    this.keepHandVisibleAfterDrawing = false,
  });

  final TimelineDuration? animationDuration;
  final TimelineDuration pauseBefore;
  final bool pauseBeforeEnabled;
  final TimelineDuration pauseAfter;
  final bool pauseAfterEnabled;
  final TimelineDuration transitionAfter;
  final double speedMultiplier;
  final DocumentPauseHandBehavior pauseHandBehavior;
  final AudioCueAnchor? audioCueAnchor;
  final SectionHandEntranceAnimation handEntranceAnimation;
  final TimelineDuration handEntranceDuration;
  final SectionHandExitAnimation handExitAnimation;
  final TimelineDuration handExitDuration;
  final bool keepHandVisibleAfterDrawing;

  bool get isDefault =>
      animationDuration == null &&
      !pauseBeforeEnabled &&
      pauseBefore.isZero &&
      !pauseAfterEnabled &&
      pauseAfter.isZero &&
      transitionAfter.isZero &&
      speedMultiplier == 1 &&
      pauseHandBehavior == DocumentPauseHandBehavior.keepVisible &&
      audioCueAnchor == null &&
      handEntranceAnimation == SectionHandEntranceAnimation.none &&
      handEntranceDuration.isZero &&
      handExitAnimation == SectionHandExitAnimation.none &&
      handExitDuration.isZero &&
      !keepHandVisibleAfterDrawing;

  DocumentSectionTiming copyWith({
    Object? animationDuration = _unsetDocumentValue,
    TimelineDuration? pauseBefore,
    bool? pauseBeforeEnabled,
    TimelineDuration? pauseAfter,
    bool? pauseAfterEnabled,
    TimelineDuration? transitionAfter,
    double? speedMultiplier,
    DocumentPauseHandBehavior? pauseHandBehavior,
    Object? audioCueAnchor = _unsetDocumentValue,
    SectionHandEntranceAnimation? handEntranceAnimation,
    TimelineDuration? handEntranceDuration,
    SectionHandExitAnimation? handExitAnimation,
    TimelineDuration? handExitDuration,
    bool? keepHandVisibleAfterDrawing,
  }) => DocumentSectionTiming(
    animationDuration: identical(animationDuration, _unsetDocumentValue)
        ? this.animationDuration
        : animationDuration as TimelineDuration?,
    pauseBefore: pauseBefore ?? this.pauseBefore,
    pauseBeforeEnabled: pauseBeforeEnabled ?? this.pauseBeforeEnabled,
    pauseAfter: pauseAfter ?? this.pauseAfter,
    pauseAfterEnabled: pauseAfterEnabled ?? this.pauseAfterEnabled,
    transitionAfter: transitionAfter ?? this.transitionAfter,
    speedMultiplier: speedMultiplier ?? this.speedMultiplier,
    pauseHandBehavior: pauseHandBehavior ?? this.pauseHandBehavior,
    audioCueAnchor: identical(audioCueAnchor, _unsetDocumentValue)
        ? this.audioCueAnchor
        : audioCueAnchor as AudioCueAnchor?,
    handEntranceAnimation: handEntranceAnimation ?? this.handEntranceAnimation,
    handEntranceDuration: handEntranceDuration ?? this.handEntranceDuration,
    handExitAnimation: handExitAnimation ?? this.handExitAnimation,
    handExitDuration: handExitDuration ?? this.handExitDuration,
    keepHandVisibleAfterDrawing:
        keepHandVisibleAfterDrawing ?? this.keepHandVisibleAfterDrawing,
  );
}

final class ProjectSection {
  ProjectSection({
    required this.id,
    required this.name,
    required List<StrokeId> strokeIds,
    this.assetId,
    this.timing = const DocumentSectionTiming(),
  }) : strokeIds = List.unmodifiable(strokeIds);

  final SectionId id;
  final String name;
  final List<StrokeId> strokeIds;
  final ProjectAssetId? assetId;
  final DocumentSectionTiming timing;

  ProjectSection copyWith({
    String? name,
    List<StrokeId>? strokeIds,
    Object? assetId = _unsetDocumentValue,
    DocumentSectionTiming? timing,
  }) => ProjectSection(
    id: id,
    name: name ?? this.name,
    strokeIds: strokeIds ?? this.strokeIds,
    assetId: identical(assetId, _unsetDocumentValue)
        ? this.assetId
        : assetId as ProjectAssetId?,
    timing: timing ?? this.timing,
  );
}

final class ProjectScene {
  ProjectScene({
    required this.id,
    required this.name,
    required List<SectionId> sectionIds,
    this.locked = true,
  }) : sectionIds = List.unmodifiable(sectionIds);

  final SceneId id;
  final String name;
  final List<SectionId> sectionIds;
  final bool locked;

  ProjectScene copyWith({
    String? name,
    List<SectionId>? sectionIds,
    bool? locked,
  }) => ProjectScene(
    id: id,
    name: name ?? this.name,
    sectionIds: sectionIds ?? this.sectionIds,
    locked: locked ?? this.locked,
  );
}

/// A stable synchronization anchor into source audio media.
///
/// Manual section pauses remain independent timing values. This is existing
/// behavior parity and does not introduce semantic regions or Auto Director.
final class AudioCueAnchor {
  const AudioCueAnchor({
    required this.audioTrackId,
    required this.sourceMediaTime,
  });

  final AudioTrackId audioTrackId;
  final TimelineTime sourceMediaTime;
}

/// Persistent Voice Guide metadata. Waveform samples are derived runtime data
/// and intentionally do not belong to the document.
final class ProjectVoiceGuide {
  const ProjectVoiceGuide({
    required this.audioTrackId,
    required this.displayName,
    required this.originalFileName,
  });

  final AudioTrackId audioTrackId;
  final String displayName;
  final String originalFileName;
}

/// Persistent audio placement only. Semantic cue intent belongs to Step 2B.
final class ProjectAudioTrack {
  const ProjectAudioTrack({
    required this.id,
    required this.assetId,
    required this.start,
    required this.duration,
    required this.exportPolicy,
    this.sourceOffset = TimelineTime.zero,
    this.muted = false,
    this.affectsTimelineDuration = true,
  });

  final AudioTrackId id;
  final ProjectAssetId assetId;
  final TimelineTime start;
  final TimelineDuration duration;
  final AudioExportPolicy exportPolicy;
  final TimelineTime sourceOffset;
  final bool muted;
  final bool affectsTimelineDuration;
}

/// Persistent aggregate root for project-owned data.
///
/// Runtime images, editor selection, playback state, caches, compiled
/// timelines, file handles, and history stacks intentionally have no place in
/// this model.
final class ProjectDocument {
  ProjectDocument({
    required this.id,
    required this.title,
    required this.canvas,
    required this.frameRate,
    required this.duration,
    this.artworkAssetId,
    this.artworkPlacement,
    this.exportConfiguration = const ProjectExportConfiguration(),
    ProjectMotionConfiguration? motionConfiguration,
    this.handConfiguration = const ProjectHandConfiguration(),
    this.writingSoundConfiguration = const ProjectWritingSoundConfiguration(),
    required List<ProjectAsset> assets,
    required List<ProjectStroke> strokes,
    required List<ProjectSection> sections,
    required List<SectionId> sectionOrder,
    required List<ProjectScene> scenes,
    required List<ProjectAudioTrack> audioTracks,
    this.voiceGuide,
    this.cameraTrack,
    this.contentMetadata = const ProjectContentMetadata.empty(),
    this.autoDirectorSettings = const ProjectAutoDirectorSettings(),
    this.creationDefaults = const ProjectCreationDefaults(),
    this.pathProcessingMetadata,
    PersistentTimeline? timeline,
  }) : motionConfiguration =
           motionConfiguration ??
           ProjectMotionConfiguration(drawingDuration: duration),
       assets = List.unmodifiable(assets),
       strokes = List.unmodifiable(strokes),
       sections = List.unmodifiable(sections),
       sectionOrder = List.unmodifiable(sectionOrder),
       scenes = List.unmodifiable(scenes),
       audioTracks = List.unmodifiable(audioTracks),
       timeline =
           timeline ??
           PersistentTimeline(
             camera: cameraTrack == null
                 ? const PersistentCameraTimelineTrack.disabled()
                 : PersistentCameraTimelineTrack.enabled(
                     cameraTrackId: cameraTrack.id,
                   ),
             audio: [
               for (final track in audioTracks)
                 PersistentAudioTimelineTrack(audioTrackId: track.id),
             ],
             voiceGuide: voiceGuide == null
                 ? null
                 : PersistentVoiceGuideTimelineTrack(
                     audioTrackId: voiceGuide.audioTrackId,
                   ),
           );

  final ProjectId id;
  final String title;
  final ProjectCanvas canvas;
  final FrameRate frameRate;
  final TimelineDuration duration;
  final ProjectAssetId? artworkAssetId;
  final ProjectArtworkPlacement? artworkPlacement;
  final ProjectExportConfiguration exportConfiguration;
  final ProjectMotionConfiguration motionConfiguration;
  final ProjectHandConfiguration handConfiguration;
  final ProjectWritingSoundConfiguration writingSoundConfiguration;
  final List<ProjectAsset> assets;
  final List<ProjectStroke> strokes;
  final List<ProjectSection> sections;
  final List<SectionId> sectionOrder;
  final List<ProjectScene> scenes;
  final List<ProjectAudioTrack> audioTracks;
  final ProjectVoiceGuide? voiceGuide;
  final ProjectCameraTrack? cameraTrack;
  final ProjectContentMetadata contentMetadata;
  final ProjectAutoDirectorSettings autoDirectorSettings;
  final ProjectCreationDefaults creationDefaults;
  final ProjectPathProcessingMetadata? pathProcessingMetadata;
  final PersistentTimeline timeline;

  ProjectDocument copyWith({
    ProjectId? id,
    String? title,
    ProjectCanvas? canvas,
    FrameRate? frameRate,
    TimelineDuration? duration,
    Object? artworkAssetId = _unsetDocumentValue,
    Object? artworkPlacement = _unsetDocumentValue,
    ProjectExportConfiguration? exportConfiguration,
    ProjectMotionConfiguration? motionConfiguration,
    ProjectHandConfiguration? handConfiguration,
    ProjectWritingSoundConfiguration? writingSoundConfiguration,
    List<ProjectAsset>? assets,
    List<ProjectStroke>? strokes,
    List<ProjectSection>? sections,
    List<SectionId>? sectionOrder,
    List<ProjectScene>? scenes,
    List<ProjectAudioTrack>? audioTracks,
    Object? voiceGuide = _unsetDocumentValue,
    Object? cameraTrack = _unsetDocumentValue,
    ProjectContentMetadata? contentMetadata,
    ProjectAutoDirectorSettings? autoDirectorSettings,
    ProjectCreationDefaults? creationDefaults,
    Object? pathProcessingMetadata = _unsetDocumentValue,
    PersistentTimeline? timeline,
  }) => ProjectDocument(
    id: id ?? this.id,
    title: title ?? this.title,
    canvas: canvas ?? this.canvas,
    frameRate: frameRate ?? this.frameRate,
    duration: duration ?? this.duration,
    artworkAssetId: identical(artworkAssetId, _unsetDocumentValue)
        ? this.artworkAssetId
        : artworkAssetId as ProjectAssetId?,
    artworkPlacement: identical(artworkPlacement, _unsetDocumentValue)
        ? this.artworkPlacement
        : artworkPlacement as ProjectArtworkPlacement?,
    exportConfiguration: exportConfiguration ?? this.exportConfiguration,
    motionConfiguration: motionConfiguration ?? this.motionConfiguration,
    handConfiguration: handConfiguration ?? this.handConfiguration,
    writingSoundConfiguration:
        writingSoundConfiguration ?? this.writingSoundConfiguration,
    assets: assets ?? this.assets,
    strokes: strokes ?? this.strokes,
    sections: sections ?? this.sections,
    sectionOrder: sectionOrder ?? this.sectionOrder,
    scenes: scenes ?? this.scenes,
    audioTracks: audioTracks ?? this.audioTracks,
    voiceGuide: identical(voiceGuide, _unsetDocumentValue)
        ? this.voiceGuide
        : voiceGuide as ProjectVoiceGuide?,
    cameraTrack: identical(cameraTrack, _unsetDocumentValue)
        ? this.cameraTrack
        : cameraTrack as ProjectCameraTrack?,
    contentMetadata: contentMetadata ?? this.contentMetadata,
    autoDirectorSettings: autoDirectorSettings ?? this.autoDirectorSettings,
    creationDefaults: creationDefaults ?? this.creationDefaults,
    pathProcessingMetadata:
        identical(pathProcessingMetadata, _unsetDocumentValue)
        ? this.pathProcessingMetadata
        : pathProcessingMetadata as ProjectPathProcessingMetadata?,
    timeline: timeline ?? this.timeline,
  );
}

const _unsetDocumentValue = Object();
