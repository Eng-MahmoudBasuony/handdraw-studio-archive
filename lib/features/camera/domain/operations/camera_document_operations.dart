import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';

final class CameraDocumentOperations {
  const CameraDocumentOperations();

  DocumentOperationResult createTrack(
    ProjectDocument document,
    ProjectCameraTrack track,
  ) => document.cameraTrack == null
      ? DocumentOperationResult.success(
          document: document.copyWith(
            cameraTrack: track,
            timeline: document.timeline.copyWith(
              camera: PersistentCameraTimelineTrack.enabled(
                cameraTrackId: track.id,
              ),
            ),
          ),
          affectedScopes: const {DocumentScope.camera},
          summary: DocumentChangeSummary(
            action: 'camera.track.create',
            entityIds: [track.id.value],
          ),
        )
      : DocumentOperationResult.failure(
          document: document,
          code: DocumentOperationFailureCode.duplicateEntity,
          message: 'Camera track already exists.',
        );

  DocumentOperationResult setDefaultView(
    ProjectDocument document,
    CameraView view,
  ) => _track(
    document,
    (track) => track.copyWith(defaultView: view),
    'camera.defaultView',
  );
  DocumentOperationResult setTrackEnabled(
    ProjectDocument document,
    bool enabled,
  ) => _track(
    document,
    (track) => track.copyWith(enabled: enabled),
    'camera.track.enabled',
  );
  DocumentOperationResult createShot(
    ProjectDocument document,
    CameraShot shot,
  ) => _track(
    document,
    (track) => track.copyWith(shots: _sorted([...track.shots, shot])),
    'camera.create',
    ids: [shot.id.value],
  );
  DocumentOperationResult installSceneClip(
    ProjectDocument document, {
    required CameraTrackId trackId,
    required CameraShot clip,
    Set<CameraShotId> replacing = const {},
  }) {
    final sceneId = clip.ownerSceneId;
    if (sceneId == null) {
      return _invalid(document, 'A scene camera clip requires a scene owner.');
    }
    if (!document.scenes.any((scene) => scene.id == sceneId)) {
      return _invalid(document, 'The owning scene does not exist.');
    }
    final current = document.cameraTrack;
    final retained =
        current?.shots
            .where(
              (shot) =>
                  !replacing.contains(shot.id) && shot.ownerSceneId != sceneId,
            )
            .toList() ??
        <CameraShot>[];
    final next = ProjectCameraTrack(
      id: current?.id ?? trackId,
      enabled: current?.enabled ?? true,
      defaultView: current?.defaultView ?? const CameraView.identity(),
      shots: _sorted([...retained, clip]),
    );
    if (_hasOverlap(next.shots)) {
      return _invalid(
        document,
        'The scene camera clip overlaps a camera shot outside this scene.',
      );
    }
    return DocumentOperationResult.success(
      document: document.copyWith(
        cameraTrack: next,
        timeline: document.timeline.copyWith(
          camera: PersistentCameraTimelineTrack.enabled(cameraTrackId: next.id),
        ),
      ),
      affectedScopes: const {DocumentScope.camera},
      summary: DocumentChangeSummary(
        action: 'camera.sceneClip.install',
        entityIds: [sceneId.value, clip.id.value],
        changeCount: replacing.length + 1,
      ),
    );
  }

  DocumentOperationResult setSceneConnection(
    ProjectDocument document,
    CameraShotId id,
    CameraSceneConnection connection,
  ) {
    final ordered = [...?document.cameraTrack?.shots]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final index = ordered.indexWhere((shot) => shot.id == id);
    final previousView = index > 0
        ? ordered[index - 1].keyframes.lastOrNull?.view
        : null;
    return _replaceShot(
      document,
      id,
      (shot) {
        final connect = connection != CameraSceneConnection.cut;
        return shot.copyWith(
          sceneConnection: connection,
          authorship: CameraAuthorship.manual,
          keyframes:
              connect && previousView != null && shot.keyframes.isNotEmpty
              ? [
                  shot.keyframes.first.copyWith(view: previousView),
                  ...shot.keyframes.skip(1),
                ]
              : shot.keyframes,
        );
      },
      'camera.sceneConnection',
      false,
    );
  }

  DocumentOperationResult setSceneClipTiming(
    ProjectDocument document,
    CameraShotId id, {
    required TimelineDuration enterDuration,
    required TimelineDuration exitDuration,
    required CameraEasing easing,
  }) => _replaceShot(
    document,
    id,
    (shot) {
      if (shot.ownerSceneId == null || shot.keyframes.length != 3) return shot;
      final totalUs = shot.duration.microseconds;
      final enterUs = enterDuration.microseconds.clamp(0, totalUs);
      final exitUs = exitDuration.microseconds.clamp(0, totalUs - enterUs);
      final first = shot.keyframes.first;
      final focus = shot.keyframes[1].copyWith(
        offset: TimelineTime.fromMicroseconds(enterUs),
        incomingTransition: CameraTransition(
          type: enterUs == 0
              ? CameraTransitionType.cut
              : CameraTransitionType.move,
          duration: TimelineDuration.fromMicroseconds(enterUs),
          easing: easing,
        ),
      );
      final end = shot.keyframes.last.copyWith(
        offset: TimelineTime.fromMicroseconds(totalUs),
        incomingTransition: CameraTransition(
          type: exitUs == 0
              ? CameraTransitionType.cut
              : CameraTransitionType.move,
          duration: TimelineDuration.fromMicroseconds(exitUs),
          easing: easing,
        ),
      );
      return shot.copyWith(
        authorship: CameraAuthorship.manual,
        keyframes: [first, focus, end],
      );
    },
    'camera.sceneTiming',
    false,
  );
  DocumentOperationResult deleteShot(
    ProjectDocument document,
    CameraShotId id, {
    bool overrideLock = false,
  }) => _editShot(
    document,
    id,
    overrideLock: overrideLock,
    action: 'camera.delete',
    transform: (_, track) => track.copyWith(
      shots: track.shots.where((shot) => shot.id != id).toList(),
    ),
  );
  DocumentOperationResult duplicateShot(
    ProjectDocument document,
    CameraShotId sourceId, {
    required CameraShotId shotId,
    required List<CameraKeyframeId> keyframeIds,
    required TimelineTime startTime,
  }) {
    final source = _find(document, sourceId);
    if (source == null) return _missing(document);
    if (source.isLocked) return _locked(document);
    if (keyframeIds.length != source.keyframes.length) {
      return _invalid(
        document,
        'A fresh ID is required for every camera keyframe.',
      );
    }
    return createShot(
      document,
      CameraShot(
        id: shotId,
        startTime: startTime,
        duration: source.duration,
        authorship: CameraAuthorship.manual,
        isLocked: false,
        label: source.label,
        keyframes: [
          for (var i = 0; i < source.keyframes.length; i++)
            CameraKeyframe(
              id: keyframeIds[i],
              offset: source.keyframes[i].offset,
              view: source.keyframes[i].view,
              incomingTransition: source.keyframes[i].incomingTransition,
            ),
        ],
      ),
    );
  }

  DocumentOperationResult moveShot(
    ProjectDocument document,
    CameraShotId id,
    TimelineTime start, {
    bool overrideLock = false,
  }) => _replaceShot(
    document,
    id,
    (shot) =>
        shot.copyWith(startTime: start, authorship: CameraAuthorship.manual),
    'camera.move',
    overrideLock,
  );
  DocumentOperationResult resizeShot(
    ProjectDocument document,
    CameraShotId id,
    TimelineDuration duration, {
    bool overrideLock = false,
  }) => _replaceShot(
    document,
    id,
    (shot) =>
        shot.copyWith(duration: duration, authorship: CameraAuthorship.manual),
    'camera.resize',
    overrideLock,
  );
  DocumentOperationResult trimShot(
    ProjectDocument document,
    CameraShotId id, {
    required TimelineTime trimStart,
    required TimelineDuration duration,
    required CameraKeyframeId firstKeyframeId,
    bool overrideLock = false,
  }) {
    final source = _find(document, id);
    if (source == null) return _missing(document);
    if (trimStart.microseconds >= source.duration.microseconds ||
        duration.isZero ||
        trimStart.microseconds + duration.microseconds >
            source.duration.microseconds) {
      return _invalid(
        document,
        'Trim range must remain inside the camera shot.',
      );
    }
    final held = source.keyframes
        .lastWhere((keyframe) => keyframe.offset.compareTo(trimStart) <= 0)
        .view;
    final frames = <CameraKeyframe>[
      CameraKeyframe(
        id: firstKeyframeId,
        offset: TimelineTime.zero,
        view: held,
      ),
      for (final keyframe in source.keyframes)
        if (keyframe.offset.compareTo(trimStart) > 0 &&
            keyframe.offset.microseconds <=
                trimStart.microseconds + duration.microseconds)
          keyframe.copyWith(
            offset: TimelineTime.fromMicroseconds(
              keyframe.offset.microseconds - trimStart.microseconds,
            ),
          ),
    ];
    return _replaceShot(
      document,
      id,
      (shot) => shot.copyWith(
        startTime:
            shot.startTime +
            TimelineDuration.fromMicroseconds(trimStart.microseconds),
        duration: duration,
        authorship: CameraAuthorship.manual,
        keyframes: frames,
      ),
      'camera.trim',
      overrideLock,
    );
  }

  /// Moves the leading edge while preserving the shot's absolute end time.
  /// Expanding to the left holds the first camera view until the original
  /// content begins; trimming to the right keeps the view resolved at the new
  /// start. This is deliberately different from moving the whole shot.
  DocumentOperationResult resizeShotFromStart(
    ProjectDocument document,
    CameraShotId id, {
    required TimelineTime start,
    required CameraKeyframeId firstKeyframeId,
    bool overrideLock = false,
  }) {
    final source = _find(document, id);
    if (source == null) return _missing(document);
    if (source.keyframes.isEmpty || start.compareTo(source.endTime) >= 0) {
      return _invalid(
        document,
        'The camera shot start must remain before its end.',
      );
    }
    final deltaUs = start.microseconds - source.startTime.microseconds;
    final duration = source.endTime.difference(start);
    late final List<CameraKeyframe> frames;
    if (deltaUs <= 0) {
      final shiftUs = -deltaUs;
      frames = [
        CameraKeyframe(
          id: firstKeyframeId,
          offset: TimelineTime.zero,
          view: source.keyframes.first.view,
        ),
        for (final keyframe in source.keyframes)
          keyframe.copyWith(
            offset: TimelineTime.fromMicroseconds(
              keyframe.offset.microseconds + shiftUs,
            ),
          ),
      ];
    } else {
      final trimStart = TimelineTime.fromMicroseconds(deltaUs);
      final held = source.keyframes
          .lastWhere((keyframe) => keyframe.offset.compareTo(trimStart) <= 0)
          .view;
      frames = [
        CameraKeyframe(
          id: firstKeyframeId,
          offset: TimelineTime.zero,
          view: held,
        ),
        for (final keyframe in source.keyframes)
          if (keyframe.offset.compareTo(trimStart) > 0)
            keyframe.copyWith(
              offset: TimelineTime.fromMicroseconds(
                keyframe.offset.microseconds - deltaUs,
              ),
            ),
      ];
    }
    return _replaceShot(
      document,
      id,
      (shot) => shot.copyWith(
        startTime: start,
        duration: duration,
        authorship: CameraAuthorship.manual,
        keyframes: frames,
      ),
      'camera.resize.start',
      overrideLock,
    );
  }

  DocumentOperationResult renameShot(
    ProjectDocument document,
    CameraShotId id,
    String? label, {
    bool overrideLock = false,
  }) => _replaceShot(
    document,
    id,
    (shot) => shot.copyWith(
      label: label?.trim().isEmpty == true ? null : label?.trim(),
      authorship: CameraAuthorship.manual,
    ),
    'camera.rename',
    overrideLock,
  );
  DocumentOperationResult setLock(
    ProjectDocument document,
    CameraShotId id,
    bool locked,
  ) => _replaceShot(
    document,
    id,
    (shot) => shot.copyWith(isLocked: locked),
    'camera.lock',
    true,
  );
  DocumentOperationResult setAuthorship(
    ProjectDocument document,
    CameraShotId id,
    CameraAuthorship authorship, {
    bool overrideLock = false,
  }) => _replaceShot(
    document,
    id,
    (shot) => shot.copyWith(authorship: authorship),
    'camera.authorship',
    overrideLock,
  );
  DocumentOperationResult setView(
    ProjectDocument document,
    CameraShotId id,
    CameraKeyframeId keyframeId,
    CameraView view, {
    bool overrideLock = false,
  }) => _keyframe(
    document,
    id,
    keyframeId,
    (keyframe) => keyframe.copyWith(view: view),
    'camera.view',
    overrideLock,
  );
  DocumentOperationResult setTransition(
    ProjectDocument document,
    CameraShotId id,
    CameraKeyframeId keyframeId,
    CameraTransition transition, {
    bool overrideLock = false,
  }) => _keyframe(
    document,
    id,
    keyframeId,
    (keyframe) => keyframe.copyWith(incomingTransition: transition),
    'camera.transition',
    overrideLock,
  );

  DocumentOperationResult setSimpleViewShot(
    ProjectDocument document,
    CameraShotId id, {
    required CameraView view,
    required CameraTransition transition,
    required TimelineDuration holdDuration,
    required CameraKeyframeId transitionKeyframeId,
    bool overrideLock = false,
  }) => _replaceShot(
    document,
    id,
    (shot) {
      final firstId = shot.keyframes.first.id;
      final movement = transition.type == CameraTransitionType.cut
          ? TimelineDuration.zero
          : transition.duration;
      final secondId = shot.keyframes.length > 1
          ? shot.keyframes[1].id
          : transitionKeyframeId;
      return shot.copyWith(
        authorship: CameraAuthorship.manual,
        duration: TimelineDuration.fromMicroseconds(
          movement.microseconds + holdDuration.microseconds,
        ),
        keyframes: [
          CameraKeyframe(id: firstId, offset: TimelineTime.zero, view: view),
          if (!movement.isZero)
            CameraKeyframe(
              id: secondId,
              offset: TimelineTime.fromMicroseconds(movement.microseconds),
              view: view,
              incomingTransition: transition,
            ),
        ],
      );
    },
    'camera.simpleView',
    overrideLock,
  );
  DocumentOperationResult moveKeyframe(
    ProjectDocument document,
    CameraShotId id,
    CameraKeyframeId keyframeId,
    TimelineTime offset, {
    bool overrideLock = false,
  }) => _keyframe(
    document,
    id,
    keyframeId,
    (keyframe) => keyframe.copyWith(offset: offset),
    'camera.keyframe.move',
    overrideLock,
    sort: true,
  );
  DocumentOperationResult addKeyframe(
    ProjectDocument document,
    CameraShotId id,
    CameraKeyframe keyframe, {
    bool overrideLock = false,
  }) => _replaceShot(
    document,
    id,
    (shot) => shot.copyWith(
      authorship: CameraAuthorship.manual,
      keyframes: [...shot.keyframes, keyframe]
        ..sort((a, b) => a.offset.compareTo(b.offset)),
    ),
    'camera.keyframe.add',
    overrideLock,
  );
  DocumentOperationResult deleteKeyframe(
    ProjectDocument document,
    CameraShotId id,
    CameraKeyframeId keyframeId, {
    bool overrideLock = false,
  }) => _replaceShot(
    document,
    id,
    (shot) => shot.copyWith(
      authorship: CameraAuthorship.manual,
      keyframes: shot.keyframes
          .where((keyframe) => keyframe.id != keyframeId)
          .toList(),
    ),
    'camera.keyframe.delete',
    overrideLock,
  );
  DocumentOperationResult clearAutoShots(ProjectDocument document) => _track(
    document,
    (track) => track.copyWith(
      shots: track.shots
          .where(
            (shot) => shot.authorship != CameraAuthorship.auto || shot.isLocked,
          )
          .toList(),
    ),
    'camera.auto.clear',
  );
  DocumentOperationResult replaceAutoPlan(
    ProjectDocument document,
    List<CameraShot> plan,
  ) => _track(
    document,
    (track) => track.copyWith(
      shots: _sorted([
        ...track.shots.where(
          (shot) => shot.authorship == CameraAuthorship.manual || shot.isLocked,
        ),
        ...plan,
      ]),
    ),
    'camera.auto.replace',
  );

  DocumentOperationResult installZoomInOutPreset(
    ProjectDocument document, {
    required CameraTrackId trackId,
    required CameraShotId? sourceShotId,
    required List<CameraShot> shots,
  }) {
    if (shots.length != 3) {
      return _invalid(document, 'Zoom preset requires exactly three shots.');
    }
    final current = document.cameraTrack;
    if (current == null) {
      if (sourceShotId != null) return _missing(document);
      final track = ProjectCameraTrack(id: trackId, shots: _sorted([...shots]));
      if (_hasOverlap(track.shots)) {
        return _invalid(document, 'Zoom preset camera shots overlap.');
      }
      return DocumentOperationResult.success(
        document: document.copyWith(
          cameraTrack: track,
          timeline: document.timeline.copyWith(
            camera: PersistentCameraTimelineTrack.enabled(
              cameraTrackId: track.id,
            ),
          ),
        ),
        affectedScopes: const {DocumentScope.camera},
        summary: DocumentChangeSummary(
          action: 'camera.zoomPreset.install',
          entityIds: shots.map((shot) => shot.id.value),
          changeCount: shots.length,
        ),
      );
    }
    if (sourceShotId == null && current.shots.isNotEmpty) {
      return _invalid(
        document,
        'Select an unlocked camera shot to apply the zoom preset.',
      );
    }
    final source = sourceShotId == null ? null : _find(document, sourceShotId);
    if (sourceShotId != null && source == null) return _missing(document);
    if (source?.isLocked == true) return _locked(document);
    final nextShots = _sorted([
      for (final shot in current.shots)
        if (shot.id != sourceShotId) shot,
      ...shots,
    ]);
    if (_hasOverlap(nextShots)) {
      return DocumentOperationResult.failure(
        document: document,
        code: DocumentOperationFailureCode.overlap,
        message: 'Zoom preset overlaps another camera shot.',
      );
    }
    return DocumentOperationResult.success(
      document: document.copyWith(
        cameraTrack: current.copyWith(shots: nextShots),
        timeline: document.timeline.copyWith(
          camera: PersistentCameraTimelineTrack.enabled(
            cameraTrackId: current.id,
          ),
        ),
      ),
      affectedScopes: const {DocumentScope.camera},
      summary: DocumentChangeSummary(
        action: 'camera.zoomPreset.install',
        entityIds: shots.map((shot) => shot.id.value),
        changeCount: shots.length,
      ),
    );
  }

  DocumentOperationResult splitShot(
    ProjectDocument document,
    CameraShotId id,
    TimelineTime offset, {
    required CameraShotId rightShotId,
    required CameraKeyframeId rightFirstKeyframeId,
    bool overrideLock = false,
  }) {
    final shot = _find(document, id);
    if (shot == null) return _missing(document);
    if (offset == TimelineTime.zero ||
        offset.microseconds >= shot.duration.microseconds) {
      return _invalid(document, 'Split must be inside the shot.');
    }
    final atSplit = shot.keyframes
        .lastWhere((keyframe) => keyframe.offset.compareTo(offset) <= 0)
        .view;
    final left = shot.copyWith(
      duration: TimelineDuration.fromMicroseconds(offset.microseconds),
      authorship: CameraAuthorship.manual,
      keyframes: shot.keyframes
          .where((keyframe) => keyframe.offset.compareTo(offset) <= 0)
          .toList(),
    );
    final rightDuration = TimelineDuration.fromMicroseconds(
      shot.duration.microseconds - offset.microseconds,
    );
    final right = CameraShot(
      id: rightShotId,
      startTime:
          shot.startTime +
          TimelineDuration.fromMicroseconds(offset.microseconds),
      duration: rightDuration,
      authorship: CameraAuthorship.manual,
      isLocked: false,
      label: shot.label,
      keyframes: [
        CameraKeyframe(
          id: rightFirstKeyframeId,
          offset: TimelineTime.zero,
          view: atSplit,
        ),
        ...shot.keyframes
            .where((keyframe) => keyframe.offset.compareTo(offset) > 0)
            .map(
              (keyframe) => keyframe.copyWith(
                offset: TimelineTime.fromMicroseconds(
                  keyframe.offset.microseconds - offset.microseconds,
                ),
              ),
            ),
      ],
    );
    return _editShot(
      document,
      id,
      overrideLock: overrideLock,
      action: 'camera.split',
      transform: (_, track) => track.copyWith(
        shots: _sorted([
          for (final item in track.shots)
            if (item.id == id) ...[left, right] else item,
        ]),
      ),
    );
  }

  DocumentOperationResult _keyframe(
    ProjectDocument document,
    CameraShotId shotId,
    CameraKeyframeId keyframeId,
    CameraKeyframe Function(CameraKeyframe) transform,
    String action,
    bool overrideLock, {
    bool sort = false,
  }) => _replaceShot(
    document,
    shotId,
    (shot) {
      final frames = [
        for (final frame in shot.keyframes)
          frame.id == keyframeId ? transform(frame) : frame,
      ];
      if (!frames.any((frame) => frame.id == keyframeId)) return shot;
      if (sort) frames.sort((a, b) => a.offset.compareTo(b.offset));
      return shot.copyWith(
        authorship: CameraAuthorship.manual,
        keyframes: frames,
      );
    },
    action,
    overrideLock,
  );
  DocumentOperationResult _replaceShot(
    ProjectDocument document,
    CameraShotId id,
    CameraShot Function(CameraShot) transform,
    String action,
    bool overrideLock,
  ) => _editShot(
    document,
    id,
    overrideLock: overrideLock,
    action: action,
    transform: (shot, track) => track.copyWith(
      shots: _sorted([
        for (final item in track.shots) item.id == id ? transform(shot) : item,
      ]),
    ),
  );
  DocumentOperationResult _editShot(
    ProjectDocument document,
    CameraShotId id, {
    required bool overrideLock,
    required String action,
    required ProjectCameraTrack Function(CameraShot, ProjectCameraTrack)
    transform,
  }) {
    final shot = _find(document, id);
    if (shot == null) return _missing(document);
    if (shot.isLocked && !overrideLock) return _locked(document);
    return _track(
      document,
      (track) => transform(shot, track),
      action,
      ids: [id.value],
    );
  }

  CameraShot? _find(ProjectDocument document, CameraShotId id) {
    for (final shot in document.cameraTrack?.shots ?? const <CameraShot>[]) {
      if (shot.id == id) return shot;
    }
    return null;
  }

  List<CameraShot> _sorted(List<CameraShot> shots) =>
      shots..sort((a, b) => a.startTime.compareTo(b.startTime));
  bool _hasOverlap(List<CameraShot> shots) {
    for (var i = 1; i < shots.length; i++) {
      if (shots[i].startTime.compareTo(shots[i - 1].endTime) < 0) return true;
    }
    return false;
  }

  DocumentOperationResult _track(
    ProjectDocument document,
    ProjectCameraTrack Function(ProjectCameraTrack) transform,
    String action, {
    List<String> ids = const [],
  }) {
    final current = document.cameraTrack;
    if (current == null) return _missing(document);
    final next = transform(current);
    if (_sameTrack(current, next)) {
      return DocumentOperationResult.success(
        document: document,
        affectedScopes: const {},
        summary: DocumentChangeSummary(action: action, changeCount: 0),
      );
    }
    for (var i = 1; i < next.shots.length; i++) {
      if (next.shots[i].startTime.compareTo(next.shots[i - 1].endTime) < 0) {
        return DocumentOperationResult.failure(
          document: document,
          code: DocumentOperationFailureCode.overlap,
          message: 'Camera shots cannot overlap.',
        );
      }
    }
    return DocumentOperationResult.success(
      document: document.copyWith(cameraTrack: next),
      affectedScopes: const {DocumentScope.camera},
      summary: DocumentChangeSummary(action: action, entityIds: ids),
    );
  }

  bool _sameTrack(ProjectCameraTrack a, ProjectCameraTrack b) => a == b;

  DocumentOperationResult _missing(ProjectDocument d) =>
      DocumentOperationResult.failure(
        document: d,
        code: DocumentOperationFailureCode.missingEntity,
        message: 'Camera entity was not found.',
      );
  DocumentOperationResult _locked(ProjectDocument d) =>
      DocumentOperationResult.failure(
        document: d,
        code: DocumentOperationFailureCode.lockedEntity,
        message: 'Camera shot is locked.',
      );
  DocumentOperationResult _invalid(ProjectDocument d, String message) =>
      DocumentOperationResult.failure(
        document: d,
        code: DocumentOperationFailureCode.invalidInput,
        message: message,
      );
}
