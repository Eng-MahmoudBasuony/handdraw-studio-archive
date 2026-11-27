import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('invalid interval reports complete typed diagnostic context', () {
    expect(
      () => TimelineInterval(
        start: TimelineTime.fromMicroseconds(6000001),
        end: TimelineTime.fromMicroseconds(6000000),
        intervalType: 'camera-shot',
        entityId: 'auto-shot-4',
        sourceOperation: 'auto-director-proposal',
        documentRevision: 42,
      ),
      throwsA(
        isA<InvalidTimelineIntervalException>()
            .having(
              (error) => error.intervalType,
              'intervalType',
              'camera-shot',
            )
            .having((error) => error.entityId, 'entityId', 'auto-shot-4')
            .having(
              (error) => error.attemptedDurationMicroseconds,
              'attempted duration',
              -1,
            )
            .having(
              (error) => error.sourceOperation,
              'source operation',
              'auto-director-proposal',
            )
            .having((error) => error.documentRevision, 'revision', 42),
      ),
    );
  });

  test('editor retains last-good timeline after a typed compile failure', () {
    var shouldFail = false;
    final cubit = EditorCubit(
      timelineCompiler: (document, revision) {
        if (shouldFail) {
          throw InvalidTimelineIntervalException(
            intervalType: 'camera-shot',
            entityId: 'shot-invalid',
            start: TimelineTime.fromMicroseconds(2),
            end: TimelineTime.fromMicroseconds(1),
            sourceOperation: 'camera-compile',
            documentRevision: revision,
          );
        }
        return CompiledTimeline(
          dependencyKey: TimelineDependencyKey(
            projectId: document.id,
            documentRevision: revision,
          ),
          duration: TimelineDuration.zero,
          contentEnd: TimelineTime.zero,
          drawing: null,
          camera: null,
          audio: const [],
          voiceGuide: null,
          sceneMarkers: const [],
        );
      },
    );
    addTearDown(cubit.close);

    final lastGood = cubit.compileTimeline();
    shouldFail = true;
    cubit.setExportFrameRate(24);

    expect(identical(cubit.compileTimeline(), lastGood), isTrue);
    expect(cubit.lastTimelineCompilationFailure, isNotNull);
    expect(cubit.lastTimelineCompilationFailure!.entityId, 'shot-invalid');
    expect(
      cubit.lastTimelineCompilationFailure!.documentRevision,
      cubit.state.documentRevision.value,
    );
  });
}
