import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';

class LoadedHandImage {
  const LoadedHandImage({required this.bytes, required this.image});

  final Uint8List bytes;
  final ui.Image image;
}

abstract interface class HandImageLoader {
  Future<LoadedHandImage> load(HandPreset preset);
}

class FlutterHandImageLoader implements HandImageLoader {
  const FlutterHandImageLoader();

  @override
  Future<LoadedHandImage> load(HandPreset preset) async {
    final Uint8List bytes;
    if (preset.isBundled) {
      final assetPath = preset.assetPath;
      if (assetPath == null) throw StateError('Built-in hand has no asset.');
      final data = await rootBundle.load(assetPath);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } else {
      final path = preset.managedPath;
      if (path == null) throw StateError('Custom hand file is missing.');
      bytes = await File(path).readAsBytes();
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return LoadedHandImage(bytes: bytes, image: frame.image);
  }
}
