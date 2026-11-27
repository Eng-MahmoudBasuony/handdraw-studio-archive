import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_support.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class AddStrokeInput {
  const AddStrokeInput({
    required this.sectionId,
    required this.name,
    required this.points,
    this.assetId,
    this.geometry,
    this.animationGeometry,
    this.revealOnly = false,
    this.revealStyle = DocumentRevealStyle.brush,
  });

  final SectionId sectionId;
  final String name;
  final List<DocumentPoint> points;
  final ProjectAssetId? assetId;
  final StrokePathGeometry? geometry;
  final StrokePathGeometry? animationGeometry;
  final bool revealOnly;
  final DocumentRevealStyle revealStyle;
}

final class BatchStrokeApplication {
  const BatchStrokeApplication({
    required this.strokes,
    required this.sections,
    required this.sectionOrder,
    this.action = 'apply-auto-path',
  });

  final List<ProjectStroke> strokes;
  final List<ProjectSection> sections;
  final List<SectionId> sectionOrder;
  final String action;
}

final class StrokeDocumentOperations {
  const StrokeDocumentOperations();

  DocumentOperationResult add({
    required ProjectDocument document,
    required AddStrokeInput input,
    required IdAllocationContext ids,
  }) {
    final section = sectionById(document, input.sectionId);
    if (section == null) return missing(document, 'Section', input.sectionId);
    if (input.name.trim().isEmpty || input.points.isEmpty) {
      return invalid(document, 'A stroke requires a name and sampled points.');
    }
    final id = ids.strokeId();
    final stroke = ProjectStroke(
      id: id,
      sectionId: input.sectionId,
      name: input.name.trim(),
      points: input.points,
      assetId: input.assetId,
      geometry: input.geometry,
      animationGeometry: input.animationGeometry,
      revealOnly: input.revealOnly,
      revealStyle: input.revealStyle,
    );
    return _changed(
      document.copyWith(
        strokes: [...document.strokes, stroke],
        sections: [
          for (final item in document.sections)
            item.id == section.id
                ? item.copyWith(strokeIds: [...item.strokeIds, id])
                : item,
        ],
      ),
      'add-stroke',
      [id.value],
      {DocumentScope.strokes, DocumentScope.sections},
    );
  }

  DocumentOperationResult delete({
    required ProjectDocument document,
    required StrokeId strokeId,
  }) {
    final stroke = strokeById(document, strokeId);
    if (stroke == null) return missing(document, 'Stroke', strokeId);
    return _changed(
      document.copyWith(
        strokes: document.strokes
            .where((item) => item.id != strokeId)
            .toList(growable: false),
        sections: [
          for (final section in document.sections)
            section.id == stroke.sectionId
                ? section.copyWith(
                    strokeIds: section.strokeIds
                        .where((id) => id != strokeId)
                        .toList(growable: false),
                  )
                : section,
        ],
      ),
      'delete-stroke',
      [strokeId.value],
      {DocumentScope.strokes, DocumentScope.sections},
    );
  }

  DocumentOperationResult duplicate({
    required ProjectDocument document,
    required StrokeId strokeId,
    required IdAllocationContext ids,
  }) {
    final stroke = strokeById(document, strokeId);
    if (stroke == null) return missing(document, 'Stroke', strokeId);
    final id = ids.strokeId();
    final duplicate = stroke.copyWith(
      id: id,
      name: '${stroke.name} Copy',
      pausePoints: [
        for (final pause in stroke.pausePoints)
          DocumentStrokePause(
            id: ids.strokePauseId(),
            progress: pause.progress,
            duration: pause.duration,
            keepHandVisible: pause.keepHandVisible,
          ),
      ],
    );
    final strokeIndex = document.strokes.indexOf(stroke);
    final strokes = List<ProjectStroke>.of(document.strokes)
      ..insert(strokeIndex + 1, duplicate);
    return _changed(
      document.copyWith(
        strokes: strokes,
        sections: [
          for (final section in document.sections)
            if (section.id == stroke.sectionId)
              section.copyWith(
                strokeIds: _insertAfter(section.strokeIds, strokeId, id),
              )
            else
              section,
        ],
      ),
      'duplicate-stroke',
      [strokeId.value, id.value],
      {DocumentScope.strokes, DocumentScope.sections},
    );
  }

  DocumentOperationResult reverse({
    required ProjectDocument document,
    required StrokeId strokeId,
  }) => _update(
    document,
    strokeId,
    'reverse-stroke',
    (stroke) => _setReversed(stroke, !stroke.reversed),
  );

  DocumentOperationResult setDirection({
    required ProjectDocument document,
    required StrokeId strokeId,
    required bool reversed,
  }) => _update(
    document,
    strokeId,
    'set-stroke-direction',
    (stroke) =>
        stroke.reversed == reversed ? stroke : _setReversed(stroke, reversed),
  );

  DocumentOperationResult setHidden({
    required ProjectDocument document,
    required StrokeId strokeId,
    required bool hidden,
  }) => _update(
    document,
    strokeId,
    hidden ? 'hide-stroke' : 'show-stroke',
    (stroke) => stroke.copyWith(hidden: hidden),
  );

  DocumentOperationResult setReveal({
    required ProjectDocument document,
    required StrokeId strokeId,
    required bool revealOnly,
    required DocumentRevealStyle style,
  }) => _update(
    document,
    strokeId,
    'set-stroke-reveal',
    (stroke) => stroke.copyWith(revealOnly: revealOnly, revealStyle: style),
    scopes: {DocumentScope.strokes, DocumentScope.masks},
  );

  DocumentOperationResult setRevealWidth({
    required ProjectDocument document,
    required StrokeId strokeId,
    required double width,
  }) {
    if (!width.isFinite || width <= 0) {
      return invalid(document, 'Reveal width must be greater than zero.');
    }
    return _update(
      document,
      strokeId,
      'set-stroke-reveal-width',
      (stroke) => stroke.copyWith(revealWidth: width),
      scopes: {DocumentScope.strokes, DocumentScope.masks},
    );
  }

  DocumentOperationResult replaceGeometry({
    required ProjectDocument document,
    required StrokeId strokeId,
    required StrokePathGeometry geometry,
    StrokePathGeometry? animationGeometry,
  }) => _update(
    document,
    strokeId,
    'replace-stroke-geometry',
    (stroke) => stroke.copyWith(
      points: [
        for (final point in geometry.sample())
          DocumentPoint(point.dx, point.dy),
      ],
      geometry: geometry,
      animationGeometry: animationGeometry,
    ),
    scopes: {DocumentScope.strokes, DocumentScope.paths},
  );

  DocumentOperationResult addPausePoint({
    required ProjectDocument document,
    required StrokeId strokeId,
    required double progress,
    required TimelineDuration duration,
    required IdAllocationContext ids,
    bool keepHandVisible = true,
  }) {
    if (!progress.isFinite ||
        progress <= 0 ||
        progress >= 1 ||
        duration.isZero) {
      return invalid(
        document,
        'A stroke pause requires valid progress and duration.',
      );
    }
    final pauseId = ids.strokePauseId();
    return _update(
      document,
      strokeId,
      'add-stroke-pause',
      (stroke) => stroke.copyWith(
        pausePoints: [
          ...stroke.pausePoints,
          DocumentStrokePause(
            id: pauseId,
            progress: progress,
            duration: duration,
            keepHandVisible: keepHandVisible,
          ),
        ]..sort((a, b) => a.progress.compareTo(b.progress)),
      ),
      scopes: {DocumentScope.strokes, DocumentScope.timing},
    );
  }

  DocumentOperationResult updatePausePoint({
    required ProjectDocument document,
    required StrokeId strokeId,
    required StrokePauseId pauseId,
    required double progress,
    required TimelineDuration duration,
    required bool keepHandVisible,
  }) {
    final stroke = strokeById(document, strokeId);
    if (stroke == null) return missing(document, 'Stroke', strokeId);
    if (!stroke.pausePoints.any((pause) => pause.id == pauseId)) {
      return missing(document, 'Stroke pause', pauseId);
    }
    if (!progress.isFinite ||
        progress <= 0 ||
        progress >= 1 ||
        duration.isZero) {
      return invalid(
        document,
        'A stroke pause requires valid progress and duration.',
      );
    }
    return _update(
      document,
      strokeId,
      'update-stroke-pause',
      (item) => item.copyWith(
        pausePoints: [
          for (final pause in item.pausePoints)
            pause.id == pauseId
                ? DocumentStrokePause(
                    id: pause.id,
                    progress: progress,
                    duration: duration,
                    keepHandVisible: keepHandVisible,
                  )
                : pause,
        ]..sort((a, b) => a.progress.compareTo(b.progress)),
      ),
      scopes: {DocumentScope.strokes, DocumentScope.timing},
    );
  }

  DocumentOperationResult deletePausePoint({
    required ProjectDocument document,
    required StrokeId strokeId,
    required StrokePauseId pauseId,
  }) {
    final stroke = strokeById(document, strokeId);
    if (stroke == null) return missing(document, 'Stroke', strokeId);
    if (!stroke.pausePoints.any((pause) => pause.id == pauseId)) {
      return missing(document, 'Stroke pause', pauseId);
    }
    return _update(
      document,
      strokeId,
      'delete-stroke-pause',
      (item) => item.copyWith(
        pausePoints: item.pausePoints
            .where((pause) => pause.id != pauseId)
            .toList(growable: false),
      ),
      scopes: {DocumentScope.strokes, DocumentScope.timing},
    );
  }

  /// Replace one artwork section, retaining other sections, their timings,
  /// scenes, camera track and every project setting. One undo transaction.
  DocumentOperationResult replaceSection({
    required ProjectDocument document,
    required BatchStrokeApplication input,
  }) {
    if (input.sections.length != 1) {
      return invalid(document, 'One section required.');
    }
    final section = input.sections.single;
    final ids = input.strokes.map((s) => s.id).toList();
    if (ids.toSet().length != ids.length ||
        input.strokes.any((s) => s.sectionId != section.id) ||
        section.strokeIds.length != ids.length ||
        !section.strokeIds.toSet().containsAll(ids) ||
        document.strokes.any(
          (s) => s.sectionId != section.id && ids.contains(s.id),
        )) {
      return invalid(document, 'Invalid replacement section paths.');
    }
    final exists = document.sections.any((s) => s.id == section.id);
    final strokes = <ProjectStroke>[];
    var inserted = false;
    for (final stroke in document.strokes) {
      if (stroke.sectionId == section.id) {
        if (!inserted) {
          strokes.addAll(input.strokes);
          inserted = true;
        }
      } else {
        strokes.add(stroke);
      }
    }
    if (!inserted) strokes.addAll(input.strokes);
    return _changed(
      document.copyWith(
        strokes: strokes,
        sections: [
          for (final old in document.sections)
            old.id == section.id ? section : old,
          if (!exists) section,
        ],
        sectionOrder: [...document.sectionOrder, if (!exists) section.id],
      ),
      input.action,
      [section.id.value],
      {DocumentScope.strokes, DocumentScope.sections, DocumentScope.ordering},
    );
  }

  /// Replaces the first authored section and inserts its parts directly after it.
  /// Validation happens before the editor commits the single resulting document.
  DocumentOperationResult replaceSections({
    required ProjectDocument document,
    required BatchStrokeApplication input,
  }) {
    if (input.sections.isEmpty) {
      return invalid(document, 'At least one section required.');
    }
    if (input.sections.length == 1) {
      return replaceSection(document: document, input: input);
    }
    final validated = applyBatch(document: document, input: input);
    if (!validated.isSuccess) return validated;
    var working = document;
    for (final section in input.sections) {
      final result = replaceSection(
        document: working,
        input: BatchStrokeApplication(
          strokes: input.strokes
              .where((s) => s.sectionId == section.id)
              .toList(),
          sections: [section],
          sectionOrder: [section.id],
          action: input.action,
        ),
      );
      if (!result.isSuccess) return result;
      working = result.document;
    }
    final members = input.sectionOrder.toSet();
    final anchor = input.sectionOrder.first;
    final order = <SectionId>[];
    for (final id in working.sectionOrder) {
      if (id == anchor) order.addAll(input.sectionOrder);
      if (!members.contains(id)) order.add(id);
    }
    return _changed(
      working.copyWith(sectionOrder: order),
      input.action,
      members.map((id) => id.value).toList(),
      {DocumentScope.strokes, DocumentScope.sections, DocumentScope.ordering},
    );
  }

  /// Auto Path/Auto Reveal becomes one semantic document transaction.
  DocumentOperationResult applyBatch({
    required ProjectDocument document,
    required BatchStrokeApplication input,
  }) {
    final sectionIds = input.sections.map((item) => item.id).toSet();
    final strokeIds = input.strokes.map((item) => item.id).toSet();
    if (sectionIds.length != input.sections.length ||
        strokeIds.length != input.strokes.length ||
        input.sectionOrder.length != sectionIds.length ||
        input.sectionOrder.toSet().length != sectionIds.length ||
        !input.sectionOrder.toSet().containsAll(sectionIds) ||
        input.strokes.any((stroke) => !sectionIds.contains(stroke.sectionId))) {
      return invalid(document, 'The batch contains inconsistent IDs or order.');
    }
    return _changed(
      document.copyWith(
        strokes: input.strokes,
        sections: input.sections,
        sectionOrder: input.sectionOrder,
        scenes: const [],
      ),
      input.action,
      [...strokeIds.map((id) => id.value), ...sectionIds.map((id) => id.value)],
      {
        DocumentScope.strokes,
        DocumentScope.sections,
        DocumentScope.ordering,
        DocumentScope.scenes,
      },
    );
  }

  DocumentOperationResult _update(
    ProjectDocument document,
    StrokeId id,
    String action,
    ProjectStroke Function(ProjectStroke) transform, {
    Set<DocumentScope> scopes = const {DocumentScope.strokes},
  }) {
    final stroke = strokeById(document, id);
    if (stroke == null) return missing(document, 'Stroke', id);
    return _changed(
      document.copyWith(
        strokes: [
          for (final item in document.strokes)
            item.id == id ? transform(item) : item,
        ],
      ),
      action,
      [id.value],
      scopes,
    );
  }

  DocumentOperationResult _changed(
    ProjectDocument document,
    String action,
    Iterable<String> ids,
    Iterable<DocumentScope> scopes,
  ) => DocumentOperationResult.success(
    document: document,
    affectedScopes: scopes,
    summary: DocumentChangeSummary(action: action, entityIds: ids),
  );

  List<StrokeId> _insertAfter(
    List<StrokeId> source,
    StrokeId after,
    StrokeId value,
  ) {
    final result = List<StrokeId>.of(source);
    final index = result.indexOf(after);
    result.insert(index < 0 ? result.length : index + 1, value);
    return result;
  }

  ProjectStroke _setReversed(ProjectStroke stroke, bool reversed) =>
      stroke.copyWith(
        reversed: reversed,
        pausePoints: [
          for (final pause in stroke.pausePoints)
            DocumentStrokePause(
              id: pause.id,
              progress: 1 - pause.progress,
              duration: pause.duration,
              keepHandVisible: pause.keepHandVisible,
            ),
        ]..sort((a, b) => a.progress.compareTo(b.progress)),
      );
}
