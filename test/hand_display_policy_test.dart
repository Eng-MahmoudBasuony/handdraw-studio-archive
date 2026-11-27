import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/policies/hand_display_policy.dart';

void main() {
  const policy = HandDisplayPolicy();

  for (final height in [720.0, 1080.0, 2160.0]) {
    test(
      'hand remains a stable output-height fraction at ${height.toInt()}p',
      () {
        final layout = policy.resolve(
          outputWidth: height * 16 / 9,
          outputHeight: height,
          imageWidth: 800,
          imageHeight: 1000,
          preferredHeightFraction: .24,
          penTipX: .2,
          penTipY: .1,
        );
        expect(layout.height / height, closeTo(.24, 1e-12));
        expect(layout.width / layout.height, closeTo(.8, 1e-12));
        expect(layout.penAnchorX, closeTo(layout.width * .2, 1e-12));
      },
    );
  }

  test('policy honors the editor maximum and mirrors the pen anchor', () {
    final layout = policy.resolve(
      outputWidth: 1920,
      outputHeight: 1080,
      imageWidth: 1000,
      imageHeight: 1000,
      preferredHeightFraction: .90,
      penTipX: .2,
      penTipY: .1,
      flipX: true,
    );
    expect(layout.outputHeightFraction, .90);
    expect(layout.penAnchorX, closeTo(layout.width * .8, 1e-12));
  });

  test('policy clamps values outside the hand-size control range', () {
    final oversized = policy.resolve(
      outputWidth: 1920,
      outputHeight: 1080,
      imageWidth: 1000,
      imageHeight: 1000,
      preferredHeightFraction: 1.2,
      penTipX: .2,
      penTipY: .1,
    );
    final undersized = policy.resolve(
      outputWidth: 1920,
      outputHeight: 1080,
      imageWidth: 1000,
      imageHeight: 1000,
      preferredHeightFraction: .01,
      penTipX: .2,
      penTipY: .1,
    );

    expect(oversized.outputHeightFraction, .90);
    expect(undersized.outputHeightFraction, .06);
  });
}
