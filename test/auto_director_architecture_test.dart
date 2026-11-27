import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'director domain excludes UI, Cubit, random IDs, and document mutation',
    () {
      final files = Directory('lib/features/auto_director/domain')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains('package:flutter/')), reason: file.path);
        expect(source, isNot(contains("import 'dart:ui'")), reason: file.path);
        expect(source, isNot(contains('Cubit')), reason: file.path);
        expect(source, isNot(contains('IdGenerator')), reason: file.path);
        expect(
          source,
          isNot(contains('IdAllocationContext')),
          reason: file.path,
        );
        expect(
          source,
          isNot(contains('copyWith(cameraTrack:')),
          reason: file.path,
        );
        expect(source, isNot(contains('pauseBefore:')), reason: file.path);
        expect(source, isNot(contains('OCR')), reason: file.path);
      }
    },
  );

  test('apply boundary requires stale validation before allocation', () {
    final source = File(
      'lib/features/auto_director/application/auto_director_application_service.dart',
    ).readAsStringSync();
    expect(
      source.indexOf('currentKey != plan.inputDependencyKey'),
      lessThan(source.indexOf('allocation.cameraTrackId()')),
    );
    expect(source, contains('DocumentScope.camera'));
    expect(source, contains('AutoDirectorApplyFailureCode.stalePlan'));
  });

  test('candidate and attention budgets are centrally bounded', () {
    final models = File(
      'lib/features/auto_director/domain/models/auto_director_models.dart',
    ).readAsStringSync();
    expect(models, contains('maximumCandidatesPerEvent'));
    expect(models, contains('maximumAttentionEvents'));
    expect(models, contains('lookAheadEvents'));
    expect(models, contains('maximumPlanningTime'));
  });

  test('worker request excludes UI and runtime resources', () {
    final source = File(
      'lib/features/auto_director/application/auto_director_worker.dart',
    ).readAsStringSync();
    final request = source.substring(
      source.indexOf('final class AutoDirectorWorkerRequest'),
      source.indexOf('final class AutoDirectorWorkerBootstrap'),
    );
    for (final forbidden in [
      'dart:ui',
      'package:flutter/',
      'Cubit',
      'Bloc',
      'BuildContext',
      'Widget',
      'ui.Image',
      'Function(',
      'EditorState',
      'runtime',
    ]) {
      expect(request, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('void autoDirectorWorkerMain('));
    expect(source, isNot(contains('Isolate.run')));
  });
}
