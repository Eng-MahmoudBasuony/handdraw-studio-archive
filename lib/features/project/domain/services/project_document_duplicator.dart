import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';

/// Deeply duplicates persistent entities and rewrites every internal reference.
final class ProjectDocumentDuplicator {
  const ProjectDocumentDuplicator({
    this.validator = const ProjectDocumentValidator(),
  });

  final ProjectDocumentValidator validator;

  ProjectDocument duplicate(
    ProjectDocument source, {
    required IdGenerator ids,
    String? title,
  }) {
    validator.validate(source).throwIfInvalid();
    final allocation = IdAllocationContext(
      generator: ids,
      usedIds: [
        source.id,
        ...source.assets.map((item) => item.id),
        ...source.strokes.map((item) => item.id),
        ...source.strokes.expand(
          (item) => item.pausePoints.map((pause) => pause.id),
        ),
        ...source.sections.map((item) => item.id),
        ...source.scenes.map((item) => item.id),
        ...source.audioTracks.map((item) => item.id),
        if (source.cameraTrack case final track?) track.id,
        if (source.cameraTrack case final track?)
          ...track.shots.map((item) => item.id),
        if (source.cameraTrack case final track?)
          ...track.shots.expand(
            (item) => item.keyframes.map((keyframe) => keyframe.id),
          ),
      ],
    );
    return duplicateWithAllocation(
      source,
      allocation: allocation,
      title: title,
    );
  }

  ProjectDocument duplicateWithAllocation(
    ProjectDocument source, {
    required IdAllocationContext allocation,
    String? title,
  }) {
    validator.validate(source).throwIfInvalid();
    final assetIds = <ProjectAssetId, ProjectAssetId>{
      for (final asset in source.assets) asset.id: allocation.projectAssetId(),
    };
    final strokeIds = <StrokeId, StrokeId>{
      for (final stroke in source.strokes) stroke.id: allocation.strokeId(),
    };
    final pauseIds = <StrokePauseId, StrokePauseId>{
      for (final pause in source.strokes.expand((item) => item.pausePoints))
        pause.id: allocation.strokePauseId(),
    };
    final sectionIds = <SectionId, SectionId>{
      for (final section in source.sections) section.id: allocation.sectionId(),
    };
    final sceneIds = <SceneId, SceneId>{
      for (final scene in source.scenes) scene.id: allocation.sceneId(),
    };
    final audioTrackIds = <AudioTrackId, AudioTrackId>{
      for (final track in source.audioTracks)
        track.id: allocation.audioTrackId(),
    };
    final cameraTrackId = source.cameraTrack == null
        ? null
        : allocation.cameraTrackId();
    final cameraShotIds = <CameraShotId, CameraShotId>{
      for (final shot in source.cameraTrack?.shots ?? const <CameraShot>[])
        shot.id: allocation.cameraShotId(),
    };
    final cameraKeyframeIds = <CameraKeyframeId, CameraKeyframeId>{
      for (final keyframe
          in source.cameraTrack?.shots.expand((shot) => shot.keyframes) ??
              const <CameraKeyframe>[])
        keyframe.id: allocation.cameraKeyframeId(),
    };

    final duplicate = ProjectDocument(
      id: allocation.projectId(),
      title: title ?? '${source.title} Copy',
      canvas: source.canvas,
      frameRate: source.frameRate,
      duration: source.duration,
      creationDefaults: source.creationDefaults,
      pathProcessingMetadata: source.pathProcessingMetadata,
      artworkAssetId: source.artworkAssetId == null
          ? null
          : assetIds[source.artworkAssetId]!,
      exportConfiguration: source.exportConfiguration,
      motionConfiguration: source.motionConfiguration,
      handConfiguration: ProjectHandConfiguration(
        assetId: source.handConfiguration.assetId == null
            ? null
            : assetIds[source.handConfiguration.assetId]!,
        presetId: source.handConfiguration.presetId,
        scale: source.handConfiguration.scale,
        rotationDegrees: source.handConfiguration.rotationDegrees,
        flipX: source.handConfiguration.flipX,
        penTip: source.handConfiguration.penTip,
      ),
      writingSoundConfiguration: source.writingSoundConfiguration,
      cameraTrack: source.cameraTrack == null
          ? null
          : ProjectCameraTrack(
              id: cameraTrackId!,
              enabled: source.cameraTrack!.enabled,
              defaultView: source.cameraTrack!.defaultView,
              shots: [
                for (final shot in source.cameraTrack!.shots)
                  CameraShot(
                    id: cameraShotIds[shot.id]!,
                    startTime: shot.startTime,
                    duration: shot.duration,
                    authorship: shot.authorship,
                    isLocked: shot.isLocked,
                    label: shot.label,
                    ownerSceneId: shot.ownerSceneId == null
                        ? null
                        : sceneIds[shot.ownerSceneId],
                    sceneConnection: shot.sceneConnection,
                    keyframes: [
                      for (final keyframe in shot.keyframes)
                        CameraKeyframe(
                          id: cameraKeyframeIds[keyframe.id]!,
                          offset: keyframe.offset,
                          view: keyframe.view,
                          incomingTransition: keyframe.incomingTransition,
                        ),
                    ],
                  ),
              ],
            ),
      assets: [
        for (final asset in source.assets)
          ProjectAsset(
            id: assetIds[asset.id]!,
            kind: asset.kind,
            originalFileName: asset.originalFileName,
            storagePolicy: asset.storagePolicy,
            contentHash: asset.contentHash,
            mediaType: asset.mediaType,
            artworkSourceType: asset.artworkSourceType,
            externalLocator: asset.externalLocator,
            mediaDuration: asset.mediaDuration,
          ),
      ],
      strokes: [
        for (final stroke in source.strokes)
          ProjectStroke(
            id: strokeIds[stroke.id]!,
            sectionId: sectionIds[stroke.sectionId]!,
            name: stroke.name,
            points: stroke.points,
            assetId: stroke.assetId == null ? null : assetIds[stroke.assetId]!,
            geometry: stroke.geometry,
            animationGeometry: stroke.animationGeometry,
            isFilledShape: stroke.isFilledShape,
            isTextShape: stroke.isTextShape,
            isGlobalDecoration: stroke.isGlobalDecoration,
            fillColorValue: stroke.fillColorValue,
            hidden: stroke.hidden,
            reversed: stroke.reversed,
            revealOnly: stroke.revealOnly,
            revealStyle: stroke.revealStyle,
            clipBounds: stroke.clipBounds,
            clipPolygons: stroke.clipPolygons,
            exclusionBounds: stroke.exclusionBounds,
            revealWidth: stroke.revealWidth,
            pausePoints: [
              for (final pause in stroke.pausePoints)
                DocumentStrokePause(
                  id: pauseIds[pause.id]!,
                  progress: pause.progress,
                  duration: pause.duration,
                  keepHandVisible: pause.keepHandVisible,
                ),
            ],
            vectorMaskStrokes: stroke.vectorMaskStrokes,
          ),
      ],
      sections: [
        for (final section in source.sections)
          ProjectSection(
            id: sectionIds[section.id]!,
            name: section.name,
            strokeIds: [for (final id in section.strokeIds) strokeIds[id]!],
            assetId: section.assetId == null
                ? null
                : assetIds[section.assetId]!,
            timing: DocumentSectionTiming(
              animationDuration: section.timing.animationDuration,
              pauseBefore: section.timing.pauseBefore,
              pauseBeforeEnabled: section.timing.pauseBeforeEnabled,
              pauseAfter: section.timing.pauseAfter,
              pauseAfterEnabled: section.timing.pauseAfterEnabled,
              transitionAfter: section.timing.transitionAfter,
              speedMultiplier: section.timing.speedMultiplier,
              pauseHandBehavior: section.timing.pauseHandBehavior,
              audioCueAnchor: section.timing.audioCueAnchor == null
                  ? null
                  : AudioCueAnchor(
                      audioTrackId:
                          audioTrackIds[section
                              .timing
                              .audioCueAnchor!
                              .audioTrackId]!,
                      sourceMediaTime:
                          section.timing.audioCueAnchor!.sourceMediaTime,
                    ),
              handEntranceAnimation: section.timing.handEntranceAnimation,
              handEntranceDuration: section.timing.handEntranceDuration,
              handExitAnimation: section.timing.handExitAnimation,
              handExitDuration: section.timing.handExitDuration,
              keepHandVisibleAfterDrawing:
                  section.timing.keepHandVisibleAfterDrawing,
            ),
          ),
      ],
      sectionOrder: [for (final id in source.sectionOrder) sectionIds[id]!],
      scenes: [
        for (final scene in source.scenes)
          ProjectScene(
            id: sceneIds[scene.id]!,
            name: scene.name,
            sectionIds: [for (final id in scene.sectionIds) sectionIds[id]!],
            locked: scene.locked,
          ),
      ],
      audioTracks: [
        for (final track in source.audioTracks)
          ProjectAudioTrack(
            id: audioTrackIds[track.id]!,
            assetId: assetIds[track.assetId]!,
            start: track.start,
            duration: track.duration,
            exportPolicy: track.exportPolicy,
            sourceOffset: track.sourceOffset,
            muted: track.muted,
            affectsTimelineDuration: track.affectsTimelineDuration,
          ),
      ],
      voiceGuide: source.voiceGuide == null
          ? null
          : ProjectVoiceGuide(
              audioTrackId: audioTrackIds[source.voiceGuide!.audioTrackId]!,
              displayName: source.voiceGuide!.displayName,
              originalFileName: source.voiceGuide!.originalFileName,
            ),
      timeline: PersistentTimeline(
        drawing: source.timeline.drawing,
        camera: source.timeline.camera.enabled
            ? PersistentCameraTimelineTrack.enabled(
                cameraTrackId: cameraTrackId!,
              )
            : const PersistentCameraTimelineTrack.disabled(),
        audio: [
          for (final track in source.timeline.audio)
            PersistentAudioTimelineTrack(
              audioTrackId: audioTrackIds[track.audioTrackId]!,
            ),
        ],
        voiceGuide: source.timeline.voiceGuide == null
            ? null
            : PersistentVoiceGuideTimelineTrack(
                audioTrackId:
                    audioTrackIds[source.timeline.voiceGuide!.audioTrackId]!,
              ),
        sceneMarkers: [
          for (final marker in source.timeline.sceneMarkers)
            PersistentSceneMarker(
              sceneId: sceneIds[marker.sceneId]!,
              time: marker.time,
            ),
        ],
        leadingHold: source.timeline.leadingHold,
        trailingHold: source.timeline.trailingHold,
      ),
      contentMetadata: ProjectContentMetadata(
        projectLocaleHint: source.contentMetadata.projectLocaleHint,
        entities: [
          for (final entity in source.contentMetadata.entities)
            EntitySemanticMetadata(
              target: _rebindSemanticTarget(
                entity.target,
                assetIds: assetIds,
                strokeIds: strokeIds,
                sectionIds: sectionIds,
                sceneIds: sceneIds,
              ),
              contentRole: entity.contentRole,
              textMetadata: entity.textMetadata,
              importance: entity.importance,
              keepTogether: entity.keepTogether,
              cameraExcluded: entity.cameraExcluded,
              textSensitive: entity.textSensitive,
              minimumPreferredZoom: entity.minimumPreferredZoom,
              provenance: entity.provenance,
            ),
        ],
      ),
    );
    validator.validate(duplicate).throwIfInvalid();
    return duplicate;
  }
}

SemanticTargetReference _rebindSemanticTarget(
  SemanticTargetReference target, {
  required Map<ProjectAssetId, ProjectAssetId> assetIds,
  required Map<StrokeId, StrokeId> strokeIds,
  required Map<SectionId, SectionId> sectionIds,
  required Map<SceneId, SceneId> sceneIds,
}) => switch (target.kind) {
  SemanticTargetKind.stroke => SemanticTargetReference.stroke(
    strokeIds[StrokeId(target.value)]!,
  ),
  SemanticTargetKind.section => SemanticTargetReference.section(
    sectionIds[SectionId(target.value)]!,
  ),
  SemanticTargetKind.scene => SemanticTargetReference.scene(
    sceneIds[SceneId(target.value)]!,
  ),
  SemanticTargetKind.asset => SemanticTargetReference.asset(
    assetIds[ProjectAssetId(target.value)]!,
  ),
};
