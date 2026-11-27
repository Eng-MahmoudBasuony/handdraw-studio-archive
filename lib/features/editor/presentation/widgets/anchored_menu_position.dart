import 'package:flutter/material.dart';

/// Converts a physical screen pointer position into the root overlay's space.
///
/// The resulting rect deliberately has no text-direction logic: locale changes
/// menu content direction, never the pointer's physical screen coordinates.
RelativeRect anchoredMenuPosition({
  required RenderBox overlay,
  required Offset globalPosition,
}) {
  final localPosition = overlay.globalToLocal(globalPosition);
  return RelativeRect.fromRect(
    Rect.fromLTWH(localPosition.dx, localPosition.dy, 0, 0),
    Offset.zero & overlay.size,
  );
}
