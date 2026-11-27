import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/document_revision.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_file_service.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

void main() {
  const codec = DevelopmentProjectManifestCodec();

  test('project manifest preserves every bundled hand calibration state', () {
    for (final preset in BuiltInHands.all) {
      final source = _document().copyWith(
        handConfiguration: ProjectHandConfiguration(
          presetId: preset.id,
          scale: .73,
          rotationDegrees: -37,
          flipX: !preset.flipX,
          penTip: DocumentPoint(preset.penTip.dx, preset.penTip.dy),
        ),
      );
      final restored = codec.decode(
        jsonDecode(jsonEncode(codec.encode(source))) as Map<String, Object?>,
      );
      final hand = restored.handConfiguration;
      expect(hand.presetId, preset.id);
      expect(hand.scale, .73);
      expect(hand.rotationDegrees, -37);
      expect(hand.flipX, !preset.flipX);
      expect(hand.penTip.x, preset.penTip.dx);
      expect(hand.penTip.y, preset.penTip.dy);
    }
  });

  test(
    'strict manifest round-trip preserves IDs and runtime parity metadata',
    () {
      final source = _document();
      final manifest = codec.encode(source);
      final decoded = codec.decode(
        jsonDecode(jsonEncode(manifest)) as Map<String, Object?>,
      );

      expect(decoded.id, source.id);
      expect(decoded.frameRate, FrameRate.ntsc2997);
      expect(decoded.sectionOrder, source.sectionOrder);
      expect(
        decoded.sections.single.strokeIds,
        source.sections.single.strokeIds,
      );
      expect(
        decoded.audioTracks.single.assetId,
        source.audioTracks.single.assetId,
      );
      expect(decoded.strokes.single.revealOnly, isTrue);
      expect(
        decoded.strokes.single.revealStyle,
        DocumentRevealStyle.directionalWipe,
      );
      expect(
        decoded.strokes.single.pausePoints.single.id,
        StrokePauseId('pause-a'),
      );
      expect(decoded.scenes.single.locked, isFalse);
      expect(
        decoded.sections.single.timing.audioCueAnchor?.audioTrackId,
        AudioTrackId('audio-a'),
      );
      expect(decoded.voiceGuide?.displayName, 'Narration');
      expect(
        decoded.audioTracks.single.exportPolicy,
        AudioExportPolicy.referenceOnly,
      );
      expect(decoded.audioTracks.single.sourceOffset, TimelineTime.zero);
      expect(decoded.audioTracks.single.muted, isTrue);
      expect(
        decoded.assets[1].storagePolicy,
        ProjectAssetStoragePolicy.embedded,
      );
      expect(decoded.assets.last.externalLocator?.securityBookmark, 'bookmark');
      final project = manifest['project']! as Map<String, Object?>;
      final assets = project['assets']! as List<Object?>;
      final external = assets.last! as Map<String, Object?>;
      final locator = external['externalLocator']! as Map<String, Object?>;
      expect(external['contentHash'], 'sha256:external');
      expect(locator, isNot(contains('contentHash')));
      expect(external, isNot(contains('exportPolicy')));
      expect(manifest, isNot(contains('revision')));
      expect(manifest['schemaVersion'], 0);
      expect(manifest['developmentRevision'], 15);
      expect(
        decoded.canvas.background,
        const CanvasBackground.preset(CanvasBackgroundPreset.blueprint),
      );
      expect(decoded.strokes.single.clipPolygons, hasLength(1));
      expect(
        decoded.strokes.single.clipPolygons.single.map(
          (point) => [point.x, point.y],
        ),
        const [
          [0.1, 0.2],
          [0.8, 0.2],
          [0.8, 0.9],
        ],
      );
      expect(
        decoded.sections.single.timing.handEntranceAnimation,
        SectionHandEntranceAnimation.fadeIn,
      );
      expect(
        decoded.sections.single.timing.handExitAnimation,
        SectionHandExitAnimation.moveOut,
      );
      expect(
        decoded.sections.single.timing.keepHandVisibleAfterDrawing,
        isTrue,
      );
      expect(decoded.pathProcessingMetadata?.engineId, 'handdraw-smart-path');
      expect(
        decoded.pathProcessingMetadata?.featureSet,
        contains('suspected-frame-detection-v1'),
      );
      expect(
        ((project['timeline']! as Map<String, Object?>).containsKey(
          'revision',
        )),
        isFalse,
      );
    },
  );

  test('decode rejects missing IDs instead of generating replacements', () {
    final manifest = codec.encode(_document());
    final project = manifest['project']! as Map<String, Object?>;
    project.remove('id');

    expect(() => codec.decode(manifest), throwsFormatException);
  });

  test('manifest contains asset metadata but never Base64 payloads', () {
    final encoded = jsonEncode(codec.encode(_document()));
    expect(encoded, isNot(contains('containerPath')));
    expect(encoded.toLowerCase(), isNot(contains('base64')));
    expect(encoded, isNot(contains('<svg')));
  });

  test('equal scene masks are interned again after manifest decode', () {
    final source = _document();
    final original = source.strokes.single;
    final secondId = StrokeId('stroke-b');
    final withSharedSceneMask = source.copyWith(
      strokes: [
        original,
        original.copyWith(
          id: secondId,
          name: 'Stroke B',
          pausePoints: const [],
        ),
      ],
      sections: [
        source.sections.single.copyWith(strokeIds: [original.id, secondId]),
      ],
    );

    final decoded = codec.decode(
      jsonDecode(jsonEncode(codec.encode(withSharedSceneMask)))
          as Map<String, Object?>,
    );

    expect(decoded.strokes, hasLength(2));
    expect(
      identical(
        decoded.strokes.first.clipPolygons,
        decoded.strokes.last.clipPolygons,
      ),
      isTrue,
    );
  });

  test('scene camera ownership and connection round-trip compatibly', () {
    final source = _document();
    final track = ProjectCameraTrack(
      id: CameraTrackId('camera-track'),
      shots: [
        CameraShot(
          id: CameraShotId('scene-camera'),
          startTime: TimelineTime.zero,
          duration: TimelineDuration.fromMicroseconds(3000000),
          authorship: CameraAuthorship.manual,
          isLocked: false,
          label: 'Scene camera',
          ownerSceneId: source.scenes.single.id,
          sceneConnection: CameraSceneConnection.continuePrevious,
          keyframes: [
            CameraKeyframe(
              id: CameraKeyframeId('scene-camera-start'),
              offset: TimelineTime.zero,
              view: const CameraView.identity(),
            ),
          ],
        ),
      ],
    );
    final manifest = codec.encode(
      source.copyWith(
        cameraTrack: track,
        timeline: source.timeline.copyWith(
          camera: PersistentCameraTimelineTrack.enabled(
            cameraTrackId: track.id,
          ),
        ),
      ),
    );
    final decoded = codec.decode(manifest);

    expect(
      decoded.cameraTrack!.shots.single.ownerSceneId,
      source.scenes.single.id,
    );
    expect(
      decoded.cameraTrack!.shots.single.sceneConnection,
      CameraSceneConnection.continuePrevious,
    );

    final camera =
        (manifest['project']! as Map<String, Object?>)['cameraTrack']!
            as Map<String, Object?>;
    final shot =
        (camera['shots']! as List<Object?>).single! as Map<String, Object?>;
    shot.remove('ownerSceneId');
    shot.remove('sceneConnection');
    final legacy = codec.decode(manifest);
    expect(legacy.cameraTrack!.shots.single.ownerSceneId, isNull);
    expect(
      legacy.cameraTrack!.shots.single.sceneConnection,
      CameraSceneConnection.cut,
    );
  });

  test('decoder accepts only the current development revision', () {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (manifest) => manifest['developmentRevision'] = 2,
      (manifest) => manifest['developmentRevision'] = 5,
      (manifest) => manifest.remove('developmentRevision'),
      (manifest) => manifest['schemaVersion'] = 1,
      (manifest) => manifest.remove('schemaVersion'),
      (manifest) {
        manifest.remove('schemaVersion');
        manifest.remove('developmentRevision');
        manifest['version'] = 2;
      },
    ]) {
      final manifest = codec.encode(_document());
      mutation(manifest);
      expect(
        () => codec.decode(manifest),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Unsupported development project format',
          ),
        ),
      );
    }
  });

  test('revision 11 projects open without path-processing metadata', () {
    final manifest = codec.encode(_document());
    manifest['developmentRevision'] = 11;
    final project = manifest['project']! as Map<String, Object?>;
    project.remove('pathProcessing');

    final decoded = codec.decode(manifest);

    expect(decoded.pathProcessingMetadata, isNull);
  });

  test('revision 12 projects default to no authored hand animation', () {
    final manifest = codec.encode(_document());
    manifest['developmentRevision'] = 12;
    final project = manifest['project']! as Map<String, Object?>;
    final section =
        (project['sections']! as List<Object?>).single! as Map<String, Object?>;
    final timing = section['timing']! as Map<String, Object?>;
    timing.remove('pauseBeforeEnabled');
    timing.remove('pauseAfterEnabled');
    timing.remove('handEntranceAnimation');
    timing.remove('handEntranceDurationUs');
    timing.remove('handExitAnimation');
    timing.remove('handExitDurationUs');
    timing.remove('keepHandVisibleAfterDrawing');

    final decoded = codec.decode(manifest);

    expect(
      decoded.sections.single.timing.handEntranceAnimation,
      SectionHandEntranceAnimation.none,
    );
    expect(
      decoded.sections.single.timing.handExitAnimation,
      SectionHandExitAnimation.none,
    );
    expect(decoded.sections.single.timing.keepHandVisibleAfterDrawing, isFalse);
  });

  test('revision 14 projects open with a transparent canvas background', () {
    final manifest = codec.encode(_document());
    manifest['developmentRevision'] = 14;
    final project = manifest['project']! as Map<String, Object?>;
    final canvas = project['canvas']! as Map<String, Object?>;
    canvas.remove('background');

    final decoded = codec.decode(manifest);

    expect(decoded.canvas.background, const CanvasBackground.transparent());
  });

  test('codec has no dependency on ID generation', () {
    final source = File(
      'lib/features/project/infrastructure/development_project_manifest_codec.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('IdGenerator')));
    expect(source, isNot(contains('SecureRandomIdGenerator')));
  });

  test('development File IO delegates to the permanent codec', () async {
    final directory = await Directory.systemTemp.createTemp(
      'handdraw-manifest-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/project.handdraw.dev.json');
    final state = EditorDocumentState(
      document: _document(),
      revision: DocumentRevision(3),
    );

    await const DevelopmentProjectFileService().save(file, state);
    final restored = await const DevelopmentProjectFileService().open(file);

    expect(restored.document.id, state.document.id);
    expect(restored.revision, DocumentRevision.initial);
  });
}

ProjectDocument _document() {
  final artworkId = ProjectAssetId('asset-art');
  final audioId = ProjectAssetId('asset-audio');
  final externalId = ProjectAssetId('asset-external');
  final sectionId = SectionId('section-a');
  final strokeId = StrokeId('stroke-a');
  return ProjectDocument(
    id: ProjectId('project-a'),
    title: 'Manifest test',
    canvas: const ProjectCanvas(
      width: 1920,
      height: 1080,
      background: CanvasBackground.preset(CanvasBackgroundPreset.blueprint),
    ),
    frameRate: FrameRate.ntsc2997,
    duration: TimelineDuration.fromMicroseconds(5000000),
    artworkAssetId: artworkId,
    pathProcessingMetadata: const ProjectPathProcessingMetadata(
      engineId: 'handdraw-smart-path',
      algorithmVersion: 1,
      sourceAssetHash: 'sha256:art',
      suspectedFrameDetection: true,
      suspectedFrameConfidenceThreshold: 0.96,
    ),
    motionConfiguration: ProjectMotionConfiguration(
      drawingDuration: TimelineDuration.fromMicroseconds(3500000),
      startDelay: TimelineDuration.fromMicroseconds(500000),
      endHold: TimelineDuration.fromMicroseconds(1000000),
    ),
    assets: [
      ProjectAsset(
        id: artworkId,
        kind: ProjectAssetKind.artwork,
        originalFileName: 'art.svg',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:art',
        mediaType: 'image/svg+xml',
        artworkSourceType: ArtworkSourceType.svg,
      ),
      ProjectAsset(
        id: audioId,
        kind: ProjectAssetKind.audio,
        originalFileName: 'voice.wav',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:voice',
        mediaType: 'audio/wav',
        mediaDuration: TimelineDuration.fromMicroseconds(4000000),
      ),
      ProjectAsset(
        id: externalId,
        kind: ProjectAssetKind.other,
        originalFileName: 'reference.bin',
        storagePolicy: ProjectAssetStoragePolicy.external,
        contentHash: 'sha256:external',
        externalLocator: const ExternalAssetLocator(
          pathHint: '/references/reference.bin',
          securityBookmark: 'bookmark',
        ),
      ),
    ],
    strokes: [
      ProjectStroke(
        id: strokeId,
        sectionId: sectionId,
        name: 'Stroke',
        points: const [DocumentPoint(0.1, 0.2), DocumentPoint(0.8, 0.9)],
        assetId: artworkId,
        revealOnly: true,
        revealStyle: DocumentRevealStyle.directionalWipe,
        clipBounds: const DocumentRect(
          left: 0.1,
          top: 0.2,
          right: 0.8,
          bottom: 0.9,
        ),
        clipPolygons: const [
          [
            DocumentPoint(0.1, 0.2),
            DocumentPoint(0.8, 0.2),
            DocumentPoint(0.8, 0.9),
          ],
        ],
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
        assetId: artworkId,
        timing: DocumentSectionTiming(
          animationDuration: TimelineDuration.fromMicroseconds(1500000),
          pauseAfter: TimelineDuration.fromMicroseconds(250000),
          handEntranceAnimation: SectionHandEntranceAnimation.fadeIn,
          handEntranceDuration: TimelineDuration.fromMicroseconds(300000),
          handExitAnimation: SectionHandExitAnimation.moveOut,
          handExitDuration: TimelineDuration.fromMicroseconds(400000),
          keepHandVisibleAfterDrawing: true,
          audioCueAnchor: AudioCueAnchor(
            audioTrackId: AudioTrackId('audio-a'),
            sourceMediaTime: TimelineTime.fromMicroseconds(750000),
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
        locked: false,
      ),
    ],
    audioTracks: [
      ProjectAudioTrack(
        id: AudioTrackId('audio-a'),
        assetId: audioId,
        start: TimelineTime.zero,
        duration: TimelineDuration.fromMicroseconds(4000000),
        exportPolicy: AudioExportPolicy.referenceOnly,
        muted: true,
      ),
    ],
    voiceGuide: ProjectVoiceGuide(
      audioTrackId: AudioTrackId('audio-a'),
      displayName: 'Narration',
      originalFileName: 'voice.wav',
    ),
  );
}
