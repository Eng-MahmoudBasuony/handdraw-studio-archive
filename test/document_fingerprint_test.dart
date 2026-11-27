import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/project_document_parity_fixture.dart';

void main() {
  const calculator = CanonicalDocumentFingerprintCalculator();

  test('dirty checks hash only when history cannot establish a change', () {
    final history = EditorHistory();
    var state = EditorDocumentState(document: projectDocumentParityFixture());
    var calls = 0;
    String fingerprint() {
      calls++;
      return 'saved';
    }

    expect(history.isDirty(fingerprintIfNeeded: fingerprint), isTrue);
    expect(calls, 0);
    history.markSaved(history.captureSaveSnapshot('saved'));
    expect(history.isDirty(fingerprintIfNeeded: fingerprint), isFalse);
    expect(calls, 1);
    state = _commitDocument(
      history,
      state,
      state.document.copyWith(title: 'Edited'),
    );
    expect(history.isDirty(fingerprintIfNeeded: fingerprint), isTrue);
    expect(calls, 1);
    history.undo(state);
    expect(history.isDirty(fingerprintIfNeeded: fingerprint), isFalse);
    expect(calls, 2);
    expect(
      history.isDirty(fingerprintIfNeeded: () => 'external change'),
      isTrue,
    );
  });

  test('same semantic document produces canonical stable fingerprint', () {
    final document = projectDocumentParityFixture();
    final first = calculator.calculate(document);
    final second = calculator.calculate(document);
    expect(identical(first, second), isTrue);
    expect(first.semantic, second.semantic);
    expect(first.persistence, second.persistence);
    expect(first.semantic.isCanonical, isTrue);
    expect(first.persistence.isCanonical, isTrue);
  });

  test('canonical JSON ignores non-semantic map insertion order', () {
    const encoder = CanonicalSemanticJsonEncoder();
    expect(
      encoder.encode({
        'z': 1,
        'a': {'second': 2, 'first': 1},
      }),
      encoder.encode({
        'a': {'first': 1, 'second': 2},
        'z': 1,
      }),
    );
  });

  test('stroke, timing, and asset hash changes alter fingerprint', () {
    final source = projectDocumentParityFixture();
    final baseline = calculator.calculate(source);
    final stroke = source.copyWith(
      strokes: [source.strokes.single.copyWith(hidden: true)],
    );
    final timing = source.copyWith(
      sections: [
        source.sections.single.copyWith(
          timing: source.sections.single.timing.copyWith(
            pauseAfter: TimelineDuration.fromMicroseconds(900000),
          ),
        ),
      ],
    );
    final asset = source.copyWith(
      assets: [
        source.assets.first.copyWith(contentHash: 'sha256:changed'),
        ...source.assets.skip(1),
      ],
    );
    for (final changed in [stroke, timing, asset]) {
      final result = calculator.calculate(changed);
      expect(result.semantic, isNot(baseline.semantic));
      expect(result.persistence, isNot(baseline.persistence));
    }
  });

  test(
    'revision and machine-specific external locator do not affect meaning',
    () {
      final source = projectDocumentParityFixture();
      final external = ProjectAsset(
        id: source.assets.first.id,
        kind: ProjectAssetKind.artwork,
        originalFileName: 'lesson.svg',
        storagePolicy: ProjectAssetStoragePolicy.external,
        contentHash: source.assets.first.contentHash,
        mediaType: 'image/svg+xml',
        artworkSourceType: ArtworkSourceType.svg,
        externalLocator: const ExternalAssetLocator(
          pathHint: '/machine-a/lesson.svg',
          securityBookmark: 'bookmark-a',
        ),
      );
      final first = source.copyWith(
        assets: [external, ...source.assets.skip(1)],
      );
      final moved = first.copyWith(
        assets: [
          external.copyWith(
            externalLocator: const ExternalAssetLocator(
              pathHint: '/machine-b/lesson.svg',
              securityBookmark: 'bookmark-b',
            ),
          ),
          ...source.assets.skip(1),
        ],
      );
      final original = calculator.calculate(first);
      final relinked = calculator.calculate(moved);
      expect(original.semantic, relinked.semantic);
      expect(original.persistence, isNot(relinked.persistence));
      final revisionOne = EditorDocumentState(document: first).replace(first);
      expect(
        calculator.calculate(revisionOne.document).semantic,
        original.semantic,
      );
      expect(
        calculator.calculate(revisionOne.document).persistence,
        original.persistence,
      );
    },
  );

  test('bookmark-only persistence changes do not change semantics', () {
    final source = projectDocumentParityFixture();
    final external = source.assets.first.copyWith(
      storagePolicy: ProjectAssetStoragePolicy.external,
      externalLocator: const ExternalAssetLocator(
        pathHint: '/same/file',
        securityBookmark: 'a',
      ),
    );
    final first = source.copyWith(assets: [external, ...source.assets.skip(1)]);
    final changed = first.copyWith(
      assets: [
        external.copyWith(
          externalLocator: const ExternalAssetLocator(
            pathHint: '/same/file',
            securityBookmark: 'b',
          ),
        ),
        ...source.assets.skip(1),
      ],
    );
    final a = calculator.calculate(first);
    final b = calculator.calculate(changed);
    expect(a.semantic, b.semantic);
    expect(a.persistence, isNot(b.persistence));
  });

  test(
    'dirty fallback after checkpoint trimming uses persistence identity',
    () {
      final source = projectDocumentParityFixture();
      final external = source.assets.first.copyWith(
        storagePolicy: ProjectAssetStoragePolicy.external,
        externalLocator: const ExternalAssetLocator(
          pathHint: '/old/file',
          securityBookmark: 'old',
        ),
      );
      var state = EditorDocumentState(
        document: source.copyWith(assets: [external, ...source.assets.skip(1)]),
      );
      final saved = calculator.calculate(state.document).persistence.value;
      final history = EditorHistory(
        limits: const EditorHistoryLimits(
          maxEntries: 1,
          maxEstimatedBytes: 1024 * 1024,
        ),
      );
      history.markSaved(history.captureSaveSnapshot(saved));

      state = _commitDocument(
        history,
        state,
        state.document.copyWith(
          assets: [
            external.copyWith(
              externalLocator: const ExternalAssetLocator(
                pathHint: '/new/file',
                securityBookmark: 'new',
              ),
            ),
            ...source.assets.skip(1),
          ],
        ),
      );
      state = _commitDocument(
        history,
        state,
        state.document.copyWith(title: 'forces checkpoint trim'),
      );
      state = history.undo(state).state;
      final current = calculator.calculate(state.document);
      expect(
        current.semantic,
        calculator
            .calculate(
              source.copyWith(assets: [external, ...source.assets.skip(1)]),
            )
            .semantic,
      );
      expect(
        history.isDirty(currentFingerprint: current.persistence.value),
        isTrue,
      );
    },
  );
}

EditorDocumentState _commitDocument(
  EditorHistory history,
  EditorDocumentState state,
  ProjectDocument next,
) {
  history.begin(
    state,
    HistoryTransactionDescriptor(operation: HistoryOperationCode.batchEdit),
  );
  history.addFrom(
    expectedBase: state.document,
    operation: DocumentOperationResult.success(
      document: next,
      affectedScopes: const {DocumentScope.settings, DocumentScope.assets},
      summary: DocumentChangeSummary(action: 'fingerprint-test'),
    ),
  );
  return history.commit(state).state;
}
