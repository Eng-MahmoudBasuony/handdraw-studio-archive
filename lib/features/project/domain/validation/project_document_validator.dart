import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/domain/policies/project_limits.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/policies/camera_limits.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';

enum ProjectDocumentIssueCode {
  duplicateId,
  duplicateReference,
  missingReference,
  inconsistentReference,
  invalidCanvas,
  invalidPoint,
  invalidValue,
  durationLimitExceeded,
  audioOutsideProject,
}

final class ProjectDocumentIssue {
  const ProjectDocumentIssue(this.code, this.message);

  final ProjectDocumentIssueCode code;
  final String message;
}

final class ProjectDocumentValidation {
  ProjectDocumentValidation(List<ProjectDocumentIssue> issues)
    : issues = List.unmodifiable(issues);

  final List<ProjectDocumentIssue> issues;
  bool get isValid => issues.isEmpty;

  void throwIfInvalid() {
    if (isValid) return;
    throw ProjectDocumentValidationException(issues);
  }
}

final class ProjectDocumentValidationException implements Exception {
  ProjectDocumentValidationException(this.issues);

  final List<ProjectDocumentIssue> issues;

  @override
  String toString() =>
      'Invalid ProjectDocument: ${issues.map((i) => i.message).join('; ')}';
}

final class ProjectDocumentValidator {
  const ProjectDocumentValidator();

  ProjectDocumentValidation validate(ProjectDocument document) {
    final issues = <ProjectDocumentIssue>[];
    if (document.canvas.width <= 0 || document.canvas.height <= 0) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.invalidCanvas,
          'Canvas dimensions must be positive.',
        ),
      );
    }
    if (!document.canvas.background.isTransparent &&
        !document.canvas.background.isOpaque) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.invalidCanvas,
          'Canvas backgrounds must be fully opaque or transparent.',
        ),
      );
    }
    if (!ProjectLimits.supportsDuration(document.duration)) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.durationLimitExceeded,
          'Project duration exceeds the supported 24-hour limit.',
        ),
      );
    }

    final assetIds = _uniqueIds(
      document.assets.map((asset) => asset.id),
      'asset',
      issues,
    );
    final assetsById = {for (final asset in document.assets) asset.id: asset};
    final strokeIds = _uniqueIds(
      document.strokes.map((stroke) => stroke.id),
      'stroke',
      issues,
    );
    final strokesById = {
      for (final stroke in document.strokes) stroke.id: stroke,
    };
    _uniqueIds(
      document.strokes.expand(
        (stroke) => stroke.pausePoints.map((pause) => pause.id),
      ),
      'stroke pause',
      issues,
    );
    final sectionIds = _uniqueIds(
      document.sections.map((section) => section.id),
      'section',
      issues,
    );
    final sceneIds = _uniqueIds(
      document.scenes.map((scene) => scene.id),
      'scene',
      issues,
    );
    _uniqueIds(
      document.audioTracks.map((track) => track.id),
      'audio track',
      issues,
    );
    _validateCamera(document, issues);
    _validateSemanticMetadata(
      document,
      strokeIds: strokeIds,
      sectionIds: sectionIds,
      sceneIds: sceneIds,
      assetIds: assetIds,
      issues: issues,
    );
    _requireAsset(document.artworkAssetId, assetIds, 'Artwork', issues);
    _requireAsset(
      document.handConfiguration.assetId,
      assetIds,
      'Hand configuration',
      issues,
    );
    _requireAssetKind(
      document.artworkAssetId,
      ProjectAssetKind.artwork,
      assetsById,
      'Artwork',
      issues,
    );
    if (document.pathProcessingMetadata case final metadata?) {
      final artwork = document.artworkAssetId == null
          ? null
          : assetsById[document.artworkAssetId];
      if (metadata.engineId.trim().isEmpty ||
          metadata.algorithmVersion <= 0 ||
          metadata.sourceAssetHash.trim().isEmpty ||
          !metadata.suspectedFrameConfidenceThreshold.isFinite ||
          metadata.suspectedFrameConfidenceThreshold < 0 ||
          metadata.suspectedFrameConfidenceThreshold > 1 ||
          artwork == null ||
          artwork.contentHash != metadata.sourceAssetHash) {
        issues.add(
          const ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Path processing metadata must identify the current artwork and a valid algorithm configuration.',
          ),
        );
      }
    }
    if (document.artworkPlacement case final placement?) {
      final rects = [
        placement.encodedBounds,
        placement.visibleBounds,
        placement.destination,
      ];
      if (document.artworkAssetId == null ||
          rects.any(
            (rect) =>
                !rect.left.isFinite ||
                !rect.top.isFinite ||
                !rect.right.isFinite ||
                !rect.bottom.isFinite ||
                rect.right <= rect.left ||
                rect.bottom <= rect.top,
          )) {
        issues.add(
          const ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Artwork placement requires an artwork asset and positive finite bounds.',
          ),
        );
      }
    }
    _requireAssetKind(
      document.handConfiguration.assetId,
      ProjectAssetKind.hand,
      assetsById,
      'Hand configuration',
      issues,
    );
    final numericConfiguration = [
      document.motionConfiguration.drawingSpeed,
      document.motionConfiguration.penTravelSpeed,
      document.motionConfiguration.revealWidth,
      document.handConfiguration.scale,
    ];
    if (numericConfiguration.any((value) => !value.isFinite || value <= 0) ||
        !document.handConfiguration.rotationDegrees.isFinite ||
        !document.writingSoundConfiguration.volume.isFinite ||
        document.writingSoundConfiguration.volume < 0 ||
        document.writingSoundConfiguration.volume > 1) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.invalidValue,
          'Project configuration contains an invalid numeric value.',
        ),
      );
    }

    for (final asset in document.assets) {
      if (asset.originalFileName.trim().isEmpty ||
          asset.contentHash.trim().isEmpty) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Asset ${asset.id} requires a filename and content hash.',
          ),
        );
      }
      if (asset.kind == ProjectAssetKind.artwork &&
          asset.artworkSourceType == null) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Artwork asset ${asset.id} requires an SVG or raster source type.',
          ),
        );
      }
      switch (asset.storagePolicy) {
        case ProjectAssetStoragePolicy.embedded:
          if (asset.externalLocator != null) {
            issues.add(
              ProjectDocumentIssue(
                ProjectDocumentIssueCode.inconsistentReference,
                'Embedded asset ${asset.id} cannot have an external locator.',
              ),
            );
          }
        case ProjectAssetStoragePolicy.external:
          final locator = asset.externalLocator;
          if (locator == null ||
              locator.pathHint.trim().isEmpty ||
              locator.pathHint.contains(r'\')) {
            issues.add(
              ProjectDocumentIssue(
                ProjectDocumentIssueCode.inconsistentReference,
                'External asset ${asset.id} requires only a valid external locator.',
              ),
            );
          }
      }
    }

    for (final stroke in document.strokes) {
      if (!sectionIds.contains(stroke.sectionId)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Stroke ${stroke.id} references missing section ${stroke.sectionId}.',
          ),
        );
      }
      final assetId = stroke.assetId;
      if (assetId != null && !assetIds.contains(assetId)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Stroke ${stroke.id} references missing asset $assetId.',
          ),
        );
      }
      if (stroke.points.any(
        (point) => !point.x.isFinite || !point.y.isFinite,
      )) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Stroke ${stroke.id} contains a non-finite point.',
          ),
        );
      }
      for (final polygon in stroke.clipPolygons) {
        final malformed =
            polygon.length < 3 ||
            polygon.any(
              (point) =>
                  !point.x.isFinite ||
                  !point.y.isFinite ||
                  point.x < 0 ||
                  point.x > 1 ||
                  point.y < 0 ||
                  point.y > 1,
            );
        if (malformed) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.invalidValue,
              'Stroke ${stroke.id} contains an invalid scene clip polygon.',
            ),
          );
        }
      }
      if (stroke.revealWidth case final width?
          when !width.isFinite || width <= 0) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidPoint,
            'Stroke ${stroke.id} has an invalid reveal width.',
          ),
        );
      }
      for (final pause in stroke.pausePoints) {
        if (!pause.progress.isFinite ||
            pause.progress <= 0 ||
            pause.progress >= 1 ||
            pause.duration.isZero) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.invalidValue,
              'Stroke ${stroke.id} has an invalid pause point ${pause.id}.',
            ),
          );
        }
      }
      for (final mask in stroke.vectorMaskStrokes) {
        if (!mask.width.isFinite ||
            mask.width <= 0 ||
            !mask.feather.isFinite ||
            mask.feather < 0) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.invalidValue,
              'Stroke ${stroke.id} has an invalid vector mask.',
            ),
          );
        }
      }
    }

    final strokeReferenceCounts = <StrokeId, int>{};
    for (final section in document.sections) {
      final timing = section.timing;
      if (!timing.speedMultiplier.isFinite ||
          timing.speedMultiplier < 0.25 ||
          timing.speedMultiplier > 4 ||
          timing.animationDuration?.isZero == true ||
          timing.handEntranceDuration.microseconds > 10000000 ||
          timing.handExitDuration.microseconds > 10000000 ||
          (timing.handEntranceAnimation == SectionHandEntranceAnimation.none &&
              !timing.handEntranceDuration.isZero) ||
          ((timing.handExitAnimation == SectionHandExitAnimation.none ||
                  timing.handExitAnimation ==
                      SectionHandExitAnimation.disappear) &&
              !timing.handExitDuration.isZero)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Section ${section.id} contains invalid authored timing.',
          ),
        );
      }
      _checkUniqueReferences(
        section.strokeIds,
        'section ${section.id}',
        issues,
      );
      for (final strokeId in section.strokeIds) {
        strokeReferenceCounts.update(
          strokeId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (!strokeIds.contains(strokeId)) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.missingReference,
              'Section ${section.id} references missing stroke $strokeId.',
            ),
          );
          continue;
        }
        final stroke = strokesById[strokeId]!;
        if (stroke.sectionId != section.id) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.inconsistentReference,
              'Stroke $strokeId belongs to ${stroke.sectionId}, not ${section.id}.',
            ),
          );
        }
      }
      final assetId = section.assetId;
      if (assetId != null && !assetIds.contains(assetId)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Section ${section.id} references missing asset $assetId.',
          ),
        );
      }
    }
    for (final strokeId in strokeIds) {
      if (strokeReferenceCounts[strokeId] != 1) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.inconsistentReference,
            'Stroke $strokeId must be owned by exactly one section.',
          ),
        );
      }
    }

    _checkUniqueReferences(document.sectionOrder, 'section order', issues);
    if (document.sectionOrder.length != sectionIds.length ||
        document.sectionOrder.any((id) => !sectionIds.contains(id))) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.missingReference,
          'Section order must contain every section exactly once.',
        ),
      );
    }

    final sceneMembershipCounts = <SectionId, int>{};
    for (final scene in document.scenes) {
      _checkUniqueReferences(scene.sectionIds, 'scene ${scene.id}', issues);
      for (final sectionId in scene.sectionIds) {
        sceneMembershipCounts.update(
          sectionId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (!sectionIds.contains(sectionId)) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.missingReference,
              'Scene ${scene.id} references missing section $sectionId.',
            ),
          );
        }
      }
    }
    for (final entry in sceneMembershipCounts.entries) {
      if (entry.value > 1) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.inconsistentReference,
            'Section ${entry.key} cannot belong to more than one scene.',
          ),
        );
      }
    }

    final audioTracksById = {
      for (final track in document.audioTracks) track.id: track,
    };
    final timelineAudioIds = document.timeline.audio
        .map((track) => track.audioTrackId)
        .toList(growable: false);
    _checkUniqueReferences(
      timelineAudioIds,
      'persistent timeline audio',
      issues,
    );
    for (final id in timelineAudioIds) {
      if (!audioTracksById.containsKey(id)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Persistent timeline references missing audio track $id.',
          ),
        );
      }
    }
    final timelineVoice = document.timeline.voiceGuide;
    if (timelineVoice != null &&
        !audioTracksById.containsKey(timelineVoice.audioTrackId)) {
      issues.add(
        ProjectDocumentIssue(
          ProjectDocumentIssueCode.missingReference,
          'Persistent Voice Guide track references missing audio ${timelineVoice.audioTrackId}.',
        ),
      );
    }
    if (timelineVoice?.audioTrackId != document.voiceGuide?.audioTrackId) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.inconsistentReference,
          'Persistent timeline and project Voice Guide must reference the same track.',
        ),
      );
    }
    for (final marker in document.timeline.sceneMarkers) {
      if (!document.scenes.any((scene) => scene.id == marker.sceneId)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Timeline marker references missing scene ${marker.sceneId}.',
          ),
        );
      }
    }
    for (final track in document.audioTracks) {
      if (!assetIds.contains(track.assetId)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Audio track ${track.id} references missing asset ${track.assetId}.',
          ),
        );
      }
      _requireAssetKind(
        track.assetId,
        ProjectAssetKind.audio,
        assetsById,
        'Audio track ${track.id}',
        issues,
      );
      final end = track.start + track.duration;
      if (end.microseconds > document.duration.microseconds) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.audioOutsideProject,
            'Audio track ${track.id} ends outside the project duration.',
          ),
        );
      }
      final mediaDuration = assetsById[track.assetId]?.mediaDuration;
      if (mediaDuration != null &&
          track.sourceOffset.microseconds + track.duration.microseconds >
              mediaDuration.microseconds) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.audioOutsideProject,
            'Audio track ${track.id} exceeds its source media duration.',
          ),
        );
      }
    }
    final voiceGuide = document.voiceGuide;
    if (voiceGuide != null) {
      if (!audioTracksById.containsKey(voiceGuide.audioTrackId)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Voice Guide references missing audio track ${voiceGuide.audioTrackId}.',
          ),
        );
      }
      if (voiceGuide.displayName.trim().isEmpty ||
          voiceGuide.originalFileName.trim().isEmpty) {
        issues.add(
          const ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Voice Guide requires display and original filenames.',
          ),
        );
      }
    }
    for (final section in document.sections) {
      final cue = section.timing.audioCueAnchor;
      if (cue == null) continue;
      final track = audioTracksById[cue.audioTrackId];
      if (track == null) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Section ${section.id} cue references missing audio track ${cue.audioTrackId}.',
          ),
        );
      } else if (cue.sourceMediaTime.microseconds >
          (assetsById[track.assetId]?.mediaDuration ?? track.duration)
              .microseconds) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.audioOutsideProject,
            'Section ${section.id} cue lies outside its source audio track.',
          ),
        );
      }
    }
    return ProjectDocumentValidation(issues);
  }

  void _validateSemanticMetadata(
    ProjectDocument document, {
    required Set<StrokeId> strokeIds,
    required Set<SectionId> sectionIds,
    required Set<SceneId> sceneIds,
    required Set<ProjectAssetId> assetIds,
    required List<ProjectDocumentIssue> issues,
  }) {
    final seen = <String>{};
    for (final entity in document.contentMetadata.entities) {
      final target = entity.target;
      if (!seen.add(target.stableKey)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.duplicateReference,
            'Duplicate semantic target ${target.stableKey}.',
          ),
        );
      }
      final exists = switch (target.kind) {
        SemanticTargetKind.stroke => strokeIds.any(
          (id) => id.value == target.value,
        ),
        SemanticTargetKind.section => sectionIds.any(
          (id) => id.value == target.value,
        ),
        SemanticTargetKind.scene => sceneIds.any(
          (id) => id.value == target.value,
        ),
        SemanticTargetKind.asset => assetIds.any(
          (id) => id.value == target.value,
        ),
      };
      if (!exists) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Semantic metadata references missing ${target.stableKey}.',
          ),
        );
      }
      final text = entity.textMetadata;
      if ((text?.originalText?.length ?? 0) > 16384 ||
          (text?.fontSize != null &&
              (!text!.fontSize!.isFinite || text.fontSize! <= 0)) ||
          (text?.lineCount != null && text!.lineCount! <= 0) ||
          (text?.languageHint?.length ?? 0) > 128 ||
          (text?.sourceProvenance.trim().isEmpty ?? false)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Semantic metadata for ${target.stableKey} is invalid.',
          ),
        );
      }
    }
    if ((document.contentMetadata.projectLocaleHint?.length ?? 0) > 128) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.invalidValue,
          'Project locale hint is too long.',
        ),
      );
    }
  }

  void _validateCamera(
    ProjectDocument document,
    List<ProjectDocumentIssue> issues,
  ) {
    final track = document.cameraTrack;
    if (track == null) {
      if (document.timeline.camera.enabled) {
        issues.add(
          const ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Timeline references a missing camera track.',
          ),
        );
      }
      return;
    }
    if (document.timeline.camera.enabled &&
        document.timeline.camera.cameraTrackId != track.id) {
      issues.add(
        const ProjectDocumentIssue(
          ProjectDocumentIssueCode.inconsistentReference,
          'Timeline camera reference does not match the document camera track.',
        ),
      );
    }
    _uniqueIds([track.id], 'camera track', issues);
    _uniqueIds(track.shots.map((shot) => shot.id), 'camera shot', issues);
    _uniqueIds(
      track.shots.expand(
        (shot) => shot.keyframes.map((keyframe) => keyframe.id),
      ),
      'camera keyframe',
      issues,
    );
    void checkView(CameraView view, String owner) {
      if (!view.centerX.isFinite ||
          !view.centerY.isFinite ||
          !view.viewportWidth.isFinite ||
          view.viewportWidth < CameraLimits.minimumViewportWidth ||
          view.viewportWidth > CameraLimits.maximumViewportWidth ||
          view.centerX.abs() > CameraLimits.maximumAbsoluteCenter ||
          view.centerY.abs() > CameraLimits.maximumAbsoluteCenter) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            '$owner has an invalid camera view.',
          ),
        );
      }
    }

    checkView(track.defaultView, 'Camera track');
    CameraShot? previous;
    final ownedScenes = <SceneId>{};
    final sceneIds = document.scenes.map((scene) => scene.id).toSet();
    for (final shot in track.shots) {
      final owner = shot.ownerSceneId;
      if (owner != null && !sceneIds.contains(owner)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.missingReference,
            'Camera shot ${shot.id} references missing scene $owner.',
          ),
        );
      } else if (owner != null && !ownedScenes.add(owner)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.duplicateReference,
            'Scene $owner can own only one camera clip.',
          ),
        );
      }
      if (shot.duration.isZero ||
          (previous != null &&
              shot.startTime.compareTo(previous.endTime) < 0 &&
              (shot.ownerSceneId == null || previous.ownerSceneId == null))) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Camera shot ${shot.id} has invalid or overlapping timing.',
          ),
        );
      }
      if (shot.keyframes.isEmpty ||
          shot.keyframes.first.offset != TimelineTime.zero) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.invalidValue,
            'Camera shot ${shot.id} must start with a keyframe at zero.',
          ),
        );
      }
      TimelineTime? priorOffset;
      for (final keyframe in shot.keyframes) {
        checkView(keyframe.view, 'Camera keyframe ${keyframe.id}');
        if (keyframe.offset.microseconds > shot.duration.microseconds ||
            (priorOffset != null &&
                keyframe.offset.compareTo(priorOffset) <= 0)) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.invalidValue,
              'Camera keyframe ${keyframe.id} has an invalid offset.',
            ),
          );
        }
        final transition = keyframe.incomingTransition;
        final availableUs =
            keyframe.offset.microseconds - (priorOffset?.microseconds ?? 0);
        if (transition.duration.microseconds > availableUs ||
            (transition.type == CameraTransitionType.cut &&
                !transition.duration.isZero)) {
          issues.add(
            ProjectDocumentIssue(
              ProjectDocumentIssueCode.invalidValue,
              'Camera keyframe ${keyframe.id} has an invalid transition.',
            ),
          );
        }
        priorOffset = keyframe.offset;
      }
      previous = shot;
    }
  }

  Set<T> _uniqueIds<T extends ProjectEntityId>(
    Iterable<T> ids,
    String label,
    List<ProjectDocumentIssue> issues,
  ) {
    final result = <T>{};
    for (final id in ids) {
      if (!result.add(id)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.duplicateId,
            'Duplicate $label ID: $id.',
          ),
        );
      }
    }
    return result;
  }

  void _checkUniqueReferences<T extends ProjectEntityId>(
    Iterable<T> ids,
    String owner,
    List<ProjectDocumentIssue> issues,
  ) {
    final seen = <T>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        issues.add(
          ProjectDocumentIssue(
            ProjectDocumentIssueCode.duplicateReference,
            'Duplicate reference $id in $owner.',
          ),
        );
      }
    }
  }

  void _requireAsset(
    ProjectAssetId? id,
    Set<ProjectAssetId> assetIds,
    String owner,
    List<ProjectDocumentIssue> issues,
  ) {
    if (id != null && !assetIds.contains(id)) {
      issues.add(
        ProjectDocumentIssue(
          ProjectDocumentIssueCode.missingReference,
          '$owner references missing asset $id.',
        ),
      );
    }
  }

  void _requireAssetKind(
    ProjectAssetId? id,
    ProjectAssetKind expectedKind,
    Map<ProjectAssetId, ProjectAsset> assetsById,
    String owner,
    List<ProjectDocumentIssue> issues,
  ) {
    if (id == null) return;
    final asset = assetsById[id];
    if (asset != null && asset.kind != expectedKind) {
      issues.add(
        ProjectDocumentIssue(
          ProjectDocumentIssueCode.inconsistentReference,
          '$owner requires a ${expectedKind.name} asset, not ${asset.kind.name}.',
        ),
      );
    }
  }
}
