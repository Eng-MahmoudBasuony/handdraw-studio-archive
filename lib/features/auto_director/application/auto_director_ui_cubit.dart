import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_application_service.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_ui_state.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';

final class AutoDirectorUiCubit extends Cubit<AutoDirectorUiState> {
  AutoDirectorUiCubit({
    required ProjectAutoDirectorSettings initialSettings,
    AutoDirectorApplicationService? service,
  }) : _service = service ?? AutoDirectorApplicationService(),
       super(AutoDirectorUiState(settings: initialSettings));

  final AutoDirectorApplicationService _service;
  int _session = 0;

  void selectPreset(AutoDirectorPresetId id) {
    emit(
      state.copyWith(
        settings: ProjectAutoDirectorSettings(
          presetId: id,
          presetVersion: AutoDirectorPresetCatalog.currentVersion,
        ),
        plan: null,
        phase: AutoDirectorUiPhase.idle,
      ),
    );
  }

  void setCustomOverrides(AutoDirectorCustomOverrides overrides) => emit(
    state.copyWith(
      settings: ProjectAutoDirectorSettings(
        presetId: AutoDirectorPresetId.custom,
        presetVersion: AutoDirectorPresetCatalog.currentVersion,
        customOverrides: overrides,
      ),
      plan: null,
      phase: AutoDirectorUiPhase.idle,
    ),
  );

  void setScope(AutoDirectorScope scope) => emit(
    state.copyWith(scope: scope, plan: null, phase: AutoDirectorUiPhase.idle),
  );

  void toggleAdvanced() =>
      emit(state.copyWith(advancedVisible: !state.advancedVisible));

  void showPlan(AutoDirectorPlanView value) =>
      emit(state.copyWith(planView: value));

  Future<void> generate({
    required CompiledTimeline timeline,
    required CompiledSemanticRegionGraph graph,
    required ProjectCameraTrack? cameraTrack,
  }) async {
    final scope = state.scope ?? AutoDirectorScope.entireProject();
    final session = ++_session;
    emit(
      state.copyWith(
        phase: AutoDirectorUiPhase.preparing,
        scope: scope,
        plan: null,
        progress: 0,
        progressUpdateCount: 1,
        errorMessage: null,
        technicalDetails: null,
      ),
    );
    try {
      final plan = await _service.generatePlanAsync(
        timeline: timeline,
        graph: graph,
        cameraTrack: cameraTrack,
        configuration: const AutoDirectorPresetMapper().configuration(
          state.settings,
        ),
        scope: scope,
        onProgress: (stage, fraction) {
          if (session != _session || isClosed) return;
          emit(
            state.copyWith(
              phase: _phase(stage),
              progress: fraction,
              progressUpdateCount: state.progressUpdateCount + 1,
            ),
          );
        },
      );
      if (session != _session || isClosed) return;
      emit(
        state.copyWith(
          phase: AutoDirectorUiPhase.ready,
          plan: plan,
          progress: 1,
          planView: AutoDirectorPlanView.proposed,
        ),
      );
    } on AutoDirectorCancelledException {
      if (session == _session && !isClosed) {
        emit(state.copyWith(phase: AutoDirectorUiPhase.cancelled, plan: null));
      }
    } on Object catch (error, stackTrace) {
      developer.log(
        'Auto Camera generation failed',
        name: 'handdraw.auto_director',
        error: error,
        stackTrace: stackTrace,
      );
      if (session == _session && !isClosed) {
        emit(
          state.copyWith(
            phase: AutoDirectorUiPhase.failed,
            plan: null,
            errorMessage: 'auto_director_generation_failed',
            technicalDetails: '$error\n$stackTrace',
          ),
        );
      }
    }
  }

  void cancel() {
    _session++;
    _service.cancel();
    emit(state.copyWith(phase: AutoDirectorUiPhase.cancelled, plan: null));
  }

  void markStale() {
    if (state.isGenerating) {
      _session++;
      _service.cancel();
      emit(
        state.copyWith(
          phase: AutoDirectorUiPhase.stale,
          plan: null,
          progress: 0,
        ),
      );
    } else if (state.plan != null) {
      emit(state.copyWith(phase: AutoDirectorUiPhase.stale));
    }
  }

  Future<bool> apply(
    FutureOr<AutoDirectorApplyResult> Function(AutoDirectorPlan plan) action,
  ) async {
    final plan = state.plan;
    if (plan == null || state.phase != AutoDirectorUiPhase.ready) return false;
    emit(state.copyWith(phase: AutoDirectorUiPhase.applying));
    final result = await action(plan);
    if (result.isSuccess) {
      emit(
        state.copyWith(
          phase: AutoDirectorUiPhase.completed,
          plan: null,
          progress: 1,
        ),
      );
      return true;
    }
    emit(
      state.copyWith(
        phase: result.failureCode == AutoDirectorApplyFailureCode.stalePlan
            ? AutoDirectorUiPhase.stale
            : AutoDirectorUiPhase.failed,
        errorMessage: result.message,
      ),
    );
    return false;
  }

  static AutoDirectorUiPhase _phase(AutoDirectorProgressStage stage) =>
      switch (stage) {
        AutoDirectorProgressStage.preparing => AutoDirectorUiPhase.preparing,
        AutoDirectorProgressStage.analyzing => AutoDirectorUiPhase.analyzing,
        AutoDirectorProgressStage.generatingCandidates =>
          AutoDirectorUiPhase.generatingCandidates,
        AutoDirectorProgressStage.optimizing => AutoDirectorUiPhase.optimizing,
        AutoDirectorProgressStage.validating => AutoDirectorUiPhase.validating,
        AutoDirectorProgressStage.completed => AutoDirectorUiPhase.ready,
      };

  @override
  Future<void> close() {
    _service.cancel();
    return super.close();
  }
}
