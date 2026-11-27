import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';

final class CameraProjection {
  const CameraProjection({
    required this.worldLeft,
    required this.worldTop,
    required this.worldWidth,
    required this.worldHeight,
    required this.outputWidth,
    required this.outputHeight,
  });
  final double worldLeft,
      worldTop,
      worldWidth,
      worldHeight,
      outputWidth,
      outputHeight;
  double normalizedViewportX(double worldX) =>
      (worldX - worldLeft) / worldWidth;
  double normalizedViewportY(double worldY) =>
      (worldY - worldTop) / worldHeight;
}

final class CameraProjectionCalculator {
  const CameraProjectionCalculator();
  CameraProjection calculate({
    required CameraView view,
    required double projectAspectRatio,
    required double outputWidth,
    required double outputHeight,
  }) {
    if (!projectAspectRatio.isFinite ||
        projectAspectRatio <= 0 ||
        !outputWidth.isFinite ||
        outputWidth <= 0 ||
        !outputHeight.isFinite ||
        outputHeight <= 0) {
      throw ArgumentError(
        'Projection dimensions and aspect ratio must be finite and positive.',
      );
    }
    final height = view.normalizedViewportHeightFor(
      projectAspectRatio: projectAspectRatio,
      outputAspectRatio: outputWidth / outputHeight,
    );
    return CameraProjection(
      worldLeft: view.centerX - view.viewportWidth / 2,
      worldTop: view.centerY - height / 2,
      worldWidth: view.viewportWidth,
      worldHeight: height,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
    );
  }
}
