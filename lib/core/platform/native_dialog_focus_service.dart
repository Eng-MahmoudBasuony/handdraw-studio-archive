import 'package:flutter/services.dart';

/// Gives the host window focus before presenting a native modal dialog.
///
/// macOS can occasionally show an open panel above an inactive application
/// window. In that state, the user's first click activates the panel instead of
/// selecting the intended file. Other platforms safely use the no-op fallback.
class NativeDialogFocusService {
  const NativeDialogFocusService();

  static const _channel = MethodChannel('handdraw_studio/lifecycle');

  Future<void> prepareForPresentation() async {
    try {
      await _channel.invokeMethod<void>('prepareForNativeDialog');
    } on MissingPluginException {
      // Platforms without a native window coordinator need no preparation.
    } on PlatformException {
      // Focus preparation is best-effort and must never block file access.
    }
  }
}
