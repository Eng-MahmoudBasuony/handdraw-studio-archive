import 'package:handdraw_studio/features/camera/domain/models/camera_world_bounds.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

enum CameraContentCoverage {
  noContent,
  fullyVisible,
  partiallyVisible,
  outside,
}

final class CameraContentVisibilityService {
  const CameraContentVisibilityService();

  CameraContentCoverage evaluate({
    required ProjectDocument document,
    required CameraView view,
  }) {
    final content = contentBounds(document);
    if (content == null || content.isEmpty) {
      return CameraContentCoverage.noContent;
    }
    final aspect = document.canvas.width / document.canvas.height;
    final viewportHeight = view.normalizedViewportHeightFor(
      projectAspectRatio: aspect,
      outputAspectRatio: aspect,
    );
    final camera = CameraWorldBounds(
      left: view.centerX - view.viewportWidth / 2,
      top: view.centerY - viewportHeight / 2,
      right: view.centerX + view.viewportWidth / 2,
      bottom: view.centerY + viewportHeight / 2,
    );
    const epsilon = 1e-9;
    final overlapWidth =
        _min(camera.right, content.right) - _max(camera.left, content.left);
    final overlapHeight =
        _min(camera.bottom, content.bottom) - _max(camera.top, content.top);
    if (overlapWidth <= epsilon || overlapHeight <= epsilon) {
      return CameraContentCoverage.outside;
    }
    final contains =
        camera.left <= content.left + epsilon &&
        camera.top <= content.top + epsilon &&
        camera.right >= content.right - epsilon &&
        camera.bottom >= content.bottom - epsilon;
    return contains
        ? CameraContentCoverage.fullyVisible
        : CameraContentCoverage.partiallyVisible;
  }

  CameraWorldBounds? contentBounds(ProjectDocument document) {
    CameraWorldBounds? result;
    void include(CameraWorldBounds? value) {
      if (value == null || value.isEmpty) return;
      result = result == null ? value : result!.union(value);
    }

    final placement = document.artworkPlacement;
    if (placement != null) {
      include(_visibleArtworkBounds(document, placement));
    } else if (document.artworkAssetId != null) {
      include(const CameraWorldBounds(left: 0, top: 0, right: 1, bottom: 1));
    }
    for (final stroke in document.strokes) {
      if (stroke.hidden) continue;
      include(_strokeBounds(document, stroke));
    }
    return result;
  }

  CameraWorldBounds _visibleArtworkBounds(
    ProjectDocument document,
    ProjectArtworkPlacement placement,
  ) {
    final source = placement.mode == ArtworkPlacementMode.fitVisible
        ? placement.visibleBounds
        : placement.encodedBounds;
    final visible = placement.visibleBounds;
    final destination = placement.destination;
    final sourceWidth = source.right - source.left;
    final sourceHeight = source.bottom - source.top;
    final destinationWidth = destination.right - destination.left;
    final destinationHeight = destination.bottom - destination.top;
    final canvasWidth = document.canvas.width.toDouble();
    final canvasHeight = document.canvas.height.toDouble();
    return CameraWorldBounds(
      left:
          (destination.left +
              (visible.left - source.left) / sourceWidth * destinationWidth) /
          canvasWidth,
      top:
          (destination.top +
              (visible.top - source.top) / sourceHeight * destinationHeight) /
          canvasHeight,
      right:
          (destination.left +
              (visible.right - source.left) / sourceWidth * destinationWidth) /
          canvasWidth,
      bottom:
          (destination.top +
              (visible.bottom - source.top) /
                  sourceHeight *
                  destinationHeight) /
          canvasHeight,
    );
  }

  CameraWorldBounds? _strokeBounds(
    ProjectDocument document,
    ProjectStroke stroke,
  ) {
    final clip = stroke.clipBounds;
    if (clip != null) {
      return _mapNormalizedBounds(document, clip);
    }
    if (stroke.points.isEmpty) return null;
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final point in stroke.points) {
      if (point.x < left) left = point.x;
      if (point.y < top) top = point.y;
      if (point.x > right) right = point.x;
      if (point.y > bottom) bottom = point.y;
    }
    if (!left.isFinite) return null;
    const minimumSpan = .001;
    if (right - left < minimumSpan) {
      final center = (left + right) / 2;
      left = center - minimumSpan / 2;
      right = center + minimumSpan / 2;
    }
    if (bottom - top < minimumSpan) {
      final center = (top + bottom) / 2;
      top = center - minimumSpan / 2;
      bottom = center + minimumSpan / 2;
    }
    return _mapNormalizedBounds(
      document,
      DocumentRect(left: left, top: top, right: right, bottom: bottom),
    );
  }

  CameraWorldBounds _mapNormalizedBounds(
    ProjectDocument document,
    DocumentRect bounds,
  ) {
    final destination = document.artworkPlacement?.destination;
    if (destination == null) {
      return CameraWorldBounds(
        left: bounds.left,
        top: bounds.top,
        right: bounds.right,
        bottom: bounds.bottom,
      );
    }
    final width = destination.right - destination.left;
    final height = destination.bottom - destination.top;
    return CameraWorldBounds(
      left: (destination.left + bounds.left * width) / document.canvas.width,
      top: (destination.top + bounds.top * height) / document.canvas.height,
      right: (destination.left + bounds.right * width) / document.canvas.width,
      bottom:
          (destination.top + bounds.bottom * height) / document.canvas.height,
    );
  }

  double _min(double a, double b) => a < b ? a : b;
  double _max(double a, double b) => a > b ? a : b;
}
