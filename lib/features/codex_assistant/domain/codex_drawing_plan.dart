import 'dart:ui';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';

final class CodexDrawingPart {
  const CodexDrawingPart({
    required this.id,
    required this.name,
    required this.bounds,
    required this.mode,
    required this.seconds,
    required this.excludeText,
  });
  final String id, name, mode;
  final Rect bounds;
  final double seconds;
  final bool excludeText;
}

final class CodexDrawingPlan {
  CodexDrawingPlan({
    required this.summary,
    required List<CodexDrawingPart> parts,
    required this.showHand,
    required this.confidence,
    required this.textRegions,
  }) : parts = List.unmodifiable(parts);
  final String summary;
  final List<CodexDrawingPart> parts;
  final bool showHand;
  final double confidence;
  final List<SmartTextRegion> textRegions;

  factory CodexDrawingPlan.parse(
    Map<String, dynamic> json,
    List<SmartTextRegion> texts,
  ) {
    final rawParts = json['parts'];
    if (rawParts is! List ||
        rawParts.isEmpty ||
        rawParts.length > 24 ||
        json['showHand'] is! bool ||
        json['summary'] is! String) {
      throw const FormatException('Invalid drawing plan');
    }
    final confidence = _number(json['confidence'], 0, 1);
    final parts = <CodexDrawingPart>[];
    var total = 0.0;
    for (final raw in rawParts) {
      if (raw is! Map) throw const FormatException('Invalid part');
      final name = raw['name'];
      final mode = raw['mode'];
      if (name is! String ||
          name.trim().isEmpty ||
          name.length > 100 ||
          !{'drawPaint', 'write', 'reveal'}.contains(mode) ||
          raw['excludeText'] is! bool) {
        throw const FormatException('Invalid part');
      }
      final b = raw['bounds'];
      if (b is! List || b.length != 4) {
        throw const FormatException('Invalid bounds');
      }
      var rect = Rect.fromLTRB(
        _number(b[0], 0, 1),
        _number(b[1], 0, 1),
        _number(b[2], 0, 1),
        _number(b[3], 0, 1),
      );
      final textId = raw['textId'];
      if (textId is! String) {
        throw const FormatException('Invalid text reference');
      }
      if (mode == 'write') {
        final index = int.tryParse(textId.replaceFirst(RegExp(r'^text-'), ''));
        if (index == null ||
            !textId.startsWith('text-') ||
            index < 0 ||
            index >= texts.length) {
          throw const FormatException('Unknown OCR text line');
        }
        // Use measured OCR geometry, never the model's estimate, for letters.
        rect = texts[index].bounds
            .inflate(.002)
            .intersect(const Rect.fromLTWH(0, 0, 1, 1));
      }
      if (rect.width < .002 || rect.height < .002) {
        throw const FormatException('Empty part');
      }
      final seconds = _number(raw['seconds'], .2, 60);
      total += seconds;
      parts.add(
        CodexDrawingPart(
          id: 'ai-part-${parts.length}',
          name: name.trim(),
          bounds: rect,
          mode: mode as String,
          seconds: seconds,
          excludeText: raw['excludeText'] as bool,
        ),
      );
    }
    if (total > 300 || (json['summary'] as String).length > 500) {
      throw const FormatException('Plan too large');
    }
    return CodexDrawingPlan(
      summary: json['summary'] as String,
      parts: parts,
      showHand: json['showHand'] as bool,
      confidence: confidence,
      textRegions: List.unmodifiable(texts),
    );
  }

  /// Only scheduled writing is hidden; OCR can mistake icons/window controls
  /// for letters, and unscheduled content must remain in its parent region.
  List<Rect> get textExclusionBounds => [
    for (final part in parts)
      if (part.mode == 'write') part.bounds,
  ];

  List<SceneRegion> get regions => [for (final part in parts) _region(part)];

  SceneRegion _region(CodexDrawingPart part) {
    var pieces = [part.bounds];
    if (part.excludeText && part.mode != 'write') {
      for (final bounds in textExclusionBounds) {
        pieces = [for (final piece in pieces) ..._subtract(piece, bounds)];
      }
    }
    if (pieces.isEmpty) {
      throw const FormatException('Part is entirely excluded');
    }
    return SceneRegion(
      id: part.id,
      name: part.name,
      polygon: const [],
      fragments: pieces,
    );
  }

  static List<Rect> _subtract(Rect source, Rect cut) {
    final overlap = source.intersect(cut);
    if (overlap.isEmpty) return [source];
    return [
      Rect.fromLTRB(source.left, source.top, source.right, overlap.top),
      Rect.fromLTRB(source.left, overlap.bottom, source.right, source.bottom),
      Rect.fromLTRB(source.left, overlap.top, overlap.left, overlap.bottom),
      Rect.fromLTRB(overlap.right, overlap.top, source.right, overlap.bottom),
    ].where((r) => !r.isEmpty).toList();
  }

  static double _number(Object? value, double min, double max) {
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw const FormatException('Invalid number');
    }
    return value.toDouble();
  }

  static const schema = <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'required': ['summary', 'showHand', 'confidence', 'parts'],
    'properties': {
      'summary': {'type': 'string'},
      'showHand': {'type': 'boolean'},
      'confidence': {'type': 'number'},
      'parts': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'name',
            'bounds',
            'mode',
            'seconds',
            'excludeText',
            'textId',
          ],
          'properties': {
            'name': {'type': 'string'},
            'bounds': {
              'type': 'array',
              'items': {'type': 'number'},
            },
            'mode': {
              'type': 'string',
              'enum': ['drawPaint', 'write', 'reveal'],
            },
            'seconds': {'type': 'number'},
            'excludeText': {'type': 'boolean'},
            'textId': {'type': 'string'},
          },
        },
      },
    },
  };
}
