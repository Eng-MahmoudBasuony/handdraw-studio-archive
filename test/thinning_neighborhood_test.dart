import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/src/thinning_neighborhood.dart';

void main() {
  test('all 512 binary neighborhood decisions match legacy Zhang-Suen', () {
    for (var mask = 0; mask < 256; mask++) {
      final ring = List<int>.generate(9, (i) => (mask >> (i % 8)) & 1);
      final count = ring.take(8).fold(0, (sum, value) => sum + value);
      var transitions = 0;
      for (var i = 0; i < 8; i++) {
        if (ring[i] == 0 && ring[i + 1] == 1) transitions++;
      }
      final n = ring[0], e = ring[2], s = ring[4], w = ring[6];
      for (var step = 0; step < 2; step++) {
        final first = step == 0 ? n * e * s == 0 : n * e * w == 0;
        final second = step == 0 ? e * s * w == 0 : n * s * w == 0;
        expect(
          ThinningNeighborhood.shouldDelete(mask, step),
          count >= 2 && count <= 6 && transitions == 1 && first && second,
          reason: 'mask=$mask step=$step',
        );
      }
    }
  });
}
