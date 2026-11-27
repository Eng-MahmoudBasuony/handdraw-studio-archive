import 'package:shared_preferences/shared_preferences.dart';

import 'package:handdraw_studio/app/startup_sound/domain/startup_sound_repository.dart';

class SharedPreferencesStartupSoundRepository
    implements StartupSoundRepository {
  const SharedPreferencesStartupSoundRepository();

  static const _enabledKey = 'app.startupSound.enabled';

  @override
  Future<bool> loadEnabled() async {
    try {
      return await SharedPreferencesAsync().getBool(_enabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> saveEnabled(bool enabled) async {
    try {
      await SharedPreferencesAsync().setBool(_enabledKey, enabled);
    } catch (_) {
      // Startup audio is optional and persistence must never block launch.
    }
  }
}
