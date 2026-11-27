import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Test-only policy for bounded coverage differences at opaque raster edges.
/// This does not blur, align, resize, recolor or change either image.
class EdgeComparison {
  const EdgeComparison(this.matches, this.edgePixels, this.reason);
  final bool matches;
  final int edgePixels;
  final String reason;
}

class GoldenRaster {
  const GoldenRaster(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
}

class GoldenEdgePolicy {
  const GoldenEdgePolicy();

  // A secondary ceiling, never an alternative to validating every changed
  // pixel. Flat-region differences fail even when only one pixel differs.
  static const maximumChangedFraction = .001;
  static const maximumChannelDelta = 40;
  static const roundingDelta = 3;
  static const minimumContrast = 16.0;
  static const anchorRadius = 8;

  EdgeComparison compare(GoldenRaster expected, GoldenRaster actual) {
    if (expected.width != actual.width || expected.height != actual.height) {
      return const EdgeComparison(false, 0, 'Image dimensions differ');
    }
    final width = expected.width;
    final height = expected.height;
    final a = expected.rgba;
    final b = actual.rgba;
    if (a.length != width * height * 4 || b.length != a.length) {
      return const EdgeComparison(false, 0, 'Invalid RGBA buffer');
    }
    final changed = <int>[];
    for (var i = 0; i < a.length; i += 4) {
      if (!_same(a, b, i)) changed.add(i);
    }
    if (changed.isEmpty) return const EdgeComparison(true, 0, 'Exact match');
    if (changed.length > width * height * maximumChangedFraction) {
      return const EdgeComparison(false, 0, 'Edge difference budget exceeded');
    }
    for (final i in changed) {
      final x = (i ~/ 4) % width;
      final y = (i ~/ 4) ~/ width;
      if (!_isCoverageDifference(a, b, i, x, y, width, height)) {
        return EdgeComparison(false, 0, 'Non-AA difference at ($x, $y)');
      }
    }
    return EdgeComparison(true, changed.length, 'Bounded opaque-edge coverage');
  }

  bool _isCoverageDifference(
    Uint8List a,
    Uint8List b,
    int i,
    int x,
    int y,
    int width,
    int height,
  ) {
    // Transparency, including partially transparent artwork, stays exact.
    if (a[i + 3] != 255 || b[i + 3] != 255) return false;
    var delta = 0;
    for (var c = 0; c < 3; c++) {
      delta = math.max(delta, (a[i + c] - b[i + c]).abs());
    }
    if (delta > maximumChannelDelta) return false;

    // Both renders must contain a real edge at this SAME coordinate.
    for (final pixels in [a, b]) {
      var low = 255.0;
      var high = 0.0;
      for (
        var yy = math.max(0, y - 1);
        yy <= math.min(height - 1, y + 1);
        yy++
      ) {
        for (
          var xx = math.max(0, x - 1);
          xx <= math.min(width - 1, x + 1);
          xx++
        ) {
          final value = _luminance(pixels, (yy * width + xx) * 4);
          low = math.min(low, value);
          high = math.max(high, value);
        }
      }
      if (high - low < minimumContrast) return false;
    }

    // An isolated edit to a flat fill beside an edge is not antialiasing.
    // Coverage may extend into a solid pixel only as part of a changed contour
    // containing neighboring transition pixels; enforce this symmetrically.
    for (final pixels in [a, b]) {
      if (!_solidPatch(pixels, x, y, width, height)) continue;
      var transitionNeighbor = false;
      for (
        var yy = math.max(0, y - 1);
        yy <= math.min(height - 1, y + 1);
        yy++
      ) {
        for (
          var xx = math.max(0, x - 1);
          xx <= math.min(width - 1, x + 1);
          xx++
        ) {
          final j = (yy * width + xx) * 4;
          if (j != i &&
              !_same(a, b, j) &&
              !_solidPatch(pixels, xx, yy, width, height)) {
            transitionNeighbor = true;
          }
        }
      }
      if (!transitionNeighbor) return false;
    }

    // Anchors must be unchanged at identical coordinates in BOTH images.
    // The larger window includes the straight portions of a rounded border.
    var low = 255.0;
    var high = 0.0;
    final anchorColors = <int>{};
    for (
      var yy = math.max(0, y - anchorRadius);
      yy <= math.min(height - 1, y + anchorRadius);
      yy++
    ) {
      for (
        var xx = math.max(0, x - anchorRadius);
        xx <= math.min(width - 1, x + anchorRadius);
        xx++
      ) {
        final j = (yy * width + xx) * 4;
        if (j == i || a[j + 3] != 255 || !_same(a, b, j)) continue;
        anchorColors.add((a[j] << 16) | (a[j + 1] << 8) | a[j + 2]);
        final value = _luminance(a, j);
        low = math.min(low, value);
        high = math.max(high, value);
      }
    }
    if (high - low < minimumContrast) return false;
    if (delta <= roundingDelta) return true;
    if (!_followsAnchorColorDirection(a, b, i, anchorColors.toList())) {
      return false;
    }
    final before = _luminance(a, i);
    final after = _luminance(b, i);
    return math.min(before, after) >= low - roundingDelta &&
        math.max(before, after) <= high + roundingDelta &&
        ((before > low + .01 && before < high - .01) ||
            (after > low + .01 && after < high - .01));
  }

  static bool _solidPatch(
    Uint8List pixels,
    int x,
    int y,
    int width,
    int height,
  ) {
    final i = (y * width + x) * 4;
    for (final top in [y - 1, y]) {
      for (final left in [x - 1, x]) {
        if (left < 0 || top < 0 || left + 1 >= width || top + 1 >= height) {
          continue;
        }
        var uniform = true;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            final j = ((top + dy) * width + left + dx) * 4;
            for (var c = 0; c < 4; c++) {
              if (pixels[i + c] != pixels[j + c]) uniform = false;
            }
          }
        }
        if (uniform) return true;
      }
    }
    return false;
  }

  // Changing coverage follows an existing foreground/background color vector.
  // A luminance-only check would incorrectly accept new hues on gray edges.
  static bool _followsAnchorColorDirection(
    Uint8List a,
    Uint8List b,
    int i,
    List<int> colors,
  ) {
    final delta = [for (var c = 0; c < 3; c++) b[i + c] - a[i + c]];
    for (var first = 0; first < colors.length; first++) {
      for (var second = first + 1; second < colors.length; second++) {
        final vector = [
          for (final shift in [16, 8, 0])
            ((colors[second] >> shift) & 255) -
                ((colors[first] >> shift) & 255),
        ];
        final norm = vector.fold<int>(0, (sum, v) => sum + v * v);
        if (norm < minimumContrast * minimumContrast) continue;
        final projection =
            (delta[0] * vector[0] +
                delta[1] * vector[1] +
                delta[2] * vector[2]) /
            norm;
        if ([0, 1, 2].every(
          (c) => (delta[c] - projection * vector[c]).abs() <= roundingDelta,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _same(Uint8List a, Uint8List b, int i) =>
      a[i] == b[i] &&
      a[i + 1] == b[i + 1] &&
      a[i + 2] == b[i + 2] &&
      a[i + 3] == b[i + 3];
  static double _luminance(Uint8List pixels, int i) =>
      .2126 * pixels[i] + .7152 * pixels[i + 1] + .0722 * pixels[i + 2];
}

class EdgeAwareGoldenComparator extends LocalFileComparator {
  EdgeAwareGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final expected = await _decode(
      Uint8List.fromList(await getGoldenBytes(golden)),
    );
    final actual = await _decode(imageBytes);
    final result = const GoldenEdgePolicy().compare(expected, actual);
    if (result.matches) {
      if (result.edgePixels > 0) {
        // Keep relaxed matches visible in CI, instead of silently accepting them.
        // ignore: avoid_print
        print('Golden AA: $golden — ${result.edgePixels} bounded edge pixels');
      }
      return true;
    }
    // Preserve Flutter's original failure images and exact-difference report.
    return super.compare(imageBytes, golden);
  }

  Future<GoldenRaster> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return GoldenRaster(
          frame.image.width,
          frame.image.height,
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
