import 'dart:isolate';

import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';

/// Complete, immutable and isolate-safe input boundary for planning.
/// Runtime images, Flutter state and callbacks never cross this boundary.
final class AutoDirectorWorkerRequest {
  const AutoDirectorWorkerRequest({
    required this.sessionId,
    required this.timeline,
    required this.graph,
    required this.cameraTrack,
    required this.configuration,
    required this.scope,
  });

  final int sessionId;
  final CompiledTimeline timeline;
  final CompiledSemanticRegionGraph graph;
  final ProjectCameraTrack? cameraTrack;
  final AutoDirectorConfiguration configuration;
  final AutoDirectorScope scope;
}

final class AutoDirectorWorkerBootstrap {
  const AutoDirectorWorkerBootstrap(this.request, this.output);
  final AutoDirectorWorkerRequest request;
  final SendPort output;
}

sealed class AutoDirectorWorkerMessage {
  const AutoDirectorWorkerMessage(this.sessionId);
  final int sessionId;
}

final class AutoDirectorWorkerProgress extends AutoDirectorWorkerMessage {
  const AutoDirectorWorkerProgress(super.sessionId, this.stage, this.fraction);
  final AutoDirectorProgressStage stage;
  final double fraction;
}

final class AutoDirectorWorkerSuccess extends AutoDirectorWorkerMessage {
  const AutoDirectorWorkerSuccess(super.sessionId, this.plan);
  final AutoDirectorPlan plan;
}

final class AutoDirectorWorkerFailure extends AutoDirectorWorkerMessage {
  const AutoDirectorWorkerFailure(super.sessionId, this.error, this.stackTrace);
  final String error;
  final String stackTrace;
}

/// Top-level entrypoint: deliberately cannot capture Cubits, widgets or UI.
void autoDirectorWorkerMain(AutoDirectorWorkerBootstrap bootstrap) {
  final request = bootstrap.request;
  try {
    final plan = const SmartAutoDirector().generate(
      timeline: request.timeline,
      graph: request.graph,
      cameraTrack: request.cameraTrack,
      configuration: request.configuration,
      scope: request.scope,
      onProgress: (stage, fraction) => bootstrap.output.send(
        AutoDirectorWorkerProgress(request.sessionId, stage, fraction),
      ),
    );
    bootstrap.output.send(AutoDirectorWorkerSuccess(request.sessionId, plan));
  } on Object catch (error, stackTrace) {
    bootstrap.output.send(
      AutoDirectorWorkerFailure(
        request.sessionId,
        error.toString(),
        stackTrace.toString(),
      ),
    );
  }
}

final class AutoDirectorWorkerException implements Exception {
  const AutoDirectorWorkerException(this.message, this.stackTrace);
  final String message;
  final String stackTrace;

  @override
  String toString() => message;
}
