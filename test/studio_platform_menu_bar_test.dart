import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/app_menu/presentation/studio_platform_menu_bar.dart';

void main() {
  test('application menu contains only studio-owned actions', () {
    final items = buildStudioApplicationMenuItems(
      aboutLabel: 'About HandDraw Studio',
      whatsNewLabel: 'What’s New',
      licensesLabel: 'Licenses',
      onAbout: () {},
      onWhatsNew: () {},
      onLicenses: () {},
    );

    expect(items.map((item) => item.label), [
      'About HandDraw Studio',
      'What’s New',
      'Licenses',
    ]);
    expect(items, everyElement(isNot(isA<PlatformProvidedMenuItem>())));
    expect(items, everyElement(isNot(isA<PlatformMenuItemGroup>())));
  });
}
