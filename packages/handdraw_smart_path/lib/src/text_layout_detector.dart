import 'package:flutter/services.dart';

import 'models.dart';

abstract interface class TextLayoutDetector {
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage);
}

class MethodChannelTextLayoutDetector implements TextLayoutDetector {
  const MethodChannelTextLayoutDetector();

  static const MethodChannel _channel = MethodChannel(
    'handdraw_studio/smart_path',
  );

  @override
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage) async {
    final raw = await _channel.invokeListMethod<dynamic>('detectText', {
      'image': encodedImage,
    });
    if (raw == null) return const [];
    return raw
        .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final bounds = _rectFromList(map['bounds']);
          final rawCharacters = map['characters'] as List<dynamic>? ?? const [];
          return SmartTextRegion(
            text: map['text'] as String? ?? '',
            confidence: (map['confidence'] as num? ?? 0).toDouble(),
            bounds: bounds,
            characters: rawCharacters
                .map((character) {
                  final characterMap = Map<String, dynamic>.from(
                    character as Map,
                  );
                  return SmartCharacterRegion(
                    value: characterMap['value'] as String? ?? '',
                    bounds: _rectFromList(characterMap['bounds']),
                  );
                })
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  static Rect _rectFromList(dynamic value) {
    final values = (value as List<dynamic>).cast<num>();
    return Rect.fromLTWH(
      values[0].toDouble(),
      values[1].toDouble(),
      values[2].toDouble(),
      values[3].toDouble(),
    );
  }
}
