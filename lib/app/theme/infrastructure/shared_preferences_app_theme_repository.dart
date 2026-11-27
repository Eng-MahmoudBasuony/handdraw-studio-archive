import 'package:shared_preferences/shared_preferences.dart';

import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_repository.dart';

class SharedPreferencesAppThemeRepository implements AppThemeRepository {
  const SharedPreferencesAppThemeRepository();

  static const _themeKey = 'app.theme';

  @override
  Future<AppThemePreference> load() async {
    try {
      final value = await SharedPreferencesAsync().getString(_themeKey);
      return AppThemePreference.fromStorage(value);
    } catch (_) {
      return AppThemePreference.system;
    }
  }

  @override
  Future<void> save(AppThemePreference preference) async {
    try {
      final preferences = SharedPreferencesAsync();
      final value = preference.storageValue;
      if (value == null) {
        await preferences.remove(_themeKey);
        return;
      }
      await preferences.setString(_themeKey, value);
    } catch (_) {
      // Appearance persistence is best-effort and cannot block the editor.
    }
  }
}
