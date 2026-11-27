import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

/// Paints the project-owned background identically in editor preview and MOV.
///
/// The visual vocabulary is inspired by Inkplainer's Apache-2.0 canvas
/// backgrounds, reimplemented as resolution-independent Dart drawing commands.
/// Recorded pictures are bounded and reused because the same background is
/// composited into every preview/export frame.
final class CanvasBackgroundRenderer {
  const CanvasBackgroundRenderer();

  static const _maxCachedPictures = 16;
  static final LinkedHashMap<_BackgroundPictureKey, Picture> _pictures =
      LinkedHashMap();

  void paint({
    required Canvas canvas,
    required Rect rect,
    required CanvasBackground background,
  }) {
    final normalized = background.normalized();
    if (normalized.isTransparent || rect.isEmpty) return;
    final key = _BackgroundPictureKey(
      width: rect.width,
      height: rect.height,
      background: normalized,
    );
    final picture = _pictures.remove(key) ?? _record(key);
    _pictures[key] = picture;
    while (_pictures.length > _maxCachedPictures) {
      _pictures.remove(_pictures.keys.first)?.dispose();
    }
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.clipRect(Offset.zero & rect.size);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  Picture _record(_BackgroundPictureKey key) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & Size(key.width, key.height);
    final background = key.background;
    switch (background.mode) {
      case CanvasBackgroundMode.transparent:
        return recorder.endRecording();
      case CanvasBackgroundMode.solid:
        canvas.drawRect(rect, Paint()..color = Color(background.colorValue));
        break;
      case CanvasBackgroundMode.preset:
        _paintPreset(canvas, rect, background.preset!);
        break;
    }
    return recorder.endRecording();
  }

  void _paintPreset(Canvas canvas, Rect rect, CanvasBackgroundPreset preset) {
    switch (preset) {
      case CanvasBackgroundPreset.notebook:
        _solid(canvas, rect, const Color(0xFFF4F8FC));
        final step = rect.shortestSide / 48;
        _horizontalLines(
          canvas,
          rect,
          step: step,
          color: const Color(0xFFC8D8E8),
        );
        canvas.drawLine(
          Offset(rect.left + step * 2.7, rect.top),
          Offset(rect.left + step * 2.7, rect.bottom),
          Paint()
            ..color = const Color(0xFFD0A5A5).withValues(alpha: 0.66)
            ..strokeWidth = _hairline(rect),
        );
        break;
      case CanvasBackgroundPreset.graph:
        _solid(canvas, rect, const Color(0xFFF0F6FA));
        final step = rect.shortestSide / 54;
        _grid(
          canvas,
          rect,
          step: step,
          color: const Color(0xFFDDE8EF),
          strokeWidth: _hairline(rect) * 0.55,
        );
        _grid(
          canvas,
          rect,
          step: step * 5,
          color: const Color(0xFFC1D4E1),
          strokeWidth: _hairline(rect),
        );
        break;
      case CanvasBackgroundPreset.cream:
        final center = Offset(
          rect.left + rect.width * 0.3,
          rect.top + rect.height * 0.2,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..shader = Gradient.radial(
              center,
              rect.longestSide * 0.75,
              const [Color(0xFFEDE0C4), Color(0xFFE8D5A0), Color(0xFFD4B87A)],
              const [0, 0.46, 1],
            ),
        );
        break;
      case CanvasBackgroundPreset.chalkboard:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = Gradient.radial(
              rect.center,
              rect.longestSide * 0.7,
              const [Color(0xFF2D4A3E), Color(0xFF1A3328), Color(0xFF0F2318)],
              const [0, 0.62, 1],
            ),
        );
        break;
      case CanvasBackgroundPreset.softGradient:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = Gradient.linear(
              rect.topLeft,
              rect.bottomRight,
              const [Color(0xFFF5F0FF), Color(0xFFE8F4FF), Color(0xFFF0FFF4)],
              const [0, 0.5, 1],
            ),
        );
        break;
      case CanvasBackgroundPreset.warmWhite:
        _solid(canvas, rect, const Color(0xFFFAFAF7));
        break;
      case CanvasBackgroundPreset.blueprint:
        _solid(canvas, rect, const Color(0xFF173653));
        final step = rect.shortestSide / 54;
        _grid(
          canvas,
          rect,
          step: step,
          color: const Color(0xFF34739A).withValues(alpha: 0.58),
          strokeWidth: _hairline(rect) * 0.7,
        );
        _grid(
          canvas,
          rect,
          step: step * 5,
          color: const Color(0xFF5C9ABE).withValues(alpha: 0.36),
          strokeWidth: _hairline(rect),
        );
        break;
      case CanvasBackgroundPreset.kraft:
        _solid(canvas, rect, const Color(0xFFC8973A));
        final step = math.max(4.0, rect.shortestSide / 180);
        final paint = Paint()
          ..color = const Color(0xFF7B5422).withValues(alpha: 0.14)
          ..strokeWidth = _hairline(rect);
        for (var x = -rect.height; x < rect.width + rect.height; x += step) {
          canvas.drawLine(
            Offset(rect.left + x, rect.top),
            Offset(rect.left + x + rect.height, rect.bottom),
            paint,
          );
        }
        break;
      case CanvasBackgroundPreset.dark:
        _solid(canvas, rect, const Color(0xFF0F0F11));
        break;
      case CanvasBackgroundPreset.linen:
        _solid(canvas, rect, const Color(0xFFF5EDE0));
        final step = math.max(3.0, rect.shortestSide / 270);
        _grid(
          canvas,
          rect,
          step: step,
          color: const Color(0xFF30261D).withValues(alpha: 0.045),
          strokeWidth: _hairline(rect) * 0.55,
        );
        break;
    }
  }

  void _solid(Canvas canvas, Rect rect, Color color) =>
      canvas.drawRect(rect, Paint()..color = color);

  void _horizontalLines(
    Canvas canvas,
    Rect rect, {
    required double step,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _hairline(rect);
    for (var y = rect.top + step; y < rect.bottom; y += step) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  void _grid(
    Canvas canvas,
    Rect rect, {
    required double step,
    required Color color,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    for (var x = rect.left; x <= rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
    for (var y = rect.top; y <= rect.bottom; y += step) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  double _hairline(Rect rect) => math.max(0.75, rect.shortestSide / 1080);
}

final class _BackgroundPictureKey {
  const _BackgroundPictureKey({
    required this.width,
    required this.height,
    required this.background,
  });

  final double width;
  final double height;
  final CanvasBackground background;

  @override
  bool operator ==(Object other) =>
      other is _BackgroundPictureKey &&
      width == other.width &&
      height == other.height &&
      background == other.background;

  @override
  int get hashCode => Object.hash(width, height, background);
}
