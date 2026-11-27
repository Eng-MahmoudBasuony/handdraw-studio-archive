import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/app/handdraw_studio_app.dart';
import 'package:handdraw_studio/app/localization/application/app_locale_cubit.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_repository.dart';
import 'package:handdraw_studio/app/localization/presentation/editor_status_localizer.dart';
import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_workspace.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations_ar.dart';

void main() {
  group('AppLocalePreference', () {
    test('round-trips supported storage values and safely falls back', () {
      expect(
        AppLocalePreference.fromStorage('en'),
        AppLocalePreference.english,
      );
      expect(AppLocalePreference.fromStorage('ar'), AppLocalePreference.arabic);
      expect(
        AppLocalePreference.fromStorage('future-language'),
        AppLocalePreference.system,
      );
      expect(AppLocalePreference.system.storageValue, isNull);
      expect(AppLocalePreference.english.storageValue, 'en');
      expect(AppLocalePreference.arabic.storageValue, 'ar');
    });
  });

  test('AppLocaleCubit emits and persists a selected language', () async {
    final repository = _FakeLocaleRepository();
    final cubit = AppLocaleCubit(repository);
    addTearDown(cubit.close);

    cubit.select(AppLocalePreference.arabic);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, AppLocalePreference.arabic);
    expect(repository.saved, [AppLocalePreference.arabic]);
  });

  testWidgets('switches the complete app to Arabic and RTL at runtime', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeLocaleRepository();

    await tester.pumpWidget(HandDrawStudioApp(localeRepository: repository));
    expect(find.text('Drawing'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العربية').last);
    await tester.pumpAndSettle();

    final drawing = find.text('الرسم').first;
    expect(drawing, findsOneWidget);
    expect(Directionality.of(tester.element(drawing)), TextDirection.rtl);
    expect(find.text('رسم وكشف يدوي'), findsNothing);
    expect(find.text('تحريك الصورة'), findsOneWidget);
    expect(repository.saved, [AppLocalePreference.arabic]);
  });

  testWidgets('preference hydration never blocks the first editor frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _DelayedLocaleRepository();

    await tester.pumpWidget(
      HandDrawStudioApp(localeRepository: repository, hydratePreferences: true),
    );

    expect(find.text('Drawing'), findsWidgets);
    repository.loaded.complete(AppLocalePreference.arabic);
    await tester.pumpAndSettle();
    expect(find.text('الرسم'), findsWidgets);
  });

  test('a user selection wins over late preference hydration', () async {
    final repository = _DelayedLocaleRepository();
    final cubit = AppLocaleCubit(repository);
    addTearDown(cubit.close);

    final hydration = cubit.hydrate();
    cubit.select(AppLocalePreference.english);
    repository.loaded.complete(AppLocalePreference.arabic);
    await hydration;

    expect(cubit.state, AppLocalePreference.english);
  });

  testWidgets('starts in a previously persisted Arabic preference', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HandDrawStudioApp(
        key: const ValueKey('wide-english-app'),
        localeRepository: _FakeLocaleRepository(),
        initialLocalePreference: AppLocalePreference.arabic,
      ),
    );

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('canvas-preview-toggle')),
          )
          .tooltip,
      'معاينة',
    );
    final drawing = find.text('الرسم').first;
    expect(Directionality.of(tester.element(drawing)), TextDirection.rtl);
  });

  testWidgets(
    'mirrors toolbar direction while keeping the editor workspace stable',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        HandDrawStudioApp(
          key: const ValueKey('wide-arabic-app'),
          localeRepository: _FakeLocaleRepository(),
          initialLocalePreference: AppLocalePreference.english,
        ),
      );
      final englishBrand = tester.getCenter(
        find.byKey(const ValueKey('editor-brand-label')),
      );
      final englishInspector = tester.getRect(
        find.byKey(const ValueKey('editor-inspector-docked')),
      );
      final englishWorkspace = tester.getRect(find.byType(EditorWorkspace));
      expect(englishBrand.dx, lessThan(900));
      expect(englishInspector.left, greaterThan(englishWorkspace.left));

      await tester.pumpWidget(
        HandDrawStudioApp(
          localeRepository: _FakeLocaleRepository(),
          initialLocalePreference: AppLocalePreference.arabic,
        ),
      );
      await tester.pumpAndSettle();
      final arabicBrand = tester.getCenter(
        find.byKey(const ValueKey('editor-brand-label')),
      );
      final arabicInspector = tester.getRect(
        find.byKey(const ValueKey('editor-inspector-docked')),
      );
      final arabicWorkspace = tester.getRect(find.byType(EditorWorkspace));

      expect(arabicBrand.dx, greaterThan(900));
      expect(arabicInspector.left, greaterThan(arabicWorkspace.left));
      expect(arabicInspector.left, closeTo(englishInspector.left, 0.1));
      expect(englishWorkspace.size, arabicWorkspace.size);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps RTL compact and narrow layouts responsive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HandDrawStudioApp(
        localeRepository: _FakeLocaleRepository(),
        initialLocalePreference: AppLocalePreference.arabic,
      ),
    );
    expect(find.byKey(const ValueKey('editor-layout-compact')), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(800, 700);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editor-layout-narrow')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-inspector')));
    await tester.pumpAndSettle();
    final drawer = tester.getRect(
      find.byKey(const ValueKey('editor-inspector-drawer')),
    );
    expect(drawer.right, closeTo(800, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('About and release notes follow Arabic RTL without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      HandDrawStudioApp(
        localeRepository: _FakeLocaleRepository(),
        initialLocalePreference: AppLocalePreference.arabic,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('app-info-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حول HandDraw Studio'));
    await tester.pumpAndSettle();

    final about = find.text('عن التطبيق');
    expect(about, findsOneWidget);
    expect(Directionality.of(tester.element(about)), TextDirection.rtl);
    expect(
      find.text(
        'الإصدار ${AppBuildInfo.version} • البناء ${AppBuildInfo.buildNumber}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'ما الجديد'));
    await tester.pumpAndSettle();
    expect(find.text('تصدير MOV أسرع بالجودة الكاملة'), findsOneWidget);
    expect(find.text('الحالي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('localizes static and parameterized editor statuses', () {
    final arabic = AppLocalizationsAr();

    expect(
      arabic.localizeEditorStatus('Drawing imported. Draw the first stroke.'),
      'تم استيراد الرسم. ارسم المسار الأول.',
    );
    expect(
      arabic.localizeEditorStatus('Importing drawing…'),
      'جارٍ استيراد الرسم…',
    );
    expect(
      arabic.localizeEditorStatus('Could not import drawing: invalid image'),
      'تعذر استيراد الرسم: invalid image',
    );
    expect(arabic.localizeEditorStatus('3 stroke(s) ready'), '3 مسارات جاهزة');
    expect(
      arabic.localizeEditorStatus(
        '2 ordered scene reveal(s) ready with one broad hand path each.',
      ),
      'أصبح كشف مشهدين مرتبًا وجاهزًا، بمسار يد عريض واحد لكل مشهد.',
    );
    expect(
      arabic.localizeEditorStatus(
        'Smart Region Reveal ready with Canny+ detail analysis.',
      ),
      'الإظهار الذكي بالمناطق جاهز باستخدام تحليل التفاصيل Canny+.',
    );
    expect(
      arabic.localizeEditorStatus(
        'Auto Reveal ready with a continuous side-to-side hand sweep.',
      ),
      'الإظهار التلقائي جاهز بحركة يد متصلة من جانب إلى آخر.',
    );
    expect(
      arabic.localizeEditorStatus('Unexpected diagnostic'),
      'Unexpected diagnostic',
    );
  });
}

class _FakeLocaleRepository implements AppLocaleRepository {
  final List<AppLocalePreference> saved = [];

  @override
  Future<AppLocalePreference> load() async => AppLocalePreference.system;

  @override
  Future<void> save(AppLocalePreference preference) async {
    saved.add(preference);
  }
}

class _DelayedLocaleRepository implements AppLocaleRepository {
  final loaded = Completer<AppLocalePreference>();

  @override
  Future<AppLocalePreference> load() => loaded.future;

  @override
  Future<void> save(AppLocalePreference preference) async {}
}
