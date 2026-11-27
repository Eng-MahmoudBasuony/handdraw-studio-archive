import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/app/branding/app_brand_assets.dart';
import 'package:handdraw_studio/app/branding/app_brand_logo.dart';
import 'package:handdraw_studio/app/handdraw_studio_app.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_repository.dart';
import 'package:handdraw_studio/app/theme/application/app_theme_cubit.dart';
import 'package:handdraw_studio/app/theme/app_typography.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_repository.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';

void main() {
  group('AppThemePreference', () {
    test('round-trips supported storage values and safely falls back', () {
      expect(AppThemePreference.fromStorage('light'), AppThemePreference.light);
      expect(AppThemePreference.fromStorage('dark'), AppThemePreference.dark);
      expect(
        AppThemePreference.fromStorage('future-theme'),
        AppThemePreference.system,
      );
      expect(AppThemePreference.system.storageValue, isNull);
      expect(AppThemePreference.light.storageValue, 'light');
      expect(AppThemePreference.dark.storageValue, 'dark');
    });
  });

  test('AppThemeCubit emits and persists the selected appearance', () async {
    final repository = _FakeThemeRepository();
    final cubit = AppThemeCubit(repository);
    addTearDown(cubit.close);

    cubit.select(AppThemePreference.light);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, AppThemePreference.light);
    expect(repository.saved, [AppThemePreference.light]);
  });

  testWidgets('starts with persisted light theme and switches to dark', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeThemeRepository();

    await tester.pumpWidget(
      HandDrawStudioApp(
        localeRepository: _FakeLocaleRepository(),
        initialLocalePreference: AppLocalePreference.english,
        themeRepository: repository,
        initialThemePreference: AppThemePreference.light,
      ),
    );

    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
    expect(
      tester.element(find.byType(Scaffold)).studioColors.appBackground,
      AppPalette.light.appBackground,
    );
    expect(
      _displayedLogo(tester).image,
      isA<AssetImage>().having(
        (image) => image.assetName,
        'assetName',
        AppBrandAssets.logoForLightTheme,
      ),
    );
    expect(
      tester
          .widget<AppBrandLogo>(find.byKey(const ValueKey('editor-brand-logo')))
          .size,
      58,
    );
    expect(
      Theme.of(
        tester.element(find.byType(Scaffold)),
      ).textTheme.bodyMedium?.fontFamily,
      AppTypography.fontFamily,
    );

    await tester.tap(find.byKey(const ValueKey('theme-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    expect(
      _displayedLogo(tester).image,
      isA<AssetImage>().having(
        (image) => image.assetName,
        'assetName',
        AppBrandAssets.logoForDarkTheme,
      ),
    );
    expect(repository.saved, [AppThemePreference.dark]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic light appearance remains responsive', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HandDrawStudioApp(
        localeRepository: _FakeLocaleRepository(),
        initialLocalePreference: AppLocalePreference.arabic,
        themeRepository: _FakeThemeRepository(),
        initialThemePreference: AppThemePreference.light,
      ),
    );

    expect(find.byKey(const ValueKey('editor-layout-narrow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Image _displayedLogo(WidgetTester tester) => tester.widget<Image>(
  find.descendant(
    of: find.byKey(const ValueKey('editor-brand-logo')),
    matching: find.byType(Image),
  ),
);

class _FakeThemeRepository implements AppThemeRepository {
  final List<AppThemePreference> saved = [];

  @override
  Future<AppThemePreference> load() async => AppThemePreference.system;

  @override
  Future<void> save(AppThemePreference preference) async {
    saved.add(preference);
  }
}

class _FakeLocaleRepository implements AppLocaleRepository {
  @override
  Future<AppLocalePreference> load() async => AppLocalePreference.system;

  @override
  Future<void> save(AppLocalePreference preference) async {}
}
