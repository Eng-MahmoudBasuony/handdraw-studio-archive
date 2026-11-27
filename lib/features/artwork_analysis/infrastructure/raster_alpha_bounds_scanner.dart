import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

enum RasterAlphaBoundsStatus {
  visible,
  opaque,
  fullyTransparent,
  decodeFailed,
  limitExceeded,
  cancelled,
}

final class RasterPixelBounds {
  const RasterPixelBounds(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom;
}

/// Lightweight color statistics collected during the existing alpha scan.
///
/// Keeping these values on the scan result lets product policies distinguish
/// sparse line art from a full-background raster without decoding the image a
/// second time.
final class RasterPixelProfile {
  const RasterPixelProfile({
    required this.visiblePixelCount,
    required this.nearWhiteNeutralPixelCount,
    required this.colorfulPixelCount,
  });

  final int visiblePixelCount;
  final int nearWhiteNeutralPixelCount;
  final int colorfulPixelCount;

  double get nearWhiteNeutralFraction => visiblePixelCount == 0
      ? 0
      : nearWhiteNeutralPixelCount / visiblePixelCount;
  double get colorfulFraction =>
      visiblePixelCount == 0 ? 0 : colorfulPixelCount / visiblePixelCount;
}

final class RasterAlphaBoundsResult {
  const RasterAlphaBoundsResult({
    required this.contentHash,
    required this.status,
    this.bounds,
    this.pixelProfile,
    this.warning,
  });
  final String contentHash;
  final RasterAlphaBoundsStatus status;
  final RasterPixelBounds? bounds;
  final RasterPixelProfile? pixelProfile;
  final String? warning;
}

final class RasterAlphaBoundsCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Computes alpha bounds once per encoded-content hash outside the UI isolate.
final class RasterAlphaBoundsScanner {
  const RasterAlphaBoundsScanner({
    this.maximumPixels = 64 * 1024 * 1024,
    this.alphaThreshold = 1,
  });

  final int maximumPixels;
  final int alphaThreshold;
  static final Map<String, RasterAlphaBoundsResult> _cache = {};

  Future<RasterAlphaBoundsResult> scan(
    Uint8List bytes, {
    RasterAlphaBoundsCancellation? cancellation,
  }) async {
    final hash = 'sha256:${sha256.convert(bytes)}';
    final cached = _cache[hash];
    if (cached != null) return cached;
    if (cancellation?.isCancelled ?? false) return _cancelled(hash);
    final result = await Isolate.run(
      () => _scanRaster(bytes, hash, maximumPixels, alphaThreshold),
    );
    if (cancellation?.isCancelled ?? false) return _cancelled(hash);
    _cache[hash] = result;
    return result;
  }

  RasterAlphaBoundsResult _cancelled(String hash) => RasterAlphaBoundsResult(
    contentHash: hash,
    status: RasterAlphaBoundsStatus.cancelled,
    warning: 'Visible-content analysis was cancelled; encoded bounds are used.',
  );
}

RasterAlphaBoundsResult _scanRaster(
  Uint8List bytes,
  String hash,
  int maximumPixels,
  int alphaThreshold,
) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    return RasterAlphaBoundsResult(
      contentHash: hash,
      status: RasterAlphaBoundsStatus.decodeFailed,
      warning: 'Raster alpha could not be decoded; encoded bounds are used.',
    );
  }
  if (decoded.width * decoded.height > maximumPixels) {
    return RasterAlphaBoundsResult(
      contentHash: hash,
      status: RasterAlphaBoundsStatus.limitExceeded,
      warning:
          'Raster exceeds the alpha-analysis pixel limit; encoded bounds are used.',
    );
  }
  var left = decoded.width;
  var top = decoded.height;
  var right = -1;
  var bottom = -1;
  var transparentSeen = false;
  var visiblePixelCount = 0;
  var nearWhiteNeutralPixelCount = 0;
  var colorfulPixelCount = 0;
  for (final pixel in decoded) {
    if (pixel.a < 255) transparentSeen = true;
    if (pixel.a < alphaThreshold) continue;
    visiblePixelCount++;
    final red = pixel.r.toInt();
    final green = pixel.g.toInt();
    final blue = pixel.b.toInt();
    var maximum = red;
    if (green > maximum) maximum = green;
    if (blue > maximum) maximum = blue;
    var minimum = red;
    if (green < minimum) minimum = green;
    if (blue < minimum) minimum = blue;
    final channelSpread = maximum - minimum;
    if (minimum >= 242 && channelSpread <= 14) {
      nearWhiteNeutralPixelCount++;
    }
    if (channelSpread >= 24 && maximum >= 80) colorfulPixelCount++;
    if (pixel.x < left) left = pixel.x;
    if (pixel.y < top) top = pixel.y;
    if (pixel.x > right) right = pixel.x;
    if (pixel.y > bottom) bottom = pixel.y;
  }
  if (right < left || bottom < top) {
    return RasterAlphaBoundsResult(
      contentHash: hash,
      status: RasterAlphaBoundsStatus.fullyTransparent,
      warning: 'Raster is fully transparent; encoded bounds are used.',
    );
  }
  return RasterAlphaBoundsResult(
    contentHash: hash,
    status: transparentSeen
        ? RasterAlphaBoundsStatus.visible
        : RasterAlphaBoundsStatus.opaque,
    bounds: RasterPixelBounds(left, top, right + 1, bottom + 1),
    pixelProfile: RasterPixelProfile(
      visiblePixelCount: visiblePixelCount,
      nearWhiteNeutralPixelCount: nearWhiteNeutralPixelCount,
      colorfulPixelCount: colorfulPixelCount,
    ),
  );
}
