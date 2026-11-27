import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source code keeps the feature-first project structure', () {
    const requiredDirectories = <String>[
      'lib/app',
      'lib/app/theme/palette',
      'lib/core/storage',
      'lib/features/app_info',
      'lib/features/app_menu',
      'lib/features/auto_path',
      'lib/features/drawing_engine',
      'lib/features/editor',
      'lib/features/export',
      'lib/features/hand_library',
      'lib/features/project',
      'lib/features/voice_guide',
      'lib/features/writing_sound',
    ];
    const legacyDirectories = <String>[
      'lib/audio',
      'lib/drawing',
      'lib/export',
      'lib/models',
      'lib/screens',
      'lib/services',
      'lib/widgets',
    ];

    for (final path in requiredDirectories) {
      expect(Directory(path).existsSync(), isTrue, reason: '$path is required');
    }
    for (final path in legacyDirectories) {
      expect(
        Directory(path).existsSync(),
        isFalse,
        reason: '$path must not be recreated',
      );
    }
  });

  test('application theme has one raw UI palette source', () {
    expect(File('lib/app/theme/palette/app_palette.dart').existsSync(), isTrue);
    expect(
      Directory('lib/app/theme/palette')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .length,
      1,
    );
  });

  test('bundled typography includes its open font license', () {
    expect(
      File(
        'assets/fonts/playpen_sans_arabic/PlaypenSansArabic.ttf',
      ).existsSync(),
      isTrue,
    );
    final license = File(
      'assets/fonts/playpen_sans_arabic/OFL.txt',
    ).readAsStringSync();
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
  });

  test('product SVG icons stay monochrome and theme-driven', () {
    const requiredIcons = [
      'new-project',
      'open-project',
      'save-project',
      'clear-canvas',
      'drawing',
      'hand',
      'pen-tip',
      'auto-path',
      'auto-reveal',
      'select',
      'draw-path',
      'reveal-text',
      'voice',
      'preview',
      'export',
      'inspector',
      'about',
      'whats-new',
      'copy',
      'licenses',
      'undo',
      'redo',
    ];

    for (final name in requiredIcons) {
      final file = File('assets/icons/$name.svg');
      expect(file.existsSync(), isTrue, reason: '$name.svg is required');
      final source = file.readAsStringSync();
      expect(source, contains('currentColor'));
      expect(
        RegExp(r'#[0-9a-fA-F]{3,8}').hasMatch(source),
        isFalse,
        reason: '$name.svg must inherit its color from the active theme',
      );
    }
  });

  test(
    'macOS branding includes complete launcher and adaptive splash assets',
    () {
      const iconDirectory = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
        expect(
          File('$iconDirectory/app_icon_$size.png').existsSync(),
          isTrue,
          reason: 'macOS launcher icon size $size is required',
        );
      }

      const splashDirectory =
          'macos/Runner/Assets.xcassets/BrandSplash.imageset';
      for (final variant in [
        'brand-splash-light.png',
        'brand-splash-light@2x.png',
        'brand-splash-dark.png',
        'brand-splash-dark@2x.png',
      ]) {
        expect(
          File('$splashDirectory/$variant').existsSync(),
          isTrue,
          reason: 'Native splash asset $variant is required',
        );
      }
      final manifest = File(
        '$splashDirectory/Contents.json',
      ).readAsStringSync();
      expect(manifest, contains('"appearance" : "luminosity"'));
      expect(manifest, contains('"value" : "dark"'));
    },
  );

  test('macOS splash never takes ownership of the Flutter rendering layer', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();

    expect(source, contains('self.backgroundColor = launchBackground'));
    expect(
      source,
      isNot(contains('flutterViewController.view.wantsLayer')),
      reason: 'Flutter must retain its Retina backing-scale management',
    );
  });

  test('lib uses stable package imports across feature boundaries', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(
        RegExp(r'''^import ['\"]\.\.?/''', multiLine: true).hasMatch(source),
        isFalse,
        reason: '${file.path} should use a package import',
      );
    }
  });
}
