import 'package:shared_preferences/shared_preferences.dart';

import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_repository.dart';

class SharedPreferencesAppLocaleRepository implements AppLocaleRepository {
  const SharedPreferencesAppLocaleRepository();

  static const _localeKey = 'app.locale';

  @override
  Future<AppLocalePreference> load() async {
    try {
      final value = await SharedPreferencesAsync().getString(_localeKey);
      return AppLocalePreference.fromStorage(value);
    } catch (_) {
      return AppLocalePreference.system;
    }
  }

  @override
  Future<void> save(AppLocalePreference preference) async {
    try {
      final preferences = SharedPreferencesAsync();
      final value = preference.storageValue;
      if (value == null) {
        await preferences.remove(_localeKey);
        return;
      }
      await preferences.setString(_localeKey, value);
    } catch (_) {
      // Locale persistence is best-effort and must never block the editor.
    }
  }
}
