import 'dart:ui';

import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';

/// Presentation-only adapter between normalized project space and the editor.
/// It deliberately knows nothing about the runtime camera compositor.
final class CameraCanvasTransform {
  const CameraCanvasTransform(
    this.artworkRect,
    this.projectAspectRatio, {
    this.editorZoom = 1,
    this.editorPan = Offset.zero,
  }) : assert(editorZoom > 0);

  final Rect artworkRect;
  final double projectAspectRatio;
  final double editorZoom;
  final Offset editorPan;

  Offset worldToCanvas(double x, double y) {
    final base = Offset(
      artworkRect.left + x * artworkRect.width,
      artworkRect.top + y * artworkRect.height,
    );
    return artworkRect.center +
        (base - artworkRect.center) * editorZoom +
        editorPan;
  }

  Offset canvasToWorld(Offset point) => Offset(
    (((point.dx - editorPan.dx - artworkRect.center.dx) / editorZoom) +
            artworkRect.center.dx -
            artworkRect.left) /
        artworkRect.width,
    (((point.dy - editorPan.dy - artworkRect.center.dy) / editorZoom) +
            artworkRect.center.dy -
            artworkRect.top) /
        artworkRect.height,
  );

  Rect frameFor(CameraView view) {
    final center = worldToCanvas(view.centerX, view.centerY);
    return Rect.fromCenter(
      center: center,
      width: view.viewportWidth * artworkRect.width * editorZoom,
      height: view.viewportWidth * artworkRect.height * editorZoom,
    );
  }

  CameraView move(CameraView source, Offset canvasDelta) => CameraView(
    centerX: source.centerX + canvasDelta.dx / (artworkRect.width * editorZoom),
    centerY:
        source.centerY + canvasDelta.dy / (artworkRect.height * editorZoom),
    viewportWidth: source.viewportWidth,
  );

  CameraView resizeFromCorner(
    CameraView source,
    Offset canvasDelta, {
    bool centered = false,
  }) {
    final dx = canvasDelta.dx * 2 / (artworkRect.width * editorZoom);
    final widthFromHeight =
        canvasDelta.dy * 2 / (artworkRect.height * editorZoom);
    final widthDelta = dx.abs() >= widthFromHeight.abs() ? dx : widthFromHeight;
    final width = (source.viewportWidth + widthDelta).clamp(.02, 20.0);
    return CameraView(
      centerX: centered
          ? source.centerX
          : source.centerX +
                canvasDelta.dx / (2 * artworkRect.width * editorZoom),
      centerY: centered
          ? source.centerY
          : source.centerY +
                canvasDelta.dy / (2 * artworkRect.height * editorZoom),
      viewportWidth: width,
    );
  }
}
