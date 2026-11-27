import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_polygon_list.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_rect_list.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';

const _unset = Object();

double _safeProjectRange(
  dynamic raw,
  double minimum,
  double maximum,
  double fallback,
) {
  if (raw is! num) return fallback;
  final value = raw.toDouble();
  if (!value.isFinite) return fallback;
  return value.clamp(minimum, maximum);
}

CanvasBackground _decodeLegacyCanvasBackground(Map<String, dynamic>? raw) {
  if (raw == null) return const CanvasBackground.transparent();
  final mode = CanvasBackgroundMode.values.firstWhere(
    (value) => value.name == raw['mode'],
    orElse: () => CanvasBackgroundMode.transparent,
  );
  return switch (mode) {
    CanvasBackgroundMode.transparent => const CanvasBackground.transparent(),
    CanvasBackgroundMode.solid => CanvasBackground.solid(
      (raw['colorValue'] as num? ?? 0xFFFFFFFF).toInt(),
    ).normalized(),
    CanvasBackgroundMode.preset => CanvasBackground.preset(
      CanvasBackgroundPreset.values.firstWhere(
        (value) => value.name == raw['preset'],
        orElse: () => CanvasBackgroundPreset.warmWhite,
      ),
    ),
  };
}

enum RevealMaskStyle { brush, directionalWipe }

enum PauseHandBehavior { keepVisible, hide }

class DrawingSceneGroup {
  DrawingSceneGroup({
    required this.id,
    required this.name,
    required List<String> sectionIds,
    this.locked = true,
    this.collapsed = false,
  }) : sectionIds = List.unmodifiable(sectionIds);

  final String id;
  final String name;
  final List<String> sectionIds;
  final bool locked;
  final bool collapsed;

  DrawingSceneGroup copyWith({
    String? name,
    List<String>? sectionIds,
    bool? locked,
    bool? collapsed,
  }) => DrawingSceneGroup(
    id: id,
    name: name ?? this.name,
    sectionIds: sectionIds ?? this.sectionIds,
    locked: locked ?? this.locked,
    collapsed: collapsed ?? this.collapsed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sectionIds': sectionIds,
    'locked': locked,
    'collapsed': collapsed,
  };

  factory DrawingSceneGroup.fromJson(Map<String, dynamic> json) =>
      DrawingSceneGroup(
        id: json['id'] as String? ?? 'scene',
        name: json['name'] as String? ?? 'Scene',
        sectionIds: (json['sectionIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        locked: json['locked'] as bool? ?? true,
        collapsed: json['collapsed'] as bool? ?? false,
      );
}

class SectionTiming {
  const SectionTiming({
    this.pauseBeforeEnabled = false,
    this.pauseBeforeSeconds = 0,
    this.pauseAfterEnabled = false,
    this.pauseAfterSeconds = 0,
    this.speedMultiplier = 1,
    this.animationDurationSeconds,
    this.transitionAfterSeconds,
    this.pauseHandBehavior = PauseHandBehavior.keepVisible,
    this.voiceCueSeconds,
    this.handEntranceAnimation = SectionHandEntranceAnimation.none,
    this.handEntranceDurationSeconds = 0,
    this.handExitAnimation = SectionHandExitAnimation.none,
    this.handExitDurationSeconds = 0,
    this.keepHandVisibleAfterDrawing = false,
  });

  final bool pauseBeforeEnabled;
  final double pauseBeforeSeconds;
  final bool pauseAfterEnabled;
  final double pauseAfterSeconds;
  final double speedMultiplier;
  final double? animationDurationSeconds;
  final double? transitionAfterSeconds;
  final PauseHandBehavior pauseHandBehavior;
  final double? voiceCueSeconds;
  final SectionHandEntranceAnimation handEntranceAnimation;
  final double handEntranceDurationSeconds;
  final SectionHandExitAnimation handExitAnimation;
  final double handExitDurationSeconds;
  final bool keepHandVisibleAfterDrawing;

  bool get isDefault =>
      !pauseBeforeEnabled &&
      pauseBeforeSeconds == 0 &&
      !pauseAfterEnabled &&
      pauseAfterSeconds == 0 &&
      speedMultiplier == 1 &&
      animationDurationSeconds == null &&
      transitionAfterSeconds == null &&
      pauseHandBehavior == PauseHandBehavior.keepVisible &&
      voiceCueSeconds == null &&
      handEntranceAnimation == SectionHandEntranceAnimation.none &&
      handEntranceDurationSeconds == 0 &&
      handExitAnimation == SectionHandExitAnimation.none &&
      handExitDurationSeconds == 0 &&
      !keepHandVisibleAfterDrawing;

  SectionTiming copyWith({
    bool? pauseBeforeEnabled,
    double? pauseBeforeSeconds,
    bool? pauseAfterEnabled,
    double? pauseAfterSeconds,
    double? speedMultiplier,
    Object? animationDurationSeconds = _unset,
    Object? transitionAfterSeconds = _unset,
    PauseHandBehavior? pauseHandBehavior,
    Object? voiceCueSeconds = _unset,
    SectionHandEntranceAnimation? handEntranceAnimation,
    double? handEntranceDurationSeconds,
    SectionHandExitAnimation? handExitAnimation,
    double? handExitDurationSeconds,
    bool? keepHandVisibleAfterDrawing,
  }) => SectionTiming(
    pauseBeforeEnabled: pauseBeforeEnabled ?? this.pauseBeforeEnabled,
    pauseBeforeSeconds: pauseBeforeSeconds ?? this.pauseBeforeSeconds,
    pauseAfterEnabled: pauseAfterEnabled ?? this.pauseAfterEnabled,
    pauseAfterSeconds: pauseAfterSeconds ?? this.pauseAfterSeconds,
    speedMultiplier: speedMultiplier ?? this.speedMultiplier,
    animationDurationSeconds: identical(animationDurationSeconds, _unset)
        ? this.animationDurationSeconds
        : animationDurationSeconds as double?,
    transitionAfterSeconds: identical(transitionAfterSeconds, _unset)
        ? this.transitionAfterSeconds
        : transitionAfterSeconds as double?,
    pauseHandBehavior: pauseHandBehavior ?? this.pauseHandBehavior,
    voiceCueSeconds: identical(voiceCueSeconds, _unset)
        ? this.voiceCueSeconds
        : voiceCueSeconds as double?,
    handEntranceAnimation: handEntranceAnimation ?? this.handEntranceAnimation,
    handEntranceDurationSeconds:
        handEntranceDurationSeconds ?? this.handEntranceDurationSeconds,
    handExitAnimation: handExitAnimation ?? this.handExitAnimation,
    handExitDurationSeconds:
        handExitDurationSeconds ?? this.handExitDurationSeconds,
    keepHandVisibleAfterDrawing:
        keepHandVisibleAfterDrawing ?? this.keepHandVisibleAfterDrawing,
  );

  Map<String, dynamic> toJson() => {
    'pauseBeforeEnabled': pauseBeforeEnabled || pauseBeforeSeconds > 0,
    'pauseBeforeSeconds': pauseBeforeSeconds,
    'pauseAfterEnabled': pauseAfterEnabled || pauseAfterSeconds > 0,
    'pauseAfterSeconds': pauseAfterSeconds,
    'speedMultiplier': speedMultiplier,
    'animationDurationSeconds': animationDurationSeconds,
    'transitionAfterSeconds': transitionAfterSeconds,
    'pauseHandBehavior': pauseHandBehavior.name,
    'voiceCueSeconds': voiceCueSeconds,
    'handEntranceAnimation': handEntranceAnimation.name,
    'handEntranceDurationSeconds': handEntranceDurationSeconds,
    'handExitAnimation': handExitAnimation.name,
    'handExitDurationSeconds': handExitDurationSeconds,
    'keepHandVisibleAfterDrawing': keepHandVisibleAfterDrawing,
  };

  factory SectionTiming.fromJson(Map<String, dynamic> json) => SectionTiming(
    pauseBeforeEnabled:
        json['pauseBeforeEnabled'] as bool? ??
        _safeRange(json['pauseBeforeSeconds'], 0, 60, 0) > 0,
    pauseBeforeSeconds: _safeRange(json['pauseBeforeSeconds'], 0, 60, 0),
    pauseAfterEnabled:
        json['pauseAfterEnabled'] as bool? ??
        _safeRange(json['pauseAfterSeconds'], 0, 60, 0) > 0,
    pauseAfterSeconds: _safeRange(json['pauseAfterSeconds'], 0, 60, 0),
    speedMultiplier: _safeRange(json['speedMultiplier'], 0.25, 4, 1),
    animationDurationSeconds: _safeOptionalRange(
      json['animationDurationSeconds'],
      0.05,
      60,
    ),
    transitionAfterSeconds: _safeOptionalRange(
      json['transitionAfterSeconds'],
      0,
      60,
    ),
    pauseHandBehavior: PauseHandBehavior.values.firstWhere(
      (value) => value.name == json['pauseHandBehavior'],
      orElse: () => PauseHandBehavior.keepVisible,
    ),
    voiceCueSeconds: _safeOptionalRange(
      json['voiceCueSeconds'],
      0,
      24 * 60 * 60,
    ),
    handEntranceAnimation: SectionHandEntranceAnimation.values.firstWhere(
      (value) => value.name == json['handEntranceAnimation'],
      orElse: () => SectionHandEntranceAnimation.none,
    ),
    handEntranceDurationSeconds: _safeRange(
      json['handEntranceDurationSeconds'],
      0,
      10,
      0,
    ),
    handExitAnimation: SectionHandExitAnimation.values.firstWhere(
      (value) => value.name == json['handExitAnimation'],
      orElse: () => SectionHandExitAnimation.none,
    ),
    handExitDurationSeconds: _safeRange(
      json['handExitDurationSeconds'],
      0,
      10,
      0,
    ),
    keepHandVisibleAfterDrawing:
        json['keepHandVisibleAfterDrawing'] as bool? ?? false,
  );

  static double? _safeOptionalRange(
    dynamic raw,
    double minimum,
    double maximum,
  ) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    if (!value.isFinite) return null;
    return value.clamp(minimum, maximum);
  }

  static double _safeRange(
    dynamic raw,
    double minimum,
    double maximum,
    double fallback,
  ) {
    final value = raw is num ? raw.toDouble() : fallback;
    if (!value.isFinite) return fallback;
    return value.clamp(minimum, maximum);
  }
}

class DrawingStroke {
  DrawingStroke({
    required this.id,
    required this.name,
    List<Offset>? points,
    this.geometry,
    this.animationGeometry,
    this.isFilledShape = false,
    this.isTextShape = false,
    this.isGlobalDecoration = false,
    this.sceneGroupId,
    this.fillColorValue,
    this.hidden = false,
    this.reversed = false,
    this.revealOnly = false,
    this.isPaintStroke = false,
    this.paintRegion = 0,
    this.revealStyle = RevealMaskStyle.brush,
    this.sectionId,
    this.clipBounds,
    List<List<Offset>> clipPolygons = const [],
    List<Rect> exclusionBounds = const [],
    this.revealWidth,
    List<StrokePausePoint> pausePoints = const [],
    List<VectorMaskStroke> vectorMaskStrokes = const [],
  }) : assert(
         points != null || geometry != null,
         'A stroke requires sampled points or editable geometry.',
       ),
       points = List.unmodifiable(points ?? geometry!.sample()),
       clipPolygons = ImmutablePolygonList<Offset>.freeze(clipPolygons),
       exclusionBounds = ImmutableRectList.freeze(exclusionBounds),
       pausePoints = List.unmodifiable(
         [...pausePoints]..sort((a, b) => a.progress.compareTo(b.progress)),
       ),
       vectorMaskStrokes = List.unmodifiable(vectorMaskStrokes);

  final String id;
  final String name;
  final List<Offset> points;
  final StrokePathGeometry? geometry;
  final StrokePathGeometry? animationGeometry;
  final bool isFilledShape;
  final bool isTextShape;
  final bool isGlobalDecoration;
  final String? sceneGroupId;
  final int? fillColorValue;
  final bool hidden;
  final bool reversed;
  final bool revealOnly;
  final bool isPaintStroke;
  final int paintRegion;
  final RevealMaskStyle revealStyle;
  final String? sectionId;
  final Rect? clipBounds;
  final List<List<Offset>> clipPolygons;
  final List<Rect> exclusionBounds;
  final double? revealWidth;
  final List<StrokePausePoint> pausePoints;
  final List<VectorMaskStroke> vectorMaskStrokes;

  DrawingStroke copyWith({
    String? id,
    String? name,
    List<Offset>? points,
    Object? geometry = _unset,
    Object? animationGeometry = _unset,
    bool? isFilledShape,
    bool? isTextShape,
    bool? isGlobalDecoration,
    Object? sceneGroupId = _unset,
    Object? fillColorValue = _unset,
    bool? hidden,
    bool? reversed,
    bool? revealOnly,
    bool? isPaintStroke,
    int? paintRegion,
    RevealMaskStyle? revealStyle,
    Object? sectionId = _unset,
    Object? clipBounds = _unset,
    List<List<Offset>>? clipPolygons,
    List<Rect>? exclusionBounds,
    Object? revealWidth = _unset,
    List<StrokePausePoint>? pausePoints,
    List<VectorMaskStroke>? vectorMaskStrokes,
  }) {
    return DrawingStroke(
      id: id ?? this.id,
      name: name ?? this.name,
      points: points ?? this.points,
      geometry: identical(geometry, _unset)
          ? this.geometry
          : geometry as StrokePathGeometry?,
      animationGeometry: identical(animationGeometry, _unset)
          ? this.animationGeometry
          : animationGeometry as StrokePathGeometry?,
      isFilledShape: isFilledShape ?? this.isFilledShape,
      isTextShape: isTextShape ?? this.isTextShape,
      isGlobalDecoration: isGlobalDecoration ?? this.isGlobalDecoration,
      sceneGroupId: identical(sceneGroupId, _unset)
          ? this.sceneGroupId
          : sceneGroupId as String?,
      fillColorValue: identical(fillColorValue, _unset)
          ? this.fillColorValue
          : fillColorValue as int?,
      hidden: hidden ?? this.hidden,
      reversed: reversed ?? this.reversed,
      revealOnly: revealOnly ?? this.revealOnly,
      isPaintStroke: isPaintStroke ?? this.isPaintStroke,
      paintRegion: paintRegion ?? this.paintRegion,
      revealStyle: revealStyle ?? this.revealStyle,
      sectionId: identical(sectionId, _unset)
          ? this.sectionId
          : sectionId as String?,
      clipBounds: identical(clipBounds, _unset)
          ? this.clipBounds
          : clipBounds as Rect?,
      clipPolygons: clipPolygons ?? this.clipPolygons,
      exclusionBounds: exclusionBounds ?? this.exclusionBounds,
      revealWidth: identical(revealWidth, _unset)
          ? this.revealWidth
          : revealWidth as double?,
      pausePoints: pausePoints ?? this.pausePoints,
      vectorMaskStrokes: vectorMaskStrokes ?? this.vectorMaskStrokes,
    );
  }

  List<Offset> get orderedPoints {
    final source = animationGeometry?.sample() ?? geometry?.sample() ?? points;
    return reversed ? source.reversed.toList(growable: false) : source;
  }

  StrokePathGeometry? get orderedGeometry =>
      reversed ? geometry?.reversed() : geometry;

  StrokePathGeometry? get orderedAnimationGeometry {
    final source = animationGeometry ?? geometry;
    return reversed ? source?.reversed() : source;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'geometry': geometry?.toJson(),
    'animationGeometry': animationGeometry?.toJson(),
    'isFilledShape': isFilledShape,
    'isTextShape': isTextShape,
    'isGlobalDecoration': isGlobalDecoration,
    'sceneGroupId': sceneGroupId,
    'fillColorValue': fillColorValue,
    'hidden': hidden,
    'reversed': reversed,
    'revealOnly': revealOnly,
    'isPaintStroke': isPaintStroke,
    'paintRegion': paintRegion,
    'revealStyle': revealStyle.name,
    'sectionId': sectionId,
    'clipBounds': clipBounds == null
        ? null
        : [
            clipBounds!.left,
            clipBounds!.top,
            clipBounds!.right,
            clipBounds!.bottom,
          ],
    'clipPolygons': [
      for (final polygon in clipPolygons)
        [
          for (final point in polygon) [point.dx, point.dy],
        ],
    ],
    'exclusionBounds': exclusionBounds
        .map((rect) => [rect.left, rect.top, rect.right, rect.bottom])
        .toList(),
    'revealWidth': revealWidth,
    'pausePoints': pausePoints.map((pause) => pause.toJson()).toList(),
    'vectorMaskStrokes': vectorMaskStrokes
        .map((stroke) => stroke.toJson())
        .toList(),
    'points': points.map((point) => [point.dx, point.dy]).toList(),
  };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List<dynamic>? ?? const []);
    final rawClip = json['clipBounds'] as List<dynamic>?;
    final rawClipPolygons = json['clipPolygons'] as List<dynamic>? ?? const [];
    final rawExclusions = json['exclusionBounds'] as List<dynamic>? ?? const [];
    return DrawingStroke(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Stroke',
      geometry: json['geometry'] is Map
          ? StrokePathGeometry.fromJson(
              Map<String, dynamic>.from(json['geometry'] as Map),
            )
          : null,
      animationGeometry: json['animationGeometry'] is Map
          ? StrokePathGeometry.fromJson(
              Map<String, dynamic>.from(json['animationGeometry'] as Map),
            )
          : null,
      isFilledShape: json['isFilledShape'] as bool? ?? false,
      isTextShape: json['isTextShape'] as bool? ?? false,
      isGlobalDecoration: json['isGlobalDecoration'] as bool? ?? false,
      sceneGroupId: json['sceneGroupId'] as String?,
      fillColorValue: (json['fillColorValue'] as num?)?.toInt(),
      hidden: json['hidden'] as bool? ?? false,
      reversed: json['reversed'] as bool? ?? false,
      revealOnly: json['revealOnly'] as bool? ?? false,
      isPaintStroke: json['isPaintStroke'] as bool? ?? false,
      paintRegion: json['paintRegion'] as int? ?? 0,
      revealStyle: RevealMaskStyle.values.firstWhere(
        (style) => style.name == json['revealStyle'],
        orElse: () => RevealMaskStyle.brush,
      ),
      sectionId: json['sectionId'] as String?,
      clipBounds: rawClip == null
          ? null
          : Rect.fromLTRB(
              (rawClip[0] as num).toDouble(),
              (rawClip[1] as num).toDouble(),
              (rawClip[2] as num).toDouble(),
              (rawClip[3] as num).toDouble(),
            ),
      clipPolygons: [
        for (final rawPolygon in rawClipPolygons)
          [
            for (final rawPoint in rawPolygon as List<dynamic>)
              Offset(
                ((rawPoint as List<dynamic>)[0] as num).toDouble(),
                (rawPoint[1] as num).toDouble(),
              ),
          ],
      ],
      exclusionBounds: rawExclusions
          .map((raw) {
            final values = raw as List<dynamic>;
            return Rect.fromLTRB(
              (values[0] as num).toDouble(),
              (values[1] as num).toDouble(),
              (values[2] as num).toDouble(),
              (values[3] as num).toDouble(),
            );
          })
          .toList(growable: false),
      revealWidth: (json['revealWidth'] as num?)?.toDouble(),
      pausePoints: (json['pausePoints'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StrokePausePoint.fromJson)
          .toList(growable: false),
      vectorMaskStrokes:
          (json['vectorMaskStrokes'] as List<dynamic>? ?? const [])
              .map(
                (raw) => VectorMaskStroke.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList(growable: false),
      points: rawPoints.map((raw) {
        final pair = raw as List<dynamic>;
        return Offset((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList(),
    );
  }
}

class HandDrawProject {
  HandDrawProject({
    this.canvasWidth = 1920,
    this.canvasHeight = 1080,
    this.canvasBackground = const CanvasBackground.transparent(),
    this.frameRate = 30,
    this.exportPresetId = ExportPresetId.presentationHd,
    this.exportAlphaMode = ExportAlphaMode.premultiplied,
    this.exportRenderQuality = ExportRenderQuality.full,
    this.durationSeconds = 6,
    double? drawingDurationSeconds,
    this.drawingSpeed = 1,
    this.penTravelSpeed = 1,
    this.startDelaySeconds = 0.4,
    this.endHoldSeconds = 0.9,
    this.revealWidth = 54,
    this.imageAnimationEffect = 'legacy',
    this.showDrawingHand = true,
    this.handScale = 0.24,
    this.handRotationDegrees = 0,
    this.handFlipX = false,
    this.writingSoundEnabled = false,
    this.writingSoundPreset = WritingSoundPreset.defaultPreset,
    this.writingSoundVolume = 0.65,
    this.handPresetId = 'marker-technical-wheat-right',
    this.drawingImagePath,
    this.artworkDestination,
    this.handImagePath,
    this.drawingImageBase64,
    this.drawingSourceKind = ArtworkSourceKind.raster,
    this.drawingSourceBase64,
    this.drawingRevealBase64,
    this.drawingRevealStrokeBase64,
    this.handImageBase64,
    this.penTip = const Offset(0.114583, 0.485677),
    List<DrawingStroke>? strokes,
    List<DrawingSceneGroup>? sceneGroups,
    List<String>? timelineSectionOrder,
    Map<String, SectionTiming>? sectionTimings,
    this.voiceGuide,
  }) : drawingDurationSeconds =
           drawingDurationSeconds ??
           math.max(
             0.001,
             durationSeconds - startDelaySeconds - endHoldSeconds,
           ),
       strokes = List.unmodifiable(strokes ?? const []),
       sceneGroups = List.unmodifiable(sceneGroups ?? const []),
       timelineSectionOrder = List.unmodifiable(
         timelineSectionOrder ?? const [],
       ),
       sectionTimings = Map.unmodifiable(sectionTimings ?? const {});

  final int canvasWidth;
  final int canvasHeight;
  final CanvasBackground canvasBackground;
  final int frameRate;
  final ExportPresetId exportPresetId;
  final ExportAlphaMode exportAlphaMode;
  final ExportRenderQuality exportRenderQuality;

  /// The nominal time assigned to drawing and natural pen travel at 1×.
  final double drawingDurationSeconds;

  /// Global speed while the pen is touching and revealing the artwork.
  final double durationSeconds;
  final double drawingSpeed;

  /// Global speed while the pen is lifted between two drawing paths.
  /// This is intentionally independent from [drawingSpeed].
  final double penTravelSpeed;
  final double startDelaySeconds;
  final double endHoldSeconds;
  final double revealWidth;
  final String imageAnimationEffect;
  final bool showDrawingHand;
  final double handScale;
  final double handRotationDegrees;
  final bool handFlipX;
  final bool writingSoundEnabled;
  final WritingSoundPreset writingSoundPreset;
  final double writingSoundVolume;
  final String? handPresetId;
  final String? drawingImagePath;

  /// Project-canvas coordinates; independent from preview viewport/camera.
  final Rect? artworkDestination;
  final String? handImagePath;
  final String? drawingImageBase64;
  final ArtworkSourceKind drawingSourceKind;

  /// Original imported bytes. SVG keeps its XML here so native geometry can
  /// be rebuilt after reopening a project; raster files keep their image bytes.
  final String? drawingSourceBase64;
  final String? drawingRevealBase64;
  final String? drawingRevealStrokeBase64;
  final String? handImageBase64;
  final Offset penTip;
  final List<DrawingStroke> strokes;
  final List<DrawingSceneGroup> sceneGroups;

  /// The user-visible Auto Path timeline order. It remains independent from
  /// generated stroke IDs so native SVG and raster paths share one contract.
  /// Old projects leave it empty and therefore preserve their stroke order.
  final List<String> timelineSectionOrder;
  final Map<String, SectionTiming> sectionTimings;
  final VoiceGuide? voiceGuide;

  HandDrawProject copyWith({
    int? canvasWidth,
    int? canvasHeight,
    CanvasBackground? canvasBackground,
    int? frameRate,
    ExportPresetId? exportPresetId,
    ExportAlphaMode? exportAlphaMode,
    ExportRenderQuality? exportRenderQuality,
    double? durationSeconds,
    double? drawingDurationSeconds,
    double? drawingSpeed,
    double? penTravelSpeed,
    double? startDelaySeconds,
    double? endHoldSeconds,
    double? revealWidth,
    String? imageAnimationEffect,
    bool? showDrawingHand,
    double? handScale,
    double? handRotationDegrees,
    bool? handFlipX,
    bool? writingSoundEnabled,
    WritingSoundPreset? writingSoundPreset,
    double? writingSoundVolume,
    Object? handPresetId = _unset,
    Object? drawingImagePath = _unset,
    Object? artworkDestination = _unset,
    Object? handImagePath = _unset,
    Object? drawingImageBase64 = _unset,
    ArtworkSourceKind? drawingSourceKind,
    Object? drawingSourceBase64 = _unset,
    Object? drawingRevealBase64 = _unset,
    Object? drawingRevealStrokeBase64 = _unset,
    Object? handImageBase64 = _unset,
    Offset? penTip,
    List<DrawingStroke>? strokes,
    List<DrawingSceneGroup>? sceneGroups,
    List<String>? timelineSectionOrder,
    Map<String, SectionTiming>? sectionTimings,
    Object? voiceGuide = _unset,
  }) {
    return HandDrawProject(
      canvasWidth: canvasWidth ?? this.canvasWidth,
      canvasHeight: canvasHeight ?? this.canvasHeight,
      canvasBackground: canvasBackground ?? this.canvasBackground,
      frameRate: frameRate ?? this.frameRate,
      exportPresetId: exportPresetId ?? this.exportPresetId,
      exportAlphaMode: exportAlphaMode ?? this.exportAlphaMode,
      exportRenderQuality: exportRenderQuality ?? this.exportRenderQuality,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      drawingDurationSeconds:
          drawingDurationSeconds ?? this.drawingDurationSeconds,
      drawingSpeed: drawingSpeed ?? this.drawingSpeed,
      penTravelSpeed: penTravelSpeed ?? this.penTravelSpeed,
      startDelaySeconds: startDelaySeconds ?? this.startDelaySeconds,
      endHoldSeconds: endHoldSeconds ?? this.endHoldSeconds,
      revealWidth: revealWidth ?? this.revealWidth,
      imageAnimationEffect: imageAnimationEffect ?? this.imageAnimationEffect,
      showDrawingHand: showDrawingHand ?? this.showDrawingHand,
      handScale: handScale ?? this.handScale,
      handRotationDegrees: handRotationDegrees ?? this.handRotationDegrees,
      handFlipX: handFlipX ?? this.handFlipX,
      writingSoundEnabled: writingSoundEnabled ?? this.writingSoundEnabled,
      writingSoundPreset: writingSoundPreset ?? this.writingSoundPreset,
      writingSoundVolume: writingSoundVolume ?? this.writingSoundVolume,
      handPresetId: identical(handPresetId, _unset)
          ? this.handPresetId
          : handPresetId as String?,
      drawingImagePath: identical(drawingImagePath, _unset)
          ? this.drawingImagePath
          : drawingImagePath as String?,
      artworkDestination: identical(artworkDestination, _unset)
          ? this.artworkDestination
          : artworkDestination as Rect?,
      handImagePath: identical(handImagePath, _unset)
          ? this.handImagePath
          : handImagePath as String?,
      drawingImageBase64: identical(drawingImageBase64, _unset)
          ? this.drawingImageBase64
          : drawingImageBase64 as String?,
      drawingSourceKind: drawingSourceKind ?? this.drawingSourceKind,
      drawingSourceBase64: identical(drawingSourceBase64, _unset)
          ? this.drawingSourceBase64
          : drawingSourceBase64 as String?,
      drawingRevealBase64: identical(drawingRevealBase64, _unset)
          ? this.drawingRevealBase64
          : drawingRevealBase64 as String?,
      drawingRevealStrokeBase64: identical(drawingRevealStrokeBase64, _unset)
          ? this.drawingRevealStrokeBase64
          : drawingRevealStrokeBase64 as String?,
      handImageBase64: identical(handImageBase64, _unset)
          ? this.handImageBase64
          : handImageBase64 as String?,
      penTip: penTip ?? this.penTip,
      strokes: strokes ?? this.strokes,
      sceneGroups: sceneGroups ?? this.sceneGroups,
      timelineSectionOrder: timelineSectionOrder ?? this.timelineSectionOrder,
      sectionTimings: sectionTimings ?? this.sectionTimings,
      voiceGuide: identical(voiceGuide, _unset)
          ? this.voiceGuide
          : voiceGuide as VoiceGuide?,
    );
  }

  /// Changes the legacy nominal duration while preserving independent holds.
  ///
  /// New UI uses [drawingSpeed]. This method remains for project migrations
  /// and integrations that still set a nominal duration directly.
  HandDrawProject retimed(double newDurationSeconds) {
    if (!newDurationSeconds.isFinite || newDurationSeconds <= 0) {
      throw ArgumentError.value(
        newDurationSeconds,
        'newDurationSeconds',
        'Duration must be a positive finite number.',
      );
    }
    return copyWith(
      durationSeconds: newDurationSeconds,
      drawingDurationSeconds: math.max(
        0.001,
        newDurationSeconds - startDelaySeconds - endHoldSeconds,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 22,
    'canvas': {
      'width': canvasWidth,
      'height': canvasHeight,
      'background': {
        'mode': canvasBackground.mode.name,
        'colorValue': canvasBackground.colorValue,
        'preset': canvasBackground.preset?.name,
      },
    },
    'frameRate': frameRate,
    'exportPresetId': exportPresetId.name,
    'exportAlphaMode': exportAlphaMode.name,
    'exportRenderQuality': exportRenderQuality.name,
    'durationSeconds': durationSeconds,
    'drawingDurationSeconds': drawingDurationSeconds,
    'drawingSpeed': drawingSpeed,
    'penTravelSpeed': penTravelSpeed,
    'startDelaySeconds': startDelaySeconds,
    'endHoldSeconds': endHoldSeconds,
    'revealWidth': revealWidth,
    'imageAnimationEffect': imageAnimationEffect,
    'showDrawingHand': showDrawingHand,
    'handScale': handScale,
    'handRotationDegrees': handRotationDegrees,
    'handFlipX': handFlipX,
    'writingSoundEnabled': writingSoundEnabled,
    'writingSoundPreset': writingSoundPreset.name,
    'writingSoundVolume': writingSoundVolume,
    'handPresetId': handPresetId,
    'drawingImagePath': drawingImagePath,
    'artworkDestination': artworkDestination == null
        ? null
        : [
            artworkDestination!.left,
            artworkDestination!.top,
            artworkDestination!.right,
            artworkDestination!.bottom,
          ],
    'handImagePath': handImagePath,
    'drawingImageBase64': drawingImageBase64,
    'drawingSourceKind': drawingSourceKind.name,
    'drawingSourceBase64': drawingSourceBase64,
    'drawingRevealBase64': drawingRevealBase64,
    'drawingRevealStrokeBase64': drawingRevealStrokeBase64,
    'handImageBase64': handImageBase64,
    'penTip': [penTip.dx, penTip.dy],
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    'sceneGroups': sceneGroups.map((group) => group.toJson()).toList(),
    'timelineSectionOrder': timelineSectionOrder,
    'sectionTimings': sectionTimings.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'voiceGuide': voiceGuide?.toJson(),
  };

  factory HandDrawProject.fromJson(Map<String, dynamic> json) {
    final canvas = json['canvas'] as Map<String, dynamic>? ?? const {};
    final rawBackground = canvas['background'] as Map<String, dynamic>?;
    final handPresetId = json['handPresetId'] as String?;
    final hasCustomHand =
        json['handImagePath'] != null || json['handImageBase64'] != null;
    final usesDefaultTechnicalPen =
        handPresetId == 'marker-technical-wheat-right' ||
        (handPresetId == null && !hasCustomHand);
    final rawPenTip =
        json['penTip'] as List<dynamic>? ??
        (usesDefaultTechnicalPen
            ? const [0.114583, 0.485677]
            : const [0.18, 0.72]);
    final rawStrokes = json['strokes'] as List<dynamic>? ?? const [];
    final rawSceneGroups = json['sceneGroups'] as List<dynamic>? ?? const [];
    final rawTimelineOrder =
        json['timelineSectionOrder'] as List<dynamic>? ?? const [];
    final rawSectionTimings =
        json['sectionTimings'] as Map<String, dynamic>? ?? const {};
    final rawVoiceGuide = json['voiceGuide'] as Map<String, dynamic>?;
    final rawArtworkDestination = json['artworkDestination'] as List<dynamic>?;
    return HandDrawProject(
      canvasWidth: (canvas['width'] as num? ?? 1920).toInt(),
      canvasHeight: (canvas['height'] as num? ?? 1080).toInt(),
      canvasBackground: _decodeLegacyCanvasBackground(rawBackground),
      frameRate: (json['frameRate'] as num? ?? 30).toInt(),
      exportPresetId: ExportPresetId.values.firstWhere(
        (value) => value.name == json['exportPresetId'],
        orElse: () => ExportPresetId.custom,
      ),
      exportAlphaMode: ExportAlphaMode.values.firstWhere(
        (value) => value.name == json['exportAlphaMode'],
        orElse: () => ExportAlphaMode.premultiplied,
      ),
      exportRenderQuality: ExportRenderQuality.values.firstWhere(
        (value) => value.name == json['exportRenderQuality'],
        orElse: () => ExportRenderQuality.full,
      ),
      durationSeconds: (json['durationSeconds'] as num? ?? 6).toDouble(),
      drawingDurationSeconds: json['drawingDurationSeconds'] is num
          ? (json['drawingDurationSeconds'] as num).toDouble()
          : null,
      drawingSpeed: _safeProjectRange(json['drawingSpeed'], 0.25, 8, 1),
      penTravelSpeed: _safeProjectRange(json['penTravelSpeed'], 0.25, 4, 1),
      startDelaySeconds: (json['startDelaySeconds'] as num? ?? 0.4).toDouble(),
      endHoldSeconds: (json['endHoldSeconds'] as num? ?? 0.9).toDouble(),
      revealWidth: (json['revealWidth'] as num? ?? 54).toDouble(),
      imageAnimationEffect: json['imageAnimationEffect'] as String? ?? 'legacy',
      showDrawingHand: json['showDrawingHand'] as bool? ?? true,
      handScale: (json['handScale'] as num? ?? 0.24).toDouble(),
      handRotationDegrees: (json['handRotationDegrees'] as num? ?? 0)
          .toDouble(),
      handFlipX: json['handFlipX'] as bool? ?? false,
      writingSoundEnabled: json['writingSoundEnabled'] as bool? ?? false,
      writingSoundPreset: WritingSoundPreset.fromName(
        json['writingSoundPreset'] as String?,
      ),
      writingSoundVolume: (json['writingSoundVolume'] as num? ?? 0.65)
          .toDouble(),
      handPresetId: handPresetId,
      drawingImagePath: json['drawingImagePath'] as String?,
      artworkDestination: rawArtworkDestination == null
          ? null
          : Rect.fromLTRB(
              (rawArtworkDestination[0] as num).toDouble(),
              (rawArtworkDestination[1] as num).toDouble(),
              (rawArtworkDestination[2] as num).toDouble(),
              (rawArtworkDestination[3] as num).toDouble(),
            ),
      handImagePath: json['handImagePath'] as String?,
      drawingImageBase64: json['drawingImageBase64'] as String?,
      drawingSourceKind: ArtworkSourceKind.values.firstWhere(
        (value) => value.name == json['drawingSourceKind'],
        orElse: () => ArtworkSourceKind.raster,
      ),
      drawingSourceBase64: json['drawingSourceBase64'] as String?,
      drawingRevealBase64: json['drawingRevealBase64'] as String?,
      drawingRevealStrokeBase64: json['drawingRevealStrokeBase64'] as String?,
      handImageBase64: json['handImageBase64'] as String?,
      penTip: Offset(
        (rawPenTip[0] as num).toDouble(),
        (rawPenTip[1] as num).toDouble(),
      ),
      strokes: rawStrokes
          .map((raw) => DrawingStroke.fromJson(raw as Map<String, dynamic>))
          .toList(),
      sceneGroups: rawSceneGroups
          .map(
            (raw) => DrawingSceneGroup.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList(growable: false),
      timelineSectionOrder: rawTimelineOrder.whereType<String>().toList(
        growable: false,
      ),
      sectionTimings: rawSectionTimings.map(
        (key, raw) => MapEntry(
          key,
          SectionTiming.fromJson(Map<String, dynamic>.from(raw as Map)),
        ),
      ),
      voiceGuide: rawVoiceGuide == null
          ? null
          : VoiceGuide.fromJson(rawVoiceGuide),
    );
  }
}
