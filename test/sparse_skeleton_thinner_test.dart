import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/src/sparse_skeleton_thinner.dart';

void main() {
  test(
    'sparse thinning preserves all 4x4 binary rasters including borders',
    () {
      for (var mask = 0; mask < 65536; mask++) {
        final input = Uint8List.fromList(
          List.generate(16, (bit) => (mask >> bit) & 1),
        );
        expect(
          const SparseSkeletonThinner().thin(input, 4, 4),
          _referenceThinning(input, 4, 4),
          reason: 'mask=$mask',
        );
      }
    },
  );
  test(
    'sparse thinning preserves seeded textures, solid fills and narrow rasters',
    () {
      final random = Random(50201);
      for (final size in [
        (0, 0),
        (1, 31),
        (31, 1),
        (2, 20),
        (32, 48),
        (181, 181),
      ]) {
        final (width, height) = size;
        for (final density in [0.0, .1, .5, .9, 1.0]) {
          final input = Uint8List.fromList(
            List.generate(
              width * height,
              (_) => random.nextDouble() < density ? 1 : 0,
            ),
          );
          final before = Uint8List.fromList(input);
          expect(
            const SparseSkeletonThinner().thin(input, width, height),
            _referenceThinning(input, width, height),
          );
          expect(input, before, reason: 'source is immutable');
        }
      }
    },
  );
}

// Frozen baseline algorithm: independent full-raster oracle, including the
// production 80-iteration limit and simultaneous sub-pass deletions.
Uint8List _referenceThinning(Uint8List source, int width, int height) {
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
