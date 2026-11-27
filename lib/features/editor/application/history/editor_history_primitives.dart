import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';

final class HistoryEntryId {
  const HistoryEntryId(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is HistoryEntryId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class HistoryMergeKey {
  HistoryMergeKey(String value) : value = value.trim() {
    if (this.value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Merge key cannot be empty.');
    }
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is HistoryMergeKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Stable application codes. Presentation translates these codes later.
enum HistoryOperationCode {
  addStroke,
  deleteStroke,
  duplicateStroke,
  changeStroke,
  changePause,
  splitPath,
  joinPath,
  changePath,
  changeMask,
  changeTiming,
  changeAudioCue,
  reorderSections,
  changeScene,
  deleteSection,
  changeAssets,
  importArtwork,
  changeCanvas,
  changeHand,
  changeExport,
  changeSettings,
  batchEdit,
}

enum EditorHistoryFailureCode {
  transactionAlreadyActive,
  noActiveTransaction,
  transactionRejected,
  staleEditorState,
  emptyTransaction,
  validationFailed,
  nothingToUndo,
  nothingToRedo,
  staleSaveSnapshot,
  assetRetentionFailed,
}

final class EditorHistoryFailure {
  const EditorHistoryFailure(this.code, this.message);

  final EditorHistoryFailureCode code;
  final String message;
}

final class EditorHistoryLimits {
  const EditorHistoryLimits({
    this.maxEntries = 256,
    this.maxEstimatedBytes = 64 * 1024 * 1024,
    this.coalescingWindowTicks = 500000,
  }) : assert(maxEntries > 0),
       assert(maxEstimatedBytes > 0),
       assert(coalescingWindowTicks >= 0);

  final int maxEntries;
  final int maxEstimatedBytes;

  /// Clock-unit independent. The injected clock and this value must use the
  /// same monotonic unit; production uses microseconds.
  final int coalescingWindowTicks;
}

abstract interface class MonotonicEditClock {
  int get nowTicks;
}

final class StopwatchEditClock implements MonotonicEditClock {
  StopwatchEditClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  int get nowTicks => _stopwatch.elapsedMicroseconds;
}

/// Runtime lease boundary. Implementations retain staged sources, never bytes
/// inside history entries, until [release] is called for a discarded entry.
abstract interface class HistoryAssetRetention {
  void retain(HistoryEntryId entryId, Set<ProjectAssetId> assetIds);

  void release(HistoryEntryId entryId);
}

final class NoopHistoryAssetRetention implements HistoryAssetRetention {
  const NoopHistoryAssetRetention();

  @override
  void retain(HistoryEntryId entryId, Set<ProjectAssetId> assetIds) {}

  @override
  void release(HistoryEntryId entryId) {}
}

/// Captured before asynchronous save starts. Completion marks this exact state,
/// not whichever state happens to be current when IO finishes.
final class HistorySaveSnapshot {
  const HistorySaveSnapshot({
    required this.stateToken,
    required this.fingerprint,
  });

  final int stateToken;
  final String fingerprint;
}

final class HistoryCheckpoint {
  const HistoryCheckpoint({
    required this.stateToken,
    required this.fingerprint,
  });

  final int stateToken;
  final String fingerprint;
}

final class HistoryTransactionDescriptor {
  HistoryTransactionDescriptor({
    required this.operation,
    Iterable<String> entityIds = const [],
    this.mergeKey,
    this.allowCoalescing = false,
  }) : entityIds = Set.unmodifiable(entityIds);

  final HistoryOperationCode operation;
  final Set<String> entityIds;
  final HistoryMergeKey? mergeKey;
  final bool allowCoalescing;
}

bool historyOperationCanCoalesce(
  HistoryOperationCode operation,
  Set<DocumentScope> scopes,
) {
  if (scopes.contains(DocumentScope.assets) || scopes.length != 1) return false;
  return switch (operation) {
    HistoryOperationCode.changePause ||
    HistoryOperationCode.changePath ||
    HistoryOperationCode.changeTiming ||
    HistoryOperationCode.changeAudioCue ||
    HistoryOperationCode.changeCanvas ||
    HistoryOperationCode.changeHand ||
    HistoryOperationCode.changeExport ||
    HistoryOperationCode.changeSettings => true,
    _ => false,
  };
}
