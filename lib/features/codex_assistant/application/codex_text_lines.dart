import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

/// Reconciles OCR word fragments and measures ink on flat raster backgrounds.
/// This is local geometry work; it never changes the source artwork.
class CodexTextLines {
  const CodexTextLines();

  List<SmartTextRegion> resolve(
    List<SmartTextRegion> observations,
    Uint8List rgba,
    int width,
    int height,
  ) {
    final groups = <List<SmartTextRegion>>[];
    for (final item in observations) {
      List<SmartTextRegion>? target;
      for (final group in groups) {
        final a = group.first.bounds, b = item.bounds;
        final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
        final gap = math.max(a.left, b.left) - math.min(a.right, b.right);
        if (overlap >= math.min(a.height, b.height) * .65 &&
            gap * width < math.min(a.height, b.height) * height * 2 &&
            gap >= 0) {
          target = group;
          break;
        }
      }
      if (target == null) {
        target = [];
        groups.add(target);
      }
      target.add(item);
    }
    return groups
        .map((group) {
          final rtl = RegExp(r'[\u0590-\u08ff]').hasMatch(group.first.text);
          group.sort(
            (a, b) => rtl
                ? b.bounds.right.compareTo(a.bounds.right)
                : a.bounds.left.compareTo(b.bounds.left),
          );
          var bounds = group.first.bounds;
          for (final item in group.skip(1)) {
            bounds = bounds.expandToInclude(item.bounds);
          }
          final refined = _inkBounds(bounds, rgba, width, height);
          return SmartTextRegion(
            text: group.map((item) => item.text).join(' '),
            bounds: refined,
            confidence: group.map((item) => item.confidence).reduce(math.min),
            characters: [for (final item in group) ...item.characters],
          );
        })
        .toList(growable: false);
  }

  Rect _inkBounds(Rect bounds, Uint8List pixels, int width, int height) {
    final margin = math.max(3, (bounds.height * height * .12).ceil());
    final left = (bounds.left * width).floor().clamp(0, width - 1);
    final right = (bounds.right * width).ceil().clamp(left + 1, width);
    final top = ((bounds.top * height).floor() - margin).clamp(0, height - 1);
    final bottom = ((bounds.bottom * height).ceil() + margin).clamp(
      top + 1,
      height,
    );
    // Require a dominant opaque background; retain OCR geometry for photos.
    final counts = <int, int>{};
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final p = (y * width + x) * 4;
        if (pixels[p + 3] < 240) continue;
        final key =
            (pixels[p] ~/ 16) << 8 |
            (pixels[p + 1] ~/ 16) << 4 |
            pixels[p + 2] ~/ 16;
        counts.update(key, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    if (counts.isEmpty) return bounds;
    final color = counts.keys.reduce((a, b) => counts[a]! > counts[b]! ? a : b);
    if (counts[color]! < (right - left) * (bottom - top) * .55) return bounds;
    final background = [
      (color >> 8) * 16 + 8,
      ((color >> 4) & 15) * 16 + 8,
      (color & 15) * 16 + 8,
    ];
    bool ink(int x, int y) {
      final p = (y * width + x) * 4;
      return pixels[p + 3] > 128 &&
          ((pixels[p] - background[0]).abs() > 65 ||
              (pixels[p + 1] - background[1]).abs() > 65 ||
              (pixels[p + 2] - background[2]).abs() > 65);
    }

    final bands = <(int, int, int)>[];
    var start = -1, last = -1, weight = 0;
    final maxGap = math.max(2, (bounds.height * height * .12).round());
    for (var y = top; y < bottom; y++) {
      var count = 0;
      for (var x = left; x < right; x++) {
        if (ink(x, y)) count++;
      }
      if (count == 0) continue;
      if (start >= 0 && y - last > maxGap) {
        bands.add((start, last, weight));
        start = -1;
        weight = 0;
      }
      if (start < 0) start = y;
      last = y;
      weight += count;
    }
    if (start >= 0) bands.add((start, last, weight));
    if (bands.isEmpty) return bounds;
    final band = bands.reduce((a, b) => a.$3 >= b.$3 ? a : b);
    // Keep horizontal OCR coverage, including accents and word ends. Refine
    // vertical bounds only, so a neighboring line cannot enter the writing crop.
    return Rect.fromLTRB(
      bounds.left,
      math.max(0, band.$1 - 2) / height,
      bounds.right,
      math.min(height, band.$2 + 3) / height,
    );
  }
}
