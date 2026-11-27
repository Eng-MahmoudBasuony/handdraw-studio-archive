import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_visual_compositor.dart';

void main() {
  const project = Size(1600, 900);
  const output = Size(1920, 1080);

  test(
    'identity maps project top-left, center, and bottom-right exactly once',
    () {
      final transform = CameraCanvasTransform.forView(
        view: const CameraView.identity(),
        projectSize: project,
        outputSize: output,
      );
      expect(transform.transformPoint(Offset.zero), Offset.zero);
      expect(
        transform.transformPoint(const Offset(800, 450)),
        const Offset(960, 540),
      );
      expect(
        transform.transformPoint(const Offset(1600, 900)),
        const Offset(1920, 1080),
      );
    },
  );

  test(
    'scale and translate preserve the requested normalized camera center',
    () {
      const view = CameraView(centerX: .25, centerY: .75, viewportWidth: .5);
      final transform = CameraCanvasTransform.forView(
        view: view,
        projectSize: project,
        outputSize: output,
      );
      expect(
        transform.transformPoint(const Offset(400, 675)),
        const Offset(960, 540),
      );
      expect(transform.transformPoint(const Offset(0, 450)), Offset.zero);
      expect(
        transform.transformPoint(const Offset(-400, 225)),
        const Offset(-960, -540),
      );
    },
  );
}
