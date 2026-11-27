import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_support.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_duplicator.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

final class ProjectSettingsOperations {
  const ProjectSettingsOperations({
    this.duplicator = const ProjectDocumentDuplicator(),
  });

  final ProjectDocumentDuplicator duplicator;

  DocumentOperationResult setCanvas({
    required ProjectDocument document,
    required ProjectCanvas canvas,
  }) {
    if (canvas.width <= 0 || canvas.height <= 0) {
      return invalid(document, 'Canvas dimensions must be positive.');
    }
    return _changed(document.copyWith(canvas: canvas), 'set-canvas', {
      DocumentScope.canvas,
      DocumentScope.settings,
    });
  }

  DocumentOperationResult setCanvasBackground({
    required ProjectDocument document,
    required CanvasBackground background,
  }) => _changed(
    document.copyWith(
      canvas: document.canvas.copyWith(background: background.normalized()),
    ),
    'set-canvas-background',
    {DocumentScope.canvas},
  );

  DocumentOperationResult setMotion({
    required ProjectDocument document,
    required ProjectMotionConfiguration configuration,
  }) {
    if (!configuration.drawingSpeed.isFinite ||
        configuration.drawingSpeed <= 0 ||
        !configuration.penTravelSpeed.isFinite ||
        configuration.penTravelSpeed <= 0 ||
        !configuration.revealWidth.isFinite ||
        configuration.revealWidth <= 0) {
      return invalid(document, 'Motion settings contain invalid values.');
    }
    return _changed(
      document.copyWith(motionConfiguration: configuration),
      'set-motion-configuration',
      {DocumentScope.settings, DocumentScope.timing},
    );
  }

  DocumentOperationResult setHand({
    required ProjectDocument document,
    required ProjectHandConfiguration configuration,
  }) {
    if (!configuration.scale.isFinite ||
        configuration.scale <= 0 ||
        !configuration.rotationDegrees.isFinite ||
        !configuration.penTip.x.isFinite ||
        !configuration.penTip.y.isFinite) {
      return invalid(document, 'Hand configuration contains invalid values.');
    }
    final assetId = configuration.assetId;
    if (assetId != null &&
        !document.assets.any(
          (asset) => asset.id == assetId && asset.kind == ProjectAssetKind.hand,
        )) {
      return invalid(document, 'The configured hand asset is unavailable.');
    }
    return _changed(
      document.copyWith(handConfiguration: configuration),
      'set-hand-configuration',
      {DocumentScope.hand, DocumentScope.settings},
    );
  }

  DocumentOperationResult setWritingSound({
    required ProjectDocument document,
    required ProjectWritingSoundConfiguration configuration,
  }) {
    if (!configuration.volume.isFinite ||
        configuration.volume < 0 ||
        configuration.volume > 1) {
      return invalid(document, 'Writing-sound volume must be between 0 and 1.');
    }
    return _changed(
      document.copyWith(writingSoundConfiguration: configuration),
      'set-writing-sound',
      {DocumentScope.settings, DocumentScope.audio},
    );
  }

  DocumentOperationResult resetDefaults({
    required ProjectDocument document,
    ProjectHandConfiguration? handConfiguration,
  }) => _changed(
    document.copyWith(
      canvas: const ProjectCanvas(width: 1920, height: 1080),
      frameRate: FrameRate.fps30,
      duration: TimelineDuration.fromMicroseconds(6000000),
      exportConfiguration: const ProjectExportConfiguration(),
      motionConfiguration: ProjectMotionConfiguration(
        drawingDuration: TimelineDuration.fromMicroseconds(4700000),
        startDelay: TimelineDuration.fromMicroseconds(400000),
        endHold: TimelineDuration.fromMicroseconds(900000),
      ),
      // A reset must never combine the selected hand with another hand's
      // hard-coded anchor. The caller can supply the selected preset's
      // defaults; otherwise preserve the active hand and its calibration.
      handConfiguration: handConfiguration ?? document.handConfiguration,
      writingSoundConfiguration: const ProjectWritingSoundConfiguration(),
      sections: [
        for (final section in document.sections)
          section.copyWith(timing: const DocumentSectionTiming()),
      ],
    ),
    'reset-project-settings',
    {
      DocumentScope.settings,
      DocumentScope.canvas,
      DocumentScope.export,
      DocumentScope.hand,
      DocumentScope.timing,
    },
  );

  DocumentOperationResult setExport({
    required ProjectDocument document,
    required ProjectExportConfiguration configuration,
    FrameRate? frameRate,
    ProjectCanvas? outputSize,
  }) {
    if (outputSize != null &&
        (outputSize.width <= 0 || outputSize.height <= 0)) {
      return invalid(document, 'Output dimensions must be positive.');
    }
    return _changed(
      document.copyWith(
        exportConfiguration: configuration,
        frameRate: frameRate,
        canvas: outputSize?.copyWith(background: document.canvas.background),
      ),
      'set-export-configuration',
      {DocumentScope.export, DocumentScope.canvas},
    );
  }

  DocumentOperationResult addAsset({
    required ProjectDocument document,
    required ProjectAsset asset,
  }) {
    if (document.assets.any((item) => item.id == asset.id)) {
      return DocumentOperationResult.failure(
        document: document,
        code: DocumentOperationFailureCode.duplicateEntity,
        message: 'Asset ${asset.id} already exists.',
      );
    }
    return _changed(
      document.copyWith(assets: [...document.assets, asset]),
      'add-asset',
      {DocumentScope.assets},
      ids: [asset.id.value],
    );
  }

  DocumentOperationResult removeAsset({
    required ProjectDocument document,
    required ProjectAssetId assetId,
  }) {
    if (!document.assets.any((asset) => asset.id == assetId)) {
      return missing(document, 'Asset', assetId);
    }
    final referenced =
        document.artworkAssetId == assetId ||
        document.handConfiguration.assetId == assetId ||
        document.strokes.any((stroke) => stroke.assetId == assetId) ||
        document.sections.any((section) => section.assetId == assetId) ||
        document.audioTracks.any((track) => track.assetId == assetId);
    if (referenced) {
      return DocumentOperationResult.failure(
        document: document,
        code: DocumentOperationFailureCode.referencedEntity,
        message: 'Asset $assetId is still referenced by the project.',
      );
    }
    return _changed(
      document.copyWith(
        assets: document.assets
            .where((asset) => asset.id != assetId)
            .toList(growable: false),
      ),
      'remove-asset',
      {DocumentScope.assets},
      ids: [assetId.value],
    );
  }

  /// Clears artwork-owned content while preserving the hand, audio, and global
  /// settings, matching the current editor's persistent clear-canvas behavior.
  DocumentOperationResult clearArtwork({required ProjectDocument document}) {
    final artworkAssetIds = document.assets
        .where((asset) => asset.kind == ProjectAssetKind.artwork)
        .map((asset) => asset.id)
        .toSet();
    return _changed(
      document.copyWith(
        artworkAssetId: null,
        artworkPlacement: null,
        assets: document.assets
            .where((asset) => !artworkAssetIds.contains(asset.id))
            .toList(growable: false),
        strokes: const [],
        sections: const [],
        sectionOrder: const [],
        scenes: const [],
        cameraTrack: null,
        contentMetadata: document.contentMetadata.copyWith(entities: const []),
        pathProcessingMetadata: null,
        timeline: PersistentTimeline(
          drawing: document.timeline.drawing,
          camera: const PersistentCameraTimelineTrack.disabled(),
          audio: document.timeline.audio,
          voiceGuide: document.timeline.voiceGuide,
          leadingHold: document.timeline.leadingHold,
          trailingHold: document.timeline.trailingHold,
        ),
      ),
      'clear-artwork',
      {
        DocumentScope.assets,
        DocumentScope.strokes,
        DocumentScope.sections,
        DocumentScope.ordering,
        DocumentScope.scenes,
        DocumentScope.camera,
        DocumentScope.semantic,
        DocumentScope.settings,
      },
      ids: artworkAssetIds.map((id) => id.value),
    );
  }

  DocumentOperationResult setVoiceGuide({
    required ProjectDocument document,
    required ProjectVoiceGuide guide,
  }) {
    if (!document.audioTracks.any((track) => track.id == guide.audioTrackId)) {
      return missing(document, 'Audio track', guide.audioTrackId);
    }
    return _changed(
      document.copyWith(
        voiceGuide: guide,
        timeline: PersistentTimeline(
          drawing: document.timeline.drawing,
          camera: document.timeline.camera,
          audio:
              document.timeline.audio.any(
                (track) => track.audioTrackId == guide.audioTrackId,
              )
              ? document.timeline.audio
              : [
                  ...document.timeline.audio,
                  PersistentAudioTimelineTrack(
                    audioTrackId: guide.audioTrackId,
                  ),
                ],
          voiceGuide: PersistentVoiceGuideTimelineTrack(
            audioTrackId: guide.audioTrackId,
          ),
          sceneMarkers: document.timeline.sceneMarkers,
          leadingHold: document.timeline.leadingHold,
          trailingHold: document.timeline.trailingHold,
        ),
      ),
      'set-voice-guide',
      {DocumentScope.audio, DocumentScope.settings},
      ids: [guide.audioTrackId.value],
    );
  }

  DocumentOperationResult attachVoiceGuide({
    required ProjectDocument document,
    required ProjectAssetId assetId,
    required String displayName,
    required IdAllocationContext ids,
    AudioExportPolicy exportPolicy = AudioExportPolicy.referenceOnly,
  }) {
    final assets = document.assets.where(
      (asset) => asset.id == assetId && asset.kind == ProjectAssetKind.audio,
    );
    if (assets.isEmpty || assets.single.mediaDuration == null) {
      return invalid(
        document,
        'Voice Guide requires an audio asset with duration.',
      );
    }
    final asset = assets.single;
    final trackId = ids.audioTrackId();
    final track = ProjectAudioTrack(
      id: trackId,
      assetId: assetId,
      start: TimelineTime.zero,
      duration: asset.mediaDuration!,
      exportPolicy: exportPolicy,
    );
    return _changed(
      document.copyWith(
        duration:
            document.duration.microseconds >= asset.mediaDuration!.microseconds
            ? document.duration
            : asset.mediaDuration,
        audioTracks: [...document.audioTracks, track],
        voiceGuide: ProjectVoiceGuide(
          audioTrackId: trackId,
          displayName: displayName,
          originalFileName: asset.originalFileName,
        ),
        timeline: PersistentTimeline(
          drawing: document.timeline.drawing,
          camera: document.timeline.camera,
          audio: [
            ...document.timeline.audio,
            PersistentAudioTimelineTrack(audioTrackId: trackId),
          ],
          voiceGuide: PersistentVoiceGuideTimelineTrack(audioTrackId: trackId),
          sceneMarkers: document.timeline.sceneMarkers,
          leadingHold: document.timeline.leadingHold,
          trailingHold: document.timeline.trailingHold,
        ),
      ),
      'attach-voice-guide',
      {DocumentScope.audio, DocumentScope.assets},
      ids: [assetId.value, trackId.value],
    );
  }

  DocumentOperationResult clearVoiceGuide({required ProjectDocument document}) {
    final guide = document.voiceGuide;
    if (guide == null) {
      return invalid(document, 'The project has no Voice Guide.');
    }
    return _changed(
      document.copyWith(
        voiceGuide: null,
        timeline: PersistentTimeline(
          drawing: document.timeline.drawing,
          camera: document.timeline.camera,
          audio: document.timeline.audio,
          sceneMarkers: document.timeline.sceneMarkers,
          leadingHold: document.timeline.leadingHold,
          trailingHold: document.timeline.trailingHold,
        ),
        sections: [
          for (final section in document.sections)
            section.timing.audioCueAnchor?.audioTrackId == guide.audioTrackId
                ? section.copyWith(
                    timing: section.timing.copyWith(audioCueAnchor: null),
                  )
                : section,
        ],
      ),
      'clear-voice-guide',
      {DocumentScope.audio, DocumentScope.timing},
      ids: [guide.audioTrackId.value],
    );
  }

  DocumentOperationResult setVoiceGuideMuted({
    required ProjectDocument document,
    required bool muted,
  }) {
    final guide = document.voiceGuide;
    if (guide == null) {
      return invalid(document, 'The project has no Voice Guide.');
    }
    final index = document.audioTracks.indexWhere(
      (track) => track.id == guide.audioTrackId,
    );
    if (index < 0) return missing(document, 'Audio track', guide.audioTrackId);
    final current = document.audioTracks[index];
    if (current.muted == muted) {
      return DocumentOperationResult.success(
        document: document,
        affectedScopes: const {},
        summary: DocumentChangeSummary(
          action: 'voice-guide-muted',
          changeCount: 0,
        ),
      );
    }
    final replacement = ProjectAudioTrack(
      id: current.id,
      assetId: current.assetId,
      start: current.start,
      duration: current.duration,
      exportPolicy: current.exportPolicy,
      sourceOffset: current.sourceOffset,
      muted: muted,
      affectsTimelineDuration: current.affectsTimelineDuration,
    );
    return _changed(
      document.copyWith(
        audioTracks: [
          for (
            var trackIndex = 0;
            trackIndex < document.audioTracks.length;
            trackIndex++
          )
            trackIndex == index
                ? replacement
                : document.audioTracks[trackIndex],
        ],
      ),
      'voice-guide-muted',
      {DocumentScope.audio, DocumentScope.settings},
      ids: [guide.audioTrackId.value],
    );
  }

  DocumentOperationResult createNew({
    required ProjectDocument current,
    required IdAllocationContext ids,
    String title = 'Untitled Project',
    ProjectCanvas canvas = const ProjectCanvas(width: 1920, height: 1080),
    FrameRate frameRate = FrameRate.fps30,
  }) => DocumentOperationResult.success(
    document: ProjectDocument(
      id: ids.projectId(),
      title: title,
      canvas: canvas,
      frameRate: frameRate,
      duration: TimelineDuration.zero,
      assets: const [],
      strokes: const [],
      sections: const [],
      sectionOrder: const [],
      scenes: const [],
      audioTracks: const [],
    ),
    affectedScopes: const {DocumentScope.settings},
    summary: DocumentChangeSummary(action: 'new-project'),
  );

  DocumentOperationResult duplicateProject({
    required ProjectDocument document,
    required IdAllocationContext ids,
    String? title,
  }) => DocumentOperationResult.success(
    document: duplicator.duplicateWithAllocation(
      document,
      allocation: ids,
      title: title,
    ),
    affectedScopes: DocumentScope.values,
    summary: DocumentChangeSummary(
      action: 'duplicate-project',
      entityIds: [document.id.value],
    ),
  );

  DocumentOperationResult _changed(
    ProjectDocument document,
    String action,
    Iterable<DocumentScope> scopes, {
    Iterable<String> ids = const [],
  }) => DocumentOperationResult.success(
    document: document,
    affectedScopes: scopes,
    summary: DocumentChangeSummary(action: action, entityIds: ids),
  );
}
