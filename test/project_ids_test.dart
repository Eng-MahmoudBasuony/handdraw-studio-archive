import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

void main() {
  test('typed IDs compare by both type and normalized value', () {
    expect(ProjectId(' same '), ProjectId('same'));
    expect(ProjectId('same'), isNot(StrokeId('same')));
    expect(ProjectId('same').hashCode, ProjectId('same').hashCode);
  });

  test('missing development-schema identity is rejected', () {
    expect(() => ProjectId(''), throwsArgumentError);
    expect(() => SectionId('   '), throwsArgumentError);
  });

  test('secure generator emits unique typed 128-bit payloads', () {
    final generator = SecureRandomIdGenerator();
    final values = <String>{};
    for (var index = 0; index < 1000; index++) {
      values.add(generator.strokeId().value);
    }
    expect(values, hasLength(1000));
    expect(
      values.every((value) => RegExp(r'^stroke_[0-9a-f]{32}$').hasMatch(value)),
      isTrue,
    );
  });

  test('allocator retries collisions and fails after its bound', () {
    final recovers = IdAllocationContext(
      generator: _CollisionIdGenerator(recover: true),
      usedIds: [StrokeId('stroke_collision')],
      maximumAttempts: 2,
    );
    expect(recovers.strokeId(), StrokeId('stroke_unique'));

    final fails = IdAllocationContext(
      generator: _CollisionIdGenerator(recover: false),
      usedIds: [StrokeId('stroke_collision')],
      maximumAttempts: 2,
    );
    expect(fails.strokeId, throwsStateError);
  });
}

final class _CollisionIdGenerator implements IdGenerator {
  _CollisionIdGenerator({required this.recover});

  final bool recover;
  var _strokeCalls = 0;

  @override
  StrokeId strokeId() {
    _strokeCalls++;
    return StrokeId(
      recover && _strokeCalls > 1 ? 'stroke_unique' : 'stroke_collision',
    );
  }

  @override
  StrokePauseId strokePauseId() => StrokePauseId('pause');

  @override
  ProjectId projectId() => ProjectId('project');
  @override
  SectionId sectionId() => SectionId('section');
  @override
  SceneId sceneId() => SceneId('scene');
  @override
  AudioTrackId audioTrackId() => AudioTrackId('audio');
  @override
  ProjectAssetId projectAssetId() => ProjectAssetId('asset');
  @override
  CameraTrackId cameraTrackId() => CameraTrackId('camera_track');
  @override
  CameraShotId cameraShotId() => CameraShotId('camera_shot');
  @override
  CameraKeyframeId cameraKeyframeId() => CameraKeyframeId('camera_keyframe');
}
