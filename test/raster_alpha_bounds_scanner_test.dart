import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/raster_alpha_bounds_scanner.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_animation_guidance.dart';
import 'package:handdraw_studio/features/artwork_analysis/application/artwork_animation_guidance_policy.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';

void main() {
  test(
    'finds trimmed alpha bounds with exclusive right and bottom edges',
    () async {
      final raster = image.Image(width: 10, height: 8, numChannels: 4);
      image.fill(raster, color: image.ColorRgba8(0, 0, 0, 0));
      image.fillRect(
        raster,
        x1: 2,
        y1: 1,
        x2: 6,
        y2: 5,
        color: image.ColorRgba8(10, 20, 30, 255),
      );
      final result = await const RasterAlphaBoundsScanner().scan(
        Uint8List.fromList(image.encodePng(raster)),
      );
      expect(result.status, RasterAlphaBoundsStatus.visible);
      expect(result.bounds?.left, 2);
      expect(result.bounds?.top, 1);
      expect(result.bounds?.right, 7);
      expect(result.bounds?.bottom, 6);
      expect(result.contentHash, startsWith('sha256:'));
    },
  );

  test('returns typed fallback for limits and cancellation', () async {
    final raster = image.Image(width: 3, height: 3);
    final bytes = Uint8List.fromList(image.encodePng(raster));
    final limited = await const RasterAlphaBoundsScanner(
      maximumPixels: 4,
    ).scan(bytes);
    expect(limited.status, RasterAlphaBoundsStatus.limitExceeded);
    expect(limited.warning, isNotEmpty);

    final cancellation = RasterAlphaBoundsCancellation()..cancel();
    final cancelled = await const RasterAlphaBoundsScanner().scan(
      Uint8List.fromList([...bytes, 0]),
      cancellation: cancellation,
    );
    expect(cancelled.status, RasterAlphaBoundsStatus.cancelled);
  });

  test(
    'guidance preserves line art and redirects full-background images',
    () async {
      final lineArt = image.Image(width: 20, height: 20, numChannels: 4);
      image.fill(lineArt, color: image.ColorRgba8(255, 255, 255, 255));
      image.drawLine(
        lineArt,
        x1: 2,
        y1: 10,
        x2: 17,
        y2: 10,
        color: image.ColorRgba8(0, 0, 0, 255),
        thickness: 2,
      );
      final colorful = image.Image(width: 20, height: 20, numChannels: 4);
      image.fill(colorful, color: image.ColorRgba8(45, 105, 190, 255));
      final scanner = const RasterAlphaBoundsScanner();
      final policy = const ArtworkAnimationGuidancePolicy();

      final lineAnalysis = await scanner.scan(
        Uint8List.fromList(image.encodePng(lineArt)),
      );
      final colorfulAnalysis = await scanner.scan(
        Uint8List.fromList(image.encodePng(colorful)),
      );

      expect(
        policy.resolve(
          sourceKind: ArtworkSourceKind.raster,
          rasterAnalysis: lineAnalysis,
        ),
        ArtworkAnimationGuidance.autoPathRecommended,
      );
      expect(
        policy.resolve(
          sourceKind: ArtworkSourceKind.raster,
          rasterAnalysis: colorfulAnalysis,
        ),
        ArtworkAnimationGuidance.autoRevealRecommended,
      );
    },
  );
}
