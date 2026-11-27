import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/image_animation/application/flat_text_background_sampler.dart';

void main() {
  const sampler = FlatTextBackgroundSampler();
  const cut = Rect.fromLTRB(.1, .3, .9, .6);
  Uint8List source() =>
      Uint8List.fromList(List.generate(100 * 100 * 4, (_) => 255));
  test(
    'OCR edge glyphs and sparse antialiasing do not reject a white panel',
    () {
      final pixels = source();
      for (var x = 20; x < 60; x++) {
        for (final y in [30, 60]) {
          for (var c = 0; c < 3; c++) {
            pixels[(y * 100 + x) * 4 + c] = 10;
          }
        }
      }
      pixels[(26 * 100 + 10) * 4 + 3] = 254;
      expect(sampler.sample(pixels, 100, 100, [cut]), 0xffffffff);
    },
  );
  test('transparent and strongly textured backgrounds still fail safely', () {
    final transparent = Uint8List(40000);
    expect(sampler.sample(transparent, 100, 100, [cut]), isNull);
    final textured = source();
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 100; x++) {
        for (var c = 0; c < 3; c++) {
          textured[(y * 100 + x) * 4 + c] = x * 2;
        }
      }
    }
    expect(sampler.sample(textured, 100, 100, [cut]), isNull);
  });
}
