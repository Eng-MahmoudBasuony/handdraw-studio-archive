import 'package:flutter/widgets.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations_en.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}
