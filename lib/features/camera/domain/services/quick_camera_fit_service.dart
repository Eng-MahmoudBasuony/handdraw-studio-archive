import 'dart:math' as math;

import 'package:handdraw_studio/features/camera/domain/models/camera_world_bounds.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/policies/camera_view_policy.dart';

enum CameraFitFailure { emptyBounds, invalidAspectRatio, unsafeResult }

final class CameraFitResult {
  const CameraFitResult.success(this.view) : failure = null;
  const CameraFitResult.failure(this.failure) : view = null;
  final CameraView? view;
  final CameraFitFailure? failure;
  bool get isSuccess => view != null;
}

final class QuickCameraFitService {
  const QuickCameraFitService({this.policy = const CameraViewPolicy()});
  final CameraViewPolicy policy;

  CameraFitResult fit({
    required CameraWorldBounds? bounds,
    required double projectAspectRatio,
    double paddingFraction = CameraViewPolicy.fitPaddingFraction,
  }) {
    if (bounds == null || bounds.isEmpty) {
      return const CameraFitResult.failure(CameraFitFailure.emptyBounds);
    }
    if (!projectAspectRatio.isFinite || projectAspectRatio <= 0) {
      return const CameraFitResult.failure(CameraFitFailure.invalidAspectRatio);
    }
    final paddingScale = 1 + math.max(0, paddingFraction) * 2;
    final width = math.max(bounds.width, bounds.height) * paddingScale;
    final view = policy.clampZoom(
      CameraView(
        centerX: bounds.centerX,
        centerY: bounds.centerY,
        viewportWidth: width,
      ),
    );
    return policy.isSafe(view)
        ? CameraFitResult.success(view)
        : const CameraFitResult.failure(CameraFitFailure.unsafeResult);
  }
}
