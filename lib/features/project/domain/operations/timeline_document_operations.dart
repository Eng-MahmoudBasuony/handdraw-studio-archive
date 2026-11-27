import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_support.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class TimelineDocumentOperations {
  const TimelineDocumentOperations();

  /// Rescales authored drawing time, including fixed section overrides. Media
  /// tracks remain untouched. Absolute audio anchors require explicit editing.
  DocumentOperationResult resizeDrawingDuration({
    required ProjectDocument document,
    required double resolvedDurationSeconds,
    required double targetSeconds,
  }) {
    if (!targetSeconds.isFinite ||
        targetSeconds < 1 ||
        targetSeconds > 300 ||
        !resolvedDurationSeconds.isFinite ||
        resolvedDurationSeconds <= 0) {
      return invalid(document, 'Duration must be between 1 and 300 seconds.');
    }
    if (document.sections.any(
      (section) => section.timing.audioCueAnchor != null,
    )) {
      return invalid(
        document,
        'Drawing is anchored to audio. Edit its timing anchors before resizing.',
      );
    }
    final factor = targetSeconds / resolvedDurationSeconds;
    TimelineDuration scale(
      TimelineDuration value,
    ) => TimelineDuration.fromMicroseconds(
      // Round down so accumulated segments cannot add an extra export frame.
      (value.microseconds * factor).floor(),
    );
    final motion = document.motionConfiguration;
    return DocumentOperationResult.success(
      document: document.copyWith(
        duration: TimelineDuration.fromMicroseconds(
          (targetSeconds * 1000000).round(),
        ),
        motionConfiguration: motion.copyWith(
          drawingDuration: scale(motion.drawingDuration),
          startDelay: scale(motion.startDelay),
          endHold: scale(motion.endHold),
        ),
        sections: [
          for (final section in document.sections)
            section.copyWith(
              timing: section.timing.copyWith(
                animationDuration: section.timing.animationDuration == null
                    ? null
                    : scale(section.timing.animationDuration!),
                pauseBefore: scale(section.timing.pauseBefore),
                pauseAfter: scale(section.timing.pauseAfter),
                transitionAfter: scale(section.timing.transitionAfter),
                handEntranceDuration: scale(
                  section.timing.handEntranceDuration,
                ),
                handExitDuration: scale(section.timing.handExitDuration),
              ),
            ),
        ],
        strokes: [
          for (final stroke in document.strokes)
            if (stroke.pausePoints.isEmpty)
              stroke
            else
              stroke.copyWith(
                pausePoints: [
                  for (final pause in stroke.pausePoints)
                    DocumentStrokePause(
                      id: pause.id,
                      progress: pause.progress,
                      duration: scale(pause.duration),
                      keepHandVisible: pause.keepHandVisible,
                    ),
                ],
              ),
        ],
      ),
      affectedScopes: const {
        DocumentScope.timing,
        DocumentScope.settings,
        DocumentScope.strokes,
      },
      summary: DocumentChangeSummary(action: 'resize-drawing-duration'),
    );
  }

  DocumentOperationResult setPauseBefore({
    required ProjectDocument document,
    required SectionId sectionId,
    required TimelineDuration duration,
  }) => _timing(
    document,
    sectionId,
    'set-pause-before',
    (value) => value.copyWith(pauseBefore: duration),
  );

  DocumentOperationResult setPauseAfter({
    required ProjectDocument document,
    required SectionId sectionId,
    required TimelineDuration duration,
  }) => _timing(
    document,
    sectionId,
    'set-pause-after',
    (value) => value.copyWith(pauseAfter: duration),
  );

  DocumentOperationResult setSpeedMultiplier({
    required ProjectDocument document,
    required SectionId sectionId,
    required double multiplier,
  }) {
    if (!multiplier.isFinite || multiplier < 0.25 || multiplier > 4) {
      return invalid(document, 'Section speed must be between 0.25 and 4.');
    }
    return _timing(
      document,
      sectionId,
      'set-section-speed',
      (value) =>
          value.copyWith(speedMultiplier: multiplier, animationDuration: null),
    );
  }

  DocumentOperationResult setDurationOverride({
    required ProjectDocument document,
    required SectionId sectionId,
    required TimelineDuration? duration,
  }) {
    if (duration != null && duration.isZero) {
      return invalid(
        document,
        'A duration override must be greater than zero.',
      );
    }
    return _timing(
      document,
      sectionId,
      'set-duration-override',
      (value) => value.copyWith(animationDuration: duration),
    );
  }

  DocumentOperationResult setTransitionAfter({
    required ProjectDocument document,
    required SectionId sectionId,
    required TimelineDuration duration,
  }) => _timing(
    document,
    sectionId,
    'set-transition-after',
    (value) => value.copyWith(transitionAfter: duration),
  );

  DocumentOperationResult setPauseHandBehavior({
    required ProjectDocument document,
    required SectionId sectionId,
    required DocumentPauseHandBehavior behavior,
  }) => _timing(
    document,
    sectionId,
    'set-pause-hand-behavior',
    (value) => value.copyWith(pauseHandBehavior: behavior),
  );

  DocumentOperationResult setAudioCue({
    required ProjectDocument document,
    required SectionId sectionId,
    required AudioCueAnchor anchor,
  }) {
    final trackExists = document.audioTracks.any(
      (track) => track.id == anchor.audioTrackId,
    );
    if (!trackExists) {
      return missing(document, 'Audio track', anchor.audioTrackId);
    }
    return _timing(
      document,
      sectionId,
      'set-audio-cue',
      (value) => value.copyWith(audioCueAnchor: anchor),
      scopes: {DocumentScope.timing, DocumentScope.audio},
    );
  }

  DocumentOperationResult clearAudioCue({
    required ProjectDocument document,
    required SectionId sectionId,
  }) => _timing(
    document,
    sectionId,
    'clear-audio-cue',
    (value) => value.copyWith(audioCueAnchor: null),
    scopes: {DocumentScope.timing, DocumentScope.audio},
  );

  DocumentOperationResult reset({
    required ProjectDocument document,
    required SectionId sectionId,
  }) => _timing(
    document,
    sectionId,
    'reset-section-timing',
    (_) => const DocumentSectionTiming(),
  );

  /// Global pen travel is persistent motion timing, independent of section
  /// drawing speed and authored pauses.
  DocumentOperationResult setPenTravelSpeed({
    required ProjectDocument document,
    required double multiplier,
  }) {
    if (!multiplier.isFinite || multiplier < 0.25 || multiplier > 4) {
      return invalid(document, 'Pen travel speed must be between 0.25 and 4.');
    }
    return DocumentOperationResult.success(
      document: document.copyWith(
        motionConfiguration: document.motionConfiguration.copyWith(
          penTravelSpeed: multiplier,
        ),
      ),
      affectedScopes: const {DocumentScope.timing, DocumentScope.settings},
      summary: DocumentChangeSummary(action: 'set-pen-travel-speed'),
    );
  }

  DocumentOperationResult _timing(
    ProjectDocument document,
    SectionId id,
    String action,
    DocumentSectionTiming Function(DocumentSectionTiming) transform, {
    Set<DocumentScope> scopes = const {DocumentScope.timing},
  }) {
    final section = sectionById(document, id);
    if (section == null) return missing(document, 'Section', id);
    return DocumentOperationResult.success(
      document: document.copyWith(
        sections: [
          for (final item in document.sections)
            item.id == id
                ? item.copyWith(timing: transform(item.timing))
                : item,
        ],
      ),
      affectedScopes: scopes,
      summary: DocumentChangeSummary(action: action, entityIds: [id.value]),
    );
  }
}
