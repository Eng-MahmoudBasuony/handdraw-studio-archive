import 'dart:math' as math;
import 'dart:ui';

import 'package:path_parsing/path_parsing.dart';
import 'package:xml/xml.dart';

import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_artwork_import.dart';

class SvgArtworkParser {
  const SvgArtworkParser();

  static const maximumElements = 20000;
  static const maximumGroupDepth = 128;
  static const maximumTextCharacters = 262144;

  SvgArtworkImport parse(String source, {bool Function()? isCancelled}) {
    if (isCancelled?.call() ?? false) {
      throw const SvgImportCancelledException();
    }
    final document = XmlDocument.parse(source);
    if (document.doctypeElement != null) {
      throw const FormatException('SVG documents with a DOCTYPE are rejected.');
    }
    final root = document.rootElement;
    if (root.name.local.toLowerCase() != 'svg') {
      throw const FormatException('The document root must be an SVG element.');
    }
    final elements = root.descendants.whereType<XmlElement>().toList();
    if (elements.length > maximumElements) {
      throw const FormatException('The SVG contains too many elements.');
    }
    final textCharacters = elements.fold<int>(
      0,
      (total, element) => element.name.local.toLowerCase() == 'text'
          ? total + element.innerText.length
          : total,
    );
    if (textCharacters > maximumTextCharacters) {
      throw const FormatException('The SVG contains too much text.');
    }
    if (elements.any((element) => element.name.local == 'script')) {
      throw const FormatException('SVG scripts are not supported.');
    }
    for (final element in elements) {
      for (final attribute in element.attributes) {
        final name = attribute.name.local.toLowerCase();
        final value = attribute.value.trim().toLowerCase();
        if ((name == 'href' || name == 'src') &&
            (value.startsWith('http:') ||
                value.startsWith('https:') ||
                value.startsWith('file:'))) {
          throw const FormatException('External SVG resources are rejected.');
        }
      }
    }

    final viewport = _SvgViewport.fromRoot(root);
    final warnings = <String>[];
    final paths = <SvgImportedPath>[];
    var generatedId = 0;

    void visit(
      XmlElement element,
      _AffineTransform parentTransform,
      _SvgStyle inheritedStyle,
      int depth,
    ) {
      if (isCancelled?.call() ?? false) {
        throw const SvgImportCancelledException();
      }
      if (depth > maximumGroupDepth) {
        throw const FormatException('SVG group nesting exceeds 128 levels.');
      }
      final name = element.name.local.toLowerCase();
      if (_definitionContainers.contains(name)) return;
      if (_rasterFallbackContainers.contains(name)) {
        warnings.add('Unsupported SVG element <$name> was rasterized only.');
        return;
      }
      final transform = parentTransform.then(
        _AffineTransform.parse(element.getAttribute('transform')),
      );
      final style = inheritedStyle.merge(element);
      if (!style.isVisible) return;
      if (element.getAttribute('mask') != null ||
          element.getAttribute('clip-path') != null) {
        warnings.add(
          'Complex SVG masks and clip paths use raster fallback for appearance.',
        );
      }
      if (element.getAttribute('class') != null) {
        warnings.add(
          'CSS class styling is rendered in the preview but is not editable.',
        );
      }
      if (style.fill.contains('url(') || style.stroke.contains('url(')) {
        warnings.add(
          'Gradient or pattern paint is rendered from the SVG preview only.',
        );
      }
      if (name == 'text') {
        final imported = _textPath(
          element,
          transform,
          viewport,
          style,
          generatedId,
        );
        if (imported != null) {
          paths.add(imported);
          generatedId++;
        }
        return;
      }
      final contours = switch (name) {
        'path' => _pathContours(element.getAttribute('d')),
        'line' => _lineContours(element),
        'polyline' => _polyContours(element, closed: false),
        'polygon' => _polyContours(element, closed: true),
        'rect' => _rectContours(element),
        'circle' => _ellipseContours(element, circle: true),
        'ellipse' => _ellipseContours(element, circle: false),
        _ => const <StrokePathGeometry>[],
      };

      if (contours.isNotEmpty && style.hasPaint) {
        for (final contour in contours) {
          final normalized = _transformGeometry(contour, transform, viewport);
          if (normalized.isEmpty) continue;
          if (!normalized.closed && !style.hasStroke) continue;
          final bounds = _geometryBounds(normalized);
          final filled = style.hasFill && normalized.closed;
          final hasMarker = _hasMarker(element);
          final globalDecoration =
              name == 'line' && bounds.width >= 0.60 && bounds.height >= 0.35;
          final strokeWidth = viewport.normalizeStrokeWidth(
            style.strokeWidth * (hasMarker ? 6 : 1),
          );
          final revealWidth = filled
              ? math.max(strokeWidth, bounds.shortestSide * 1.08)
              : math.max(strokeWidth, 0.004);
          final safeRevealWidth = revealWidth.clamp(0.002, 1.0);
          final clipBounds = bounds
              .inflate(filled ? 0.001 : safeRevealWidth * 0.6)
              .intersect(const Rect.fromLTWH(0, 0, 1, 1));
          paths.add(
            SvgImportedPath(
              id:
                  element.getAttribute('id') ??
                  '${name.isEmpty ? 'path' : name}-${generatedId++}',
              geometry: normalized,
              animationGeometry: filled
                  ? _directionalFillGeometry(bounds)
                  : null,
              clipBounds: clipBounds,
              recommendedRevealWidth: safeRevealWidth,
              isFilled: filled,
              isText: false,
              isConnector: hasMarker,
              isGlobalDecoration: globalDecoration,
              fillColorValue: filled ? _svgColorValue(style.fill, style) : null,
            ),
          );
        }
      } else if (_unsupportedDrawableElements.contains(name)) {
        warnings.add('Unsupported SVG element <$name> was rasterized only.');
      }

      for (final child in element.childElements) {
        visit(child, transform, style, depth + 1);
      }
    }

    visit(root, const _AffineTransform.identity(), const _SvgStyle(), 0);
    if (paths.isEmpty) {
      warnings.add('No editable SVG paths were found.');
    }
    return SvgArtworkImport(paths: paths, warnings: warnings.toSet().toList());
  }
}

final class SvgImportCancelledException implements Exception {
  const SvgImportCancelledException();

  @override
  String toString() => 'SVG import cancelled.';
}

const _unsupportedDrawableElements = {'image', 'use', 'foreignobject'};
const _rasterFallbackContainers = {
  'filter',
  'style',
  'animate',
  'animatemotion',
  'animatetransform',
  'set',
};
const _definitionContainers = {
  'defs',
  'marker',
  'symbol',
  'clippath',
  'mask',
  'pattern',
};

bool _hasMarker(XmlElement element) {
  final style = element.getAttribute('style') ?? '';
  for (final name in const ['marker-start', 'marker-mid', 'marker-end']) {
    final value = element.getAttribute(name);
    if (value != null && value.trim().toLowerCase() != 'none') return true;
    if (RegExp('$name\\s*:\\s*(?!none)').hasMatch(style.toLowerCase())) {
      return true;
    }
  }
  return false;
}

StrokePathGeometry _directionalFillGeometry(Rect bounds) => StrokePathGeometry(
  start: Offset(bounds.left, bounds.center.dy),
  segments: [StrokeLineSegment(end: Offset(bounds.right, bounds.center.dy))],
);

SvgImportedPath? _textPath(
  XmlElement element,
  _AffineTransform transform,
  _SvgViewport viewport,
  _SvgStyle style,
  int generatedId,
) {
  if (!style.hasPaint) return null;
  final content = element.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (content.isEmpty) return null;
  final x = _number(element.getAttribute('x')) ?? 0;
  final y = _number(element.getAttribute('y')) ?? 0;
  final fontSize = math.max(1.0, style.fontSize);
  final explicitLength = _number(element.getAttribute('textLength'));
  final estimatedLength = math.max(
    fontSize * 0.6,
    content.runes.length * fontSize * 0.62,
  );
  final width = explicitLength != null && explicitLength > 0
      ? explicitLength
      : estimatedLength;
  final left = switch (style.textAnchor.trim().toLowerCase()) {
    'middle' => x - width / 2,
    'end' => x - width,
    _ => x,
  };
  final sourceBounds = Rect.fromLTRB(
    left,
    y - fontSize * 1.05,
    left + width,
    y + fontSize * 0.32,
  );
  final bounds = _transformRect(
    sourceBounds,
    transform,
    viewport,
  ).inflate(0.002).intersect(const Rect.fromLTWH(0, 0, 1, 1));
  if (bounds.isEmpty) return null;
  Offset normalize(Offset point) => viewport.normalize(transform.apply(point));
  final sourceCenterY = sourceBounds.center.dy;
  final start = normalize(Offset(sourceBounds.left, sourceCenterY));
  final end = normalize(Offset(sourceBounds.right, sourceCenterY));
  final fontTop = normalize(Offset(x, y - fontSize));
  final fontBottom = normalize(Offset(x, y + fontSize * 0.32));
  final textThickness = (fontBottom - fontTop).distance;
  final geometry = StrokePathGeometry(
    start: start,
    segments: [StrokeLineSegment(end: end)],
  );
  return SvgImportedPath(
    id: element.getAttribute('id') ?? 'text-$generatedId',
    geometry: geometry,
    animationGeometry: null,
    clipBounds: bounds,
    recommendedRevealWidth: (textThickness * 1.08).clamp(0.004, 1.0),
    isFilled: false,
    isText: true,
    isConnector: false,
    rightToLeft: _containsRtl(content),
    originalText: content,
    fontSize: fontSize,
    lineCount: content.split('\n').length,
  );
}

bool _containsRtl(String value) => value.runes.any(
  (rune) =>
      (rune >= 0x0590 && rune <= 0x08ff) ||
      (rune >= 0xfb1d && rune <= 0xfdff) ||
      (rune >= 0xfe70 && rune <= 0xfeff),
);

Rect _transformRect(
  Rect source,
  _AffineTransform transform,
  _SvgViewport viewport,
) {
  final points = [
    source.topLeft,
    source.topRight,
    source.bottomRight,
    source.bottomLeft,
  ].map((point) => viewport.normalize(transform.apply(point)));
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final point in points) {
    left = math.min(left, point.dx);
    top = math.min(top, point.dy);
    right = math.max(right, point.dx);
    bottom = math.max(bottom, point.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

class _SvgViewport {
  const _SvgViewport({
    required this.viewBox,
    required this.width,
    required this.height,
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
  });

  factory _SvgViewport.fromRoot(XmlElement root) {
    final raw = _numbers(root.getAttribute('viewBox'));
    final hasViewBox = raw.length == 4 && raw[2] > 0 && raw[3] > 0;
    final viewBox = hasViewBox
        ? Rect.fromLTWH(raw[0], raw[1], raw[2], raw[3])
        : Rect.fromLTWH(
            0,
            0,
            _number(root.getAttribute('width')) ?? 1920,
            _number(root.getAttribute('height')) ?? 1080,
          );
    final width = _number(root.getAttribute('width')) ?? viewBox.width;
    final height = _number(root.getAttribute('height')) ?? viewBox.height;
    if (viewBox.width <= 0 ||
        viewBox.height <= 0 ||
        width <= 0 ||
        height <= 0) {
      throw const FormatException('SVG width and height must be positive.');
    }

    final preserve =
        (root.getAttribute('preserveAspectRatio') ?? 'xMidYMid meet')
            .trim()
            .toLowerCase();
    if (preserve.startsWith('none')) {
      return _SvgViewport(
        viewBox: viewBox,
        width: width,
        height: height,
        scaleX: width / viewBox.width,
        scaleY: height / viewBox.height,
        offsetX: 0,
        offsetY: 0,
      );
    }
    final slice = preserve.contains('slice');
    final scale = slice
        ? math.max(width / viewBox.width, height / viewBox.height)
        : math.min(width / viewBox.width, height / viewBox.height);
    final remainingX = width - viewBox.width * scale;
    final remainingY = height - viewBox.height * scale;
    final xFactor = preserve.contains('xmin')
        ? 0.0
        : preserve.contains('xmax')
        ? 1.0
        : 0.5;
    final yFactor = preserve.contains('ymin')
        ? 0.0
        : preserve.contains('ymax')
        ? 1.0
        : 0.5;
    return _SvgViewport(
      viewBox: viewBox,
      width: width,
      height: height,
      scaleX: scale,
      scaleY: scale,
      offsetX: remainingX * xFactor,
      offsetY: remainingY * yFactor,
    );
  }

  final Rect viewBox;
  final double width;
  final double height;
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;

  Offset normalize(Offset point) => Offset(
    (offsetX + (point.dx - viewBox.left) * scaleX) / width,
    (offsetY + (point.dy - viewBox.top) * scaleY) / height,
  );

  double normalizeStrokeWidth(double value) {
    return math.max(value * scaleX / width, value * scaleY / height);
  }
}

List<StrokePathGeometry> _pathContours(String? data) {
  if (data == null || data.trim().isEmpty) return const [];
  final proxy = _GeometryPathProxy();
  writeSvgPathDataToPath(data, proxy);
  return proxy.finish();
}

List<StrokePathGeometry> _lineContours(XmlElement element) {
  final x1 = _number(element.getAttribute('x1')) ?? 0;
  final y1 = _number(element.getAttribute('y1')) ?? 0;
  final x2 = _number(element.getAttribute('x2')) ?? 0;
  final y2 = _number(element.getAttribute('y2')) ?? 0;
  return [
    StrokePathGeometry(
      start: Offset(x1, y1),
      segments: [StrokeLineSegment(end: Offset(x2, y2))],
    ),
  ];
}

List<StrokePathGeometry> _polyContours(
  XmlElement element, {
  required bool closed,
}) {
  final values = _numbers(element.getAttribute('points'));
  if (values.length < 4 || values.length.isOdd) return const [];
  final points = <Offset>[
    for (var index = 0; index < values.length; index += 2)
      Offset(values[index], values[index + 1]),
  ];
  return [
    StrokePathGeometry(
      start: points.first,
      segments: [
        for (final point in points.skip(1)) StrokeLineSegment(end: point),
      ],
      closed: closed,
    ),
  ];
}

List<StrokePathGeometry> _rectContours(XmlElement element) {
  final x = _number(element.getAttribute('x')) ?? 0;
  final y = _number(element.getAttribute('y')) ?? 0;
  final width = _number(element.getAttribute('width')) ?? 0;
  final height = _number(element.getAttribute('height')) ?? 0;
  if (width <= 0 || height <= 0) return const [];
  var radiusX = _number(element.getAttribute('rx'));
  var radiusY = _number(element.getAttribute('ry'));
  radiusX ??= radiusY ?? 0;
  radiusY ??= radiusX;
  radiusX = radiusX.clamp(0, width / 2);
  radiusY = radiusY.clamp(0, height / 2);
  if (radiusX > 0 && radiusY > 0) {
    const kappa = 0.5522847498307936;
    return [
      StrokePathGeometry(
        start: Offset(x + radiusX, y),
        segments: [
          StrokeLineSegment(end: Offset(x + width - radiusX, y)),
          StrokeCubicSegment(
            control1: Offset(x + width - radiusX + radiusX * kappa, y),
            control2: Offset(x + width, y + radiusY - radiusY * kappa),
            end: Offset(x + width, y + radiusY),
          ),
          StrokeLineSegment(end: Offset(x + width, y + height - radiusY)),
          StrokeCubicSegment(
            control1: Offset(x + width, y + height - radiusY + radiusY * kappa),
            control2: Offset(x + width - radiusX + radiusX * kappa, y + height),
            end: Offset(x + width - radiusX, y + height),
          ),
          StrokeLineSegment(end: Offset(x + radiusX, y + height)),
          StrokeCubicSegment(
            control1: Offset(x + radiusX - radiusX * kappa, y + height),
            control2: Offset(x, y + height - radiusY + radiusY * kappa),
            end: Offset(x, y + height - radiusY),
          ),
          StrokeLineSegment(end: Offset(x, y + radiusY)),
          StrokeCubicSegment(
            control1: Offset(x, y + radiusY - radiusY * kappa),
            control2: Offset(x + radiusX - radiusX * kappa, y),
            end: Offset(x + radiusX, y),
          ),
        ],
        closed: true,
      ),
    ];
  }
  return [
    StrokePathGeometry(
      start: Offset(x, y),
      segments: [
        StrokeLineSegment(end: Offset(x + width, y)),
        StrokeLineSegment(end: Offset(x + width, y + height)),
        StrokeLineSegment(end: Offset(x, y + height)),
      ],
      closed: true,
    ),
  ];
}

List<StrokePathGeometry> _ellipseContours(
  XmlElement element, {
  required bool circle,
}) {
  final centerX = _number(element.getAttribute('cx')) ?? 0;
  final centerY = _number(element.getAttribute('cy')) ?? 0;
  final radiusX = circle
      ? _number(element.getAttribute('r')) ?? 0
      : _number(element.getAttribute('rx')) ?? 0;
  final radiusY = circle ? radiusX : _number(element.getAttribute('ry')) ?? 0;
  if (radiusX <= 0 || radiusY <= 0) return const [];
  const kappa = 0.5522847498307936;
  return [
    StrokePathGeometry(
      start: Offset(centerX + radiusX, centerY),
      segments: [
        StrokeCubicSegment(
          control1: Offset(centerX + radiusX, centerY + radiusY * kappa),
          control2: Offset(centerX + radiusX * kappa, centerY + radiusY),
          end: Offset(centerX, centerY + radiusY),
        ),
        StrokeCubicSegment(
          control1: Offset(centerX - radiusX * kappa, centerY + radiusY),
          control2: Offset(centerX - radiusX, centerY + radiusY * kappa),
          end: Offset(centerX - radiusX, centerY),
        ),
        StrokeCubicSegment(
          control1: Offset(centerX - radiusX, centerY - radiusY * kappa),
          control2: Offset(centerX - radiusX * kappa, centerY - radiusY),
          end: Offset(centerX, centerY - radiusY),
        ),
        StrokeCubicSegment(
          control1: Offset(centerX + radiusX * kappa, centerY - radiusY),
          control2: Offset(centerX + radiusX, centerY - radiusY * kappa),
          end: Offset(centerX + radiusX, centerY),
        ),
      ],
      closed: true,
    ),
  ];
}

StrokePathGeometry _transformGeometry(
  StrokePathGeometry source,
  _AffineTransform transform,
  _SvgViewport viewport,
) {
  Offset normalize(Offset point) {
    final transformed = transform.apply(point);
    return viewport.normalize(transformed);
  }

  return StrokePathGeometry(
    start: normalize(source.start),
    closed: source.closed,
    segments: [
      for (final segment in source.segments)
        switch (segment) {
          StrokeLineSegment(:final end) => StrokeLineSegment(
            end: normalize(end),
          ),
          StrokeQuadraticSegment(:final control, :final end) =>
            StrokeQuadraticSegment(
              control: normalize(control),
              end: normalize(end),
            ),
          StrokeCubicSegment(:final control1, :final control2, :final end) =>
            StrokeCubicSegment(
              control1: normalize(control1),
              control2: normalize(control2),
              end: normalize(end),
            ),
        },
    ],
  );
}

Rect _geometryBounds(StrokePathGeometry geometry) {
  var left = geometry.start.dx;
  var right = geometry.start.dx;
  var top = geometry.start.dy;
  var bottom = geometry.start.dy;
  var current = geometry.start;

  void include(Offset point) {
    left = math.min(left, point.dx);
    right = math.max(right, point.dx);
    top = math.min(top, point.dy);
    bottom = math.max(bottom, point.dy);
  }

  for (final segment in geometry.segments) {
    include(segment.end);
    switch (segment) {
      case StrokeLineSegment():
        break;
      case StrokeQuadraticSegment(:final control, :final end):
        for (final axis in [0, 1]) {
          final p0 = axis == 0 ? current.dx : current.dy;
          final p1 = axis == 0 ? control.dx : control.dy;
          final p2 = axis == 0 ? end.dx : end.dy;
          final denominator = p0 - 2 * p1 + p2;
          if (denominator.abs() <= 0.0000000001) continue;
          final t = (p0 - p1) / denominator;
          if (t > 0 && t < 1) {
            include(_quadraticPoint(current, control, end, t));
          }
        }
      case StrokeCubicSegment(:final control1, :final control2, :final end):
        final candidates = <double>{};
        for (final axis in [0, 1]) {
          final p0 = axis == 0 ? current.dx : current.dy;
          final p1 = axis == 0 ? control1.dx : control1.dy;
          final p2 = axis == 0 ? control2.dx : control2.dy;
          final p3 = axis == 0 ? end.dx : end.dy;
          final a = -p0 + 3 * p1 - 3 * p2 + p3;
          final b = 2 * (p0 - 2 * p1 + p2);
          final c = p1 - p0;
          if (a.abs() <= 0.0000000001) {
            if (b.abs() > 0.0000000001) candidates.add(-c / b);
            continue;
          }
          final discriminant = b * b - 4 * a * c;
          if (discriminant < 0) continue;
          final root = math.sqrt(discriminant);
          candidates
            ..add((-b + root) / (2 * a))
            ..add((-b - root) / (2 * a));
        }
        for (final t in candidates) {
          if (t > 0 && t < 1) {
            include(_cubicPoint(current, control1, control2, end, t));
          }
        }
    }
    current = segment.end;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

Offset _quadraticPoint(Offset p0, Offset p1, Offset p2, double t) {
  final inverse = 1 - t;
  return p0 * (inverse * inverse) + p1 * (2 * inverse * t) + p2 * (t * t);
}

Offset _cubicPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final inverse = 1 - t;
  return p0 * (inverse * inverse * inverse) +
      p1 * (3 * inverse * inverse * t) +
      p2 * (3 * inverse * t * t) +
      p3 * (t * t * t);
}

class _GeometryPathProxy extends PathProxy {
  final List<StrokePathGeometry> _contours = [];
  Offset? _start;
  final List<StrokePathSegment> _segments = [];
  bool _closed = false;

  @override
  void moveTo(double x, double y) {
    _commit();
    _start = Offset(x, y);
  }

  @override
  void lineTo(double x, double y) {
    _start ??= Offset(x, y);
    _segments.add(StrokeLineSegment(end: Offset(x, y)));
  }

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _start ??= Offset(x3, y3);
    _segments.add(
      StrokeCubicSegment(
        control1: Offset(x1, y1),
        control2: Offset(x2, y2),
        end: Offset(x3, y3),
      ),
    );
  }

  @override
  void close() => _closed = true;

  List<StrokePathGeometry> finish() {
    _commit();
    return List.unmodifiable(_contours);
  }

  void _commit() {
    if (_start != null && _segments.isNotEmpty) {
      _contours.add(
        StrokePathGeometry(
          start: _start!,
          segments: List.of(_segments),
          closed: _closed,
        ),
      );
    }
    _start = null;
    _segments.clear();
    _closed = false;
  }
}

class _SvgStyle {
  const _SvgStyle({
    this.fill = 'black',
    this.stroke = 'none',
    this.strokeWidth = 1,
    this.opacity = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.display = 'inline',
    this.visibility = 'visible',
    this.fontSize = 16,
    this.textAnchor = 'start',
  });

  final String fill;
  final String stroke;
  final double strokeWidth;
  final double opacity;
  final double fillOpacity;
  final double strokeOpacity;
  final String display;
  final String visibility;
  final double fontSize;
  final String textAnchor;

  bool get isVisible =>
      opacity > 0 &&
      display.toLowerCase() != 'none' &&
      visibility.toLowerCase() != 'hidden' &&
      visibility.toLowerCase() != 'collapse';
  bool get hasFill =>
      fillOpacity > 0 && !_isTransparentPaint(fill) && isVisible;
  bool get hasStroke =>
      strokeOpacity > 0 &&
      strokeWidth > 0 &&
      !_isTransparentPaint(stroke) &&
      isVisible;
  bool get hasPaint => hasFill || hasStroke;

  _SvgStyle merge(XmlElement element) {
    final declarations = <String, String>{};
    final rawStyle = element.getAttribute('style');
    if (rawStyle != null) {
      for (final declaration in rawStyle.split(';')) {
        final separator = declaration.indexOf(':');
        if (separator <= 0) continue;
        declarations[declaration.substring(0, separator).trim()] = declaration
            .substring(separator + 1)
            .trim();
      }
    }
    String? property(String name) =>
        element.getAttribute(name) ?? declarations[name];
    return _SvgStyle(
      fill: property('fill') ?? fill,
      stroke: property('stroke') ?? stroke,
      strokeWidth: _number(property('stroke-width')) ?? strokeWidth,
      opacity: opacity * (_number(property('opacity')) ?? 1).clamp(0, 1),
      fillOpacity:
          fillOpacity * (_number(property('fill-opacity')) ?? 1).clamp(0, 1),
      strokeOpacity:
          strokeOpacity *
          (_number(property('stroke-opacity')) ?? 1).clamp(0, 1),
      display: property('display') ?? display,
      visibility: property('visibility') ?? visibility,
      fontSize: _number(property('font-size')) ?? fontSize,
      textAnchor: property('text-anchor') ?? textAnchor,
    );
  }
}

bool _isTransparentPaint(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'none' ||
      normalized == 'transparent' ||
      normalized == '#00000000' ||
      normalized == '#0000';
}

int? _svgColorValue(String value, _SvgStyle style) {
  final normalized = value.trim().toLowerCase();
  int? rgb;
  if (normalized.startsWith('#')) {
    final hex = normalized.substring(1);
    if (hex.length == 3) {
      rgb = int.tryParse(
        '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}',
        radix: 16,
      );
    } else if (hex.length == 6) {
      rgb = int.tryParse(hex, radix: 16);
    } else if (hex.length == 8) {
      final rgba = int.tryParse(hex, radix: 16);
      if (rgba != null) {
        final alpha = rgba & 0xff;
        rgb = rgba >> 8;
        final combinedAlpha = (alpha * style.opacity * style.fillOpacity)
            .round()
            .clamp(0, 255);
        return (combinedAlpha << 24) | rgb;
      }
    }
  } else {
    final match = RegExp(
      r'rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)',
    ).firstMatch(normalized);
    if (match != null) {
      final red = int.parse(match.group(1)!).clamp(0, 255);
      final green = int.parse(match.group(2)!).clamp(0, 255);
      final blue = int.parse(match.group(3)!).clamp(0, 255);
      rgb = (red << 16) | (green << 8) | blue;
      final inlineAlpha = double.tryParse(match.group(4) ?? '1') ?? 1;
      final alpha = (255 * inlineAlpha * style.opacity * style.fillOpacity)
          .round()
          .clamp(0, 255);
      return (alpha << 24) | rgb;
    }
    rgb = const {
      'black': 0x000000,
      'white': 0xffffff,
      'red': 0xff0000,
      'green': 0x008000,
      'blue': 0x0000ff,
    }[normalized];
  }
  if (rgb == null) return null;
  final alpha = (255 * style.opacity * style.fillOpacity).round().clamp(0, 255);
  return (alpha << 24) | rgb;
}

class _AffineTransform {
  const _AffineTransform(this.a, this.b, this.c, this.d, this.e, this.f);
  const _AffineTransform.identity() : this(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  Offset apply(Offset point) =>
      Offset(a * point.dx + c * point.dy + e, b * point.dx + d * point.dy + f);

  _AffineTransform then(_AffineTransform child) => _AffineTransform(
    a * child.a + c * child.b,
    b * child.a + d * child.b,
    a * child.c + c * child.d,
    b * child.c + d * child.d,
    a * child.e + c * child.f + e,
    b * child.e + d * child.f + f,
  );

  factory _AffineTransform.parse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const _AffineTransform.identity();
    }
    var result = const _AffineTransform.identity();
    final expression = RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)');
    for (final match in expression.allMatches(value)) {
      final operation = match.group(1)!.toLowerCase();
      final values = _numbers(match.group(2));
      final next = switch (operation) {
        'matrix' when values.length == 6 => _AffineTransform(
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
          values[5],
        ),
        'translate' when values.isNotEmpty => _AffineTransform(
          1,
          0,
          0,
          1,
          values[0],
          values.length > 1 ? values[1] : 0,
        ),
        'scale' when values.isNotEmpty => _AffineTransform(
          values[0],
          0,
          0,
          values.length > 1 ? values[1] : values[0],
          0,
          0,
        ),
        'rotate' when values.isNotEmpty => _rotation(values),
        _ => const _AffineTransform.identity(),
      };
      result = result.then(next);
    }
    return result;
  }

  static _AffineTransform _rotation(List<double> values) {
    final radians = values[0] * math.pi / 180;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    final rotation = _AffineTransform(cosine, sine, -sine, cosine, 0, 0);
    if (values.length < 3) return rotation;
    final toCenter = _AffineTransform(1, 0, 0, 1, values[1], values[2]);
    final fromCenter = _AffineTransform(1, 0, 0, 1, -values[1], -values[2]);
    return toCenter.then(rotation).then(fromCenter);
  }
}

double? _number(String? value) {
  if (value == null) return null;
  final match = RegExp(
    r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
  ).firstMatch(value);
  return match == null ? null : double.tryParse(match.group(0)!);
}

List<double> _numbers(String? value) {
  if (value == null) return const [];
  return RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
      .allMatches(value)
      .map((match) => double.parse(match.group(0)!))
      .toList(growable: false);
}
