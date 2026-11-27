import 'dart:ui';

import 'package:handdraw_studio/features/path_document/domain/models/path_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

class SvgArtworkImport {
  SvgArtworkImport({
    required List<SvgImportedPath> paths,
    required List<String> warnings,
  }) : paths = List.unmodifiable(paths),
       warnings = List.unmodifiable(warnings),
       report = SvgImportReport(
         importedPathCount: paths.length,
         filledShapeCount: paths.where((path) => path.isFilled).length,
         textPathCount: paths.where((path) => path.isText).length,
         warningCount: warnings.length,
       );

  final List<SvgImportedPath> paths;
  final List<String> warnings;
  final SvgImportReport report;

  Map<String, Object?> toTransferJson() => {
    'paths': [for (final path in paths) path.toTransferJson()],
    'warnings': warnings,
  };

  factory SvgArtworkImport.fromTransferJson(Map<Object?, Object?> json) =>
      SvgArtworkImport(
        paths: [
          for (final raw in json['paths']! as List)
            SvgImportedPath.fromTransferJson(raw as Map<Object?, Object?>),
        ],
        warnings: List<String>.from(json['warnings']! as List),
      );

  PathDocument get document => PathDocument(
    viewBox: const Size(1, 1),
    layers: [
      for (final path in paths)
        PathLayer(
          id: 'layer:${path.id}',
          name: path.id,
          kind: path.isText ? PathLayerKind.text : PathLayerKind.artwork,
          paths: [
            EditablePath(
              id: path.id,
              name: path.id,
              geometry: path.geometry,
              appearance: PathAppearance(
                hasFill: path.isFilled,
                hasStroke: !path.isFilled,
                fillColorValue: path.fillColorValue,
              ),
              revealBehavior: PathRevealBehavior(
                mode: path.isFilled || path.isText
                    ? PathRevealMode.directionalWipe
                    : PathRevealMode.brush,
                widthFraction: path.recommendedRevealWidth,
                clipBounds: path.clipBounds,
                animationGeometry: path.animationGeometry,
              ),
            ),
          ],
        ),
    ],
  );
}

class SvgImportedPath {
  const SvgImportedPath({
    required this.id,
    required this.geometry,
    required this.animationGeometry,
    required this.clipBounds,
    required this.recommendedRevealWidth,
    required this.isFilled,
    required this.isText,
    this.isConnector = false,
    this.isGlobalDecoration = false,
    this.rightToLeft = false,
    this.originalText,
    this.fontSize,
    this.lineCount,
    this.fillColorValue,
  });

  final String id;
  final StrokePathGeometry geometry;
  final StrokePathGeometry? animationGeometry;
  final Rect clipBounds;

  /// Reveal width normalized against the SVG view-box height.
  final double recommendedRevealWidth;
  final bool isFilled;
  final bool isText;
  final bool isConnector;
  final bool isGlobalDecoration;
  final bool rightToLeft;
  final String? originalText;
  final double? fontSize;
  final int? lineCount;
  final int? fillColorValue;

  Map<String, Object?> toTransferJson() => {
    'id': id,
    'geometry': geometry.toJson(),
    'animationGeometry': animationGeometry?.toJson(),
    'clipBounds': [
      clipBounds.left,
      clipBounds.top,
      clipBounds.right,
      clipBounds.bottom,
    ],
    'recommendedRevealWidth': recommendedRevealWidth,
    'isFilled': isFilled,
    'isText': isText,
    'isConnector': isConnector,
    'isGlobalDecoration': isGlobalDecoration,
    'rightToLeft': rightToLeft,
    'originalText': originalText,
    'fontSize': fontSize,
    'lineCount': lineCount,
    'fillColorValue': fillColorValue,
  };

  factory SvgImportedPath.fromTransferJson(Map<Object?, Object?> json) {
    final clip = json['clipBounds']! as List;
    final animation = json['animationGeometry'];
    return SvgImportedPath(
      id: json['id']! as String,
      geometry: StrokePathGeometry.fromJson(
        Map<String, dynamic>.from(json['geometry']! as Map),
      ),
      animationGeometry: animation == null
          ? null
          : StrokePathGeometry.fromJson(
              Map<String, dynamic>.from(animation as Map),
            ),
      clipBounds: Rect.fromLTRB(
        (clip[0] as num).toDouble(),
        (clip[1] as num).toDouble(),
        (clip[2] as num).toDouble(),
        (clip[3] as num).toDouble(),
      ),
      recommendedRevealWidth: (json['recommendedRevealWidth']! as num)
          .toDouble(),
      isFilled: json['isFilled']! as bool,
      isText: json['isText']! as bool,
      isConnector: json['isConnector'] as bool? ?? false,
      isGlobalDecoration: json['isGlobalDecoration'] as bool? ?? false,
      rightToLeft: json['rightToLeft'] as bool? ?? false,
      originalText: json['originalText'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      lineCount: (json['lineCount'] as num?)?.toInt(),
      fillColorValue: (json['fillColorValue'] as num?)?.toInt(),
    );
  }
}

class SvgImportReport {
  const SvgImportReport({
    required this.importedPathCount,
    required this.filledShapeCount,
    required this.textPathCount,
    required this.warningCount,
  });

  final int importedPathCount;
  final int filledShapeCount;
  final int textPathCount;
  final int warningCount;

  String get summary =>
      '$importedPathCount paths imported • '
      '$filledShapeCount filled shapes • '
      '$textPathCount text paths • '
      '$warningCount warnings';
}
