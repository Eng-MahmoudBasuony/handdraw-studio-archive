import 'dart:typed_data';

import 'thinning_neighborhood.dart';

/// Zhang-Suen with an boundary candidate list. Deletions remain
/// simultaneous within each sub-pass, just as in the raster reference.
final class SparseSkeletonThinner {
  const SparseSkeletonThinner();

  Uint8List thin(Uint8List source, int width, int height) {
    final image = Uint8List.fromList(source);
    final active = <int>[];
    final queued = Uint8List(source.length);
    // Border pixels are preserved, including their influence on neighbors.
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final index = y * width + x;
        if (image[index] == 0) continue;
        var boundary = false;
        for (var dy = -1; dy <= 1 && !boundary; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (image[index + dy * width + dx] == 0) {
              boundary = true;
              break;
            }
          }
        }
        if (boundary) {
          active.add(index);
          queued[index] = 1;
        }
      }
    }
    final remove = <int>[];
    var changed = true;
    var iteration = 0;
    while (changed && iteration++ < 80) {
      changed = false;
      for (var step = 0; step < 2; step++) {
        remove.clear();
        for (final index in active) {
          final mask =
              image[index - width] |
              (image[index - width + 1] << 1) |
              (image[index + 1] << 2) |
              (image[index + width + 1] << 3) |
              (image[index + width] << 4) |
              (image[index + width - 1] << 5) |
              (image[index - 1] << 6) |
              (image[index - width - 1] << 7);
          if (ThinningNeighborhood.shouldDelete(mask, step)) remove.add(index);
        }
        if (remove.isEmpty) continue;
        changed = true;
        for (final index in remove) {
          image[index] = 0;
        }
        active.removeWhere((index) => image[index] == 0);
        // Only neighbors of deleted pixels can become new boundary candidates.
        // Enqueue after all deletions, so the sub-pass remains simultaneous.
        for (final removed in remove) {
          final x = removed % width;
          final y = removed ~/ width;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx, ny = y + dy;
              if (nx <= 0 || nx >= width - 1 || ny <= 0 || ny >= height - 1) {
                continue;
              }
              final next = ny * width + nx;
              if (image[next] == 0 || queued[next] != 0) continue;
              queued[next] = 1;
              active.add(next);
            }
          }
        }
      }
    }
    return image;
  }
}
