import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/polyline_bezier_fitter.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

void main() {
  const fitter = PolylineBezierFitter();

  test('fits a deterministic editable cubic geometry', () {
    const source = [
      Offset(0, 0.5),
      Offset(0.2, 0.25),
      Offset(0.5, 0.2),
      Offset(0.8, 0.25),
      Offset(1, 0.5),
    ];

    final first = fitter.fit(source, tolerance: 0.0001);
    final second = fitter.fit(source, tolerance: 0.0001);

    expect(first.toJson(), second.toJson());
    expect(first.start, source.first);
    expect(first.end, source.last);
    expect(first.segments, everyElement(isA<StrokeCubicSegment>()));
  });

  test('reduces a straight dense polyline to one exact segment', () {
    final source = [
      for (var index = 0; index <= 100; index++) Offset(index / 100, 0.5),
    ];
    final geometry = fitter.fit(source);

    expect(geometry.segments, hasLength(1));
    expect(geometry.segments.single, isA<StrokeLineSegment>());
    expect(geometry.end, const Offset(1, 0.5));
  });
}
