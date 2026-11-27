import 'dart:math' as math;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'models.dart';
import 'sparse_skeleton_thinner.dart';
import 'text_layout_detector.dart';
import 'skeleton_graph_planner.dart';
import 'mask_coverage_validator.dart';
import 'suspected_frame_detector.dart';

enum SmartPathProgressStage {
  recognizingText,
  readingPixels,
  preparingRaster,
  tracingText,
  findingShapes,
  tracingShapes,
  validatingPaths,
  finalizing,
}

class SmartPathProgress {
  const SmartPathProgress({required this.stage, required this.fraction});

  final SmartPathProgressStage stage;
  final double fraction;
}

typedef SmartPathProgressCallback = void Function(SmartPathProgress update);

/// Cooperative cancellation for Smart Path work, including its raster
/// isolate. Cancelling is idempotent and terminates every worker currently
/// owned by the token so a superseded analysis cannot keep consuming CPU.
final class SmartPathCancellationToken {
  final Set<void Function()> _listeners = {};
  final Set<Isolate> _workers = {};
  var _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final worker in _workers.toList(growable: false)) {
      worker.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    for (final listener in _listeners.toList(growable: false)) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const SmartPathCancelledException();
  }

  void _attach(Isolate worker) {
    if (_isCancelled) {
      worker.kill(priority: Isolate.immediate);
      throw const SmartPathCancelledException();
    }
    _workers.add(worker);
  }

  void _detach(Isolate worker) {
    _workers.remove(worker);
  }
}

final class SmartPathCancelledException implements Exception {
  const SmartPathCancelledException();

  @override
  String toString() => 'Smart Path analysis was cancelled.';
}

class SmartPathEngine {
  const SmartPathEngine({
    this.textDetector = const MethodChannelTextLayoutDetector(),
    this.processingOptions = SmartPathProcessingOptions.fromEnvironment,
  });

  final TextLayoutDetector textDetector;
  final SmartPathProcessingOptions processingOptions;

  Future<SmartPathAnalysis> analyze({
    required ui.Image image,
    required Uint8List encodedImage,
    SmartPathProgressCallback? onProgress,
    SmartPathCancellationToken? cancellationToken,
    ui.Rect coordinateBounds = const ui.Rect.fromLTWH(0, 0, 1, 1),
  }) async {
    void progress(SmartPathProgressStage stage, double fraction) {
      onProgress?.call(
        SmartPathProgress(stage: stage, fraction: fraction.clamp(0.0, 1.0)),
      );
    }

    cancellationToken?.throwIfCancelled();
    progress(SmartPathProgressStage.recognizingText, 0.02);
    final warnings = <String>[];
    List<SmartTextRegion> textRegions;
    try {
      textRegions = await textDetector.detect(encodedImage);
    } catch (_) {
      textRegions = const [];
      warnings.add(
        'Text recognition was unavailable; artwork shapes were still analyzed.',
      );
    }

    cancellationToken?.throwIfCancelled();

    progress(SmartPathProgressStage.readingPixels, 0.12);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('Could not read drawing pixels.');
    }
    cancellationToken?.throwIfCancelled();
    final pixels = TransferableTypedData.fromList([
      byteData.buffer.asUint8List(),
    ]);
    final sourceWidth = image.width;
    final sourceHeight = image.height;
    final transferredTextRegions = [
      for (final region in textRegions) _textRegionToTransfer(region),
    ];
    progress(SmartPathProgressStage.preparingRaster, 0.20);
    final progressPort = onProgress == null ? null : ReceivePort();
    final progressSendPort = progressPort?.sendPort;
    final progressSubscription = progressPort?.listen((message) {
      final raw = message as List<Object?>;
      progress(
        SmartPathProgressStage.values[raw[0]! as int],
        (raw[1]! as num).toDouble(),
      );
    });
    late final Map<String, Object?> transferred;
    try {
      transferred = await _runTransferredRasterAnalysis(
        pixels,
        sourceWidth,
        sourceHeight,
        transferredTextRegions,
        warnings,
        processingOptions.suspectedFrameDetection,
        processingOptions.suspectedFrameConfidenceThreshold,
        progressSendPort,
        cancellationToken,
      );
    } finally {
      await progressSubscription?.cancel();
      progressPort?.close();
    }
    progress(SmartPathProgressStage.finalizing, 0.98);
    final analysis = await _analysisFromTransferResponsive(
      transferred,
      coordinateBounds: coordinateBounds,
      cancellationToken: cancellationToken,
      onProgress: (fraction) =>
          progress(SmartPathProgressStage.finalizing, 0.98 + fraction * 0.01),
    );
    progress(SmartPathProgressStage.finalizing, 0.99);
    return analysis;
  }

  /// Traces already-located text from an isolated transparent text layer.
  ///
  /// SVG text does not expose glyph outlines unless it was converted to
  /// paths. Rasterizing only the text layer and skeletonizing its alpha mask
  /// preserves the renderer's real font shaping without OCR or background
  /// cards becoming false pen paths.
  Future<List<SmartTextPathTrace>> traceTextRegions({
    required ui.Image image,
    required List<ui.Rect> regions,
  }) async {
    if (regions.isEmpty) return const [];
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('Could not read the isolated text pixels.');
    }
    final pixels = TransferableTypedData.fromList([
      byteData.buffer.asUint8List(),
    ]);
    final transferredRegions = [
      for (final region in regions)
        [region.left, region.top, region.right, region.bottom],
    ];
    final width = image.width;
    final height = image.height;
    final transferred = await Isolate.run(
      () => _traceTransferredText(pixels, width, height, transferredRegions),
    );
    return [
      for (final raw in transferred)
        _textTraceFromTransfer(raw as Map<Object?, Object?>),
    ];
  }
}

Future<Map<String, Object?>> _runTransferredRasterAnalysis(
  TransferableTypedData pixels,
  int sourceWidth,
  int sourceHeight,
  List<Map<String, Object?>> textRegions,
  List<String> warnings,
  bool suspectedFrameDetection,
  double suspectedFrameConfidenceThreshold,
  SendPort? progressSendPort,
  SmartPathCancellationToken? cancellationToken,
) async {
  cancellationToken?.throwIfCancelled();
  final responses = ReceivePort();
  final errors = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn<List<Object?>>(
      _rasterAnalysisWorkerMain,
      [
        responses.sendPort,
        pixels,
        sourceWidth,
        sourceHeight,
        textRegions,
        warnings,
        suspectedFrameDetection,
        suspectedFrameConfidenceThreshold,
        progressSendPort,
      ],
      debugName: 'handdraw-smart-path-raster',
      onExit: responses.sendPort,
      onError: errors.sendPort,
      errorsAreFatal: true,
    );
    cancellationToken?._attach(worker);
    final response = await Future.any<Object?>([
      responses.first,
      errors.first.then<Object?>((raw) {
        final details = raw is List && raw.isNotEmpty ? raw.first : raw;
        throw StateError('Smart Path worker failed: $details');
      }),
    ]);
    cancellationToken?.throwIfCancelled();
    if (response == null) {
      throw StateError('Smart Path worker exited before returning a result.');
    }
    final envelope = response as Map<Object?, Object?>;
    if (envelope['error'] case final Object error) {
      throw StateError('Smart Path worker failed: $error');
    }
    return Map<String, Object?>.from(
      envelope['result']! as Map<Object?, Object?>,
    );
  } finally {
    if (worker != null) {
      cancellationToken?._detach(worker);
      worker.kill(priority: Isolate.immediate);
    }
    responses.close();
    errors.close();
  }
}

void _rasterAnalysisWorkerMain(List<Object?> bootstrap) {
  final responsePort = bootstrap[0]! as SendPort;
  try {
    responsePort.send({
      'result': _analyzeTransferredRaster(
        bootstrap[1]! as TransferableTypedData,
        bootstrap[2]! as int,
        bootstrap[3]! as int,
        (bootstrap[4]! as List<Object?>)
            .cast<Map<Object?, Object?>>()
            .map(Map<String, Object?>.from)
            .toList(growable: false),
        (bootstrap[5]! as List<Object?>).cast<String>(),
        bootstrap[6]! as bool,
        (bootstrap[7]! as num).toDouble(),
        bootstrap[8] as SendPort?,
      ),
    });
  } catch (error, stackTrace) {
    responsePort.send({'error': error.toString(), 'stackTrace': '$stackTrace'});
  }
}

List<Map<String, Object?>> _traceTransferredText(
  TransferableTypedData transferredPixels,
  int width,
  int height,
  List<List<double>> transferredRegions,
) {
  final raster = _AnalysisRaster.fromRgba(
    transferredPixels.materialize().asUint8List(),
    width,
    height,
  );
  return [
    for (final raw in transferredRegions)
      _textTraceToTransfer(
        raster.pathsIn(
          ui.Rect.fromLTRB(raw[0], raw[1], raw[2], raw[3]),
          strongOnly: true,
        ),
      ),
  ];
}

Map<String, Object?> _textTraceToTransfer(_PathExtraction extraction) => {
  'bounds': [
    extraction.bounds.left,
    extraction.bounds.top,
    extraction.bounds.right,
    extraction.bounds.bottom,
  ],
  'revealWidth': extraction.revealWidth,
  'paths': [
    for (final path in extraction.paths)
      [
        for (final point in path) [point.dx, point.dy],
      ],
  ],
};

SmartTextPathTrace _textTraceFromTransfer(Map<Object?, Object?> raw) {
  final bounds = raw['bounds']! as List;
  return SmartTextPathTrace(
    bounds: ui.Rect.fromLTRB(
      (bounds[0] as num).toDouble(),
      (bounds[1] as num).toDouble(),
      (bounds[2] as num).toDouble(),
      (bounds[3] as num).toDouble(),
    ),
    recommendedRevealWidth: (raw['revealWidth']! as num).toDouble(),
    paths: [
      for (final rawPath in raw['paths']! as List)
        SmartGeneratedPath(
          points: [
            for (final rawPoint in rawPath as List)
              ui.Offset(
                ((rawPoint as List)[0] as num).toDouble(),
                (rawPoint[1] as num).toDouble(),
              ),
          ],
        ),
    ],
  );
}

Map<String, Object?> _analyzeTransferredRaster(
  TransferableTypedData transferredPixels,
  int width,
  int height,
  List<Map<String, Object?>> transferredTextRegions,
  List<String> initialWarnings,
  bool suspectedFrameDetection,
  double suspectedFrameConfidenceThreshold,
  SendPort? progressPort,
) {
  final rgba = transferredPixels.materialize().asUint8List();
  final textRegions = [
    for (final raw in transferredTextRegions) _textRegionFromTransfer(raw),
  ];
  return _analysisToTransfer(
    _analyzeRaster(
      rgba: rgba,
      width: width,
      height: height,
      textRegions: textRegions,
      initialWarnings: initialWarnings,
      processingOptions: SmartPathProcessingOptions(
        suspectedFrameDetection: suspectedFrameDetection,
        suspectedFrameConfidenceThreshold: suspectedFrameConfidenceThreshold,
      ),
      onProgress: progressPort == null
          ? null
          : (stage, fraction) => progressPort.send([stage.index, fraction]),
    ),
  );
}

SmartPathAnalysis _analyzeRaster({
  required Uint8List rgba,
  required int width,
  required int height,
  required List<SmartTextRegion> textRegions,
  required List<String> initialWarnings,
  required SmartPathProcessingOptions processingOptions,
  void Function(SmartPathProgressStage stage, double fraction)? onProgress,
}) {
  final warnings = List<String>.of(initialWarnings);
  final raster = _AnalysisRaster.fromRgba(
    rgba,
    width,
    height,
    onProgress: (fraction) => onProgress?.call(
      SmartPathProgressStage.preparingRaster,
      0.20 + fraction * 0.18,
    ),
  );

  final sections = <SmartPathSection>[];
  final claimed = Uint8List(raster.width * raster.height);
  var textIndex = 0;
  for (var regionIndex = 0; regionIndex < textRegions.length; regionIndex++) {
    final region = textRegions[regionIndex];
    onProgress?.call(
      SmartPathProgressStage.tracingText,
      0.38 + 0.14 * regionIndex / math.max(1, textRegions.length),
    );
    // Keep nearby underlines and rules out of the glyph trace. A fixed wide
    // search margin let a thick line just below a title become one of the
    // title's pen paths, so the hand jumped to that line while only the first
    // letters were visible. OCR already supplies text bounds; only allow a
    // small font-size-relative margin for antialiasing and minor detector
    // error.
    final textSearchPadding = math
        .max(0.0015, region.bounds.height * 0.06)
        .clamp(0.0, 0.004)
        .toDouble();
    final refined = raster.refineBounds(
      region.bounds,
      padding: textSearchPadding,
    );
    if (refined == null) continue;
    raster.claim(claimed, refined);
    // OCR bounds can include a translucent card or badge behind the glyphs.
    // Trace only the strong/opaque pixels for text so the pen follows the
    // letters instead of travelling through and "painting" the fill.
    final extraction = raster.pathsIn(refined, strongOnly: true);
    if (extraction.paths.isEmpty) continue;
    sections.add(
      SmartPathSection(
        id: 'text-${textIndex++}',
        kind: SmartSectionKind.text,
        bounds: extraction.bounds,
        label: region.text.trim().isEmpty
            ? 'Detected text'
            : region.text.trim(),
        paths: extraction.paths
            .map((points) => SmartGeneratedPath(points: points))
            .toList(growable: false),
        recommendedRevealWidth: extraction.revealWidth,
        mode: SmartSectionMode.handDraw,
        confidence: region.confidence,
        rightToLeft: _containsRtl(region.text),
        hasPreciseTrace: true,
      ),
    );
  }

  onProgress?.call(SmartPathProgressStage.findingShapes, 0.52);
  final shapes = raster.unclaimedComponents(claimed);
  onProgress?.call(SmartPathProgressStage.tracingShapes, 0.62);
  for (var index = 0; index < shapes.length; index++) {
    onProgress?.call(
      SmartPathProgressStage.tracingShapes,
      0.62 + 0.28 * index / math.max(1, shapes.length),
    );
    final extraction = raster.pathsIn(shapes[index], outlineOnly: true);
    if (extraction.paths.isEmpty) continue;
    var section = SmartPathSection(
      id: 'shape-$index',
      kind: SmartSectionKind.shape,
      bounds: extraction.bounds,
      label: 'Artwork ${index + 1}',
      paths: extraction.paths
          .map((points) => SmartGeneratedPath(points: points))
          .toList(growable: false),
      recommendedRevealWidth: extraction.revealWidth,
      mode: SmartSectionMode.handDraw,
    );
    if (processingOptions.suspectedFrameDetection) {
      final assessment = const SuspectedFrameDetector().assess(section);
      if (assessment.isCandidate &&
          assessment.confidence >=
              processingOptions.suspectedFrameConfidenceThreshold) {
        section = section.copyWith(
          mode: SmartSectionMode.ignore,
          artifactHint: SmartSectionArtifactHint.suspectedFrame,
          artifactConfidence: assessment.confidence,
        );
      }
    }
    sections.add(section);
  }

  sections.sort((a, b) {
    final row = a.bounds.top.compareTo(b.bounds.top);
    if ((a.bounds.top - b.bounds.top).abs() > 0.025) return row;
    return a.bounds.left.compareTo(b.bounds.left);
  });
  if (sections.isEmpty) {
    warnings.add('No clear text or artwork paths were found.');
  } else {
    onProgress?.call(SmartPathProgressStage.validatingPaths, 0.90);
    final validationPaths = <List<ui.Offset>>[];
    final validationWidths = <double>[];
    for (final section in sections) {
      for (final path in section.paths) {
        validationPaths.add(path.points);
        validationWidths.add(section.recommendedRevealWidth);
      }
    }
    final validation = const MaskCoverageValidator().validate(
      foreground: raster.foreground,
      width: raster.width,
      height: raster.height,
      paths: validationPaths,
      revealWidths: validationWidths,
      onProgress: (fraction) => onProgress?.call(
        SmartPathProgressStage.validatingPaths,
        0.90 + fraction * 0.08,
      ),
    );
    if (!validation.passes) {
      warnings.add(
        'Automatic mask validation: '
        '${(validation.coverage * 100).toStringAsFixed(1)}% coverage, '
        '${(validation.duplicateCoverage * 100).toStringAsFixed(1)}% duplicate.',
      );
    }
  }
  onProgress?.call(SmartPathProgressStage.finalizing, 0.98);
  return SmartPathAnalysis(
    sections: sections,
    warnings: warnings,
    processing: SmartPathProcessingRecord(
      suspectedFrameDetection: processingOptions.suspectedFrameDetection,
      suspectedFrameConfidenceThreshold:
          processingOptions.suspectedFrameConfidenceThreshold,
    ),
  );
}

Map<String, Object?> _textRegionToTransfer(SmartTextRegion region) => {
  'text': region.text,
  'bounds': [
    region.bounds.left,
    region.bounds.top,
    region.bounds.right,
    region.bounds.bottom,
  ],
  'confidence': region.confidence,
};

SmartTextRegion _textRegionFromTransfer(Map<String, Object?> raw) {
  final bounds = raw['bounds']! as List;
  return SmartTextRegion(
    text: raw['text']! as String,
    bounds: ui.Rect.fromLTRB(
      (bounds[0] as num).toDouble(),
      (bounds[1] as num).toDouble(),
      (bounds[2] as num).toDouble(),
      (bounds[3] as num).toDouble(),
    ),
    confidence: (raw['confidence']! as num).toDouble(),
  );
}

Map<String, Object?> _analysisToTransfer(SmartPathAnalysis analysis) => {
  'warnings': analysis.warnings,
  'processing': {
    'engineId': analysis.processing.engineId,
    'algorithmVersion': analysis.processing.algorithmVersion,
    'suspectedFrameDetection': analysis.processing.suspectedFrameDetection,
    'suspectedFrameConfidenceThreshold':
        analysis.processing.suspectedFrameConfidenceThreshold,
  },
  'sections': [
    for (final section in analysis.sections) _sectionToTransfer(section),
  ],
};

Map<String, Object?> _sectionToTransfer(SmartPathSection section) {
  final pathLengths = Uint32List(section.paths.length);
  var pointCount = 0;
  for (var index = 0; index < section.paths.length; index++) {
    final length = section.paths[index].points.length;
    pathLengths[index] = length;
    pointCount += length;
  }
  final coordinates = Float64List(pointCount * 2);
  var coordinateIndex = 0;
  for (final path in section.paths) {
    for (final point in path.points) {
      coordinates[coordinateIndex++] = point.dx;
      coordinates[coordinateIndex++] = point.dy;
    }
  }
  return {
    'id': section.id,
    'kind': section.kind.name,
    'bounds': [
      section.bounds.left,
      section.bounds.top,
      section.bounds.right,
      section.bounds.bottom,
    ],
    'label': section.label,
    // A dense illustration can contain hundreds of thousands of points.
    // Transfer flat typed buffers once instead of serializing a deep graph of
    // tiny List<double> objects back onto Flutter's UI isolate.
    'pathLengths': TransferableTypedData.fromList([
      pathLengths.buffer.asUint8List(),
    ]),
    'pathCoordinates': TransferableTypedData.fromList([
      coordinates.buffer.asUint8List(),
    ]),
    'recommendedRevealWidth': section.recommendedRevealWidth,
    'mode': section.mode.name,
    'confidence': section.confidence,
    'rightToLeft': section.rightToLeft,
    'role': section.role.name,
    'hasPreciseTrace': section.hasPreciseTrace,
    'artifactHint': section.artifactHint?.name,
    'artifactConfidence': section.artifactConfidence,
  };
}

Future<SmartPathAnalysis> _analysisFromTransferResponsive(
  Map<Object?, Object?> raw, {
  ui.Rect coordinateBounds = const ui.Rect.fromLTWH(0, 0, 1, 1),
  SmartPathCancellationToken? cancellationToken,
  void Function(double fraction)? onProgress,
}) async {
  final transferredSections = raw['sections']! as List;
  final sections = <SmartPathSection>[];
  for (var index = 0; index < transferredSections.length; index++) {
    cancellationToken?.throwIfCancelled();
    final sectionStart = transferredSections.isEmpty
        ? 1.0
        : index / transferredSections.length;
    final sectionSpan = transferredSections.isEmpty
        ? 0.0
        : 1 / transferredSections.length;
    sections.add(
      await _sectionFromTransferResponsive(
        transferredSections[index] as Map<Object?, Object?>,
        coordinateBounds: coordinateBounds,
        cancellationToken: cancellationToken,
        onProgress: (fraction) =>
            onProgress?.call(sectionStart + fraction * sectionSpan),
      ),
    );
  }
  cancellationToken?.throwIfCancelled();
  onProgress?.call(1);
  return SmartPathAnalysis(
    warnings: List<String>.from(raw['warnings']! as List),
    processing: _processingFromTransfer(
      raw['processing'] as Map<Object?, Object?>?,
    ),
    sections: sections,
  );
}

Future<SmartPathSection> _sectionFromTransferResponsive(
  Map<Object?, Object?> raw, {
  required ui.Rect coordinateBounds,
  SmartPathCancellationToken? cancellationToken,
  void Function(double fraction)? onProgress,
}) async {
  final bounds = raw['bounds']! as List;
  double mapX(num value) =>
      coordinateBounds.left + value.toDouble() * coordinateBounds.width;
  double mapY(num value) =>
      coordinateBounds.top + value.toDouble() * coordinateBounds.height;
  final paths = await _pathsFromTransferResponsive(
    raw,
    mapX: (value) => mapX(value),
    mapY: (value) => mapY(value),
    cancellationToken: cancellationToken,
    onProgress: onProgress,
  );
  return SmartPathSection(
    id: raw['id']! as String,
    kind: SmartSectionKind.values.byName(raw['kind']! as String),
    bounds: ui.Rect.fromLTRB(
      mapX(bounds[0] as num),
      mapY(bounds[1] as num),
      mapX(bounds[2] as num),
      mapY(bounds[3] as num),
    ),
    label: raw['label']! as String,
    paths: paths,
    recommendedRevealWidth:
        (raw['recommendedRevealWidth']! as num).toDouble() *
        coordinateBounds.height,
    mode: SmartSectionMode.values.byName(raw['mode']! as String),
    confidence: (raw['confidence']! as num).toDouble(),
    rightToLeft: raw['rightToLeft']! as bool,
    role: SmartSectionRole.values.byName(
      raw['role'] as String? ?? SmartSectionRole.content.name,
    ),
    hasPreciseTrace: raw['hasPreciseTrace'] as bool? ?? false,
    artifactHint: raw['artifactHint'] == null
        ? null
        : SmartSectionArtifactHint.values.byName(
            raw['artifactHint']! as String,
          ),
    artifactConfidence: (raw['artifactConfidence'] as num?)?.toDouble() ?? 0,
  );
}

Future<List<SmartGeneratedPath>> _pathsFromTransferResponsive(
  Map<Object?, Object?> raw, {
  required double Function(num value) mapX,
  required double Function(num value) mapY,
  SmartPathCancellationToken? cancellationToken,
  void Function(double fraction)? onProgress,
}) async {
  final transferredLengths = raw['pathLengths'];
  final transferredCoordinates = raw['pathCoordinates'];
  if (transferredLengths is TransferableTypedData &&
      transferredCoordinates is TransferableTypedData) {
    final lengthBytes = transferredLengths.materialize().asUint8List();
    final coordinateBytes = transferredCoordinates.materialize().asUint8List();
    final lengths = Uint32List.view(
      lengthBytes.buffer,
      lengthBytes.offsetInBytes,
      lengthBytes.lengthInBytes ~/ Uint32List.bytesPerElement,
    );
    final coordinates = Float64List.view(
      coordinateBytes.buffer,
      coordinateBytes.offsetInBytes,
      coordinateBytes.lengthInBytes ~/ Float64List.bytesPerElement,
    );
    var coordinateIndex = 0;
    var pointsSinceYield = 0;
    final paths = <SmartGeneratedPath>[];
    for (var pathIndex = 0; pathIndex < lengths.length; pathIndex++) {
      final pathLength = lengths[pathIndex];
      final points = List<ui.Offset>.generate(pathLength, (_) {
        final x = coordinates[coordinateIndex++];
        final y = coordinates[coordinateIndex++];
        return ui.Offset(mapX(x), mapY(y));
      }, growable: false);
      paths.add(SmartGeneratedPath(points: points));
      pointsSinceYield += pathLength;
      if ((pathIndex + 1) % 128 == 0 || pointsSinceYield >= 8192) {
        cancellationToken?.throwIfCancelled();
        onProgress?.call((pathIndex + 1) / lengths.length);
        pointsSinceYield = 0;
        // A zero-duration timer yields to pointer, paint, and cancellation
        // events. A microtask would continue starving Flutter's event queue.
        await Future<void>.delayed(Duration.zero);
      }
    }
    cancellationToken?.throwIfCancelled();
    onProgress?.call(1);
    return List.unmodifiable(paths);
  }
  final rawPaths = raw['paths']! as List;
  final paths = <SmartGeneratedPath>[];
  var pointsSinceYield = 0;
  for (var pathIndex = 0; pathIndex < rawPaths.length; pathIndex++) {
    final rawPath = rawPaths[pathIndex] as List;
    paths.add(
      SmartGeneratedPath(
        points: [
          for (final rawPoint in rawPath)
            ui.Offset(
              mapX((rawPoint as List)[0] as num),
              mapY(rawPoint[1] as num),
            ),
        ],
      ),
    );
    pointsSinceYield += rawPath.length;
    if ((pathIndex + 1) % 128 == 0 || pointsSinceYield >= 8192) {
      cancellationToken?.throwIfCancelled();
      onProgress?.call((pathIndex + 1) / rawPaths.length);
      pointsSinceYield = 0;
      await Future<void>.delayed(Duration.zero);
    }
  }
  cancellationToken?.throwIfCancelled();
  onProgress?.call(1);
  return List.unmodifiable(paths);
}

SmartPathProcessingRecord _processingFromTransfer(Map<Object?, Object?>? raw) =>
    raw == null
    ? const SmartPathProcessingRecord()
    : SmartPathProcessingRecord(
        engineId: raw['engineId'] as String? ?? 'handdraw-smart-path',
        algorithmVersion: raw['algorithmVersion'] as int? ?? 1,
        suspectedFrameDetection:
            raw['suspectedFrameDetection'] as bool? ?? false,
        suspectedFrameConfidenceThreshold:
            (raw['suspectedFrameConfidenceThreshold'] as num?)?.toDouble() ??
            0.96,
      );

bool _containsRtl(String value) {
  for (final rune in value.runes) {
    if ((rune >= 0x0590 && rune <= 0x08ff) ||
        (rune >= 0xfb1d && rune <= 0xfdff) ||
        (rune >= 0xfe70 && rune <= 0xfeff)) {
      return true;
    }
  }
  return false;
}

class _PathExtraction {
  const _PathExtraction({
    required this.paths,
    required this.bounds,
    required this.revealWidth,
  });

  final List<List<ui.Offset>> paths;
  final ui.Rect bounds;
  final double revealWidth;
}

class _AnalysisRaster {
  _AnalysisRaster({
    required this.width,
    required this.height,
    required this.foreground,
    required this.strongForeground,
    required this.sourceRgba,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.background,
    required this.usesAlpha,
  });

  factory _AnalysisRaster.fromRgba(
    Uint8List rgba,
    int sourceWidth,
    int sourceHeight, {
    void Function(double fraction)? onProgress,
  }) {
    const targetMax = 1100;
    final sampleScale = math.max(
      1.0,
      math.max(sourceWidth, sourceHeight) / targetMax,
    );
    final width = math.max(1, (sourceWidth / sampleScale).round());
    final height = math.max(1, (sourceHeight / sampleScale).round());
    var transparentSamples = 0;
    const sampleCount = 64;
    for (var index = 0; index < sampleCount; index++) {
      final x = index * (sourceWidth - 1) ~/ (sampleCount - 1);
      final y =
          (index * 37 % sampleCount) * (sourceHeight - 1) ~/ (sampleCount - 1);
      if (rgba[(y * sourceWidth + x) * 4 + 3] < 245) transparentSamples++;
    }
    final usesAlpha = transparentSamples >= 2;
    final cornerColors = <List<int>>[
      _rgbaAt(rgba, sourceWidth, 0, 0),
      _rgbaAt(rgba, sourceWidth, sourceWidth - 1, 0),
      _rgbaAt(rgba, sourceWidth, 0, sourceHeight - 1),
      _rgbaAt(rgba, sourceWidth, sourceWidth - 1, sourceHeight - 1),
    ];
    final background = List<int>.generate(3, (channel) {
      final values = cornerColors.map((color) => color[channel]).toList()
        ..sort();
      return (values[1] + values[2]) ~/ 2;
    });
    final mask = Uint8List(width * height);
    final strongMask = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      if (y % 24 == 0) onProgress?.call(y / height);
      final sourceTop = math.min(sourceHeight - 1, (y * sampleScale).floor());
      final sourceBottom = math.min(
        sourceHeight,
        ((y + 1) * sampleScale).ceil(),
      );
      for (var x = 0; x < width; x++) {
        final sourceLeft = math.min(sourceWidth - 1, (x * sampleScale).floor());
        final sourceRight = math.min(
          sourceWidth,
          ((x + 1) * sampleScale).ceil(),
        );
        var visible = false;
        var strong = false;
        // Max-pool the source cell instead of sampling one pixel. This keeps a
        // one-pixel 4K connector discoverable in the coarse component pass.
        for (var sourceY = sourceTop; sourceY < sourceBottom; sourceY++) {
          for (var sourceX = sourceLeft; sourceX < sourceRight; sourceX++) {
            final offset = (sourceY * sourceWidth + sourceX) * 4;
            final alpha = rgba[offset + 3];
            final difference =
                (rgba[offset] - background[0]).abs() +
                (rgba[offset + 1] - background[1]).abs() +
                (rgba[offset + 2] - background[2]).abs();
            final sampleVisible = usesAlpha
                ? alpha >= 8
                : alpha >= 24 && difference >= 54;
            if (!sampleVisible) continue;
            visible = true;
            if (!usesAlpha || alpha >= 160) strong = true;
          }
        }
        if (visible) {
          final index = y * width + x;
          mask[index] = 1;
          if (strong) strongMask[index] = 1;
        }
      }
    }
    onProgress?.call(1);
    return _AnalysisRaster(
      width: width,
      height: height,
      foreground: mask,
      strongForeground: strongMask,
      sourceRgba: rgba,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      background: background,
      usesAlpha: usesAlpha,
    );
  }

  final int width;
  final int height;
  final Uint8List foreground;
  final Uint8List strongForeground;
  final Uint8List sourceRgba;
  final int sourceWidth;
  final int sourceHeight;
  final List<int> background;
  final bool usesAlpha;

  static List<int> _rgbaAt(Uint8List rgba, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    return [rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3]];
  }

  ui.Rect? refineBounds(ui.Rect normalized, {double padding = 0.008}) {
    final box = _pixelRect(normalized.inflate(math.max(0, padding)));
    var left = box.right;
    var right = box.left;
    var top = box.bottom;
    var bottom = box.top;
    var count = 0;
    for (var y = box.top; y < box.bottom; y++) {
      for (var x = box.left; x < box.right; x++) {
        if (foreground[y * width + x] == 0) continue;
        count++;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
    if (count < 4) return null;
    return ui.Rect.fromLTRB(
      left / width,
      top / height,
      (right + 1) / width,
      (bottom + 1) / height,
    );
  }

  void claim(Uint8List claimed, ui.Rect normalized) {
    final box = _pixelRect(normalized.inflate(0.004));
    for (var y = box.top; y < box.bottom; y++) {
      for (var x = box.left; x < box.right; x++) {
        if (foreground[y * width + x] != 0) claimed[y * width + x] = 1;
      }
    }
  }

  List<ui.Rect> unclaimedComponents(Uint8List claimed) {
    final visited = Uint8List(width * height);
    final result = <_Component>[];
    final queue = <int>[];
    final minimumArea = math.max(5, (width * height * 0.000006).round());
    for (var index = 0; index < foreground.length; index++) {
      if (foreground[index] == 0 ||
          claimed[index] != 0 ||
          visited[index] != 0) {
        continue;
      }
      queue.clear();
      queue.add(index);
      visited[index] = 1;
      var cursor = 0;
      var left = index % width;
      var right = left;
      var top = index ~/ width;
      var bottom = top;
      while (cursor < queue.length) {
        final current = queue[cursor++];
        final x = current % width;
        final y = current ~/ width;
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
        for (final neighbor in _neighbors(current, width, height)) {
          if (foreground[neighbor] == 0 ||
              claimed[neighbor] != 0 ||
              visited[neighbor] != 0) {
            continue;
          }
          visited[neighbor] = 1;
          queue.add(neighbor);
        }
      }
      if (queue.length >= minimumArea) {
        result.add(_Component(left, top, right + 1, bottom + 1, queue.length));
      }
    }

    final merged = _mergeNearby(result);
    merged.sort((a, b) => b.area.compareTo(a.area));
    return merged
        .take(40)
        .map(
          (item) => ui.Rect.fromLTRB(
            item.left / width,
            item.top / height,
            item.right / width,
            item.bottom / height,
          ),
        )
        .toList(growable: false);
  }

  List<_Component> _mergeNearby(List<_Component> source) {
    final components = List<_Component>.of(source);
    var changed = true;
    while (changed) {
      changed = false;
      outer:
      for (var a = 0; a < components.length; a++) {
        for (var b = a + 1; b < components.length; b++) {
          final first = components[a];
          final second = components[b];
          final gapX = math.max(
            0,
            math.max(first.left, second.left) -
                math.min(first.right, second.right),
          );
          final gapY = math.max(
            0,
            math.max(first.top, second.top) -
                math.min(first.bottom, second.bottom),
          );
          final sameRow =
              gapY <= math.max(first.height, second.height) * 0.35 &&
              gapX <= math.max(8, math.min(first.height, second.height) * 0.65);
          final touching = gapX <= 3 && gapY <= 3;
          if (!sameRow && !touching) continue;
          components[a] = first.merge(second);
          components.removeAt(b);
          changed = true;
          break outer;
        }
      }
    }
    return components;
  }

  _PathExtraction pathsIn(
    ui.Rect normalized, {
    bool outlineOnly = false,
    bool strongOnly = false,
  }) {
    final region = _refinedRegion(
      normalized.inflate(0.003),
      strongOnly: strongOnly,
    );
    final cropWidth = region.width;
    final cropHeight = region.height;
    final crop = region.mask;
    var area = 0;
    var foregroundLeft = cropWidth;
    var foregroundTop = cropHeight;
    var foregroundRight = 0;
    var foregroundBottom = 0;
    for (var index = 0; index < crop.length; index++) {
      if (crop[index] == 0) continue;
      area++;
      final x = index % cropWidth;
      final y = index ~/ cropWidth;
      foregroundLeft = math.min(foregroundLeft, x);
      foregroundTop = math.min(foregroundTop, y);
      foregroundRight = math.max(foregroundRight, x + 1);
      foregroundBottom = math.max(foregroundBottom, y + 1);
    }
    final traceSource = outlineOnly
        ? _outlineAwareStrokeMask(crop, cropWidth, cropHeight)
        : crop;
    final skeleton = _zhangSuen(traceSource, cropWidth, cropHeight);
    final pixelPaths = const SkeletonGraphPlanner().buildTrails(
      skeleton,
      cropWidth,
      cropHeight,
    );
    final paths = <List<ui.Offset>>[];
    var skeletonLength = 0.0;
    for (var path in pixelPaths) {
      path = _simplify(path, 0.85);
      if (path.length < 2) continue;
      var normalizedPath = path
          .map(
            (point) => ui.Offset(
              (region.sourceLeft +
                      (point.dx + 0.5) * region.sourcePixelsPerSample) /
                  sourceWidth,
              (region.sourceTop +
                      (point.dy + 0.5) * region.sourcePixelsPerSample) /
                  sourceHeight,
            ),
          )
          .toList(growable: false);
      final first = normalizedPath.first;
      final last = normalizedPath.last;
      if (!outlineOnly &&
          (first.dx > last.dx ||
              ((first.dx - last.dx).abs() < 0.003 && first.dy > last.dy))) {
        normalizedPath = normalizedPath.reversed.toList(growable: false);
      }
      for (var index = 1; index < path.length; index++) {
        skeletonLength += (path[index] - path[index - 1]).distance;
      }
      paths.add(normalizedPath);
    }
    if (!outlineOnly) {
      paths.sort((a, b) {
        final x = a.first.dx.compareTo(b.first.dx);
        return x != 0 ? x : a.first.dy.compareTo(b.first.dy);
      });
    }
    final averageThickness = skeletonLength <= 0 ? 4.0 : area / skeletonLength;
    final maximumRadius = _maxInscribedRadius(crop, cropWidth, cropHeight);
    // Area / skeleton length works well for handwriting, but it can
    // underestimate solid cards and badges. The distance transform measures
    // the widest filled region so the reveal mask can cover it completely.
    final revealWidthPixels = math.max(
      averageThickness * 1.75,
      maximumRadius * 2.25,
    );
    final revealWidth =
        (revealWidthPixels * region.sourcePixelsPerSample / sourceHeight).clamp(
          0.004,
          0.80,
        );
    final foregroundBounds = area == 0
        ? region.normalizedBounds
        : ui.Rect.fromLTRB(
            (region.sourceLeft +
                    foregroundLeft * region.sourcePixelsPerSample) /
                sourceWidth,
            (region.sourceTop + foregroundTop * region.sourcePixelsPerSample) /
                sourceHeight,
            (region.sourceLeft +
                    foregroundRight * region.sourcePixelsPerSample) /
                sourceWidth,
            (region.sourceTop +
                    foregroundBottom * region.sourcePixelsPerSample) /
                sourceHeight,
          );
    return _PathExtraction(
      paths: paths,
      bounds: foregroundBounds,
      revealWidth: revealWidth,
    );
  }

  /// Refines only the requested region against source pixels. A small full-
  /// image raster remains responsible for fast component discovery, while a
  /// local high-resolution raster preserves thin 4K lines and glyph details.
  _RefinedRegion _refinedRegion(
    ui.Rect normalized, {
    required bool strongOnly,
  }) {
    const maximumRegionDimension = 1600;
    final sourceLeft = (normalized.left.clamp(0.0, 1.0) * sourceWidth).floor();
    final sourceTop = (normalized.top.clamp(0.0, 1.0) * sourceHeight).floor();
    final sourceRight = (normalized.right.clamp(0.0, 1.0) * sourceWidth).ceil();
    final sourceBottom = (normalized.bottom.clamp(0.0, 1.0) * sourceHeight)
        .ceil();
    final sourceRegionWidth = math.max(1, sourceRight - sourceLeft);
    final sourceRegionHeight = math.max(1, sourceBottom - sourceTop);
    final sourcePixelsPerSample = math.max(
      1.0,
      math.max(sourceRegionWidth, sourceRegionHeight) / maximumRegionDimension,
    );
    final regionWidth = math.max(
      1,
      (sourceRegionWidth / sourcePixelsPerSample).ceil(),
    );
    final regionHeight = math.max(
      1,
      (sourceRegionHeight / sourcePixelsPerSample).ceil(),
    );
    final mask = Uint8List(regionWidth * regionHeight);
    for (var y = 0; y < regionHeight; y++) {
      final sampleTop = math.min(
        sourceHeight - 1,
        sourceTop + (y * sourcePixelsPerSample).floor(),
      );
      final sampleBottom = math.min(
        sourceHeight,
        sourceTop + ((y + 1) * sourcePixelsPerSample).ceil(),
      );
      for (var x = 0; x < regionWidth; x++) {
        final sampleLeft = math.min(
          sourceWidth - 1,
          sourceLeft + (x * sourcePixelsPerSample).floor(),
        );
        final sampleRight = math.min(
          sourceWidth,
          sourceLeft + ((x + 1) * sourcePixelsPerSample).ceil(),
        );
        var visible = false;
        for (
          var sourceY = sampleTop;
          sourceY < sampleBottom && !visible;
          sourceY++
        ) {
          for (var sourceX = sampleLeft; sourceX < sampleRight; sourceX++) {
            if (_isForeground(sourceX, sourceY, strongOnly: strongOnly)) {
              visible = true;
              break;
            }
          }
        }
        if (visible) {
          mask[y * regionWidth + x] = 1;
        }
      }
    }
    return _RefinedRegion(
      width: regionWidth,
      height: regionHeight,
      mask: mask,
      sourceLeft: sourceLeft,
      sourceTop: sourceTop,
      sourcePixelsPerSample: sourcePixelsPerSample,
      normalizedBounds: ui.Rect.fromLTRB(
        sourceLeft / sourceWidth,
        sourceTop / sourceHeight,
        sourceRight / sourceWidth,
        sourceBottom / sourceHeight,
      ),
    );
  }

  bool _isForeground(int x, int y, {required bool strongOnly}) {
    final offset = (y * sourceWidth + x) * 4;
    final alpha = sourceRgba[offset + 3];
    final difference =
        (sourceRgba[offset] - background[0]).abs() +
        (sourceRgba[offset + 1] - background[1]).abs() +
        (sourceRgba[offset + 2] - background[2]).abs();
    final visible = usesAlpha ? alpha >= 8 : alpha >= 24 && difference >= 54;
    if (!visible) return false;
    return !strongOnly || !usesAlpha || alpha >= 160;
  }

  _IntRect _pixelRect(ui.Rect normalized) {
    return _IntRect(
      (normalized.left.clamp(0.0, 1.0) * width).floor(),
      (normalized.top.clamp(0.0, 1.0) * height).floor(),
      (normalized.right.clamp(0.0, 1.0) * width).ceil(),
      (normalized.bottom.clamp(0.0, 1.0) * height).ceil(),
    );
  }
}

class _RefinedRegion {
  const _RefinedRegion({
    required this.width,
    required this.height,
    required this.mask,
    required this.sourceLeft,
    required this.sourceTop,
    required this.sourcePixelsPerSample,
    required this.normalizedBounds,
  });

  final int width;
  final int height;
  final Uint8List mask;
  final int sourceLeft;
  final int sourceTop;
  final double sourcePixelsPerSample;
  final ui.Rect normalizedBounds;
}

double _maxInscribedRadius(Uint8List source, int width, int height) {
  final distances = _distanceTransform(source, width, height);
  var maximum = 0.0;
  for (var index = 0; index < source.length; index++) {
    if (source[index] != 0) maximum = math.max(maximum, distances[index]);
  }
  return maximum;
}

Float64List _distanceTransform(Uint8List source, int width, int height) {
  if (width == 0 || height == 0) return Float64List(0);
  final distances = Float64List(source.length);
  final unreachable = (width + height).toDouble();
  const diagonal = 1.4142135623730951;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      if (source[index] == 0) continue;
      distances[index] = x == 0 || y == 0 || x == width - 1 || y == height - 1
          ? 1
          : unreachable;
    }
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      if (source[index] == 0) continue;
      var best = distances[index];
      if (x > 0) best = math.min(best, distances[index - 1] + 1);
      if (y > 0) best = math.min(best, distances[index - width] + 1);
      if (x > 0 && y > 0) {
        best = math.min(best, distances[index - width - 1] + diagonal);
      }
      if (x + 1 < width && y > 0) {
        best = math.min(best, distances[index - width + 1] + diagonal);
      }
      distances[index] = best;
    }
  }

  for (var y = height - 1; y >= 0; y--) {
    for (var x = width - 1; x >= 0; x--) {
      final index = y * width + x;
      if (source[index] == 0) continue;
      var best = distances[index];
      if (x + 1 < width) best = math.min(best, distances[index + 1] + 1);
      if (y + 1 < height) {
        best = math.min(best, distances[index + width] + 1);
      }
      if (x + 1 < width && y + 1 < height) {
        best = math.min(best, distances[index + width + 1] + diagonal);
      }
      if (x > 0 && y + 1 < height) {
        best = math.min(best, distances[index + width - 1] + diagonal);
      }
      distances[index] = best;
    }
  }
  return distances;
}

Uint8List _outlineAwareStrokeMask(Uint8List source, int width, int height) {
  final distances = _distanceTransform(source, width, height);
  final centerLines = _zhangSuen(source, width, height);
  final result = Uint8List(source.length);
  const thickRegionRadius = 6.0;
  const searchRadius = 9;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = y * width + x;
      if (source[index] == 0) continue;

      // Thin connectors and ordinary strokes keep their natural centerline.
      if (centerLines[index] != 0 && distances[index] <= thickRegionRadius) {
        result[index] = 1;
      }

      var boundary = x == 0 || y == 0 || x == width - 1 || y == height - 1;
      if (!boundary) {
        for (var dy = -1; dy <= 1 && !boundary; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            if (source[(y + dy) * width + x + dx] == 0) {
              boundary = true;
              break;
            }
          }
        }
      }
      if (!boundary) continue;

      // A boundary belongs to a filled card only when there is a genuinely
      // thick interior nearby. This avoids tracing both edges of thin lines.
      var localMaximum = 0.0;
      final top = math.max(0, y - searchRadius);
      final bottom = math.min(height - 1, y + searchRadius);
      final left = math.max(0, x - searchRadius);
      final right = math.min(width - 1, x + searchRadius);
      for (
        var sy = top;
        sy <= bottom && localMaximum < thickRegionRadius;
        sy++
      ) {
        for (var sx = left; sx <= right; sx++) {
          localMaximum = math.max(localMaximum, distances[sy * width + sx]);
          if (localMaximum >= thickRegionRadius) break;
        }
      }
      if (localMaximum >= thickRegionRadius) result[index] = 1;
    }
  }
  return result;
}

Uint8List _zhangSuen(Uint8List source, int width, int height) {
  if (const bool.fromEnvironment('HANDDRAW_SPIKE_SPARSE_THINNING')) {
    return const SparseSkeletonThinner().thin(source, width, height);
  }
  final image = Uint8List.fromList(source);
  final remove = <int>[];
  var changed = true;
  var iteration = 0;
  while (changed && iteration++ < 80) {
    changed = false;
    for (var step = 0; step < 2; step++) {
      remove.clear();
      for (var y = 1; y < height - 1; y++) {
        for (var x = 1; x < width - 1; x++) {
          final index = y * width + x;
          if (image[index] == 0) continue;
          final p2 = image[index - width];
          final p3 = image[index - width + 1];
          final p4 = image[index + 1];
          final p5 = image[index + width + 1];
          final p6 = image[index + width];
          final p7 = image[index + width - 1];
          final p8 = image[index - 1];
          final p9 = image[index - width - 1];
          final neighbors = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
          if (neighbors < 2 || neighbors > 6) continue;
          final values = [p2, p3, p4, p5, p6, p7, p8, p9, p2];
          var transitions = 0;
          for (var n = 0; n < 8; n++) {
            if (values[n] == 0 && values[n + 1] == 1) transitions++;
          }
          if (transitions != 1) continue;
          final firstRule = step == 0 ? p2 * p4 * p6 == 0 : p2 * p4 * p8 == 0;
          final secondRule = step == 0 ? p4 * p6 * p8 == 0 : p2 * p6 * p8 == 0;
          if (firstRule && secondRule) remove.add(index);
        }
      }
      if (remove.isNotEmpty) {
        changed = true;
      }
      for (final index in remove) {
        image[index] = 0;
      }
    }
  }
  return image;
}

List<ui.Offset> _simplify(List<ui.Offset> points, double tolerance) {
  if (points.length <= 2) return points;
  var maxDistance = 0.0;
  var maxIndex = 0;
  final start = points.first;
  final end = points.last;
  for (var index = 1; index < points.length - 1; index++) {
    final distance = _lineDistance(points[index], start, end);
    if (distance > maxDistance) {
      maxDistance = distance;
      maxIndex = index;
    }
  }
  if (maxDistance <= tolerance) return [start, end];
  final left = _simplify(points.sublist(0, maxIndex + 1), tolerance);
  final right = _simplify(points.sublist(maxIndex), tolerance);
  return [...left.take(left.length - 1), ...right];
}

double _lineDistance(ui.Offset point, ui.Offset start, ui.Offset end) {
  final delta = end - start;
  if (delta.distanceSquared == 0) return (point - start).distance;
  final t =
      (((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
              delta.distanceSquared)
          .clamp(0.0, 1.0);
  return (point - (start + delta * t)).distance;
}

Iterable<int> _neighbors(int index, int width, int height) sync* {
  final x = index % width;
  final y = index ~/ width;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      final nx = x + dx;
      final ny = y + dy;
      if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
        yield ny * width + nx;
      }
    }
  }
}

class _IntRect {
  const _IntRect(this.left, this.top, this.right, this.bottom);
  final int left;
  final int top;
  final int right;
  final int bottom;
  int get width => right - left;
  int get height => bottom - top;
}

class _Component {
  const _Component(this.left, this.top, this.right, this.bottom, this.area);
  final int left;
  final int top;
  final int right;
  final int bottom;
  final int area;
  int get width => right - left;
  int get height => bottom - top;
  _Component merge(_Component other) => _Component(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
    area + other.area,
  );
}
