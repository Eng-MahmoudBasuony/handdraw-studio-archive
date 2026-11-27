import 'dart:typed_data';

/// Exact Zhang-Suen deletion decisions for the 256 binary neighborhoods.
/// Bit order is N, NE, E, SE, S, SW, W, NW. The center is already foreground.
/// A table is shared by all pixels in a raster worker; no per-pixel lists.
final class ThinningNeighborhood {
  ThinningNeighborhood._();

  static final Uint8List _deletions = _build();

  static bool shouldDelete(int mask, int step) =>
      (_deletions[mask] & (1 << step)) != 0;

  static Uint8List _build() {
    final result = Uint8List(256);
    for (var mask = 0; mask < 256; mask++) {
      final p = List<int>.generate(8, (bit) => (mask >> bit) & 1);
      final count = p.fold(0, (sum, value) => sum + value);
      if (count < 2 || count > 6) continue;
      var transitions = 0;
      for (var i = 0; i < 8; i++) {
        if (p[i] == 0 && p[(i + 1) % 8] == 1) transitions++;
      }
      if (transitions != 1) continue;
      if (p[0] * p[2] * p[4] == 0 && p[2] * p[4] * p[6] == 0) {
        result[mask] |= 1;
      }
      if (p[0] * p[2] * p[6] == 0 && p[0] * p[4] * p[6] == 0) {
        result[mask] |= 2;
      }
    }
    return result;
  }
}
