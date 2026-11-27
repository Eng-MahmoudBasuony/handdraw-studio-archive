import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('simple camera timeline exposes no legacy context menu', () {
    final source = File(
      'lib/features/editor/presentation/widgets/editor_timeline_dock.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('onSecondaryTapDown:')));
  });
}
