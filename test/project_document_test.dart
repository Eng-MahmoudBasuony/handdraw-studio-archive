import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/policies/project_limits.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_duplicator.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';

void main() {
  const validator = ProjectDocumentValidator();

  test('valid aggregate has stable references and immutable collections', () {
    final document = _document();
    expect(validator.validate(document).isValid, isTrue);
    expect(
      () => document.sections.add(document.sections.first),
      throwsUnsupportedError,
    );
    expect(
      () => document.sections.first.strokeIds.add(StrokeId('other')),
      throwsUnsupportedError,
    );
  });

  test('validator reports duplicate and missing references', () {
    final sectionId = SectionId('section-a');
    final duplicateStrokeId = StrokeId('stroke-a');
    final document = ProjectDocument(
      id: ProjectId('project-a'),
      title: 'Broken',
      canvas: const ProjectCanvas(width: 1920, height: 1080),
      frameRate: FrameRate.fps30,
      duration: TimelineDuration.fromMicroseconds(1000000),
      assets: const [],
      strokes: [
        ProjectStroke(
          id: duplicateStrokeId,
          sectionId: sectionId,
          name: 'A',
          points: const [],
        ),
        ProjectStroke(
          id: duplicateStrokeId,
          sectionId: SectionId('missing'),
          name: 'B',
          points: const [],
        ),
        ProjectStroke(
          id: StrokeId('stroke-b'),
          sectionId: SectionId('missing'),
          name: 'C',
          points: const [],
        ),
      ],
      sections: [
        ProjectSection(
          id: sectionId,
          name: 'Section',
          strokeIds: [
            duplicateStrokeId,
            duplicateStrokeId,
            StrokeId('stroke-b'),
          ],
        ),
      ],
      sectionOrder: [sectionId, sectionId],
      scenes: [
        ProjectScene(
          id: SceneId('scene-a'),
          name: 'Scene',
          sectionIds: [SectionId('missing')],
        ),
      ],
      audioTracks: const [],
    );

    final result = validator.validate(document);
    expect(result.isValid, isFalse);
    expect(
      result.issues.map((issue) => issue.code),
      containsAll([
        ProjectDocumentIssueCode.duplicateId,
        ProjectDocumentIssueCode.duplicateReference,
        ProjectDocumentIssueCode.missingReference,
        ProjectDocumentIssueCode.inconsistentReference,
      ]),
    );
    expect(
      result.throwIfInvalid,
      throwsA(isA<ProjectDocumentValidationException>()),
    );
  });

  test('validator enforces project limits and audio bounds', () {
    final asset = ProjectAsset(
      id: ProjectAssetId('audio-asset'),
      kind: ProjectAssetKind.audio,
      originalFileName: 'audio.wav',
      storagePolicy: ProjectAssetStoragePolicy.embedded,
      contentHash: 'sha256:audio',
    );
    final document = ProjectDocument(
      id: ProjectId('project-a'),
      title: 'Too long',
      canvas: const ProjectCanvas(width: 0, height: 1080),
      frameRate: FrameRate.fps60,
      duration: TimelineDuration.fromMicroseconds(
        ProjectLimits.maximumDurationMicroseconds + 1,
      ),
      assets: [asset],
      strokes: const [],
      sections: const [],
      sectionOrder: const [],
      scenes: const [],
      audioTracks: [
        ProjectAudioTrack(
          id: AudioTrackId('audio-a'),
          assetId: asset.id,
          start: TimelineTime.fromMicroseconds(
            ProjectLimits.maximumDurationMicroseconds,
          ),
          duration: TimelineDuration.fromMicroseconds(2),
          exportPolicy: AudioExportPolicy.embedInOutput,
        ),
      ],
    );
    final codes = validator
        .validate(document)
        .issues
        .map((issue) => issue.code);
    expect(codes, contains(ProjectDocumentIssueCode.invalidCanvas));
    expect(codes, contains(ProjectDocumentIssueCode.durationLimitExceeded));
    expect(codes, contains(ProjectDocumentIssueCode.audioOutsideProject));
  });

  test('every stroke must be owned by exactly one section', () {
    final valid = _document();
    final orphaned = ProjectDocument(
      id: valid.id,
      title: valid.title,
      canvas: valid.canvas,
      frameRate: valid.frameRate,
      duration: valid.duration,
      assets: valid.assets,
      strokes: valid.strokes,
      sections: [
        ProjectSection(
          id: valid.sections.single.id,
          name: valid.sections.single.name,
          strokeIds: const [],
        ),
      ],
      sectionOrder: valid.sectionOrder,
      scenes: valid.scenes,
      audioTracks: valid.audioTracks,
    );

    expect(
      validator.validate(orphaned).issues.map((issue) => issue.code),
      contains(ProjectDocumentIssueCode.inconsistentReference),
    );
  });

  test('scene clip polygons must be finite normalized shapes', () {
    final valid = _document();
    final malformed = valid.copyWith(
      strokes: [
        valid.strokes.first.copyWith(
          clipPolygons: const [
            [DocumentPoint(0, 0), DocumentPoint(double.nan, 1)],
          ],
        ),
      ],
    );

    expect(
      validator.validate(malformed).issues.map((issue) => issue.code),
      contains(ProjectDocumentIssueCode.invalidValue),
    );
  });

  test('duplicate allocates fresh IDs and rewrites all references', () {
    final source = _document();
    final copy = const ProjectDocumentDuplicator().duplicate(
      source,
      ids: FakeIdGenerator(),
    );

    expect(copy.id, isNot(source.id));
    expect(copy.assets.first.id, isNot(source.assets.first.id));
    expect(copy.sections.first.id, isNot(source.sections.first.id));
    expect(copy.strokes.first.id, isNot(source.strokes.first.id));
    expect(
      copy.strokes.first.pausePoints.single.id,
      isNot(source.strokes.first.pausePoints.single.id),
    );
    expect(copy.strokes.first.sectionId, copy.sections.first.id);
    expect(copy.sections.first.strokeIds, [copy.strokes.first.id]);
    expect(copy.scenes.first.sectionIds, [copy.sections.first.id]);
    expect(copy.audioTracks.first.assetId, copy.assets.first.id);
    expect(
      copy.audioTracks.first.exportPolicy,
      AudioExportPolicy.referenceOnly,
    );
    expect(copy.voiceGuide?.audioTrackId, copy.audioTracks.first.id);
    expect(
      copy.sections.first.timing.audioCueAnchor?.audioTrackId,
      copy.audioTracks.first.id,
    );
    expect(validator.validate(copy).isValid, isTrue);
  });

  test('a section cannot belong to two scenes', () {
    final valid = _document();
    final duplicatedMembership = valid.copyWith(
      scenes: [
        ...valid.scenes,
        ProjectScene(
          id: SceneId('scene-b'),
          name: 'Other',
          sectionIds: [valid.sections.single.id],
        ),
      ],
    );

    expect(
      validator
          .validate(duplicatedMembership)
          .issues
          .map((issue) => issue.code),
      contains(ProjectDocumentIssueCode.inconsistentReference),
    );
  });

  test('embedded assets cannot own external locators', () {
    final valid = _document();
    final invalid = valid.copyWith(
      assets: [
        valid.assets.single.copyWith(
          externalLocator: const ExternalAssetLocator(pathHint: '/asset.wav'),
        ),
      ],
    );

    expect(
      validator.validate(invalid).issues.map((issue) => issue.code),
      contains(ProjectDocumentIssueCode.inconsistentReference),
    );
  });

  test('copyWith can explicitly clear every nullable asset reference', () {
    final source = _document();
    final externalAsset = source.assets.single.copyWith(
      storagePolicy: ProjectAssetStoragePolicy.external,
      externalLocator: const ExternalAssetLocator(
        pathHint: '/resolved/voice.wav',
      ),
    );
    final populated = source.copyWith(
      artworkAssetId: externalAsset.id,
      handConfiguration: ProjectHandConfiguration(
        assetId: externalAsset.id,
        presetId: 'custom-hand',
      ),
      assets: [externalAsset],
    );

    final cleared = populated.copyWith(
      artworkAssetId: null,
      voiceGuide: null,
      handConfiguration: populated.handConfiguration.copyWith(
        assetId: null,
        presetId: null,
      ),
      assets: [
        externalAsset.copyWith(externalLocator: null, mediaDuration: null),
      ],
    );

    expect(cleared.artworkAssetId, isNull);
    expect(cleared.voiceGuide, isNull);
    expect(cleared.handConfiguration.assetId, isNull);
    expect(cleared.handConfiguration.presetId, isNull);
    expect(cleared.assets.single.externalLocator, isNull);
    expect(cleared.assets.single.mediaDuration, isNull);
  });
}

ProjectDocument _document() {
  final assetId = ProjectAssetId('asset-a');
  final sectionId = SectionId('section-a');
  final strokeId = StrokeId('stroke-a');
  return ProjectDocument(
    id: ProjectId('project-a'),
    title: 'Valid',
    canvas: const ProjectCanvas(width: 1920, height: 1080),
    frameRate: FrameRate.ntsc2997,
    duration: TimelineDuration.fromMicroseconds(3000000),
    assets: [
      ProjectAsset(
        id: assetId,
        kind: ProjectAssetKind.audio,
        originalFileName: 'voice.wav',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:voice',
        mediaDuration: TimelineDuration.fromMicroseconds(1000000),
      ),
    ],
    strokes: [
      ProjectStroke(
        id: strokeId,
        sectionId: sectionId,
        name: 'Stroke',
        points: const [DocumentPoint(0, 0), DocumentPoint(1, 1)],
        pausePoints: [
          DocumentStrokePause(
            id: StrokePauseId('pause-a'),
            progress: 0.5,
            duration: TimelineDuration.fromMicroseconds(250000),
          ),
        ],
      ),
    ],
    sections: [
      ProjectSection(
        id: sectionId,
        name: 'Section',
        strokeIds: [strokeId],
        timing: DocumentSectionTiming(
          audioCueAnchor: AudioCueAnchor(
            audioTrackId: AudioTrackId('audio-a'),
            sourceMediaTime: TimelineTime.fromMicroseconds(500000),
          ),
        ),
      ),
    ],
    sectionOrder: [sectionId],
    scenes: [
      ProjectScene(
        id: SceneId('scene-a'),
        name: 'Scene',
        sectionIds: [sectionId],
      ),
    ],
    audioTracks: [
      ProjectAudioTrack(
        id: AudioTrackId('audio-a'),
        assetId: assetId,
        start: TimelineTime.zero,
        duration: TimelineDuration.fromMicroseconds(1000000),
        exportPolicy: AudioExportPolicy.referenceOnly,
      ),
    ],
    voiceGuide: ProjectVoiceGuide(
      audioTrackId: AudioTrackId('audio-a'),
      displayName: 'Voice Guide',
      originalFileName: 'voice.wav',
    ),
  );
}
