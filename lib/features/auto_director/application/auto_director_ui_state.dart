import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';

enum AutoDirectorUiPhase {
  idle,
  preparing,
  analyzing,
  generatingCandidates,
  optimizing,
  validating,
  ready,
  applying,
  completed,
  cancelled,
  failed,
  stale,
}

enum AutoDirectorPlanView { current, proposed }

final class AutoDirectorUiState {
  const AutoDirectorUiState({
    this.phase = AutoDirectorUiPhase.idle,
    this.settings = const ProjectAutoDirectorSettings(),
    this.scope,
    this.plan,
    this.progress = 0,
    this.progressUpdateCount = 0,
    this.planView = AutoDirectorPlanView.proposed,
    this.advancedVisible = false,
    this.errorMessage,
    this.technicalDetails,
  });

  final AutoDirectorUiPhase phase;
  final ProjectAutoDirectorSettings settings;
  final AutoDirectorScope? scope;
  final AutoDirectorPlan? plan;
  final double progress;
  final int progressUpdateCount;
  final AutoDirectorPlanView planView;
  final bool advancedVisible;
  final String? errorMessage;
  final String? technicalDetails;

  bool get isGenerating => switch (phase) {
    AutoDirectorUiPhase.preparing ||
    AutoDirectorUiPhase.analyzing ||
    AutoDirectorUiPhase.generatingCandidates ||
    AutoDirectorUiPhase.optimizing ||
    AutoDirectorUiPhase.validating => true,
    _ => false,
  };

  AutoDirectorUiState copyWith({
    AutoDirectorUiPhase? phase,
    ProjectAutoDirectorSettings? settings,
    AutoDirectorScope? scope,
    Object? plan = _unset,
    double? progress,
    int? progressUpdateCount,
    AutoDirectorPlanView? planView,
    bool? advancedVisible,
    Object? errorMessage = _unset,
    Object? technicalDetails = _unset,
  }) => AutoDirectorUiState(
    phase: phase ?? this.phase,
    settings: settings ?? this.settings,
    scope: scope ?? this.scope,
    plan: identical(plan, _unset) ? this.plan : plan as AutoDirectorPlan?,
    progress: progress ?? this.progress,
    progressUpdateCount: progressUpdateCount ?? this.progressUpdateCount,
    planView: planView ?? this.planView,
    advancedVisible: advancedVisible ?? this.advancedVisible,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    technicalDetails: identical(technicalDetails, _unset)
        ? this.technicalDetails
        : technicalDetails as String?,
  );
}

const _unset = Object();
