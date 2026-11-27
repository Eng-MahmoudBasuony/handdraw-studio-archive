import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'package:handdraw_studio/features/artwork_analysis/domain/raster_outline_analysis.dart';

/// Decodes and downsamples a raster off the UI isolate before comparing the
/// three deterministic outline strategies.
final class RasterOutlineAnalysisService {
  const RasterOutlineAnalysisService({this.maximumAnalysisDimension = 480});

  final int maximumAnalysisDimension;

  Future<RasterOutlineComparison?> analyze(Uint8List encoded) =>
      Isolate.run(() => _analyzeRaster(encoded, maximumAnalysisDimension));
}

RasterOutlineComparison? _analyzeRaster(
  Uint8List encoded,
  int maximumAnalysisDimension,
) {
  final image.Image? decoded;
  try {
    decoded = image.decodeImage(encoded);
  } on Object {
    return null;
  }
  if (decoded == null || decoded.width <= 1 || decoded.height <= 1) return null;
  final safeMaximum = maximumAnalysisDimension.clamp(96, 1024);
  final longest = math.max(decoded.width, decoded.height);
  final scale = longest <= safeMaximum ? 1.0 : safeMaximum / longest;
  final analysisImage = scale == 1
      ? decoded
      : image.copyResize(
          decoded,
          width: math.max(2, (decoded.width * scale).round()),
          height: math.max(2, (decoded.height * scale).round()),
          interpolation: image.Interpolation.average,
        );
  final rgba = Uint8List(analysisImage.width * analysisImage.height * 4);
  var offset = 0;
  for (final pixel in analysisImage) {
    rgba[offset++] = pixel.r.toInt();
    rgba[offset++] = pixel.g.toInt();
    rgba[offset++] = pixel.b.toInt();
    rgba[offset++] = pixel.a.toInt();
  }
  return const RasterOutlineComparator().compare(
    RasterPixelBuffer(
      width: analysisImage.width,
      height: analysisImage.height,
      rgba: rgba,
    ),
  );
}
