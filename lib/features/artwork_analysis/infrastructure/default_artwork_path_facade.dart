import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui';

import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/path_document/domain/repositories/artwork_importer.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_artwork_import.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_artwork_importer.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_filled_path_tracer.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_text_layer_rasterizer.dart';

class DefaultArtworkPathFacade implements ArtworkPathFacade {
  DefaultArtworkPathFacade({required List<ArtworkPathStrategy> strategies})
    : _strategies = Map.unmodifiable({
        for (final strategy in strategies) strategy.kind: strategy,
      }) {
    if (_strategies.length != strategies.length) {
      throw ArgumentError(
        'Only one artwork path strategy is allowed per type.',
      );
    }
  }

  factory DefaultArtworkPathFacade.standard({SmartPathEngine? rasterEngine}) =>
      DefaultArtworkPathFacade(
        strategies: [
          RasterArtworkPathStrategy(rasterEngine ?? const SmartPathEngine()),
          SvgArtworkPathStrategy(rasterEngine ?? const SmartPathEngine()),
        ],
      );

  final Map<ArtworkSourceKind, ArtworkPathStrategy> _strategies;

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) {
    final strategy = _strategies[request.kind];
    if (strategy == null) {
      throw UnsupportedError('No path strategy supports ${request.kind.name}.');
    }
    return strategy.analyze(request);
  }
}

class RasterArtworkPathStrategy implements ArtworkPathStrategy {
  const RasterArtworkPathStrategy(this._engine);

  final SmartPathEngine _engine;

  @override
  ArtworkSourceKind get kind => ArtworkSourceKind.raster;

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async =>
      ArtworkPathResult(
        analysis: await _engine.analyze(
          image: request.previewImage,
          encodedImage: request.previewBytes,
          onProgress: request.onProgress,
          cancellationToken: request.cancellationToken,
          coordinateBounds: request.coordinateBounds,
        ),
      );
}

class SvgArtworkPathStrategy implements ArtworkPathStrategy {
  const SvgArtworkPathStrategy(
    this._rasterEngine, [
    this._importer = const SvgArtworkImporter(),
    this._textLayerRasterizer = const SvgTextLayerRasterizer(),
    this._filledPathRasterizer = const SvgFilledPathRasterizer(),
    this._filledPathTracePolicy = const SvgFilledPathTracePolicy(),
  ]);

  final SmartPathEngine _rasterEngine;
  final ArtworkImporter<SvgArtworkImport> _importer;
  final SvgTextLayerRasterizer _textLayerRasterizer;
  final SvgFilledPathRasterizer _filledPathRasterizer;
  final SvgFilledPathTracePolicy _filledPathTracePolicy;

  @override
  ArtworkSourceKind get kind => ArtworkSourceKind.svg;

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async {
    request.onProgress?.call(
      const SmartPathProgress(
        stage: SmartPathProgressStage.recognizingText,
        fraction: 0.02,
      ),
    );
    final imported = request.cachedSvgPaths.isNotEmpty
        ? SvgArtworkImport(paths: request.cachedSvgPaths, warnings: const [])
        : await _importer.import(
            ArtworkSource(
              path: 'embedded.svg',
              bytes: request.sourceBytes,
              extension: 'svg',
            ),
          );
    final hasNativeText = imported.paths.any((path) => path.isText);
    final preciseTraces = List<SmartTextPathTrace?>.filled(
      imported.paths.length,
      null,
    );
    if (hasNativeText && request.sourceBytes.isNotEmpty) {
      request.onProgress?.call(
        const SmartPathProgress(
          stage: SmartPathProgressStage.tracingText,
          fraction: 0.38,
        ),
      );
      Image? textLayer;
      try {
        textLayer = await _textLayerRasterizer.rasterize(
          utf8.decode(request.sourceBytes),
        );
        final textTraces = await _rasterEngine.traceTextRegions(
          image: textLayer,
          regions: [
            for (final path in imported.paths)
              if (path.isText) path.clipBounds,
          ],
        );
        var traceIndex = 0;
        for (var index = 0; index < imported.paths.length; index++) {
          if (!imported.paths[index].isText) continue;
          if (traceIndex < textTraces.length) {
            preciseTraces[index] = textTraces[traceIndex];
          }
          traceIndex++;
        }
      } on Object {
        // Imported and migrated SVGs remain usable through their legacy
        // baseline geometry when a renderer cannot isolate their text layer.
      } finally {
        textLayer?.dispose();
      }
    }
    for (var index = 0; index < imported.paths.length; index++) {
      request.onProgress?.call(
        SmartPathProgress(
          stage: SmartPathProgressStage.tracingShapes,
          fraction: 0.62 + 0.26 * index / math.max(1, imported.paths.length),
        ),
      );
      final path = imported.paths[index];
      if (!path.isFilled ||
          path.isText ||
          !_filledPathTracePolicy.shouldTrace(path.geometry)) {
        continue;
      }
      Image? isolatedPath;
      try {
        isolatedPath = await _filledPathRasterizer.rasterize(path.geometry);
        final traces = await _rasterEngine.traceTextRegions(
          image: isolatedPath,
          regions: [path.clipBounds],
        );
        if (traces.isNotEmpty && traces.single.isUsable) {
          preciseTraces[index] = traces.single;
        }
      } on Object {
        // A compact directional reveal remains a safe fallback when a device
        // cannot rasterize or trace one vector contour.
      } finally {
        isolatedPath?.dispose();
      }
    }
    final nativeSections = _nativeSections(imported.paths, preciseTraces);
    var rasterTextSections = const <SmartPathSection>[];
    var rasterWarnings = const <String>[];
    var processing = const SmartPathProcessingRecord();
    if (!hasNativeText) {
      final raster = await _rasterEngine.analyze(
        image: request.previewImage,
        encodedImage: request.previewBytes,
        onProgress: request.onProgress == null
            ? null
            : (update) => request.onProgress!(
                SmartPathProgress(
                  stage: update.stage,
                  fraction: 0.88 + update.fraction * 0.10,
                ),
              ),
        cancellationToken: request.cancellationToken,
      );
      rasterTextSections = raster.sections
          .where((section) => section.kind == SmartSectionKind.text)
          .toList(growable: false);
      rasterWarnings = raster.warnings;
      processing = raster.processing;
    }
    request.onProgress?.call(
      const SmartPathProgress(
        stage: SmartPathProgressStage.finalizing,
        fraction: 0.98,
      ),
    );
    return ArtworkPathResult(
      analysis: SmartPathAnalysis(
        sections: [...nativeSections, ...rasterTextSections],
        warnings: [...imported.warnings, ...rasterWarnings],
        processing: processing,
      ),
      nativePaths: imported.paths,
    );
  }
}

List<SmartPathSection> _nativeSections(
  List<SvgImportedPath> paths, [
  List<SmartTextPathTrace?> preciseTraces = const [],
]) {
  const unitRect = Rect.fromLTWH(0, 0, 1, 1);
  final sections = <SmartPathSection>[];
  for (var index = 0; index < paths.length; index++) {
    final path = paths[index];
    final trace = index < preciseTraces.length ? preciseTraces[index] : null;
    final hasPreciseTrace = trace?.isUsable ?? false;
    final animation = path.animationGeometry ?? path.geometry;
    sections.add(
      SmartPathSection(
        id: 'svg-edit:svg-${paths[index].id}-$index',
        kind: path.isText ? SmartSectionKind.text : SmartSectionKind.shape,
        bounds: path.isText
            ? hasPreciseTrace
                  ? trace!.bounds
                  : path.clipBounds
            : animation
                  .toPath(unitRect)
                  .getBounds()
                  .inflate(math.max(0.001, path.recommendedRevealWidth * 0.5))
                  .intersect(unitRect),
        label: path.id,
        paths: hasPreciseTrace
            ? trace!.paths
            : [SmartGeneratedPath(points: animation.sample())],
        recommendedRevealWidth: hasPreciseTrace
            ? trace!.recommendedRevealWidth
            : path.recommendedRevealWidth,
        mode: SmartSectionMode.handDraw,
        role: path.isConnector
            ? SmartSectionRole.connector
            : path.isGlobalDecoration
            ? SmartSectionRole.globalDecoration
            : SmartSectionRole.content,
        hasPreciseTrace: hasPreciseTrace,
        rightToLeft: path.rightToLeft,
      ),
    );
  }
  return List.unmodifiable(sections);
}
