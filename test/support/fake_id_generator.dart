import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

final class SequentialIdGenerator implements IdGenerator {
  var _next = 0;

  String _value(String prefix) => '${prefix}_${_next++}';

  @override
  ProjectId projectId() => ProjectId(_value('project'));

  @override
  StrokeId strokeId() => StrokeId(_value('stroke'));

  @override
  StrokePauseId strokePauseId() => StrokePauseId(_value('pause'));

  @override
  SectionId sectionId() => SectionId(_value('section'));

  @override
  SceneId sceneId() => SceneId(_value('scene'));

  @override
  AudioTrackId audioTrackId() => AudioTrackId(_value('audio'));

  @override
  ProjectAssetId projectAssetId() => ProjectAssetId(_value('asset'));
  @override
  CameraTrackId cameraTrackId() => CameraTrackId(_value('camera_track'));
  @override
  CameraShotId cameraShotId() => CameraShotId(_value('camera_shot'));
  @override
  CameraKeyframeId cameraKeyframeId() =>
      CameraKeyframeId(_value('camera_keyframe'));
}

typedef FakeIdGenerator = SequentialIdGenerator;
