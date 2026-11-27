import 'dart:math' as math;

import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_projection.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';

final class ProjectedFramingResult {
  const ProjectedFramingResult({
    required this.projectedSafeContainmentRatio,
    required this.isContained,
  });
  final double projectedSafeContainmentRatio;
  final bool isContained;
}

/// Uses the renderer's camera projection contract to validate final targets.
final class ProjectedFramingValidator {
  const ProjectedFramingValidator();

  ProjectedFramingResult validate({
    required CameraView view,
    required SemanticWorldBounds target,
    required double worldWidth,
    required double worldHeight,
    required double safeOutputFraction,
  }) {
    const outputWidth = 1920.0;
    const outputHeight = 1080.0;
    final projection = const CameraProjectionCalculator().calculate(
      view: view,
      projectAspectRatio: worldWidth / worldHeight,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
    );
    final left = projection.normalizedViewportX(target.left / worldWidth);
    final right = projection.normalizedViewportX(target.right / worldWidth);
    final top = projection.normalizedViewportY(target.top / worldHeight);
    final bottom = projection.normalizedViewportY(target.bottom / worldHeight);
    final inset = (1 - safeOutputFraction) / 2;
    final intersectionWidth = math.max(
      0,
      math.min(right, 1 - inset) - math.max(left, inset),
    );
    final intersectionHeight = math.max(
      0,
      math.min(bottom, 1 - inset) - math.max(top, inset),
    );
    final targetArea = math.max(.000000001, (right - left) * (bottom - top));
    final ratio = (intersectionWidth * intersectionHeight / targetArea)
        .clamp(0, 1)
        .toDouble();
    return ProjectedFramingResult(
      projectedSafeContainmentRatio: ratio,
      isContained: ratio >= 1 - 1e-9,
    );
  }

  CameraView repair({
    required CameraView view,
    required SemanticWorldBounds target,
    required double worldWidth,
    required double worldHeight,
    required double safeOutputFraction,
    required double maximumViewportWidth,
  }) {
    const outputAspectRatio = 1920 / 1080;
    final projectAspectRatio = worldWidth / worldHeight;
    final requiredWidth = math.max(
      (target.right - target.left) / worldWidth,
      (target.bottom - target.top) /
          worldHeight *
          outputAspectRatio /
          projectAspectRatio,
    );
    final viewportWidth = math
        .max(view.viewportWidth, requiredWidth / safeOutputFraction)
        .clamp(.0001, maximumViewportWidth)
        .toDouble();
    return CameraView(
      centerX: target.centerX / worldWidth,
      centerY: target.centerY / worldHeight,
      viewportWidth: viewportWidth,
    );
  }
}
