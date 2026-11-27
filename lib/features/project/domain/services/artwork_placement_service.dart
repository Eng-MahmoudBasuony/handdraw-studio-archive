import 'dart:math' as math;

import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

final class ArtworkPlacementService {
  const ArtworkPlacementService();

  ProjectArtworkPlacement createDefault({
    required ProjectCanvas canvas,
    required double encodedWidth,
    required double encodedHeight,
    DocumentRect? visibleBounds,
    double safePaddingFraction = .04,
  }) {
    final encoded = DocumentRect(
      left: 0,
      top: 0,
      right: encodedWidth,
      bottom: encodedHeight,
    );
    final sameAspect =
        ((encodedWidth / encodedHeight) - (canvas.width / canvas.height))
            .abs() <
        .001;
    return ProjectArtworkPlacement(
      encodedBounds: encoded,
      visibleBounds: visibleBounds ?? encoded,
      destination: sameAspect
          ? DocumentRect(
              left: 0,
              top: 0,
              right: canvas.width.toDouble(),
              bottom: canvas.height.toDouble(),
            )
          : _contain(canvas, encodedWidth, encodedHeight, safePaddingFraction),
    );
  }

  ProjectArtworkPlacement applyMode({
    required ProjectArtworkPlacement placement,
    required ProjectCanvas canvas,
    required ArtworkPlacementMode mode,
    double safePaddingFraction = .04,
  }) {
    final source = mode == ArtworkPlacementMode.fitVisible
        ? placement.visibleBounds
        : placement.encodedBounds;
    final width = source.right - source.left;
    final height = source.bottom - source.top;
    final destination = switch (mode) {
      ArtworkPlacementMode.fitEntire || ArtworkPlacementMode.fitVisible =>
        _contain(canvas, width, height, safePaddingFraction),
      ArtworkPlacementMode.originalSize => DocumentRect(
        left: (canvas.width - width) / 2,
        top: (canvas.height - height) / 2,
        right: (canvas.width + width) / 2,
        bottom: (canvas.height + height) / 2,
      ),
      ArtworkPlacementMode.fillCanvas => DocumentRect(
        left: 0,
        top: 0,
        right: canvas.width.toDouble(),
        bottom: canvas.height.toDouble(),
      ),
    };
    return placement.copyWith(destination: destination, mode: mode);
  }

  DocumentRect _contain(
    ProjectCanvas canvas,
    double width,
    double height,
    double padding,
  ) {
    final availableWidth = canvas.width * (1 - padding * 2);
    final availableHeight = canvas.height * (1 - padding * 2);
    final scale = math.min(availableWidth / width, availableHeight / height);
    final fittedWidth = width * scale;
    final fittedHeight = height * scale;
    final left = (canvas.width - fittedWidth) / 2;
    final top = (canvas.height - fittedHeight) / 2;
    return DocumentRect(
      left: left,
      top: top,
      right: left + fittedWidth,
      bottom: top + fittedHeight,
    );
  }
}
