import 'package:flutter/widgets.dart';

enum AppLocalePreference {
  system,
  english,
  arabic;

  Locale? get locale => switch (this) {
    AppLocalePreference.system => null,
    AppLocalePreference.english => const Locale('en'),
    AppLocalePreference.arabic => const Locale('ar'),
  };

  static AppLocalePreference fromStorage(String? value) => switch (value) {
    'en' => AppLocalePreference.english,
    'ar' => AppLocalePreference.arabic,
    _ => AppLocalePreference.system,
  };

  String? get storageValue => locale?.languageCode;
}
