import 'dart:ui';

/// Serializable, editable path geometry kept independently from [Path].
///
/// Flutter's [Path] is an excellent rendering primitive, but it intentionally
/// does not expose its original commands. Keeping normalized commands here
/// gives SVG import, node editing, project persistence, Preview, and export one
/// lossless source of truth.
class StrokePathGeometry {
  StrokePathGeometry({
    required this.start,
    required List<StrokePathSegment> segments,
    this.closed = false,
    List<int> smoothAnchors = const [],
  }) : segments = List.unmodifiable(segments),
       smoothAnchors = List.unmodifiable(
         smoothAnchors.toSet().toList()..sort(),
       ) {
    _validatePoint(start, 'start');
    for (final segment in segments) {
      segment.validate();
    }
    if (this.smoothAnchors.any(
      (index) => index < 0 || index > segments.length,
    )) {
      throw ArgumentError.value(
        smoothAnchors,
        'smoothAnchors',
        'Smooth anchor indices must belong to this geometry.',
      );
    }
  }

  final Offset start;
  final List<StrokePathSegment> segments;
  final bool closed;
  final List<int> smoothAnchors;

  bool get isEmpty => segments.isEmpty;

  Offset get end => segments.isEmpty ? start : segments.last.end;

  Path toPath(Rect destination) {
    Offset resolve(Offset point) => Offset(
      destination.left + point.dx * destination.width,
      destination.top + point.dy * destination.height,
    );

    final path = Path();
    final resolvedStart = resolve(start);
    path.moveTo(resolvedStart.dx, resolvedStart.dy);
    for (final segment in segments) {
      switch (segment) {
        case StrokeLineSegment(:final end):
          final resolvedEnd = resolve(end);
          path.lineTo(resolvedEnd.dx, resolvedEnd.dy);
        case StrokeQuadraticSegment(:final control, :final end):
          final resolvedControl = resolve(control);
          final resolvedEnd = resolve(end);
          path.quadraticBezierTo(
            resolvedControl.dx,
            resolvedControl.dy,
            resolvedEnd.dx,
            resolvedEnd.dy,
          );
        case StrokeCubicSegment(:final control1, :final control2, :final end):
          final resolvedControl1 = resolve(control1);
          final resolvedControl2 = resolve(control2);
          final resolvedEnd = resolve(end);
          path.cubicTo(
            resolvedControl1.dx,
            resolvedControl1.dy,
            resolvedControl2.dx,
            resolvedControl2.dy,
            resolvedEnd.dx,
            resolvedEnd.dy,
          );
      }
    }
    if (closed) path.close();
    return path;
  }

  /// Reverses drawing direction without changing the rendered curve.
  StrokePathGeometry reversed() {
    if (segments.isEmpty) return this;
    final starts = <Offset>[start];
    for (final segment in segments) {
      starts.add(segment.end);
    }
    final reversedSegments = <StrokePathSegment>[];
    for (var index = segments.length - 1; index >= 0; index--) {
      final segment = segments[index];
      final originalStart = starts[index];
      reversedSegments.add(switch (segment) {
        StrokeLineSegment() => StrokeLineSegment(end: originalStart),
        StrokeQuadraticSegment(:final control) => StrokeQuadraticSegment(
          control: control,
          end: originalStart,
        ),
        StrokeCubicSegment(:final control1, :final control2) =>
          StrokeCubicSegment(
            control1: control2,
            control2: control1,
            end: originalStart,
          ),
      });
    }
    return StrokePathGeometry(
      start: end,
      segments: reversedSegments,
      closed: closed,
      smoothAnchors: [
        for (final anchor in smoothAnchors) segments.length - anchor,
      ],
    );
  }

  /// A stable approximation used by legacy planners and hit-testing.
  /// Rendering continues to use the exact line/cubic commands.
  List<Offset> sample({int cubicSteps = 12}) {
    final result = <Offset>[start];
    var current = start;
    for (final segment in segments) {
      switch (segment) {
        case StrokeLineSegment(:final end):
          result.add(end);
        case StrokeQuadraticSegment(:final control, :final end):
          for (var step = 1; step <= cubicSteps; step++) {
            final t = step / cubicSteps;
            final inverse = 1 - t;
            result.add(
              current * (inverse * inverse) +
                  control * (2 * inverse * t) +
                  end * (t * t),
            );
          }
        case StrokeCubicSegment(:final control1, :final control2, :final end):
          for (var step = 1; step <= cubicSteps; step++) {
            final t = step / cubicSteps;
            final inverse = 1 - t;
            result.add(
              current * (inverse * inverse * inverse) +
                  control1 * (3 * inverse * inverse * t) +
                  control2 * (3 * inverse * t * t) +
                  end * (t * t * t),
            );
          }
      }
      current = segment.end;
    }
    return List.unmodifiable(result);
  }

  Map<String, dynamic> toJson() => {
    'start': [start.dx, start.dy],
    'closed': closed,
    'smoothAnchors': smoothAnchors,
    'segments': segments.map((segment) => segment.toJson()).toList(),
  };

  factory StrokePathGeometry.fromJson(Map<String, dynamic> json) {
    final rawStart = json['start'] as List<dynamic>;
    return StrokePathGeometry(
      start: Offset(
        (rawStart[0] as num).toDouble(),
        (rawStart[1] as num).toDouble(),
      ),
      closed: json['closed'] as bool? ?? false,
      smoothAnchors: List<int>.from(
        json['smoothAnchors'] as List<dynamic>? ?? const [],
      ),
      segments: (json['segments'] as List<dynamic>? ?? const [])
          .map(
            (raw) => StrokePathSegment.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

sealed class StrokePathSegment {
  const StrokePathSegment();

  Offset get end;

  void validate();

  Map<String, dynamic> toJson();

  static StrokePathSegment fromJson(Map<String, dynamic> json) {
    Offset point(String key) {
      final raw = json[key] as List<dynamic>;
      return Offset((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    }

    return switch (json['type']) {
      'line' => StrokeLineSegment(end: point('end')),
      'quadratic' => StrokeQuadraticSegment(
        control: point('control'),
        end: point('end'),
      ),
      'cubic' => StrokeCubicSegment(
        control1: point('control1'),
        control2: point('control2'),
        end: point('end'),
      ),
      final type => throw FormatException('Unsupported path segment: $type'),
    };
  }
}

class StrokeLineSegment extends StrokePathSegment {
  const StrokeLineSegment({required this.end});

  @override
  final Offset end;

  @override
  void validate() => _validatePoint(end, 'line.end');

  @override
  Map<String, dynamic> toJson() => {
    'type': 'line',
    'end': [end.dx, end.dy],
  };
}

class StrokeQuadraticSegment extends StrokePathSegment {
  const StrokeQuadraticSegment({required this.control, required this.end});

  final Offset control;

  @override
  final Offset end;

  @override
  void validate() {
    _validatePoint(control, 'quadratic.control');
    _validatePoint(end, 'quadratic.end');
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'quadratic',
    'control': [control.dx, control.dy],
    'end': [end.dx, end.dy],
  };
}

class StrokeCubicSegment extends StrokePathSegment {
  const StrokeCubicSegment({
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Offset control1;
  final Offset control2;

  @override
  final Offset end;

  @override
  void validate() {
    _validatePoint(control1, 'cubic.control1');
    _validatePoint(control2, 'cubic.control2');
    _validatePoint(end, 'cubic.end');
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'cubic',
    'control1': [control1.dx, control1.dy],
    'control2': [control2.dx, control2.dy],
    'end': [end.dx, end.dy],
  };
}

void _validatePoint(Offset point, String name) {
  if (!point.dx.isFinite || !point.dy.isFinite) {
    throw ArgumentError.value(point, name, 'Path coordinates must be finite.');
  }
}
