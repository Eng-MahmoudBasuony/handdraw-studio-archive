/// Resolves the hand in output/screen space, independently of camera zoom.
/// [preferredHeightFraction] is a fraction of output height.
final class HandDisplayPolicy {
  const HandDisplayPolicy({
    this.minimumHeightFraction = .06,
    this.maximumHeightFraction = .90,
  });

  final double minimumHeightFraction;
  final double maximumHeightFraction;

  HandDisplayLayout resolve({
    required double outputWidth,
    required double outputHeight,
    required double imageWidth,
    required double imageHeight,
    required double preferredHeightFraction,
    required double penTipX,
    required double penTipY,
    bool flipX = false,
  }) {
    if (outputWidth <= 0 ||
        outputHeight <= 0 ||
        imageWidth <= 0 ||
        imageHeight <= 0) {
      throw ArgumentError('Hand and output dimensions must be positive.');
    }
    final fraction = preferredHeightFraction
        .clamp(minimumHeightFraction, maximumHeightFraction)
        .toDouble();
    final height = outputHeight * fraction;
    final width = height * imageWidth / imageHeight;
    final anchorX = (flipX ? 1 - penTipX : penTipX) * width;
    return HandDisplayLayout(
      width: width,
      height: height,
      penAnchorX: anchorX,
      penAnchorY: penTipY * height,
      outputHeightFraction: fraction,
    );
  }
}

final class HandDisplayLayout {
  const HandDisplayLayout({
    required this.width,
    required this.height,
    required this.penAnchorX,
    required this.penAnchorY,
    required this.outputHeightFraction,
  });

  final double width;
  final double height;
  final double penAnchorX;
  final double penAnchorY;
  final double outputHeightFraction;
}
