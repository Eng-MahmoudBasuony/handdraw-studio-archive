import 'dart:async';
import 'dart:isolate';

import 'package:handdraw_studio/features/auto_director/application/auto_director_worker.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/timeline_compiler.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_drawing_timeline_compiler_adapter.dart';

enum AutoDirectorApplyFailureCode {
  stalePlan,
  cancelled,
  invalidPlan,
  protectedShotConflict,
  allocationFailed,
}

final class AutoDirectorApplyResult {
  const AutoDirectorApplyResult.success(this.operation)
    : failureCode = null,
      message = null;
  const AutoDirectorApplyResult.failure(this.failureCode, this.message)
    : operation = null;
  final DocumentOperationResult? operation;
  final AutoDirectorApplyFailureCode? failureCode;
  final String? message;
  bool get isSuccess => operation != null;
}

final class AutoDirectorPreviewSnapshot {
  AutoDirectorPreviewSnapshot(this.plan);
  final AutoDirectorPlan plan;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  void dispose() => _disposed = true;
}

/// Application boundary. It owns session cancellation and persistent ID
/// allocation; the pure planner remains unaware of document transactions.
class AutoDirectorApplicationService {
  AutoDirectorApplicationService({
    this.director = const SmartAutoDirector(),
    this.inputBuilder = const DirectorInputBuilder(),
  });

  final SmartAutoDirector director;
  final DirectorInputBuilder inputBuilder;
  int _session = 0;
  _MutableCancellation? _activeCancellation;
  _ActiveWorker? _activeWorker;

  AutoDirectorPlan generatePlan({
    required CompiledTimeline timeline,
    required CompiledSemanticRegionGraph graph,
    required ProjectCameraTrack? cameraTrack,
    AutoDirectorConfiguration? configuration,
    AutoDirectorScope? scope,
    AutoDirectorProgress? onProgress,
  }) {
    cancel();
    final session = ++_session;
    final cancellation = _MutableCancellation();
    _activeCancellation = cancellation;
    final result = director.generate(
      timeline: timeline,
      graph: graph,
      cameraTrack: cameraTrack,
      configuration: configuration,
      scope: scope,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    if (session != _session || cancellation.isCancelled) {
      throw const AutoDirectorCancelledException();
    }
    _activeCancellation = null;
    return result;
  }

  /// Production execution boundary: planning runs away from the UI isolate.
  /// Session changes invalidate late results before they can be previewed.
  Future<AutoDirectorPlan> generatePlanAsync({
    required CompiledTimeline timeline,
    required CompiledSemanticRegionGraph graph,
    required ProjectCameraTrack? cameraTrack,
    AutoDirectorConfiguration? configuration,
    AutoDirectorScope? scope,
    AutoDirectorProgress? onProgress,
  }) async {
    cancel();
    final session = ++_session;
    final cancellation = _MutableCancellation();
    _activeCancellation = cancellation;
    final effectiveConfiguration = configuration ?? AutoDirectorConfiguration();
    final effectiveScope = scope ?? AutoDirectorScope.entireProject();
    final output = ReceivePort();
    final completer = Completer<AutoDirectorPlan>();
    final worker = _ActiveWorker(output, completer);
    final outcome = Future.any<AutoDirectorPlan>([
      completer.future,
      worker.cancelled.future.then<AutoDirectorPlan>(
        (_) => throw const AutoDirectorCancelledException(),
      ),
    ]);
    // Cancellation may win while Isolate.spawn is still pending. Attach an
    // error handler now; the same future is awaited after spawn completes.
    outcome.ignore();
    _activeWorker = worker;
    output.listen((message) {
      if (message is! AutoDirectorWorkerMessage ||
          message.sessionId != session ||
          session != _session ||
          cancellation.isCancelled) {
        return;
      }
      switch (message) {
        case AutoDirectorWorkerProgress(:final stage, :final fraction):
          onProgress?.call(stage, fraction);
        case AutoDirectorWorkerSuccess(:final plan):
          if (!completer.isCompleted) completer.complete(plan);
        case AutoDirectorWorkerFailure(:final error, :final stackTrace):
          if (!completer.isCompleted) {
            completer.completeError(
              AutoDirectorWorkerException(error, stackTrace),
            );
          }
      }
    });
    try {
      worker.isolate = await Isolate.spawn<AutoDirectorWorkerBootstrap>(
        autoDirectorWorkerMain,
        AutoDirectorWorkerBootstrap(
          AutoDirectorWorkerRequest(
            sessionId: session,
            timeline: timeline,
            graph: graph,
            cameraTrack: cameraTrack,
            configuration: effectiveConfiguration,
            scope: effectiveScope,
          ),
          output.sendPort,
        ),
      );
      final result = await outcome;
      if (session != _session || cancellation.isCancelled) {
        throw const AutoDirectorCancelledException();
      }
      return result;
    } finally {
      worker.dispose();
      if (identical(_activeWorker, worker)) _activeWorker = null;
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
    }
  }

  AutoDirectorPreviewSnapshot previewPlan(AutoDirectorPlan plan) =>
      AutoDirectorPreviewSnapshot(plan);

  /// Builds a disposable runtime timeline. Its ephemeral IDs never enter the
  /// document, history, manifest, or UI allocation path.
  CompiledTimeline compilePreviewTimeline({
    required AutoDirectorPlan plan,
    required ProjectDocument currentDocument,
    required CompiledTimeline currentTimeline,
    required CompiledSemanticRegionGraph currentGraph,
    required int documentRevision,
  }) {
    final applied = applyPlan(
      plan: plan,
      currentDocument: currentDocument,
      currentTimeline: currentTimeline,
      currentGraph: currentGraph,
      allocation: IdAllocationContext(generator: SecureRandomIdGenerator()),
    );
    if (!applied.isSuccess) {
      throw StateError(applied.message ?? 'Preview plan is invalid.');
    }
    return const TimelineCompiler(
      drawingAdapter: LegacyDrawingTimelineCompilerAdapter(),
    ).compile(
      document: applied.operation!.document,
      documentRevision: documentRevision,
    );
  }

  AutoDirectorApplyResult applyPlan({
    required AutoDirectorPlan plan,
    required ProjectDocument currentDocument,
    required CompiledTimeline currentTimeline,
    required CompiledSemanticRegionGraph currentGraph,
    required IdAllocationContext allocation,
  }) {
    if (plan.status == AutoDirectorPlanStatus.cancelled ||
        plan.status == AutoDirectorPlanStatus.invalid) {
      return const AutoDirectorApplyResult.failure(
        AutoDirectorApplyFailureCode.invalidPlan,
        'Cancelled or invalid plans cannot be applied.',
      );
    }
    final currentKey = inputBuilder.dependencyKey(
      timeline: currentTimeline,
      graph: currentGraph,
      cameraTrack: currentDocument.cameraTrack,
      configuration: plan.configuration,
      scope: plan.scope,
    );
    if (currentKey != plan.inputDependencyKey) {
      return const AutoDirectorApplyResult.failure(
        AutoDirectorApplyFailureCode.stalePlan,
        'The director inputs changed after this plan was generated.',
      );
    }
    final currentProtected =
        currentDocument.cameraTrack?.shots
            .where(
              (shot) =>
                  shot.authorship == CameraAuthorship.manual || shot.isLocked,
            )
            .toList() ??
        const <CameraShot>[];
    final currentInput = inputBuilder.build(
      timeline: currentTimeline,
      graph: currentGraph,
      cameraTrack: currentDocument.cameraTrack,
      configuration: plan.configuration,
      scope: plan.scope,
    );
    final invariantFailures = director.validator.validate(
      currentInput,
      plan.proposedShots,
      currentProtected,
    );
    if (invariantFailures.isNotEmpty) {
      return AutoDirectorApplyResult.failure(
        AutoDirectorApplyFailureCode.invalidPlan,
        'Plan validation failed before transaction: '
        '${invariantFailures.map((failure) => failure.code).join(', ')}',
      );
    }
    if (!_sameProtected(
      currentProtected,
      plan.preservedShots
          .where(
            (shot) =>
                shot.authorship == CameraAuthorship.manual || shot.isLocked,
          )
          .toList(),
    )) {
      return const AutoDirectorApplyResult.failure(
        AutoDirectorApplyFailureCode.protectedShotConflict,
        'Manual or locked camera shots changed and were not modified.',
      );
    }
    try {
      final trackId =
          currentDocument.cameraTrack?.id ?? allocation.cameraTrackId();
      final proposed = <CameraShot>[];
      for (final value in plan.proposedShots) {
        final shotId = allocation.cameraShotId();
        proposed.add(
          CameraShot(
            id: shotId,
            startTime: value.interval.start,
            duration: value.interval.duration,
            authorship: CameraAuthorship.auto,
            isLocked: false,
            label: value.reasonCodes.map((reason) => reason.name).join(', '),
            keyframes: [
              for (final keyframe in value.keyframes)
                CameraKeyframe(
                  id: allocation.cameraKeyframeId(),
                  offset: keyframe.offset,
                  view: keyframe.view,
                  // A shot begins at its resolved view. Scheduling diagnostics
                  // retain the pre-arrival transition without violating the
                  // persistent first-keyframe-at-zero contract.
                  incomingTransition: keyframe.offset == TimelineTime.zero
                      ? const CameraTransition()
                      : keyframe.incomingTransition,
                ),
            ],
          ),
        );
      }
      final shots = [...plan.preservedShots, ...proposed]
        ..sort((a, b) {
          final time = a.startTime.compareTo(b.startTime);
          return time != 0 ? time : a.id.value.compareTo(b.id.value);
        });
      final track = ProjectCameraTrack(
        id: trackId,
        enabled: currentDocument.cameraTrack?.enabled ?? true,
        defaultView:
            currentDocument.cameraTrack?.defaultView ??
            const CameraView.identity(),
        shots: shots,
      );
      final candidate = currentDocument.copyWith(
        cameraTrack: track,
        timeline: currentDocument.timeline.copyWith(
          camera: PersistentCameraTimelineTrack.enabled(cameraTrackId: trackId),
        ),
      );
      return AutoDirectorApplyResult.success(
        DocumentOperationResult.success(
          document: candidate,
          affectedScopes: const {DocumentScope.camera},
          summary: DocumentChangeSummary(
            action: 'camera.autoDirector.apply',
            entityIds: [
              trackId.value,
              ...proposed.map((shot) => shot.id.value),
            ],
            changeCount: proposed.length + plan.removedAutoShotIds.length,
          ),
        ),
      );
    } on Object {
      return const AutoDirectorApplyResult.failure(
        AutoDirectorApplyFailureCode.allocationFailed,
        'Camera IDs could not be allocated; the document was not changed.',
      );
    }
  }

  void cancel() {
    _activeCancellation?.cancel();
    _activeCancellation = null;
    _activeWorker?.cancel();
    _activeWorker = null;
    _session++;
  }
}

final class _ActiveWorker {
  _ActiveWorker(this.output, this.completer);
  final ReceivePort output;
  final Completer<AutoDirectorPlan> completer;
  final Completer<void> cancelled = Completer<void>();
  Isolate? isolate;
  bool _disposed = false;

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    isolate?.kill(priority: Isolate.immediate);
    output.close();
  }
}

final class _MutableCancellation implements AutoDirectorCancellation {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  @override
  bool get isCancelled => _cancelled;
}

bool _sameProtected(List<CameraShot> left, List<CameraShot> right) {
  if (left.length != right.length) return false;
  final a = [...left]..sort((x, y) => x.id.value.compareTo(y.id.value));
  final b = [...right]..sort((x, y) => x.id.value.compareTo(y.id.value));
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
