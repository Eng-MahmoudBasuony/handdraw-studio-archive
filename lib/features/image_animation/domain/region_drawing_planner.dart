import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

enum ImageStrokeRole { line, paint }

enum ImageDrawingOrder { linesFirst, regionFirst }

class ImageDrawingStroke {
  const ImageDrawingStroke(this.stroke, this.role, this.region);
  final DrawingStroke stroke;
  final ImageStrokeRole role;
  final int region;
  ImageDrawingStroke copyWith({DrawingStroke? stroke, ImageStrokeRole? role}) =>
      ImageDrawingStroke(stroke ?? this.stroke, role ?? this.role, region);
}

class RegionDrawingPlan {
  const RegionDrawingPlan(this.strokes, this.analysisMilliseconds);
  final List<ImageDrawingStroke> strokes;
  final int analysisMilliseconds;
  List<ImageDrawingStroke> ordered(ImageDrawingOrder order) {
    if (order == ImageDrawingOrder.regionFirst) return List.of(strokes);
    return [
      ...strokes.where((s) => s.role == ImageStrokeRole.line),
      ...strokes.where((s) => s.role == ImageStrokeRole.paint),
    ];
  }
}

/// Source-backed masks: color segmentation only selects geometry. No palette
/// colors replace the original pixels, and no terminal source substitution is
/// required. Executed in a killable isolate owned by the experiment session.
class RegionDrawingPlanner {
  const RegionDrawingPlanner({
    this.quickPaint = false,
    this.textOnly = false,
    this.backgroundColor,
  });

  final bool textOnly;
  final int? backgroundColor;

  /// One broad, region-clipped paint pass that preserves original pixels.
  final bool quickPaint;
  RegionDrawingPlan build(Uint8List encoded) {
    final timer = Stopwatch()..start();
    final image = img.decodeImage(encoded);
    if (image == null) throw const FormatException('Unsupported image');
    if (image.width * image.height > 4000000) {
      throw const FormatException(
        'Experiment supports images up to 4 megapixels',
      );
    }
    final w = image.width, h = image.height;
    final rgba = image.getBytes(order: img.ChannelOrder.rgba);
    // The original image remains the rendering source. Remove paper only from
    // analysis, otherwise the hand traces a blank rectangle before the letters.
    final background = backgroundColor;
    if (textOnly && background != null) {
      for (var p = 0; p < rgba.length; p += 4) {
        if ((rgba[p] - ((background >> 16) & 255)).abs() <= 32 &&
            (rgba[p + 1] - ((background >> 8) & 255)).abs() <= 32 &&
            (rgba[p + 2] - (background & 255)).abs() <= 32) {
          rgba[p + 3] = 0;
        }
      }
    }
    final labels = Int32List(w * h)..fillRange(0, w * h, -1);
    final components = <List<int>>[];
    for (var p = 0; p < labels.length; p++) {
      if (labels[p] >= 0 || rgba[p * 4 + 3] == 0) continue;
      final id = components.length;
      final pixels = <int>[p];
      labels[p] = id;
      final r = rgba[p * 4], g = rgba[p * 4 + 1], b = rgba[p * 4 + 2];
      for (var head = 0; head < pixels.length; head++) {
        final q = pixels[head], x = q % w, y = q ~/ w;
        for (final n in [
          if (x > 0) q - 1,
          if (x + 1 < w) q + 1,
          if (y > 0) q - w,
          if (y + 1 < h) q + w,
        ]) {
          if (labels[n] >= 0 || rgba[n * 4 + 3] == 0) continue;
          if ((rgba[n * 4] - r).abs() > 64 ||
              (rgba[n * 4 + 1] - g).abs() > 64 ||
              (rgba[n * 4 + 2] - b).abs() > 64) {
            continue;
          }
          labels[n] = id;
          pixels.add(n);
        }
      }
      components.add(pixels);
    }
    // Anti-aliased fringes often create single-pixel color components. Attach
    // only tiny, connected fragments to a larger neighbor; never delete source
    // pixels or bridge transparent gaps. The compositor still samples RGBA.
    for (var id = 0; id < components.length; id++) {
      final pixels = components[id];
      if (pixels.isEmpty || pixels.length > 12) continue;
      var target = -1, bestDistance = 1000000;
      for (final p in pixels) {
        final x = p % w, y = p ~/ w;
        for (final n in [
          if (x > 0) p - 1,
          if (x + 1 < w) p + 1,
          if (y > 0) p - w,
          if (y + 1 < h) p + w,
        ]) {
          final neighbor = labels[n];
          if (neighbor < 0 ||
              neighbor == id ||
              components[neighbor].length <= pixels.length) {
            continue;
          }
          var difference = 0;
          for (var channel = 0; channel < 3; channel++) {
            difference += (rgba[p * 4 + channel] - rgba[n * 4 + channel]).abs();
          }
          if (difference < bestDistance) {
            target = neighbor;
            bestDistance = difference;
          }
        }
      }
      if (target < 0) continue;
      components[target].addAll(pixels);
      for (final p in pixels) {
        labels[p] = target;
      }
      pixels.clear();
    }
    final ids = List.generate(
      components.length,
      (i) => i,
    ).where((i) => components[i].isNotEmpty).toList();
    final boxes = <int, Rect>{};
    for (final id in ids) {
      var left = w, right = 0, top = h, bottom = 0;
      for (final p in components[id]) {
        left = math.min(left, p % w);
        right = math.max(right, p % w);
        top = math.min(top, p ~/ w);
        bottom = math.max(bottom, p ~/ w);
      }
      boxes[id] = Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right + 1.0,
        bottom + 1.0,
      );
    }
    // Repeated glyph-sized components on a common row use the existing
    // skeleton trail planner, including thick display lettering. This is a
    // geometric text hint, not OCR; it intentionally stays experimental.
    final glyphCandidates = ids.where((id) {
      final box = boxes[id]!;
      return box.height >= 12 &&
          box.height <= h * .25 &&
          box.width <= box.height * 1.7 &&
          components[id].length >= 20;
    }).toList();
    final textIds = <int>{if (textOnly) ...ids};
    for (final id in glyphCandidates) {
      final box = boxes[id]!;
      var neighbors = 0;
      for (final other in glyphCandidates) {
        if (other == id) continue;
        final next = boxes[other]!;
        if (next.height < box.height * .65 || next.height > box.height * 1.5) {
          continue;
        }
        if ((next.center.dy - box.center.dy).abs() >
            math.min(next.height, box.height) * .4) {
          continue;
        }
        final gap = math.max(
          0.0,
          math.max(next.left - box.right, box.left - next.right),
        );
        if (gap <= box.height * 2.5) neighbors++;
        if (neighbors >= 2) {
          textIds.add(id);
          break;
        }
      }
    }
    int category(int id) => textIds.contains(id)
        ? 1
        : components[id].length > 3000 &&
              boxes[id]!.width / boxes[id]!.height < 6
        ? 0
        : 2;
    ids.sort((a, b) {
      final group = category(a).compareTo(category(b));
      if (group != 0) return group;
      if (category(a) == 1) {
        final aa = boxes[a]!, bb = boxes[b]!;
        if ((aa.center.dy - bb.center.dy).abs() <
            math.min(aa.height, bb.height) * .5) {
          return aa.left.compareTo(bb.left);
        }
        return aa.top.compareTo(bb.top);
      }
      return components[b].length.compareTo(components[a].length);
    });
    final result = <ImageDrawingStroke>[];
    final regionOrder = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    for (final id in ids) {
      final pixels = components[id];
      var left = w, right = 0, top = h, bottom = 0;
      for (final p in pixels) {
        left = math.min(left, p % w);
        right = math.max(right, p % w);
        top = math.min(top, p ~/ w);
        bottom = math.max(bottom, p ~/ w);
      }
      final cw = right - left + 5, ch = bottom - top + 5;
      final mask = Uint8List(cw * ch);
      for (final p in pixels) {
        mask[(p ~/ w - top + 2) * cw + p % w - left + 2] = 1;
      }
      Offset normalized(Offset p) =>
          Offset((p.dx + left - 2) / w, (p.dy + top - 2) / h);
      final contours = _contours(mask, cw, ch);
      // Margin avoids multiplying source antialias by an identical clip edge.
      // Original RGBA still determines every final color and transparent hole.
      final clipMask = Uint8List.fromList(mask);
      for (var p = 0; p < mask.length; p++) {
        if (mask[p] == 0) continue;
        for (final n in [p - 1, p + 1, p - cw, p + cw]) {
          clipMask[n] = 1;
        }
      }
      final clips = _contours(
        clipMask,
        cw,
        ch,
      ).map((c) => c.map(normalized).toList()).toList();
      final distance = Int32List(mask.length);
      final queue = Queue<int>();
      for (var p = 0; p < mask.length; p++) {
        if (mask[p] == 0) continue;
        if ([p - 1, p + 1, p - cw, p + cw].any((n) => mask[n] == 0)) {
          distance[p] = 1;
          queue.add(p);
        }
      }
      var depth = 1;
      while (queue.isNotEmpty) {
        final p = queue.removeFirst();
        for (final n in [p - 1, p + 1, p - cw, p + cw]) {
          if (mask[n] != 0 && distance[n] == 0) {
            distance[n] = distance[p] + 1;
            depth = math.max(depth, distance[n]);
            queue.add(n);
          }
        }
      }
      void add(List<Offset> points, double width, ImageStrokeRole role) {
        if (points.isEmpty) return;
        if (points.length == 1) {
          points = [points.first, points.first + const Offset(.01, 0)];
        }
        result.add(
          ImageDrawingStroke(
            DrawingStroke(
              id: 'region-$id-${result.length}',
              name: '${role.name} ${result.length + 1}',
              points: points.map(normalized).toList(),
              // One section, never thousands of top-level timeline blocks.
              sectionId: 'image-animation',
              revealWidth: width,
              clipPolygons: clips,
            ),
            role,
            regionOrder[id]!,
          ),
        );
      }

      if ((depth <= 9 || textIds.contains(id)) && pixels.length > 3) {
        final skeleton = _thin(mask, cw, ch);
        final trails = const SkeletonGraphPlanner().buildTrails(
          skeleton,
          cw,
          ch,
        );
        for (final trail in trails) {
          add(
            trail.map((p) => p + const Offset(.5, .5)).toList(),
            depth * 2.8 + 2,
            ImageStrokeRole.line,
          );
        }
        // Isolated dots are real strokes, never silently discarded.
        if (trails.isEmpty) {
          add(
            [Offset(cw / 2, ch / 2)],
            math.max(cw, ch).toDouble(),
            ImageStrokeRole.line,
          );
        }
      } else {
        // Trace the visible core rather than the almost transparent shadow
        // silhouette. Coverage still uses the entire original-alpha region.
        var maxAlpha = 0;
        for (final p in pixels) {
          maxAlpha = math.max(maxAlpha, rgba[p * 4 + 3]);
        }
        final core = Uint8List(mask.length);
        for (final p in pixels) {
          if (rgba[p * 4 + 3] >= maxAlpha * .6) {
            core[(p ~/ w - top + 2) * cw + p % w - left + 2] = 1;
          }
        }
        final visibleContours = _contours(core, cw, ch);
        for (final c in visibleContours.isEmpty ? contours : visibleContours) {
          var signedArea = 0.0;
          for (var i = 0; i < c.length; i++) {
            final next = c[(i + 1) % c.length];
            signedArea += c[i].dx * next.dy - next.dx * c[i].dy;
          }
          // Interior holes around lettering belong to the fill clip, not a
          // second outline of the glyph already traced through its center.
          if (signedArea > 0) add([...c, c.first], 6, ImageStrokeRole.line);
        }
      }
      if (quickPaint && depth > 9 && !textIds.contains(id)) {
        // Keep original pixels and holes. Sweep the shorter dimension with a
        // broad brush instead of repeatedly circling the same painted region.
        final horizontal = cw >= ch;
        add(
          horizontal
              ? [Offset(2, ch / 2), Offset(cw - 2, ch / 2)]
              : [Offset(cw / 2, 2), Offset(cw / 2, ch - 2)],
          (horizontal ? ch : cw).toDouble() * 1.5,
          ImageStrokeRole.paint,
        );
        continue;
      }
      // Concentric regional passes overlap; each disconnected contour lifts the
      // pen. Holes retain opposite winding in the shared mask compositor.
      for (
        var level = 1;
        depth > 9 && !textIds.contains(id) && level <= depth;
        level += 5
      ) {
        final inner = Uint8List(mask.length);
        for (var p = 0; p < inner.length; p++) {
          if (distance[p] >= level) inner[p] = 1;
        }
        for (final c in _contours(inner, cw, ch)) {
          add([...c, c.first], 15, ImageStrokeRole.paint);
        }
      }
    }
    return RegionDrawingPlan(
      List.unmodifiable(result),
      timer.elapsedMilliseconds,
    );
  }
}

List<List<Offset>> _contours(Uint8List mask, int w, int h) {
  final edges = <int, List<int>>{};
  final stride = w + 1;
  void edge(int x, int y, int xx, int yy) =>
      (edges[y * stride + x] ??= []).add(yy * stride + xx);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = y * w + x;
      if (mask[p] == 0) continue;
      if (mask[p - w] == 0) edge(x, y, x + 1, y);
      if (mask[p + 1] == 0) edge(x + 1, y, x + 1, y + 1);
      if (mask[p + w] == 0) edge(x + 1, y + 1, x, y + 1);
      if (mask[p - 1] == 0) edge(x, y + 1, x, y);
    }
  }
  final loops = <List<Offset>>[];
  while (edges.isNotEmpty) {
    final start = edges.keys.first;
    var p = start;
    final loop = <Offset>[];
    do {
      loop.add(Offset((p % stride).toDouble(), (p ~/ stride).toDouble()));
      final next = edges[p];
      if (next == null) break;
      final q = next.removeLast();
      if (next.isEmpty) edges.remove(p);
      p = q;
    } while (p != start);
    if (loop.length >= 3) {
      final simple = <Offset>[];
      for (var i = 0; i < loop.length; i++) {
        final a = loop[(i + loop.length - 1) % loop.length],
            b = loop[i],
            c = loop[(i + 1) % loop.length];
        if ((b.dx - a.dx) * (c.dy - b.dy) != (b.dy - a.dy) * (c.dx - b.dx)) {
          simple.add(b);
        }
      }
      loops.add(simple);
    }
  }
  return loops;
}

Uint8List _thin(Uint8List source, int w, int h) {
  final mask = Uint8List.fromList(source);
  var changed = true;
  while (changed) {
    changed = false;
    for (var phase = 0; phase < 2; phase++) {
      final remove = <int>[];
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final p = y * w + x;
          if (mask[p] == 0) continue;
          final n = [
            mask[p - w],
            mask[p - w + 1],
            mask[p + 1],
            mask[p + w + 1],
            mask[p + w],
            mask[p + w - 1],
            mask[p - 1],
            mask[p - w - 1],
          ];
          final count = n.fold<int>(0, (a, b) => a + b);
          if (count < 2 || count > 6) continue;
          var transitions = 0;
          for (var i = 0; i < 8; i++) {
            if (n[i] == 0 && n[(i + 1) % 8] == 1) transitions++;
          }
          if (transitions != 1) continue;
          if (phase == 0
              ? n[0] * n[2] * n[4] == 0 && n[2] * n[4] * n[6] == 0
              : n[0] * n[2] * n[6] == 0 && n[0] * n[4] * n[6] == 0) {
            remove.add(p);
          }
        }
      }
      for (final p in remove) {
        mask[p] = 0;
      }
      changed = changed || remove.isNotEmpty;
    }
  }
  return mask;
}

void runRegionPlanner((SendPort, Uint8List, bool, int?) input) {
  try {
    input.$1.send(
      RegionDrawingPlanner(
        quickPaint: true,
        textOnly: input.$3,
        backgroundColor: input.$4,
      ).build(input.$2),
    );
  } catch (error) {
    input.$1.send(error.toString());
  }
}
