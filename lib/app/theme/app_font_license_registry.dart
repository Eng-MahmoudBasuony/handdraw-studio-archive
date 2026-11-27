import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AppFontLicenseRegistry {
  static const _playpenLicenseAsset =
      'assets/fonts/playpen_sans_arabic/OFL.txt';

  static void register() {
    LicenseRegistry.addLicense(() async* {
      final license = await rootBundle.loadString(_playpenLicenseAsset);
      yield LicenseEntryWithLineBreaks(const ['Playpen Sans Arabic'], license);
    });
  }
}
