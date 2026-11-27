import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';

abstract interface class AppLocaleRepository {
  Future<AppLocalePreference> load();

  Future<void> save(AppLocalePreference preference);
}
