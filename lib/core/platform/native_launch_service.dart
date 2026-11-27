import 'package:flutter/services.dart';

/// Coordinates the native launch surface with Flutter's first rendered frame.
abstract final class NativeLaunchService {
  static const _channel = MethodChannel('handdraw_studio/lifecycle');

  static Future<void> notifyFirstFrameRendered({
    int maxAttempts = 4,
    Duration retryDelay = const Duration(milliseconds: 80),
  }) async {
    assert(maxAttempts > 0);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _channel.invokeMethod<void>('appReady');
        return;
      } on MissingPluginException {
        // Desktop plugin registration can briefly trail the first Dart frame.
      } on PlatformException {
        // Treat a transient channel failure exactly like late registration.
      }
      if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
    }
  }

  /// Exposes the native launch surface state for the real macOS startup smoke
  /// test. A null result means this platform has no launch coordinator.
  static Future<bool?> isLaunchSplashVisible() async {
    try {
      return await _channel.invokeMethod<bool>('isLaunchSplashVisible');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
