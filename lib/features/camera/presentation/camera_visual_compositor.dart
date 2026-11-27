import 'dart:ui';

import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';

typedef CameraScenePainter =
    void Function(Canvas canvas, CameraCanvasTransform transform);

final class CameraCanvasTransform {
  const CameraCanvasTransform._({
    required this.scaleX,
    required this.scaleY,
    required this.translateX,
    required this.translateY,
  });
  factory CameraCanvasTransform.forView({
    required CameraView view,
    required Size projectSize,
    required Size outputSize,
  }) {
    if (projectSize.width <= 0 ||
        projectSize.height <= 0 ||
        outputSize.width <= 0 ||
        outputSize.height <= 0) {
      throw const CameraRenderException(
        'Camera render dimensions must be positive.',
      );
    }
    final projectAspect = projectSize.width / projectSize.height;
    final outputAspect = outputSize.width / outputSize.height;
    final viewportHeight = view.normalizedViewportHeightFor(
      projectAspectRatio: projectAspect,
      outputAspectRatio: outputAspect,
    );
    final worldLeft = view.centerX - view.viewportWidth / 2;
    final worldTop = view.centerY - viewportHeight / 2;
    final sx = outputSize.width / (view.viewportWidth * projectSize.width);
    final sy = outputSize.height / (viewportHeight * projectSize.height);
    return CameraCanvasTransform._(
      scaleX: sx,
      scaleY: sy,
      translateX: -worldLeft * projectSize.width * sx,
      translateY: -worldTop * projectSize.height * sy,
    );
  }
  final double scaleX, scaleY, translateX, translateY;
  void apply(Canvas canvas) {
    canvas.translate(translateX, translateY);
    canvas.scale(scaleX, scaleY);
  }

  Offset transformPoint(Offset point) =>
      Offset(point.dx * scaleX + translateX, point.dy * scaleY + translateY);
}

final class CameraVisualCompositor {
  const CameraVisualCompositor();
  void paint({
    required Canvas canvas,
    required Size outputSize,
    required Size projectSize,
    required ResolvedCameraState camera,
    required CameraScenePainter paintScene,
  }) {
    canvas.save();
    canvas.clipRect(Offset.zero & outputSize);
    switch (camera) {
      case ResolvedSingleCameraView(:final view):
        _paintView(canvas, outputSize, projectSize, view, paintScene);
      case ResolvedCameraBlend(
        :final fromView,
        :final toView,
        :final targetOpacity,
      ):
        if (!targetOpacity.isFinite || targetOpacity < 0 || targetOpacity > 1) {
          throw const CameraRenderException(
            'Camera blend opacity must be in [0,1].',
          );
        }
        if (targetOpacity == 0) {
          _paintView(canvas, outputSize, projectSize, fromView, paintScene);
        } else if (targetOpacity == 1) {
          _paintView(canvas, outputSize, projectSize, toView, paintScene);
        } else {
          final bounds = Offset.zero & outputSize;
          canvas.saveLayer(bounds, Paint());
          canvas.saveLayer(
            bounds,
            Paint()
              ..color = Color.fromARGB(
                ((1 - targetOpacity) * 255).round(),
                255,
                255,
                255,
              ),
          );
          _paintView(canvas, outputSize, projectSize, fromView, paintScene);
          canvas.restore();
          canvas.saveLayer(
            bounds,
            Paint()
              ..color = Color.fromARGB(
                (targetOpacity * 255).round(),
                255,
                255,
                255,
              )
              ..blendMode = BlendMode.plus,
          );
          _paintView(canvas, outputSize, projectSize, toView, paintScene);
          canvas.restore();
          canvas.restore();
        }
    }
    canvas.restore();
  }

  void _paintView(
    Canvas canvas,
    Size output,
    Size project,
    CameraView view,
    CameraScenePainter painter,
  ) {
    final transform = CameraCanvasTransform.forView(
      view: view,
      projectSize: project,
      outputSize: output,
    );
    painter(canvas, transform);
  }
}

final class CameraRenderException implements Exception {
  const CameraRenderException(this.message);
  final String message;
  @override
  String toString() => message;
}
