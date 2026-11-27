import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_text_lines.dart';

void main() {
  test(
    'joins split words and removes adjacent line from oversized OCR box',
    () {
      final pixels = Uint8List(200 * 120 * 4)..fillRange(0, 200 * 120 * 4, 255);
      void glyph(int left, int top, int right, int bottom) {
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            final p = (y * 200 + x) * 4;
            pixels[p] = pixels[p + 1] = pixels[p + 2] = 0;
          }
        }
      }

      for (final x in [30, 50, 70, 90]) {
        glyph(x, 30, x + 5, 50);
      }
      glyph(120, 30, 125, 50);
      glyph(140, 30, 145, 50);
      for (final x in [30, 50, 70, 90, 110, 130]) {
        glyph(x, 62, x + 5, 82);
      }
      final result = const CodexTextLines().resolve(
        [
          const SmartTextRegion(
            text: 'flutter pub',
            confidence: 1,
            bounds: Rect.fromLTRB(.14, .24, .52, .54),
          ),
          const SmartTextRegion(
            text: 'get',
            confidence: 1,
            bounds: Rect.fromLTRB(.59, .24, .74, .43),
          ),
          const SmartTextRegion(
            text: 'flutter pub upgrade',
            confidence: 1,
            bounds: Rect.fromLTRB(.14, .5, .77, .71),
          ),
        ],
        pixels,
        200,
        120,
      );
      expect(result, hasLength(2));
      expect(result.first.text, 'flutter pub get');
      expect(result.first.bounds.right, .74);
      expect(result.first.bounds.bottom * 120, lessThan(60));
      expect(result.last.bounds.top * 120, greaterThan(55));
    },
  );
}
