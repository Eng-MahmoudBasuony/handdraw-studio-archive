import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

/// Allocates persistent identities without silently accepting a collision.
///
/// The retry bound is defensive; collision is not an expected control path.
final class IdAllocationContext {
  IdAllocationContext({
    required this.generator,
    Iterable<ProjectEntityId> usedIds = const [],
    this.maximumAttempts = 8,
  }) : assert(maximumAttempts > 0) {
    for (final id in usedIds) {
      reserve(id);
    }
  }

  final IdGenerator generator;
  final int maximumAttempts;
  final Set<String> _used = {};

  void reserve(ProjectEntityId id) {
    final key = _key(id);
    if (!_used.add(key)) {
      throw StateError('Persistent ID is already reserved: $id.');
    }
  }

  ProjectId projectId() => _allocate(generator.projectId);
  StrokeId strokeId() => _allocate(generator.strokeId);
  StrokePauseId strokePauseId() => _allocate(generator.strokePauseId);
  SectionId sectionId() => _allocate(generator.sectionId);
  SceneId sceneId() => _allocate(generator.sceneId);
  AudioTrackId audioTrackId() => _allocate(generator.audioTrackId);
  ProjectAssetId projectAssetId() => _allocate(generator.projectAssetId);
  CameraTrackId cameraTrackId() => _allocate(generator.cameraTrackId);
  CameraShotId cameraShotId() => _allocate(generator.cameraShotId);
  CameraKeyframeId cameraKeyframeId() => _allocate(generator.cameraKeyframeId);

  T _allocate<T extends ProjectEntityId>(T Function() create) {
    for (var attempt = 0; attempt < maximumAttempts; attempt++) {
      final candidate = create();
      if (_used.add(_key(candidate))) return candidate;
    }
    throw StateError(
      'Could not allocate a unique ${T.toString()} after '
      '$maximumAttempts attempts.',
    );
  }

  String _key(ProjectEntityId id) => '${id.runtimeType}:${id.value}';
}
