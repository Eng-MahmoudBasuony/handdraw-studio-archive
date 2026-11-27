import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Auto Director UI keeps product boundaries explicit', () {
    final document = File(
      'lib/features/project/domain/models/project_document.dart',
    ).readAsStringSync();
    final state = File(
      'lib/features/auto_director/application/auto_director_ui_state.dart',
    ).readAsStringSync();
    final cubit = File(
      'lib/features/auto_director/application/auto_director_ui_cubit.dart',
    ).readAsStringSync();
    final ui = File(
      'lib/features/auto_director/presentation/auto_director_dialog.dart',
    ).readAsStringSync();
    final timeline = File(
      'lib/features/editor/presentation/widgets/editor_timeline_dock.dart',
    ).readAsStringSync();
    expect(document, isNot(contains('PendingAutoDirectorPlan')));
    expect(document, isNot(contains('AutoDirectorUiState')));
    expect(state, contains('final AutoDirectorPlan? plan'));
    expect(cubit, isNot(contains('CameraShotId(')));
    expect(ui, isNot(contains('readabilityScore:')));
    expect(ui, isNot(contains('CameraShotId(')));
    expect(timeline, contains('textDirection: TextDirection.ltr'));
    expect(ui, isNot(contains('SmartAutoDirector(')));
  });
}
