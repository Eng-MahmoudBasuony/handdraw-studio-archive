import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

final class StagingHistoryAssetRetention implements HistoryAssetRetention {
  StagingHistoryAssetRetention({
    required this.sessionId,
    required this.staging,
  });

  final EditorSessionId sessionId;
  final EditorAssetStagingStore staging;
  final Map<HistoryEntryId, Set<ProjectAssetId>> _retained = {};

  @override
  void retain(HistoryEntryId entryId, Set<ProjectAssetId> assetIds) {
    final previous = _retained[entryId] ?? const <ProjectAssetId>{};
    final copy = Set<ProjectAssetId>.unmodifiable(assetIds);
    final acquired = <ProjectAssetId>[];
    try {
      for (final id in copy.difference(previous)) {
        staging.retain(
          sessionId: sessionId,
          assetId: id,
          kind: StagedAssetReferenceKind.history,
        );
        acquired.add(id);
      }
    } catch (_) {
      _releaseIds(acquired.toSet());
      rethrow;
    }
    _retained[entryId] = copy;
    _releaseIds(previous.difference(copy));
  }

  @override
  void release(HistoryEntryId entryId) {
    final ids = _retained.remove(entryId);
    if (ids != null) _releaseIds(ids);
  }

  void _releaseIds(Set<ProjectAssetId> ids) {
    for (final id in ids) {
      staging.releaseReference(
        sessionId: sessionId,
        assetId: id,
        kind: StagedAssetReferenceKind.history,
      );
    }
  }
}
