import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';

abstract interface class AppThemeRepository {
  Future<AppThemePreference> load();

  Future<void> save(AppThemePreference preference);
}
