import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_support.dart';

final class SceneDocumentOperations {
  const SceneDocumentOperations();

  DocumentOperationResult reorderSection({
    required ProjectDocument document,
    required SectionId sectionId,
    required int insertionIndex,
  }) => reorderSections(
    document: document,
    sectionIds: [sectionId],
    insertionIndex: insertionIndex,
  );

  DocumentOperationResult reorderSections({
    required ProjectDocument document,
    required List<SectionId> sectionIds,
    required int insertionIndex,
  }) {
    final selected = sectionIds.toSet();
    if (selected.isEmpty || selected.length != sectionIds.length) {
      return invalid(document, 'Reorder requires unique selected sections.');
    }
    if (selected.any((id) => !document.sectionOrder.contains(id))) {
      return invalid(document, 'Every reordered section must exist.');
    }
    final orderedSelection = [
      for (final id in document.sectionOrder)
        if (selected.contains(id)) id,
    ];
    final remaining = [
      for (final id in document.sectionOrder)
        if (!selected.contains(id)) id,
    ];
    final target = insertionIndex.clamp(0, remaining.length);
    remaining.insertAll(target, orderedSelection);
    return _changed(
      document.copyWith(sectionOrder: remaining),
      'reorder-sections',
      sectionIds.map((id) => id.value),
      {DocumentScope.ordering},
      count: sectionIds.length,
    );
  }

  DocumentOperationResult deleteSection({
    required ProjectDocument document,
    required SectionId sectionId,
  }) {
    final section = sectionById(document, sectionId);
    if (section == null) return missing(document, 'Section', sectionId);
    final ownedStrokes = section.strokeIds.toSet();
    final scenes = [
      for (final scene in document.scenes)
        if (scene.sectionIds.where((id) => id != sectionId).toList()
            case final members when members.isNotEmpty)
          scene.copyWith(sectionIds: members),
    ];
    final retainedSceneIds = scenes.map((scene) => scene.id).toSet();
    return _changed(
      document.copyWith(
        strokes: document.strokes
            .where((stroke) => !ownedStrokes.contains(stroke.id))
            .toList(growable: false),
        sections: document.sections
            .where((item) => item.id != sectionId)
            .toList(growable: false),
        sectionOrder: document.sectionOrder
            .where((id) => id != sectionId)
            .toList(growable: false),
        scenes: scenes,
        cameraTrack: document.cameraTrack?.copyWith(
          shots: document.cameraTrack!.shots
              .where(
                (shot) =>
                    shot.ownerSceneId == null ||
                    retainedSceneIds.contains(shot.ownerSceneId),
              )
              .toList(growable: false),
        ),
      ),
      'delete-section',
      [sectionId.value, ...ownedStrokes.map((id) => id.value)],
      {
        DocumentScope.sections,
        DocumentScope.strokes,
        DocumentScope.ordering,
        DocumentScope.scenes,
        DocumentScope.camera,
      },
    );
  }

  DocumentOperationResult createScene({
    required ProjectDocument document,
    required String name,
    required List<SectionId> sectionIds,
    required IdAllocationContext ids,
    bool locked = true,
  }) {
    final selected = sectionIds.toSet();
    if (name.trim().isEmpty ||
        selected.isEmpty ||
        selected.length != sectionIds.length ||
        selected.any((id) => !document.sectionOrder.contains(id))) {
      return invalid(
        document,
        'A scene needs a name and unique valid sections.',
      );
    }
    final sceneId = ids.sceneId();
    final retained = [
      for (final scene in document.scenes)
        if (scene.sectionIds.any((id) => !selected.contains(id)))
          scene.copyWith(
            sectionIds: scene.sectionIds
                .where((id) => !selected.contains(id))
                .toList(growable: false),
          ),
    ];
    final orderedMembers = [
      for (final id in document.sectionOrder)
        if (selected.contains(id)) id,
    ];
    return _changed(
      document.copyWith(
        scenes: [
          ...retained,
          ProjectScene(
            id: sceneId,
            name: name.trim(),
            sectionIds: orderedMembers,
            locked: locked,
          ),
        ],
      ),
      'create-scene',
      [sceneId.value, ...orderedMembers.map((id) => id.value)],
      {DocumentScope.scenes, DocumentScope.ordering},
    );
  }

  DocumentOperationResult deleteScene({
    required ProjectDocument document,
    required SceneId sceneId,
  }) {
    if (sceneById(document, sceneId) == null) {
      return missing(document, 'Scene', sceneId);
    }
    return _changed(
      document.copyWith(
        scenes: document.scenes
            .where((scene) => scene.id != sceneId)
            .toList(growable: false),
        cameraTrack: document.cameraTrack?.copyWith(
          shots: document.cameraTrack!.shots
              .where((shot) => shot.ownerSceneId != sceneId)
              .toList(growable: false),
        ),
      ),
      'delete-scene',
      [sceneId.value],
      {DocumentScope.scenes, DocumentScope.camera},
    );
  }

  DocumentOperationResult group({
    required ProjectDocument document,
    required SceneId sceneId,
    required List<SectionId> sectionIds,
  }) {
    final scene = sceneById(document, sceneId);
    if (scene == null) return missing(document, 'Scene', sceneId);
    final selected = sectionIds.toSet();
    if (selected.isEmpty ||
        selected.any((id) => !document.sectionOrder.contains(id))) {
      return invalid(document, 'Grouped sections must exist.');
    }
    final scenes = <ProjectScene>[];
    for (final item in document.scenes) {
      final retained = item.sectionIds
          .where((id) => !selected.contains(id))
          .toList(growable: false);
      if (item.id == sceneId) {
        final members = {
          ...retained,
          ...document.sectionOrder.where(selected.contains),
        };
        scenes.add(
          item.copyWith(
            sectionIds: document.sectionOrder.where(members.contains).toList(),
          ),
        );
      } else if (retained.isNotEmpty) {
        scenes.add(item.copyWith(sectionIds: retained));
      }
    }
    return _changed(
      document.copyWith(scenes: scenes),
      'group-sections',
      [sceneId.value, ...selected.map((id) => id.value)],
      {DocumentScope.scenes},
      count: selected.length,
    );
  }

  DocumentOperationResult ungroup({
    required ProjectDocument document,
    required List<SectionId> sectionIds,
  }) {
    final selected = sectionIds.toSet();
    if (selected.isEmpty ||
        selected.any((id) => !document.sectionOrder.contains(id))) {
      return invalid(document, 'Ungrouped sections must exist.');
    }
    final scenes = <ProjectScene>[
      for (final scene in document.scenes)
        if (scene.sectionIds.where((id) => !selected.contains(id)).toList()
            case final members when members.isNotEmpty)
          scene.copyWith(sectionIds: members),
    ];
    return _changed(
      document.copyWith(scenes: scenes),
      'ungroup-sections',
      selected.map((id) => id.value),
      {DocumentScope.scenes},
      count: selected.length,
    );
  }

  DocumentOperationResult moveSectionBetweenScenes({
    required ProjectDocument document,
    required SectionId sectionId,
    required SceneId? destinationSceneId,
    int? insertionIndex,
  }) {
    if (sectionById(document, sectionId) == null) {
      return missing(document, 'Section', sectionId);
    }
    if (destinationSceneId != null &&
        sceneById(document, destinationSceneId) == null) {
      return missing(document, 'Scene', destinationSceneId);
    }
    final scenes = <ProjectScene>[];
    for (final scene in document.scenes) {
      final members = scene.sectionIds
          .where((id) => id != sectionId)
          .toList(growable: true);
      if (scene.id == destinationSceneId) {
        members.insert(
          insertionIndex?.clamp(0, members.length) ?? members.length,
          sectionId,
        );
      }
      if (members.isNotEmpty) scenes.add(scene.copyWith(sectionIds: members));
    }
    return _changed(
      document.copyWith(scenes: scenes),
      'move-section-between-scenes',
      [
        sectionId.value,
        if (destinationSceneId != null) destinationSceneId.value,
      ],
      {DocumentScope.scenes},
    );
  }

  DocumentOperationResult reorderScene({
    required ProjectDocument document,
    required SceneId sceneId,
    required int insertionIndex,
  }) {
    final scene = sceneById(document, sceneId);
    if (scene == null) return missing(document, 'Scene', sceneId);
    final scenes = List<ProjectScene>.of(document.scenes)..remove(scene);
    scenes.insert(insertionIndex.clamp(0, scenes.length), scene);
    return _changed(
      document.copyWith(scenes: scenes),
      'reorder-scene',
      [sceneId.value],
      {DocumentScope.scenes, DocumentScope.ordering},
    );
  }

  DocumentOperationResult setLocked({
    required ProjectDocument document,
    required SceneId sceneId,
    required bool locked,
  }) {
    final scene = sceneById(document, sceneId);
    if (scene == null) return missing(document, 'Scene', sceneId);
    return _changed(
      document.copyWith(
        scenes: [
          for (final item in document.scenes)
            item.id == sceneId ? item.copyWith(locked: locked) : item,
        ],
      ),
      locked ? 'lock-scene' : 'unlock-scene',
      [sceneId.value],
      {DocumentScope.scenes},
    );
  }

  DocumentOperationResult _changed(
    ProjectDocument document,
    String action,
    Iterable<String> ids,
    Iterable<DocumentScope> scopes, {
    int count = 1,
  }) => DocumentOperationResult.success(
    document: document,
    affectedScopes: scopes,
    summary: DocumentChangeSummary(
      action: action,
      entityIds: ids,
      changeCount: count,
    ),
  );
}
