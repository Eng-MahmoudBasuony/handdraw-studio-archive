import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/localization/application/app_locale_cubit.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_repository.dart';
import 'package:handdraw_studio/app/localization/infrastructure/shared_preferences_app_locale_repository.dart';
import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/app/theme/application/app_theme_cubit.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_repository.dart';
import 'package:handdraw_studio/app/theme/infrastructure/shared_preferences_app_theme_repository.dart';
import 'package:handdraw_studio/app/startup_sound/application/startup_sound_cubit.dart';
import 'package:handdraw_studio/app/startup_sound/domain/startup_sound_repository.dart';
import 'package:handdraw_studio/app/startup_sound/infrastructure/shared_preferences_startup_sound_repository.dart';
import 'package:handdraw_studio/features/app_info/application/release_notes_cubit.dart';
import 'package:handdraw_studio/features/app_info/domain/release_notes_repository.dart';
import 'package:handdraw_studio/features/app_info/infrastructure/json_release_notes_repository.dart';
import 'package:handdraw_studio/features/app_info/infrastructure/release_notes_data_source.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

class HandDrawStudioApp extends StatelessWidget {
  const HandDrawStudioApp({
    super.key,
    this.localeRepository = const SharedPreferencesAppLocaleRepository(),
    this.initialLocalePreference = AppLocalePreference.system,
    this.themeRepository = const SharedPreferencesAppThemeRepository(),
    this.initialThemePreference = AppThemePreference.system,
    this.startupSoundRepository =
        const SharedPreferencesStartupSoundRepository(),
    this.startupSoundInitiallyEnabled = true,
    this.hydratePreferences = false,
    this.releaseNotesRepository = const JsonReleaseNotesRepository(
      AssetReleaseNotesDataSource(),
    ),
  });

  final AppLocaleRepository localeRepository;
  final AppLocalePreference initialLocalePreference;
  final AppThemeRepository themeRepository;
  final AppThemePreference initialThemePreference;
  final StartupSoundRepository startupSoundRepository;
  final bool startupSoundInitiallyEnabled;
  final bool hydratePreferences;
  final ReleaseNotesRepository releaseNotesRepository;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) {
            final cubit = AppLocaleCubit(
              localeRepository,
              initialPreference: initialLocalePreference,
            );
            if (hydratePreferences) cubit.hydrate();
            return cubit;
          },
        ),
        BlocProvider(
          create: (_) => ReleaseNotesCubit(releaseNotesRepository)..load(),
        ),
        BlocProvider(
          create: (_) {
            final cubit = AppThemeCubit(
              themeRepository,
              initialPreference: initialThemePreference,
            );
            if (hydratePreferences) cubit.hydrate();
            return cubit;
          },
        ),
        BlocProvider(
          create: (_) {
            final cubit = StartupSoundCubit(
              startupSoundRepository,
              initiallyEnabled: startupSoundInitiallyEnabled,
            );
            if (hydratePreferences) cubit.hydrate();
            return cubit;
          },
        ),
      ],
      child: BlocBuilder<AppLocaleCubit, AppLocalePreference>(
        builder: (context, localePreference) =>
            BlocBuilder<AppThemeCubit, AppThemePreference>(
              builder: (context, themePreference) => MaterialApp(
                debugShowCheckedModeBanner: false,
                onGenerateTitle: (context) =>
                    AppLocalizations.of(context).appTitle,
                locale: localePreference.locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppThemeFactory.light(),
                darkTheme: AppThemeFactory.dark(),
                themeMode: themePreference.themeMode,
                themeAnimationDuration: const Duration(milliseconds: 220),
                themeAnimationCurve: Curves.easeOutCubic,
                home: const EditorScreen(),
              ),
            ),
      ),
    );
  }
}
