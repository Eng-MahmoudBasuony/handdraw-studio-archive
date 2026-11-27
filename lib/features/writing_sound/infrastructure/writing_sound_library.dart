import 'package:flutter/services.dart';

import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound_clip.dart';

class WritingSoundLibrary {
  WritingSoundLibrary._();

  static final Map<WritingSoundPreset, WritingSoundClip> _cache = {};

  static Future<WritingSoundClip?> load(WritingSoundPreset preset) async {
    final path = preset.assetPath;
    if (path == null) return null;
    final cached = _cache[preset];
    if (cached != null) return cached;
    final data = await rootBundle.load(path);
    final clip = WritingSoundClip.fromWave(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    _cache[preset] = clip;
    return clip;
  }
}
