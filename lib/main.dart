import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:handdraw_studio/app/handdraw_studio_app.dart';
import 'package:handdraw_studio/app/localization/infrastructure/shared_preferences_app_locale_repository.dart';
import 'package:handdraw_studio/app/theme/app_font_license_registry.dart';
import 'package:handdraw_studio/app/theme/infrastructure/shared_preferences_app_theme_repository.dart';
import 'package:handdraw_studio/app/startup_sound/infrastructure/shared_preferences_startup_sound_repository.dart';
import 'package:handdraw_studio/app/startup_sound/infrastructure/startup_sound_service.dart';
import 'package:handdraw_studio/core/platform/native_launch_service.dart';

export 'package:handdraw_studio/app/handdraw_studio_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppFontLicenseRegistry.register();
  const localeRepository = SharedPreferencesAppLocaleRepository();
  const themeRepository = SharedPreferencesAppThemeRepository();
  const startupSoundRepository = SharedPreferencesStartupSoundRepository();
  const startupSoundService = StartupSoundService();
  runApp(
    HandDrawStudioApp(
      localeRepository: localeRepository,
      themeRepository: themeRepository,
      startupSoundRepository: startupSoundRepository,
      hydratePreferences: true,
    ),
  );
  // Start waiting immediately. The future itself completes only after Flutter
  // rasterizes its first frame, so this cannot expose an unpainted surface.
  unawaited(_completeNativeLaunch());

  var userInteracted = false;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      final enabled = await startupSoundRepository.loadEnabled();
      if (enabled && !userInteracted) await startupSoundService.play();
    }());
  });
  void stopOnFirstInteraction(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    userInteracted = true;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      stopOnFirstInteraction,
    );
    unawaited(startupSoundService.stop());
  }

  GestureBinding.instance.pointerRouter.addGlobalRoute(stopOnFirstInteraction);
}

Future<void> _completeNativeLaunch() async {
  // A built widget tree is not enough: wait until Flutter has actually put a
  // frame on the native surface before removing the launch view. This prevents
  // both a permanent splash and the black transition that a timer creates.
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  await NativeLaunchService.notifyFirstFrameRendered();
}
