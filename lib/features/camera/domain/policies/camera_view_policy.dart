import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';

final class CameraViewPolicy {
  const CameraViewPolicy();
  static const minimumViewportWidth = .02;
  static const maximumViewportWidth = 20.0;
  static const fitPaddingFraction = .12;
  static const safetyWorldLimit = 1000.0;

  bool isSafe(CameraView view) =>
      view.centerX.isFinite &&
      view.centerY.isFinite &&
      view.viewportWidth.isFinite &&
      view.viewportWidth >= minimumViewportWidth &&
      view.viewportWidth <= maximumViewportWidth &&
      view.centerX.abs() <= safetyWorldLimit &&
      view.centerY.abs() <= safetyWorldLimit;

  CameraView clampZoom(CameraView view) => CameraView(
    centerX: view.centerX,
    centerY: view.centerY,
    viewportWidth: view.viewportWidth.clamp(
      minimumViewportWidth,
      maximumViewportWidth,
    ),
  );
}
