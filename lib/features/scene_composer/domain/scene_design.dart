import 'dart:convert';
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:path_parsing/path_parsing.dart';

enum SceneElementKind { text, vector }

class SceneElement {
  SceneElement({
    required this.name,
    required this.category,
    required this.text,
    required List<Map<String, String>> paths,
    required this.bounds,
    this.seconds = 2,
    SceneElementKind? kind,
    Object? instanceId,
  }) : kind =
           kind ??
           (paths.isEmpty ? SceneElementKind.text : SceneElementKind.vector),
       instanceId = instanceId ?? Object(),
       paths = List.unmodifiable(
         paths.map((p) => Map<String, String>.unmodifiable(p)),
       );
  final String name, category, text;
  final List<Map<String, String>> paths;
  final Rect bounds;
  final double seconds;
  final SceneElementKind kind;
  // Editing identity is independent of content-addressed library assets.
  final Object instanceId;
  bool get isText => kind == SceneElementKind.text;
  String get assetId => sha256
      .convert(utf8.encode(jsonEncode({'text': text, 'paths': paths})))
      .toString();
  SceneElement copyWith({
    String? name,
    String? category,
    String? text,
    Rect? bounds,
    double? seconds,
    bool newInstance = false,
  }) => SceneElement(
    kind: kind,
    instanceId: newInstance ? null : instanceId,
    name: name ?? this.name,
    category: category ?? this.category,
    text: text ?? this.text,
    paths: paths,
    bounds: bounds ?? this.bounds,
    seconds: seconds ?? this.seconds,
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'text': text,
    'paths': paths,
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
    'seconds': seconds,
  };
  factory SceneElement.parse(Map<String, dynamic> data) {
    String string(String key, int max) {
      final value = data[key];
      if (value is! String || value.length > max) {
        throw FormatException('Invalid $key');
      }
      return value;
    }

    double number(String key, double low, double high) {
      final value = data[key];
      if (value is! num || !value.isFinite || value < low || value > high) {
        throw FormatException('Invalid $key');
      }
      return value.toDouble();
    }

    final name = string('name', 80),
        category = string('category', 40),
        text = string('text', 300);
    final raw = data['paths'];
    if (raw is! List ||
        raw.length > 32 ||
        name.trim().isEmpty ||
        category.trim().isEmpty) {
      throw const FormatException('Invalid element');
    }
    final paths = <Map<String, String>>[];
    for (final p in raw) {
      if (p is! Map || p['d'] is! String || (p['d'] as String).length > 6000) {
        throw const FormatException('Invalid path');
      }
      final d = p['d'] as String;
      if (!RegExp(r'^[MmLlHhVvCcSsQqTtAaZz0-9eE+.,\s-]+$').hasMatch(d)) {
        throw const FormatException('Invalid geometry');
      }
      final Path path;
      try {
        path = scenePath(d);
      } on StateError {
        throw const FormatException('Invalid geometry');
      }
      final b = path.getBounds();
      if (!b.left.isFinite ||
          b.left < -5 ||
          b.top < -5 ||
          b.right > 105 ||
          b.bottom > 105) {
        throw const FormatException('Path outside element');
      }
      for (final key in ['fill', 'stroke']) {
        if (p[key] is! String ||
            !RegExp(r'^(none|#[0-9a-fA-F]{6})$').hasMatch(p[key] as String)) {
          throw const FormatException('Invalid color');
        }
      }
      paths.add({
        'd': d,
        'fill': p['fill'] as String,
        'stroke': p['stroke'] as String,
      });
    }
    if ((text.isEmpty && paths.isEmpty) ||
        (text.isNotEmpty && paths.isNotEmpty)) {
      throw const FormatException('Use text or paths');
    }
    final x = number('x', 0, 1),
        y = number('y', 0, 1),
        w = number('width', .02, 1),
        h = number('height', .02, 1);
    if (x + w > 1.0001 || y + h > 1.0001) {
      throw const FormatException('Element outside scene');
    }
    return SceneElement(
      name: name,
      category: category,
      text: text,
      paths: paths,
      bounds: Rect.fromLTWH(x, y, w, h),
      seconds: number('seconds', .2, 20),
    );
  }
}

class SceneDesign {
  SceneDesign({required this.title, required List<SceneElement> elements})
    : elements = List.unmodifiable(elements);
  final String title;
  final List<SceneElement> elements;
  Map<String, dynamic> toJson() => {
    'title': title,
    'elements': elements.map((e) => e.toJson()).toList(),
  };
  factory SceneDesign.parse(Map<String, dynamic> data) {
    final title = data['title'], raw = data['elements'];
    if (title is! String ||
        title.length > 100 ||
        raw is! List ||
        raw.isEmpty ||
        raw.length > 20) {
      throw const FormatException('Invalid scene');
    }
    final elements = raw.map((e) {
      if (e is! Map<String, dynamic>) {
        throw const FormatException('Invalid scene element');
      }
      return SceneElement.parse(e);
    }).toList();
    if (elements.fold<double>(0, (v, e) => v + e.seconds) > 180) {
      throw const FormatException('Scene is too long');
    }
    return SceneDesign(title: title, elements: elements);
  }
  static final schema =
      jsonDecode(
            r'''{"type": "object", "additionalProperties": false, "required": ["title", "elements"], "properties": {"title": {"type": "string"}, "elements": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["name", "category", "text", "x", "y", "width", "height", "seconds", "paths"], "properties": {"name": {"type": "string"}, "category": {"type": "string"}, "text": {"type": "string"}, "x": {"type": "number"}, "y": {"type": "number"}, "width": {"type": "number"}, "height": {"type": "number"}, "seconds": {"type": "number"}, "paths": {"type": "array", "items": {"type": "object", "additionalProperties": false, "required": ["d", "fill", "stroke"], "properties": {"d": {"type": "string"}, "fill": {"type": "string"}, "stroke": {"type": "string"}}}}}}}}}''',
          )
          as Map<String, dynamic>;
  static SceneDesign example() => SceneDesign.parse({
    'title': 'Flutter • Package workflow',
    'elements': [
      {
        'name': 'Flutter',
        'category': 'تقنية',
        'text': '',
        'paths': [
          {
            'd': 'M 8 48 L 69 2 L 94 2 L 24 61 Z',
            'fill': '#26C8EE',
            'stroke': '#102333',
          },
          {
            'd': 'M 29 72 L 67 44 L 91 44 L 45 85 Z',
            'fill': '#26C8EE',
            'stroke': '#102333',
          },
          {
            'd': 'M 45 85 L 60 72 L 89 98 L 61 98 Z',
            'fill': '#087BE5',
            'stroke': '#102333',
          },
        ],
        'x': .07,
        'y': .2,
        'width': .22,
        'height': .53,
        'seconds': 3,
      },
      {
        'name': 'Title',
        'category': 'نصوص',
        'text': 'Flutter packages',
        'paths': [],
        'x': .37,
        'y': .13,
        'width': .55,
        'height': .12,
        'seconds': 2,
      },
      for (final (i, text) in [
        'flutter pub get',
        'flutter pub upgrade',
        'flutter pub outdated',
        'flutter pub deps',
      ].indexed)
        {
          'name': text,
          'category': 'نصوص',
          'text': text,
          'paths': [],
          'x': .39,
          'y': .33 + i * .12,
          'width': .53,
          'height': .075,
          'seconds': 1.5,
        },
    ],
  });
}

Path scenePath(String data) {
  final proxy = _ScenePathProxy();
  writeSvgPathDataToPath(data, proxy);
  return proxy.path;
}

class _ScenePathProxy extends PathProxy {
  final path = Path();
  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void close() => path.close();
}
