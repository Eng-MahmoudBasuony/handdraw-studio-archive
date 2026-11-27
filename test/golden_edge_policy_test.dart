import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/edge_aware_golden_comparator.dart';

const policy = GoldenEdgePolicy();
const side = 256;

GoldenRaster canvas([int color = 255]) {
  final bytes = Uint8List(side * side * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = bytes[i + 1] = bytes[i + 2] = color;
    bytes[i + 3] = 255;
  }
  return GoldenRaster(side, side, bytes);
}

GoldenRaster clone(GoldenRaster image) =>
    GoldenRaster(image.width, image.height, Uint8List.fromList(image.rgba));

void pixel(GoldenRaster image, int x, int y, List<int> rgb, {int alpha = 255}) {
  final i = (y * image.width + x) * 4;
  image.rgba.setRange(i, i + 4, [...rgb, alpha]);
}

void gray(GoldenRaster image, int x, int y, int value) =>
    pixel(image, x, y, [value, value, value]);

GoldenRaster edge() {
  final image = canvas();
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < 128; x++) {
      gray(image, x, y, 0);
    }
    gray(image, 128, y, 128);
  }
  return image;
}

void box(GoldenRaster image, int x, int y, int width, int height, int shade) {
  for (var yy = y; yy < y + height; yy++) {
    for (var xx = x; xx < x + width; xx++) {
      gray(image, xx, yy, shade);
    }
  }
}

void rejectsBothWays(GoldenRaster before, GoldenRaster after) {
  expect(
    policy.compare(before, after).matches,
    isFalse,
    reason: 'Original to modified must fail',
  );
  expect(
    policy.compare(after, before).matches,
    isFalse,
    reason: 'Modified to original must also fail',
  );
}

void main() {
  test('exact raster including transparent pixels remains exact', () {
    final image = canvas();
    pixel(image, 20, 20, [35, 63, 91], alpha: 128);
    final result = policy.compare(image, clone(image));
    expect(result.matches, isTrue);
    expect(result.edgePixels, 0);
  });

  test('accepts bounded partial coverage changes on an unchanged edge', () {
    final before = edge(), after = clone(before);
    gray(after, 128, 40, 148);
    gray(after, 128, 41, 115);
    final result = policy.compare(before, after);
    expect(result.matches, isTrue);
    expect(result.edgePixels, 2);
    expect(policy.compare(after, before).matches, isTrue);
  });

  test('accepts RGB coverage interpolation between two colored anchors', () {
    final before = canvas();
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        pixel(before, x, y, x < 128 ? [20, 40, 60] : [220, 180, 100]);
      }
      pixel(before, 128, y, [120, 110, 80]);
    }
    final after = clone(before);
    pixel(after, 128, 40, [140, 124, 84]);
    expect(policy.compare(before, after).matches, isTrue);
  });

  test('rejects a single RGB step in a flat background or filled region', () {
    for (final shade in [0, 80, 254]) {
      final before = canvas(shade), after = clone(before);
      gray(after, 40, 40, shade + 1);
      rejectsBothWays(before, after);
    }
  });

  test(
    'rejects a one-step solid-region recolor immediately beside an edge',
    () {
      final before = edge(), after = clone(before);
      gray(after, 129, 40, 254);
      rejectsBothWays(before, after);
    },
  );

  test('rejects hue changes that preserve approximate edge luminance', () {
    final before = edge(), after = clone(before);
    pixel(after, 128, 40, [148, 122, 128]);
    rejectsBothWays(before, after);
  });

  test(
    'rejects shifted edge hues for each RGB channel and either polarity',
    () {
      for (final base in [40, 128, 210]) {
        for (var channel = 0; channel < 3; channel++) {
          for (final direction in [-1, 1]) {
            final before = edge();
            gray(before, 128, 40, base);
            final after = clone(before);
            final color = [base, base, base];
            color[channel] += direction * 20;
            pixel(after, 128, 40, color);
            rejectsBothWays(before, after);
          }
        }
      }
    },
  );

  test(
    'rejects a one-pixel diagonal stroke shift below area and delta limits',
    () {
      final before = canvas(100), after = canvas(100);
      for (var i = 0; i < 4; i++) {
        gray(before, 40 + i, 40 + i, 132);
        gray(after, 41 + i, 40 + i, 132);
      }
      rejectsBothWays(before, after);
    },
  );

  test('rejects black tiny control removal and reappearance', () {
    for (final size in [1, 2, 3]) {
      final before = canvas(), after = canvas();
      box(before, 40, 40, size, size, 0);
      rejectsBothWays(before, after);
    }
  });

  test(
    'rejects one-pixel translations even for small low-contrast controls',
    () {
      final before = canvas(100), after = canvas(100);
      box(before, 40, 40, 3, 3, 132);
      box(after, 41, 40, 3, 3, 132);
      rejectsBothWays(before, after);
    },
  );

  test('rejects one-pixel resize of a small low-contrast control', () {
    final before = canvas(100), after = canvas(100);
    box(before, 40, 40, 3, 3, 132);
    box(after, 40, 40, 4, 3, 132);
    rejectsBothWays(before, after);
  });

  test(
    'rejects removal of single-pixel and tiny controls below area budget',
    () {
      for (final size in [1, 2, 3]) {
        final before = canvas(100), after = canvas(100);
        box(before, 40, 40, size, size, 132);
        rejectsBothWays(before, after);
      }
    },
  );

  test('rejects adding a new edge when the original coordinate was flat', () {
    final before = canvas(100), after = clone(before);
    gray(after, 40, 40, 132);
    rejectsBothWays(before, after);
  });

  test('rejects alpha changes and changes on translucent artwork', () {
    final before = edge(), after = clone(before);
    pixel(after, 128, 40, [128, 128, 128], alpha: 254);
    rejectsBothWays(before, after);
    pixel(before, 128, 40, [128, 128, 128], alpha: 128);
    pixel(after, 128, 40, [140, 140, 140], alpha: 128);
    rejectsBothWays(before, after);
  });

  test('rejects stronger coverage drift even when only one pixel changes', () {
    final before = edge(), after = clone(before);
    gray(after, 128, 40, 169);
    rejectsBothWays(before, after);
  });

  test(
    'rejects widespread small AA differences rather than averaging error',
    () {
      final before = edge(), after = clone(before);
      for (var y = 0; y < 66; y++) {
        gray(after, 128, y, 129);
      }
      rejectsBothWays(before, after);
    },
  );

  test(
    'rejects blur of a small shape rather than aligning or smoothing it',
    () {
      final before = canvas(), after = canvas();
      box(before, 40, 40, 3, 3, 0);
      // Separable [1,2,1]/4 Gaussian blur of the 3x3 square: 25 changed pixels,
      // safely under the 65-pixel budget, so local checks must reject it.
      const weights = [1, 2, 1];
      for (var y = 39; y <= 43; y++) {
        for (var x = 39; x <= 43; x++) {
          var sum = 0;
          for (var yy = -1; yy <= 1; yy++) {
            for (var xx = -1; xx <= 1; xx++) {
              sum +=
                  before.rgba[((y + yy) * side + x + xx) * 4] *
                  weights[xx + 1] *
                  weights[yy + 1];
            }
          }
          gray(after, x, y, (sum / 16).round());
        }
      }
      rejectsBothWays(before, after);
    },
  );

  test('rejects mismatched dimensions and invalid buffers', () {
    final before = canvas();
    expect(
      policy.compare(before, GoldenRaster(128, 512, before.rgba)).matches,
      isFalse,
    );
    expect(
      policy.compare(before, GoldenRaster(side, side, Uint8List(4))).matches,
      isFalse,
    );
  });
}
