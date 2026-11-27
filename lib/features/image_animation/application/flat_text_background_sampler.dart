import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Measures a flat background outside OCR boxes. A few antialiased glyph or
/// compression pixels must not reject an otherwise uniform panel. Each line
/// must independently have a predominantly opaque, consistent background.
final class FlatTextBackgroundSampler {
  const FlatTextBackgroundSampler();

  int? sample(Uint8List rgba, int width, int height, List<Rect> cuts) {
    if (width < 1 || height < 1 || rgba.length < width * height * 4) {
      return null;
    }
    final colors = <List<int>>[];
    for (final cut in cuts) {
      final left = (cut.left * width).floor().clamp(0, width - 1);
      final right = (cut.right * width).ceil().clamp(0, width - 1);
      final margin = math
          .max(2, (cut.height * height * .12).round())
          .clamp(2, 8);
      final top = ((cut.top * height).floor() - margin).clamp(0, height - 1);
      final bottom = ((cut.bottom * height).ceil() + margin).clamp(
        0,
        height - 1,
      );
      final samples = <List<int>>[];
      var total = 0;
      for (var i = 0; i <= 32; i++) {
        final x = left + ((right - left) * i / 32).round();
        for (final y in [top, bottom]) {
          final point = Offset(x / width, y / height);
          if (cuts.any((other) => other != cut && other.contains(point))) {
            continue;
          }
          total++;
          final offset = (y * width + x) * 4;
          if (rgba[offset + 3] < 250) continue;
          samples.add([rgba[offset], rgba[offset + 1], rgba[offset + 2]]);
        }
      }
      if (total < 16 || samples.length < total * .9) return null;
      final color = [
        for (var channel = 0; channel < 3; channel++)
          (samples.map((p) => p[channel]).toList()
            ..sort())[samples.length ~/ 2],
      ];
      final consistent = samples.where((p) => _distance(p, color) <= 16).length;
      if (consistent < total * .85) return null;
      colors.add(color);
    }
    if (colors.isEmpty) return null;
    final color = [
      for (var channel = 0; channel < 3; channel++)
        (colors.map((p) => p[channel]).toList()..sort())[colors.length ~/ 2],
    ];
    if (colors.any((c) => _distance(c, color) > 16)) return null;
    return 0xff000000 | color[0] << 16 | color[1] << 8 | color[2];
  }

  int _distance(List<int> a, List<int> b) =>
      [for (var i = 0; i < 3; i++) (a[i] - b[i]).abs()].reduce(math.max);
}
