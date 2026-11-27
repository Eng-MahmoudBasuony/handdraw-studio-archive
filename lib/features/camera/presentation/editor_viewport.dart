import 'package:flutter/material.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';

/// Presentation-only viewport used while composing camera views.
///
/// This transforms the raw editor scene. Runtime camera composition remains
/// reserved for Preview and export.
class EditorViewport extends StatelessWidget {
  const EditorViewport({super.key, required this.view, required this.child});

  final CameraView view;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    key: const ValueKey('camera-editor-viewport'),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = 1 / view.viewportWidth;
        final transform = Matrix4.identity()
          ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1)
          ..translateByDouble(
            -view.centerX * size.width,
            -view.centerY * size.height,
            0,
            1,
          );
        return Transform(
          key: const ValueKey('camera-editor-viewport-transform'),
          transform: transform,
          transformHitTests: false,
          child: child,
        );
      },
    ),
  );
}
