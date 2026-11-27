import 'dart:collection';
import 'dart:ui';

import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_polygon_list.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_rect_list.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';

/// Cached, one-way compatibility view for renderer call sites not migrated yet.
///
/// There is intentionally no reverse operation. ProjectDocument remains the
/// source of truth and a revision change invalidates the cached legacy view.
final class LegacyProjectViewCache {
  EditorDocumentState? _source;
  HandDrawProject? _view;
  int _buildCount = 0;

  int get buildCount => _buildCount;

  HandDrawProject resolve(EditorDocumentState state) {
    if (identical(_source?.document, state.document) &&
        _source?.revision == state.revision &&
        _view != null) {
      return _view!;
    }
    final compiled = _compile(state.document);
    _buildCount++;
    _source = state;
    _view = compiled;
    return compiled;
  }

  HandDrawProject _compile(ProjectDocument document) {
    final assetsById = {for (final asset in document.assets) asset.id: asset};
    final artwork = document.artworkAssetId == null
        ? document.assets
              .where((asset) => asset.kind == ProjectAssetKind.artwork)
              .firstOrNull
        : assetsById[document.artworkAssetId];
    final handAsset = document.handConfiguration.assetId == null
        ? null
        : assetsById[document.handConfiguration.assetId];
    final sceneBySection = {
      for (final scene in document.scenes)
        for (final sectionId in scene.sectionIds) sectionId: scene,
    };
    final sectionsById = {
      for (final section in document.sections) section.id: section,
    };
    final drawingClipMasks =
        HashMap<
          List<List<DocumentPoint>>,
          ImmutablePolygonList<Offset>
        >.identity();
    final drawingExclusionBounds =
        HashMap<List<DocumentRect>, ImmutableRectList>.identity();
    final orderedStrokes = <DrawingStroke>[];
    for (final stroke in document.strokes) {
      final section = sectionsById[stroke.sectionId]!;
      orderedStrokes.add(
        DrawingStroke(
          id: stroke.id.value,
          name: stroke.name,
          sectionId: section.id.value == 'stroke:${stroke.id.value}'
              ? null
              : section.id.value,
          points: [for (final point in stroke.points) Offset(point.x, point.y)],
          geometry: stroke.geometry,
          animationGeometry: stroke.animationGeometry,
          isFilledShape: stroke.isFilledShape,
          isTextShape: stroke.isTextShape,
          isGlobalDecoration: stroke.isGlobalDecoration,
          sceneGroupId: sceneBySection[section.id]?.id.value,
          fillColorValue: stroke.fillColorValue,
          hidden: stroke.hidden,
          reversed: stroke.reversed,
          revealOnly: stroke.revealOnly,
          isPaintStroke: stroke.isPaintStroke,
          paintRegion: stroke.paintRegion,
          revealStyle: stroke.revealStyle == DocumentRevealStyle.directionalWipe
              ? RevealMaskStyle.directionalWipe
              : RevealMaskStyle.brush,
          clipBounds: stroke.clipBounds == null
              ? null
              : Rect.fromLTRB(
                  stroke.clipBounds!.left,
                  stroke.clipBounds!.top,
                  stroke.clipBounds!.right,
                  stroke.clipBounds!.bottom,
                ),
          clipPolygons: stroke.clipPolygons.isEmpty
              ? const []
              : drawingClipMasks.putIfAbsent(
                  stroke.clipPolygons,
                  () => ImmutablePolygonList<Offset>.freeze([
                    for (final polygon in stroke.clipPolygons)
                      [for (final point in polygon) Offset(point.x, point.y)],
                  ]),
                ),
          exclusionBounds: drawingExclusionBounds.putIfAbsent(
            stroke.exclusionBounds,
            () => ImmutableRectList.freeze([
              for (final rect in stroke.exclusionBounds)
                Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom),
            ]),
          ),
          revealWidth: stroke.revealWidth,
          pausePoints: [
            for (final pause in stroke.pausePoints)
              StrokePausePoint(
                id: pause.id.value,
                progress: pause.progress,
                durationSeconds:
                    pause.duration.microseconds /
                    Duration.microsecondsPerSecond,
                keepHandVisible: pause.keepHandVisible,
              ),
          ],
          vectorMaskStrokes: [
            for (final mask in stroke.vectorMaskStrokes)
              VectorMaskStroke(
                geometry: mask.geometry,
                widthFraction: mask.width,
                operation: mask.erase
                    ? VectorMaskOperation.erase
                    : VectorMaskOperation.reveal,
                featherFraction: mask.feather,
                clipToLayer: mask.clipToLayer,
              ),
          ],
        ),
      );
    }
    final seconds =
        document.duration.microseconds / Duration.microsecondsPerSecond;
    return HandDrawProject(
      canvasWidth: document.canvas.width,
      canvasHeight: document.canvas.height,
      canvasBackground: document.canvas.background,
      frameRate: (document.frameRate.numerator / document.frameRate.denominator)
          .round(),
      exportPresetId: document.exportConfiguration.presetId,
      exportAlphaMode: document.exportConfiguration.alphaMode,
      exportRenderQuality: document.exportConfiguration.renderQuality,
      durationSeconds: seconds,
      drawingDurationSeconds:
          document.motionConfiguration.drawingDuration.microseconds /
          Duration.microsecondsPerSecond,
      drawingSpeed: document.motionConfiguration.drawingSpeed,
      penTravelSpeed: document.motionConfiguration.penTravelSpeed,
      startDelaySeconds:
          document.motionConfiguration.startDelay.microseconds /
          Duration.microsecondsPerSecond,
      endHoldSeconds:
          document.motionConfiguration.endHold.microseconds /
          Duration.microsecondsPerSecond,
      revealWidth: document.motionConfiguration.revealWidth,
      imageAnimationEffect: document.motionConfiguration.imageAnimationEffect,
      showDrawingHand: document.motionConfiguration.showDrawingHand,
      handPresetId: document.handConfiguration.presetId,
      handImagePath: handAsset == null ? null : _assetPath(handAsset),
      handScale: document.handConfiguration.scale,
      handRotationDegrees: document.handConfiguration.rotationDegrees,
      handFlipX: document.handConfiguration.flipX,
      penTip: Offset(
        document.handConfiguration.penTip.x,
        document.handConfiguration.penTip.y,
      ),
      writingSoundEnabled: document.writingSoundConfiguration.enabled,
      writingSoundPreset: document.writingSoundConfiguration.preset,
      writingSoundVolume: document.writingSoundConfiguration.volume,
      drawingImagePath: artwork == null ? null : _assetPath(artwork),
      artworkDestination: document.artworkPlacement == null
          ? null
          : Rect.fromLTRB(
              document.artworkPlacement!.destination.left,
              document.artworkPlacement!.destination.top,
              document.artworkPlacement!.destination.right,
              document.artworkPlacement!.destination.bottom,
            ),
      drawingSourceKind: artwork?.artworkSourceType == ArtworkSourceType.svg
          ? ArtworkSourceKind.svg
          : ArtworkSourceKind.raster,
      strokes: orderedStrokes,
      sceneGroups: [
        for (final scene in document.scenes)
          DrawingSceneGroup(
            id: scene.id.value,
            name: scene.name,
            sectionIds: [for (final id in scene.sectionIds) id.value],
            locked: scene.locked,
          ),
      ],
      timelineSectionOrder: [for (final id in document.sectionOrder) id.value],
      sectionTimings: {
        for (final section in document.sections)
          if (!section.timing.isDefault)
            _timingKey(section.id): SectionTiming(
              pauseBeforeEnabled:
                  section.timing.pauseBeforeEnabled ||
                  !section.timing.pauseBefore.isZero,
              pauseBeforeSeconds:
                  section.timing.pauseBefore.microseconds /
                  Duration.microsecondsPerSecond,
              pauseAfterEnabled:
                  section.timing.pauseAfterEnabled ||
                  !section.timing.pauseAfter.isZero,
              pauseAfterSeconds:
                  section.timing.pauseAfter.microseconds /
                  Duration.microsecondsPerSecond,
              animationDurationSeconds:
                  section.timing.animationDuration?.microseconds == null
                  ? null
                  : section.timing.animationDuration!.microseconds /
                        Duration.microsecondsPerSecond,
              transitionAfterSeconds:
                  section.timing.transitionAfter.microseconds /
                  Duration.microsecondsPerSecond,
              speedMultiplier: section.timing.speedMultiplier,
              pauseHandBehavior:
                  section.timing.pauseHandBehavior ==
                      DocumentPauseHandBehavior.hide
                  ? PauseHandBehavior.hide
                  : PauseHandBehavior.keepVisible,
              voiceCueSeconds:
                  section.timing.audioCueAnchor?.sourceMediaTime.microseconds ==
                      null
                  ? null
                  : section
                            .timing
                            .audioCueAnchor!
                            .sourceMediaTime
                            .microseconds /
                        Duration.microsecondsPerSecond,
              handEntranceAnimation: section.timing.handEntranceAnimation,
              handEntranceDurationSeconds:
                  section.timing.handEntranceDuration.microseconds /
                  Duration.microsecondsPerSecond,
              handExitAnimation: section.timing.handExitAnimation,
              handExitDurationSeconds:
                  section.timing.handExitDuration.microseconds /
                  Duration.microsecondsPerSecond,
              keepHandVisibleAfterDrawing:
                  section.timing.keepHandVisibleAfterDrawing,
            ),
      },
      voiceGuide: _voiceGuide(document, assetsById),
    );
  }

  String _timingKey(SectionId id) =>
      id.value.startsWith('stroke:') ? id.value : 'section:${id.value}';

  String? _assetPath(ProjectAsset asset) =>
      asset.storagePolicy == ProjectAssetStoragePolicy.external
      ? asset.externalLocator?.pathHint
      : null;

  VoiceGuide? _voiceGuide(
    ProjectDocument document,
    Map<ProjectAssetId, ProjectAsset> assetsById,
  ) {
    final metadata = document.voiceGuide;
    if (metadata == null) return null;
    final track = document.audioTracks.firstWhere(
      (candidate) => candidate.id == metadata.audioTrackId,
    );
    final asset = assetsById[track.assetId]!;
    return VoiceGuide(
      path: _assetPath(asset) ?? '',
      name: metadata.displayName,
      durationSeconds:
          (asset.mediaDuration ?? track.duration).microseconds /
          Duration.microsecondsPerSecond,
      waveform: const [],
      securityBookmark: asset.externalLocator?.securityBookmark,
    );
  }
}
