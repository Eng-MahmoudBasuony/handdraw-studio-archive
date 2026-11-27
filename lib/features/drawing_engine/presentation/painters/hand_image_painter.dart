import 'dart:ui';

void drawFeatheredHandImage({
  required Canvas canvas,
  required Image image,
  required Rect source,
  required Rect destination,
  required double opacity,
  double featherFraction = 0.09,
  Offset? armExit,
}) {
  final feather = destination.shortestSide * featherFraction.clamp(0.0, 0.3);
  canvas.saveLayer(destination, Paint());
  canvas.drawImageRect(
    image,
    source,
    destination,
    Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..color = Color.fromARGB(
        (opacity.clamp(0.0, 1.0) * 255).round(),
        255,
        255,
        255,
      ),
  );

  if (armExit != null) {
    _applyDirectionalArmFade(canvas, destination, armExit);
    _applyArmExitEdgeFeather(canvas, destination, armExit);
  } else if (feather > 0) {
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.left,
        destination.top,
        destination.left + feather,
        destination.bottom,
      ),
      Offset(destination.left, 0),
      Offset(destination.left + feather, 0),
      fadeIn: true,
    );
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.right - feather,
        destination.top,
        destination.right,
        destination.bottom,
      ),
      Offset(destination.right - feather, 0),
      Offset(destination.right, 0),
      fadeIn: false,
    );
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.left,
        destination.top,
        destination.right,
        destination.top + feather,
      ),
      Offset(0, destination.top),
      Offset(0, destination.top + feather),
      fadeIn: true,
    );
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.left,
        destination.bottom - feather,
        destination.right,
        destination.bottom,
      ),
      Offset(0, destination.bottom - feather),
      Offset(0, destination.bottom),
      fadeIn: false,
    );
  }
  canvas.restore();
}

void _applyArmExitEdgeFeather(Canvas canvas, Rect destination, Offset exit) {
  final feather = destination.shortestSide * 0.14;
  if (exit.dx <= 0.15) {
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.left,
        destination.top,
        destination.left + feather,
        destination.bottom,
      ),
      Offset(destination.left, 0),
      Offset(destination.left + feather, 0),
      fadeIn: true,
    );
  } else if (exit.dx >= 0.85) {
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.right - feather,
        destination.top,
        destination.right,
        destination.bottom,
      ),
      Offset(destination.right - feather, 0),
      Offset(destination.right, 0),
      fadeIn: false,
    );
  }

  if (exit.dy <= 0.15) {
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.left,
        destination.top,
        destination.right,
        destination.top + feather,
      ),
      Offset(0, destination.top),
      Offset(0, destination.top + feather),
      fadeIn: true,
    );
  } else if (exit.dy >= 0.85) {
    _applyEdgeFeather(
      canvas,
      Rect.fromLTRB(
        destination.left,
        destination.bottom - feather,
        destination.right,
        destination.bottom,
      ),
      Offset(0, destination.bottom - feather),
      Offset(0, destination.bottom),
      fadeIn: false,
    );
  }
}

/// Returns the calibrated arm-exit direction for bundled hands.
///
/// Custom hands keep the neutral four-edge feather until they have their own
/// calibration metadata. The bundled marker reaches the source image at the
/// bottom-right corner, so fading along the forearm axis removes its hard
/// rectangular crop without softening the pen tip or fingers.
Offset? handArmExitForProject({String? presetId, String? imagePath}) {
  if (presetId == 'marker-front-black-right') {
    return const Offset(0.5, 1);
  }
  final bundledPreset = presetId?.startsWith('marker-') ?? false;
  final legacyBundledPath =
      imagePath?.replaceAll('\\', '/').endsWith('/hand-writing-marker.png') ??
      false;
  return bundledPreset || legacyBundledPath ? const Offset(1, 1) : null;
}

void _applyDirectionalArmFade(Canvas canvas, Rect destination, Offset exit) {
  final normalizedExit = Offset(
    exit.dx.clamp(0.0, 1.0),
    exit.dy.clamp(0.0, 1.0),
  );
  const center = Offset(0.5, 0.5);
  final direction = normalizedExit - center;
  if (direction.distanceSquared < 0.0001) return;

  // End the fade before the bitmap boundary. Every opaque forearm pixel is
  // therefore already transparent before it reaches the rectangular crop.
  final exitsThroughBottomCenter =
      normalizedExit.dy >= .85 &&
      normalizedExit.dx >= .35 &&
      normalizedExit.dx <= .65;
  final fadeStart = center + direction * (exitsThroughBottomCenter ? .55 : .20);
  final fadeEnd = center + direction * (exitsThroughBottomCenter ? .96 : .65);
  Offset inDestination(Offset point) => Offset(
    destination.left + point.dx * destination.width,
    destination.top + point.dy * destination.height,
  );

  canvas.drawRect(
    destination,
    Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = Gradient.linear(
        inDestination(fadeStart),
        inDestination(fadeEnd),
        const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        const [0, 0.18, 1],
        TileMode.clamp,
      ),
  );
}

void _applyEdgeFeather(
  Canvas canvas,
  Rect rect,
  Offset from,
  Offset to, {
  required bool fadeIn,
}) {
  const transparent = Color(0x00FFFFFF);
  const opaque = Color(0xFFFFFFFF);
  canvas.drawRect(
    rect,
    Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = Gradient.linear(
        from,
        to,
        fadeIn ? const [transparent, opaque] : const [opaque, transparent],
      ),
  );
}
