import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/operations/camera_document_operations.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_duplicator.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';
import 'support/project_document_parity_fixture.dart';

void main() {
  const operations = CameraDocumentOperations();
  const codec = DevelopmentProjectManifestCodec();

  test('empty track and create/delete/duplicate preserve typed stable IDs', () {
    var document = projectDocumentParityFixture();
    final created = operations.createTrack(document, _track(const []));
    expect(created.isSuccess, isTrue);
    document = created.document;
    final shot = _shot('a', startUs: 0, durationUs: 1000);
    document = operations.createShot(document, shot).document;
    final duplicate = operations.duplicateShot(
      document,
      shot.id,
      shotId: CameraShotId('shot-b'),
      keyframeIds: [CameraKeyframeId('key-b')],
      startTime: TimelineTime.fromMicroseconds(1000),
    );
    expect(duplicate.isSuccess, isTrue);
    expect(duplicate.document.cameraTrack!.shots.map((s) => s.id.value), [
      'shot-a',
      'shot-b',
    ]);
    expect(
      duplicate.document.cameraTrack!.shots.last.keyframes.single.id.value,
      'key-b',
    );
    expect(
      operations
          .deleteShot(duplicate.document, shot.id)
          .document
          .cameraTrack!
          .shots
          .single
          .id
          .value,
      'shot-b',
    );
  });

  test(
    'overlap is typed, lock protects edits, and manual edits change authorship',
    () {
      final document = projectDocumentParityFixture().copyWith(
        cameraTrack: _track([
          _shot(
            'a',
            startUs: 0,
            durationUs: 1000,
            authorship: CameraAuthorship.auto,
          ),
        ]),
      );
      final moved = operations.moveShot(
        document,
        CameraShotId('shot-a'),
        TimelineTime.fromMicroseconds(10),
      );
      expect(
        moved.document.cameraTrack!.shots.single.authorship,
        CameraAuthorship.manual,
      );
      final locked = operations
          .setLock(document, CameraShotId('shot-a'), true)
          .document;
      expect(
        operations
            .renameShot(locked, CameraShotId('shot-a'), 'No')
            .failure!
            .code
            .name,
        'lockedEntity',
      );
      final overlap = operations.createShot(
        document,
        _shot('b', startUs: 500, durationUs: 1000),
      );
      expect(overlap.failure!.code.name, 'overlap');
    },
  );

  test(
    'split, keyframe order, transitions, zoom and non-finite values validate',
    () {
      final base = projectDocumentParityFixture().copyWith(
        cameraTrack: _track([_shot('a', startUs: 0, durationUs: 1000)]),
      );
      final split = operations.splitShot(
        base,
        CameraShotId('shot-a'),
        TimelineTime.fromMicroseconds(400),
        rightShotId: CameraShotId('right'),
        rightFirstKeyframeId: CameraKeyframeId('right-zero'),
      );
      expect(split.isSuccess, isTrue);
      expect(
        split.document.cameraTrack!.shots.map((s) => s.duration.microseconds),
        [400, 600],
      );
      final invalid = base.copyWith(
        cameraTrack: _track([
          CameraShot(
            id: CameraShotId('bad'),
            startTime: TimelineTime.zero,
            duration: TimelineDuration.fromMicroseconds(100),
            authorship: CameraAuthorship.manual,
            isLocked: false,
            keyframes: [
              CameraKeyframe(
                id: CameraKeyframeId('bad-key'),
                offset: TimelineTime.zero,
                view: const CameraView(
                  centerX: double.nan,
                  centerY: 0,
                  viewportWidth: -1,
                ),
                incomingTransition: CameraTransition(
                  type: CameraTransitionType.cut,
                  duration: TimelineDuration.fromMicroseconds(1),
                ),
              ),
            ],
          ),
        ]),
      );
      expect(
        const ProjectDocumentValidator().validate(invalid).isValid,
        isFalse,
      );
    },
  );

  test('save/open, duplicate and both fingerprints include camera data', () {
    final source = projectDocumentParityFixture().copyWith(
      cameraTrack: _track([_shot('a', startUs: 0, durationUs: 1000)]),
    );
    final decoded = codec.decode(codec.encode(source));
    expect(decoded.cameraTrack, source.cameraTrack);
    final duplicate = const ProjectDocumentDuplicator().duplicate(
      source,
      ids: SequentialIdGenerator(),
    );
    expect(duplicate.cameraTrack!.id, isNot(source.cameraTrack!.id));
    expect(
      duplicate.cameraTrack!.shots.single.id,
      isNot(source.cameraTrack!.shots.single.id),
    );
    const fingerprints = CanonicalDocumentFingerprintCalculator();
    final changed = source.copyWith(
      cameraTrack: source.cameraTrack!.copyWith(
        defaultView: const CameraView(
          centerX: 2,
          centerY: 3,
          viewportWidth: .5,
        ),
      ),
    );
    expect(
      fingerprints.calculate(changed).semantic,
      isNot(fingerprints.calculate(source).semantic),
    );
    expect(
      fingerprints.calculate(changed).persistence,
      isNot(fingerprints.calculate(source).persistence),
    );
  });

  test(
    'decode rejects missing and duplicate camera IDs without generating IDs',
    () {
      final source = projectDocumentParityFixture().copyWith(
        cameraTrack: _track([
          _shot('a', startUs: 0, durationUs: 1000),
          _shot('b', startUs: 1000, durationUs: 1000),
        ]),
      );
      final missing = codec.encode(source);
      final project = missing['project']! as Map<String, Object?>;
      final camera = project['cameraTrack']! as Map<String, Object?>;
      camera.remove('id');
      expect(() => codec.decode(missing), throwsFormatException);
      final duplicate = codec.encode(source);
      final p2 = duplicate['project']! as Map<String, Object?>;
      final c2 = p2['cameraTrack']! as Map<String, Object?>;
      final shots = c2['shots']! as List<Object?>;
      (shots[1]! as Map<String, Object?>)['id'] = 'shot-a';
      expect(() => codec.decode(duplicate), throwsA(isA<FormatException>()));
    },
  );

  test('1000 shots validate and codec round-trip', () {
    final shots = [
      for (var i = 0; i < 1000; i++)
        _shot('$i', startUs: i * 1000, durationUs: 1000),
    ];
    final document = projectDocumentParityFixture().copyWith(
      cameraTrack: _track(shots),
    );
    expect(const ProjectDocumentValidator().validate(document).isValid, isTrue);
    expect(
      codec.decode(codec.encode(document)).cameraTrack!.shots,
      hasLength(1000),
    );
  });
}

ProjectCameraTrack _track(List<CameraShot> shots) =>
    ProjectCameraTrack(id: CameraTrackId('camera-track'), shots: shots);
CameraShot _shot(
  String suffix, {
  required int startUs,
  required int durationUs,
  CameraAuthorship authorship = CameraAuthorship.manual,
}) => CameraShot(
  id: CameraShotId('shot-$suffix'),
  startTime: TimelineTime.fromMicroseconds(startUs),
  duration: TimelineDuration.fromMicroseconds(durationUs),
  authorship: authorship,
  isLocked: false,
  keyframes: [
    CameraKeyframe(
      id: CameraKeyframeId('key-$suffix'),
      offset: TimelineTime.zero,
      view: const CameraView.identity(),
    ),
  ],
);
