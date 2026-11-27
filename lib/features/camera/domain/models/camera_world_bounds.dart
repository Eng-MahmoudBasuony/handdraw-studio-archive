final class CameraWorldBounds {
  const CameraWorldBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(right >= left),
       assert(bottom >= top);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  bool get isEmpty => width <= 0 || height <= 0;

  CameraWorldBounds union(CameraWorldBounds other) => CameraWorldBounds(
    left: left < other.left ? left : other.left,
    top: top < other.top ? top : other.top,
    right: right > other.right ? right : other.right,
    bottom: bottom > other.bottom ? bottom : other.bottom,
  );
}
