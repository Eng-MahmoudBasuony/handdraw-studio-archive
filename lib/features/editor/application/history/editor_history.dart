import 'package:handdraw_studio/features/editor/application/editor_document_committer.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/application/history/scoped_document_change.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';

final class EditorHistoryEntry {
  EditorHistoryEntry({
    required this.id,
    required this.operation,
    required Iterable<DocumentScope> affectedScopes,
    required Iterable<String> entityIds,
    required List<ScopedDocumentChange> changes,
    required this.estimatedBytes,
    required this.sequence,
    required this.createdAtTicks,
    required this.beforeStateToken,
    required this.afterStateToken,
    this.mergeKey,
  }) : affectedScopes = Set.unmodifiable(affectedScopes),
       entityIds = Set.unmodifiable(entityIds),
       changes = List.unmodifiable(changes);

  final HistoryEntryId id;
  final HistoryOperationCode operation;
  final Set<DocumentScope> affectedScopes;
  final Set<String> entityIds;
  final List<ScopedDocumentChange> changes;
  final HistoryMergeKey? mergeKey;
  final int estimatedBytes;
  final int sequence;
  final int createdAtTicks;
  final int beforeStateToken;
  final int afterStateToken;

  Set<ProjectAssetId> get retainedAssetIds => {
    for (final change in changes) ...change.retainedAssetIds,
  };

  EditorHistoryEntry coalesceWith(EditorHistoryEntry newer) {
    final newerByKind = {
      for (final change in newer.changes) change.kind: change,
    };
    final merged = <ScopedDocumentChange>[
      for (final change in changes)
        change.coalesceWith(newerByKind[change.kind]!),
    ];
    return EditorHistoryEntry(
      id: id,
      operation: operation,
      affectedScopes: affectedScopes,
      entityIds: entityIds,
      changes: merged,
      mergeKey: mergeKey,
      estimatedBytes: merged.fold(
        0,
        (sum, change) => sum + change.estimatedBytes,
      ),
      sequence: sequence,
      createdAtTicks: newer.createdAtTicks,
      beforeStateToken: beforeStateToken,
      afterStateToken: newer.afterStateToken,
    );
  }
}

final class EditorHistoryResult {
  const EditorHistoryResult._({required this.state, this.failure});

  const EditorHistoryResult.success(EditorDocumentState state)
    : this._(state: state);

  const EditorHistoryResult.failure(
    EditorDocumentState state,
    EditorHistoryFailure failure,
  ) : this._(state: state, failure: failure);

  final EditorDocumentState state;
  final EditorHistoryFailure? failure;

  bool get isSuccess => failure == null;
}

final class _ActiveHistoryTransaction {
  _ActiveHistoryTransaction({required this.base, required this.descriptor})
    : candidate = base.document;

  final EditorDocumentState base;
  final HistoryTransactionDescriptor descriptor;
  ProjectDocument candidate;
  final Set<DocumentScope> scopes = {};
  bool rejected = false;
  String? rejectionMessage;
}

/// Runtime-only history foundation, independent from presentation, persistence,
/// and the current legacy runtime owner.
final class EditorHistory {
  EditorHistory({
    this.limits = const EditorHistoryLimits(),
    MonotonicEditClock? clock,
    this.committer = const EditorDocumentCommitter(),
    this.validator = const ProjectDocumentValidator(),
    HistoryAssetRetention? assetRetention,
  }) : clock = clock ?? StopwatchEditClock(),
       assetRetention = assetRetention ?? const NoopHistoryAssetRetention();

  final EditorHistoryLimits limits;
  final MonotonicEditClock clock;
  final EditorDocumentCommitter committer;
  final ProjectDocumentValidator validator;
  final HistoryAssetRetention assetRetention;

  final List<EditorHistoryEntry> _undo = [];
  final List<EditorHistoryEntry> _redo = [];
  _ActiveHistoryTransaction? _active;
  int _nextEntryId = 1;
  int _nextSequence = 1;
  int _nextStateToken = 1;
  int _currentStateToken = 0;
  HistoryCheckpoint? _checkpoint;
  EditorDocumentState? _expectedState;

  List<EditorHistoryEntry> get undoEntries => List.unmodifiable(_undo);
  List<EditorHistoryEntry> get redoEntries => List.unmodifiable(_redo);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasActiveTransaction => _active != null;
  int get currentStateToken => _currentStateToken;
  HistoryCheckpoint? get checkpoint => _checkpoint;
  int get estimatedBytes =>
      [..._undo, ..._redo].fold(0, (sum, entry) => sum + entry.estimatedBytes);

  EditorHistoryFailure? begin(
    EditorDocumentState current,
    HistoryTransactionDescriptor descriptor,
  ) {
    if (_active != null) {
      return const EditorHistoryFailure(
        EditorHistoryFailureCode.transactionAlreadyActive,
        'A history transaction is already active.',
      );
    }
    if (!_acceptCurrent(current)) {
      return const EditorHistoryFailure(
        EditorHistoryFailureCode.staleEditorState,
        'The editor state does not match the history cursor.',
      );
    }
    _active = _ActiveHistoryTransaction(base: current, descriptor: descriptor);
    return null;
  }

  /// Adds an operation that was applied to [expectedBase]. This explicit form
  /// prevents accidentally composing results from a stale document.
  EditorHistoryFailure? addFrom({
    required ProjectDocument expectedBase,
    required DocumentOperationResult operation,
  }) {
    final active = _active;
    if (active == null) {
      return const EditorHistoryFailure(
        EditorHistoryFailureCode.noActiveTransaction,
        'No history transaction is active.',
      );
    }
    if (!identical(expectedBase, active.candidate)) {
      active.rejected = true;
      active.rejectionMessage = 'An operation used a stale transaction base.';
      return EditorHistoryFailure(
        EditorHistoryFailureCode.transactionRejected,
        active.rejectionMessage!,
      );
    }
    if (!operation.isSuccess) {
      active.rejected = true;
      active.rejectionMessage = operation.failure?.message;
      return EditorHistoryFailure(
        EditorHistoryFailureCode.transactionRejected,
        operation.failure?.message ?? 'The document operation failed.',
      );
    }
    active.candidate = operation.document;
    active.scopes.addAll(operation.affectedScopes);
    return null;
  }

  EditorHistoryResult commit(EditorDocumentState current) {
    final active = _active;
    if (active == null) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.noActiveTransaction,
          'No history transaction is active.',
        ),
      );
    }
    _active = null;
    if (active.rejected) {
      return EditorHistoryResult.failure(
        current,
        EditorHistoryFailure(
          EditorHistoryFailureCode.transactionRejected,
          active.rejectionMessage ?? 'The transaction was rejected.',
        ),
      );
    }
    if (!identical(current, active.base)) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.transactionRejected,
          'The editor state changed during the transaction.',
        ),
      );
    }
    if (active.candidate.id != active.base.document.id) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.transactionRejected,
          'A project identity change starts a new history session.',
        ),
      );
    }
    if (active.scopes.isEmpty ||
        identical(active.candidate, active.base.document)) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.emptyTransaction,
          'The transaction contains no document change.',
        ),
      );
    }
    final validation = validator.validate(active.candidate);
    if (!validation.isValid) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.validationFailed,
          'The transaction candidate is invalid.',
        ),
      );
    }

    late final EditorDocumentState next;
    try {
      next = committer.commit(current, active.candidate);
    } catch (_) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.validationFailed,
          'The transaction candidate could not be committed.',
        ),
      );
    }
    final afterToken = _nextStateToken++;
    final changes = captureScopedChanges(
      before: active.base.document,
      after: active.candidate,
      scopes: active.scopes,
    );
    final entry = EditorHistoryEntry(
      id: HistoryEntryId(_nextEntryId++),
      operation: active.descriptor.operation,
      affectedScopes: active.scopes,
      entityIds: active.descriptor.entityIds,
      changes: changes,
      mergeKey: active.descriptor.allowCoalescing
          ? active.descriptor.mergeKey
          : null,
      estimatedBytes: changes.fold(
        0,
        (sum, change) => sum + change.estimatedBytes,
      ),
      sequence: _nextSequence++,
      createdAtTicks: clock.nowTicks,
      beforeStateToken: _currentStateToken,
      afterStateToken: afterToken,
    );
    final prepared = _coalescedEntry(entry);
    try {
      assetRetention.retain(prepared.id, prepared.retainedAssetIds);
    } catch (_) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.assetRetentionFailed,
          'Assets required by the history entry could not be retained.',
        ),
      );
    }
    _currentStateToken = afterToken;
    _clearRedo();
    _pushPrepared(entry, prepared);
    _trim();
    _expectedState = next;
    return EditorHistoryResult.success(next);
  }

  EditorHistoryFailure? cancel() {
    if (_active == null) {
      return const EditorHistoryFailure(
        EditorHistoryFailureCode.noActiveTransaction,
        'No history transaction is active.',
      );
    }
    _active = null;
    return null;
  }

  EditorHistoryResult undo(EditorDocumentState current) {
    if (_active != null) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.transactionAlreadyActive,
          'Finish or cancel the active transaction before undo.',
        ),
      );
    }
    if (!_acceptCurrent(current)) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.staleEditorState,
          'The editor state does not match the history cursor.',
        ),
      );
    }
    if (_undo.isEmpty) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.nothingToUndo,
          'There is no edit to undo.',
        ),
      );
    }
    final entry = _undo.last;
    final candidate = _restore(
      current.document,
      entry.changes,
      useAfter: false,
    );
    if (!validator.validate(candidate).isValid) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.validationFailed,
          'Undo restoration is invalid.',
        ),
      );
    }
    final next = committer.commit(current, candidate);
    _undo.removeLast();
    _redo.add(entry);
    _currentStateToken = entry.beforeStateToken;
    _expectedState = next;
    return EditorHistoryResult.success(next);
  }

  EditorHistoryResult redo(EditorDocumentState current) {
    if (_active != null) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.transactionAlreadyActive,
          'Finish or cancel the active transaction before redo.',
        ),
      );
    }
    if (!_acceptCurrent(current)) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.staleEditorState,
          'The editor state does not match the history cursor.',
        ),
      );
    }
    if (_redo.isEmpty) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.nothingToRedo,
          'There is no edit to redo.',
        ),
      );
    }
    final entry = _redo.last;
    final candidate = _restore(current.document, entry.changes, useAfter: true);
    if (!validator.validate(candidate).isValid) {
      return EditorHistoryResult.failure(
        current,
        const EditorHistoryFailure(
          EditorHistoryFailureCode.validationFailed,
          'Redo restoration is invalid.',
        ),
      );
    }
    final next = committer.commit(current, candidate);
    _redo.removeLast();
    _undo.add(entry);
    _currentStateToken = entry.afterStateToken;
    _expectedState = next;
    return EditorHistoryResult.success(next);
  }

  HistorySaveSnapshot captureSaveSnapshot(String fingerprint) =>
      HistorySaveSnapshot(
        stateToken: _currentStateToken,
        fingerprint: fingerprint,
      );

  void markSaved(HistorySaveSnapshot snapshot) {
    _checkpoint = HistoryCheckpoint(
      stateToken: snapshot.stateToken,
      fingerprint: snapshot.fingerprint,
    );
  }

  bool isDirty({
    String? currentFingerprint,
    String Function()? fingerprintIfNeeded,
  }) {
    final checkpoint = _checkpoint;
    if (checkpoint == null) return true;
    if (checkpoint.stateToken == _currentStateToken) {
      final fingerprint = currentFingerprint ?? fingerprintIfNeeded?.call();
      return fingerprint != null && fingerprint != checkpoint.fingerprint;
    }
    if (_retainedStateTokens.contains(checkpoint.stateToken)) return true;
    final fingerprint = currentFingerprint ?? fingerprintIfNeeded?.call();
    return fingerprint == null || fingerprint != checkpoint.fingerprint;
  }

  void clear() {
    for (final entry in [..._undo, ..._redo]) {
      assetRetention.release(entry.id);
    }
    _undo.clear();
    _redo.clear();
    _active = null;
    _checkpoint = null;
    _expectedState = null;
    _currentStateToken = 0;
    _nextStateToken = 1;
  }

  Set<int> get _retainedStateTokens => {
    _currentStateToken,
    for (final entry in _undo) entry.beforeStateToken,
    for (final entry in _undo) entry.afterStateToken,
    for (final entry in _redo) entry.beforeStateToken,
    for (final entry in _redo) entry.afterStateToken,
  };

  EditorHistoryEntry _coalescedEntry(EditorHistoryEntry entry) {
    if (_undo.isNotEmpty && _canCoalesce(_undo.last, entry)) {
      return _undo.last.coalesceWith(entry);
    }
    return entry;
  }

  void _pushPrepared(EditorHistoryEntry original, EditorHistoryEntry prepared) {
    if (!identical(original, prepared)) {
      _undo.removeLast();
    }
    _undo.add(prepared);
  }

  bool _canCoalesce(EditorHistoryEntry older, EditorHistoryEntry newer) =>
      older.mergeKey != null &&
      older.mergeKey == newer.mergeKey &&
      older.operation == newer.operation &&
      _sameStrings(older.entityIds, newer.entityIds) &&
      _sameScopes(older.affectedScopes, newer.affectedScopes) &&
      older.changes.length == newer.changes.length &&
      newer.createdAtTicks - older.createdAtTicks <=
          limits.coalescingWindowTicks &&
      historyOperationCanCoalesce(newer.operation, newer.affectedScopes);

  void _clearRedo() {
    for (final entry in _redo) {
      assetRetention.release(entry.id);
    }
    _redo.clear();
  }

  void _trim() {
    while (_undo.length + _redo.length > limits.maxEntries ||
        estimatedBytes > limits.maxEstimatedBytes) {
      if (_undo.isEmpty && _redo.isEmpty) return;
      final oldestUndo = _undo.isEmpty ? null : _undo.first;
      final oldestRedo = _redo.isEmpty ? null : _redo.first;
      final removeUndo =
          oldestRedo == null ||
          oldestUndo != null && oldestUndo.sequence <= oldestRedo.sequence;
      final removed = removeUndo ? _undo.removeAt(0) : _redo.removeAt(0);
      assetRetention.release(removed.id);
    }
  }

  bool _acceptCurrent(EditorDocumentState current) {
    final expected = _expectedState;
    if (expected != null) return identical(expected, current);
    if (_undo.isNotEmpty || _redo.isNotEmpty || _active != null) return false;
    _expectedState = current;
    return true;
  }
}

ProjectDocument _restore(
  ProjectDocument current,
  List<ScopedDocumentChange> changes, {
  required bool useAfter,
}) {
  var candidate = current;
  for (final change in changes) {
    candidate = useAfter
        ? change.applyAfter(candidate)
        : change.applyBefore(candidate);
  }
  return candidate;
}

bool _sameScopes(Set<DocumentScope> left, Set<DocumentScope> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
