import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

enum PathLayerKind { artwork, text, annotation }

enum PathRevealMode { brush, directionalWipe }

class PathAppearance {
  const PathAppearance({
    this.hasFill = false,
    this.hasStroke = true,
    this.opacity = 1,
    this.fillColorValue,
  });

  final bool hasFill;
  final bool hasStroke;
  final double opacity;
  final int? fillColorValue;
}

class PathRevealBehavior {
  const PathRevealBehavior({
    this.mode = PathRevealMode.brush,
    this.widthFraction = 0.02,
    this.clipBounds,
    this.animationGeometry,
  });

  final PathRevealMode mode;
  final double widthFraction;
  final Rect? clipBounds;
  final StrokePathGeometry? animationGeometry;
}

class EditablePath {
  const EditablePath({
    required this.id,
    required this.name,
    required this.geometry,
    this.reversed = false,
    this.hidden = false,
    this.appearance = const PathAppearance(),
    this.revealBehavior = const PathRevealBehavior(),
  });

  final String id;
  final String name;
  final StrokePathGeometry geometry;
  final bool reversed;
  final bool hidden;
  final PathAppearance appearance;
  final PathRevealBehavior revealBehavior;

  StrokePathGeometry get displayedGeometry =>
      reversed ? geometry.reversed() : geometry;
}

class PathLayer {
  PathLayer({
    required this.id,
    required this.name,
    required this.kind,
    required List<EditablePath> paths,
  }) : paths = List.unmodifiable(paths);

  final String id;
  final String name;
  final PathLayerKind kind;
  final List<EditablePath> paths;
}

/// Unified document exchanged by manual, SVG, and raster import adapters.
class PathDocument {
  PathDocument({required this.viewBox, required List<PathLayer> layers})
    : layers = List.unmodifiable(layers);

  final Size viewBox;
  final List<PathLayer> layers;

  List<EditablePath> get paths => List.unmodifiable([
    for (final layer in layers)
      for (final path in layer.paths)
        if (!path.hidden) path,
  ]);
}
