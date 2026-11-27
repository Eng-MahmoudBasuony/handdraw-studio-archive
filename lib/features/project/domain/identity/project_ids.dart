/// Stable, strongly typed identity for a persistent project entity.
///
/// IDs are deliberately not decoded or generated here. A schema decoder must
/// supply a present value, while creation and migration flows use an
/// [IdGenerator].
abstract base class ProjectEntityId {
  ProjectEntityId(String value) : value = _validate(value);

  final String value;

  static String _validate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'An entity ID cannot be empty.',
      );
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ProjectEntityId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class ProjectId extends ProjectEntityId {
  ProjectId(super.value);
}

final class StrokeId extends ProjectEntityId {
  StrokeId(super.value);
}

final class StrokePauseId extends ProjectEntityId {
  StrokePauseId(super.value);
}

final class SectionId extends ProjectEntityId {
  SectionId(super.value);
}

final class SceneId extends ProjectEntityId {
  SceneId(super.value);
}

final class AudioTrackId extends ProjectEntityId {
  AudioTrackId(super.value);
}

final class ProjectAssetId extends ProjectEntityId {
  ProjectAssetId(super.value);
}

final class CameraTrackId extends ProjectEntityId {
  CameraTrackId(super.value);
}

final class CameraShotId extends ProjectEntityId {
  CameraShotId(super.value);
}

final class CameraKeyframeId extends ProjectEntityId {
  CameraKeyframeId(super.value);
}
