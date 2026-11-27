import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_operation_policy.dart';

void main() {
  test(
    'transaction coordinator has no runtime, UI, legacy, Koni, or IO dependency',
    () {
      final files = Directory(
        'lib/features/editor/application/transactions',
      ).listSync(recursive: true).whereType<File>();
      for (final file in files) {
        final source = file.readAsStringSync();
        for (final forbidden in [
          'HandDrawProject',
          'EditorCubit',
          'dart:ui',
          'ui.Image',
          'dart:io',
          'Koni',
          'ProjectContainerStore',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '${file.path}: $forbidden',
          );
        }
      }
    },
  );

  test('runtime cutover routes EditorCubit writes through transactions', () {
    final cubit = File(
      'lib/features/editor/application/editor_cubit.dart',
    ).readAsStringSync();
    expect(cubit, contains('DocumentTransactionCoordinator'));
    expect(cubit, contains('DocumentOperationKind'));
  });

  test(
    'the policy registry is exhaustive for exactly 61 operation families',
    () {
      const registry = DocumentOperationPolicyRegistry();
      expect(DocumentOperationKind.values, hasLength(61));
      for (final kind in DocumentOperationKind.values) {
        expect(
          registry.policyFor(kind).labelCode,
          isNotEmpty,
          reason: kind.name,
        );
        expect(
          registry.policyFor(kind).allowedScopes,
          isNotEmpty,
          reason: kind.name,
        );
      }
    },
  );

  test('legacy copyWith is confined to the read-model boundary', () {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('drawing_project.dart') ||
          file.path.endsWith('legacy_render_project_transform.dart')) {
        continue;
      }
      expect(
        file.readAsStringSync(),
        isNot(matches(RegExp(r'\bproject\.copyWith\s*\('))),
        reason: file.path,
      );
    }
  });

  test(
    'EditorCubit does not mutate the current document outside operations',
    () {
      final cubit = File(
        'lib/features/editor/application/editor_cubit.dart',
      ).readAsStringSync();
      expect(cubit, isNot(contains('state.document.copyWith(')));
      expect(cubit, isNot(contains('state.documentState.document.copyWith(')));
      expect(cubit, isNot(contains('state.documentState =')));
    },
  );
}
