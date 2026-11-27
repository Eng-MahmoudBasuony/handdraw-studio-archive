import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';

void main() {
  test('writing a cropped opaque line traces ink rather than white paper', () {
    final source = img.Image(width: 160, height: 40, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
    for (final x in [15, 45, 75, 105]) {
      img.fillRect(
        source,
        x1: x,
        y1: 8,
        x2: x + 4,
        y2: 30,
        color: img.ColorRgba8(10, 10, 10, 255),
      );
    }
    final plan = const RegionDrawingPlanner(
      quickPaint: true,
      textOnly: true,
      backgroundColor: 0xffffffff,
    ).build(img.encodePng(source));
    expect(plan.strokes, isNotEmpty);
    for (final item in plan.strokes) {
      for (final point in item.stroke.points) {
        final pixel = source.getPixel(
          (point.dx * 160).floor().clamp(0, 159),
          (point.dy * 40).floor().clamp(0, 39),
        );
        expect(pixel.r, lessThan(100), reason: 'Pen on blank paper at $point');
      }
    }
  });
}
