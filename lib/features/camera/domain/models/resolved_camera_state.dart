import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';

sealed class ResolvedCameraState {
  const ResolvedCameraState();
}

final class ResolvedSingleCameraView extends ResolvedCameraState {
  const ResolvedSingleCameraView(this.view);
  final CameraView view;
}

final class ResolvedCameraBlend extends ResolvedCameraState {
  const ResolvedCameraBlend({
    required this.fromView,
    required this.toView,
    required this.targetOpacity,
  });
  final CameraView fromView;
  final CameraView toView;
  final double targetOpacity;
}
