import 'dart:io';
import 'package:flutter/services.dart';

class StartupSoundService {
  const StartupSoundService();

  static const assetPath = 'assets/sounds/بسم الله الرحمن الرحيم.mp3';
  static const _channel = MethodChannel('handdraw_studio/startup_sound');

  Future<void> play() async {
    try {
      final bytes = await rootBundle.load(assetPath);
      final file = await _prepareTemporaryAsset(bytes.buffer.asUint8List());
      await _channel.invokeMethod<void>('play', {
        'path': file.path,
        'volume': 0.3,
        'fadeInMilliseconds': 220,
        'fadeOutMilliseconds': 420,
      });
    } on MissingPluginException {
      // Unsupported platforms continue launch silently.
    } on PlatformException {
      // Startup sound must never prevent the editor from opening.
    } on FileSystemException {
      // A read-only temporary directory should only disable this optional cue.
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop', {'fadeOutMilliseconds': 140});
    } on MissingPluginException {
      // Unsupported platforms have nothing to stop.
    } on PlatformException {
      // The editor remains interactive even if native audio is unavailable.
    }
  }

  Future<File> _prepareTemporaryAsset(Uint8List bytes) async {
    final directory = Directory(
      '${Directory.systemTemp.path}/handdraw-studio-startup',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/startup-intro.mp3');
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }
}
