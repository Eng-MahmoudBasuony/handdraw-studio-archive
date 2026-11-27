import 'dart:math';

import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

/// Creation boundary for persistent identities.
///
/// Keeping generation behind this interface makes duplication and migrations
/// deterministic in tests and prevents model decoders from inventing IDs.
abstract interface class IdGenerator {
  ProjectId projectId();
  StrokeId strokeId();
  StrokePauseId strokePauseId();
  SectionId sectionId();
  SceneId sceneId();
  AudioTrackId audioTrackId();
  ProjectAssetId projectAssetId();
  CameraTrackId cameraTrackId();
  CameraShotId cameraShotId();
  CameraKeyframeId cameraKeyframeId();
}

/// Dependency-free 128-bit random IDs for production creation flows.
///
/// The 32 hexadecimal digits provide the same random payload size as UUID v4.
/// Type prefixes improve diagnostics without participating in type safety.
final class SecureRandomIdGenerator implements IdGenerator {
  SecureRandomIdGenerator() : _random = Random.secure();

  final Random _random;

  String _next(String prefix) {
    final buffer = StringBuffer(prefix);
    for (var index = 0; index < 16; index++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  @override
  ProjectId projectId() => ProjectId(_next('project_'));

  @override
  StrokeId strokeId() => StrokeId(_next('stroke_'));

  @override
  StrokePauseId strokePauseId() => StrokePauseId(_next('pause_'));

  @override
  SectionId sectionId() => SectionId(_next('section_'));

  @override
  SceneId sceneId() => SceneId(_next('scene_'));

  @override
  AudioTrackId audioTrackId() => AudioTrackId(_next('audio_'));

  @override
  ProjectAssetId projectAssetId() => ProjectAssetId(_next('asset_'));
  @override
  CameraTrackId cameraTrackId() => CameraTrackId(_next('camera_track_'));
  @override
  CameraShotId cameraShotId() => CameraShotId(_next('camera_shot_'));
  @override
  CameraKeyframeId cameraKeyframeId() =>
      CameraKeyframeId(_next('camera_keyframe_'));
}
