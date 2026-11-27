import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/presentation/layout/editor_layout_spec.dart';

void main() {
  EditorLayoutSpec layout(double width, [double height = 900]) =>
      EditorLayoutSpec.fromConstraints(
        BoxConstraints.tightFor(width: width, height: height),
      );

  test('selects stable editor breakpoints', () {
    expect(layout(1800).tier, EditorLayoutTier.wide);
    expect(layout(1366).tier, EditorLayoutTier.compact);
    expect(layout(800).tier, EditorLayoutTier.narrow);
  });

  test('only docks the inspector when the canvas has enough room', () {
    expect(layout(1800).docksInspector, isTrue);
    expect(layout(1200).docksInspector, isTrue);
    expect(layout(900).docksInspector, isFalse);
  });

  test('uses compact menus and spacing at minimum width', () {
    final minimum = layout(520, 640);
    expect(minimum.usesFileMenu, isTrue);
    expect(minimum.showsBrandLabel, isFalse);
    expect(minimum.workspacePadding, const EdgeInsets.all(8));
    expect(minimum.inspectorDrawerWidth, lessThanOrEqualTo(520));
  });
}
