import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum AutoDirectorPlanStatus {
  completed,
  completedWithWarnings,
  cancelled,
  invalid,
}

enum AutoDirectorProgressStage {
  preparing,
  analyzing,
  generatingCandidates,
  optimizing,
  validating,
  completed,
}

enum AutoDirectorScopeKind {
  entireProject,
  scene,
  selectedSections,
  selectedTimeRange,
  affectedRange,
}

enum DirectorReasonCode {
  fitContent,
  contextualView,
  sceneView,
  overview,
  heldDueToDeadZone,
  readabilityFallback,
  protectedConstraint,
  cutNoLeadTime,
  movedBeforeDrawing,
  largeJumpOverview,
  largeJumpCut,
  conservativeUnknownHand,
  budgetFallback,
}

enum AutoCameraTimelineExtensionPolicy {
  preserveBaseDuration,
  allowExplicitExtension,
}

final class AutoDirectorConfiguration {
  AutoDirectorConfiguration({
    this.minimumViewportWidth = .08,
    this.maximumViewportWidth = 2.5,
    this.safePaddingFraction = .12,
    this.innerSafeFraction = .70,
    this.maximumDeadZoneCenterDelta = .08,
    this.maximumDeadZoneLogZoomDelta = .12,
    this.minimumMeaningfulPan = .04,
    this.minimumMeaningfulLogZoom = .08,
    this.minimumHold = const Duration(milliseconds: 650),
    this.preferredMoveDuration = const Duration(milliseconds: 450),
    this.movementWindow = const Duration(seconds: 4),
    this.maximumMovementsPerWindow = 3,
    this.maximumMovesPerTenSeconds = 6,
    this.maximumNormalizedPanSpeed = 1.5,
    this.maximumLogZoomSpeed = 1.2,
    this.maximumDirectionReversals = 4,
    this.minimumTextScreenFraction = .12,
    this.maximumCandidatesPerEvent = 5,
    this.lookAheadEvents = 3,
    this.maximumAttentionEvents = 5000,
    this.maximumPlanningTime = const Duration(seconds: 3),
    this.allowFade = true,
    this.allowMovementTransitions = true,
    this.allowMovementDuringDrawing = false,
    this.preferFadeForCuts = false,
    this.allowOverview = true,
    this.overviewPreference = 0,
    this.handSafeFraming = true,
    this.timelineExtensionPolicy =
        AutoCameraTimelineExtensionPolicy.preserveBaseDuration,
  }) {
    if (!minimumViewportWidth.isFinite ||
        minimumViewportWidth <= 0 ||
        !maximumViewportWidth.isFinite ||
        maximumViewportWidth < minimumViewportWidth ||
        safePaddingFraction < 0 ||
        safePaddingFraction >= .5 ||
        innerSafeFraction <= 0 ||
        innerSafeFraction > 1 ||
        maximumCandidatesPerEvent < 1 ||
        maximumCandidatesPerEvent > 12 ||
        lookAheadEvents < 1 ||
        lookAheadEvents > 8 ||
        maximumAttentionEvents < 1 ||
        maximumMovementsPerWindow < 1 ||
        maximumMovesPerTenSeconds < 1 ||
        !maximumNormalizedPanSpeed.isFinite ||
        maximumNormalizedPanSpeed <= 0 ||
        !maximumLogZoomSpeed.isFinite ||
        maximumLogZoomSpeed <= 0 ||
        maximumDirectionReversals < 0 ||
        minimumTextScreenFraction <= 0 ||
        minimumTextScreenFraction > 1 ||
        !overviewPreference.isFinite ||
        overviewPreference < 0 ||
        maximumPlanningTime <= Duration.zero) {
      throw ArgumentError('Invalid Auto Director configuration.');
    }
  }
  final double minimumViewportWidth;
  final double maximumViewportWidth;
  final double safePaddingFraction;
  final double innerSafeFraction;
  final double maximumDeadZoneCenterDelta;
  final double maximumDeadZoneLogZoomDelta;
  final double minimumMeaningfulPan;
  final double minimumMeaningfulLogZoom;
  final Duration minimumHold;
  final Duration preferredMoveDuration;
  final Duration movementWindow;
  final int maximumMovementsPerWindow;
  final int maximumMovesPerTenSeconds;
  final double maximumNormalizedPanSpeed;
  final double maximumLogZoomSpeed;
  final int maximumDirectionReversals;
  final double minimumTextScreenFraction;
  final int maximumCandidatesPerEvent;
  final int lookAheadEvents;
  final int maximumAttentionEvents;
  final Duration maximumPlanningTime;
  final bool allowFade;
  final bool allowMovementTransitions;
  final bool allowMovementDuringDrawing;
  final bool preferFadeForCuts;
  final bool allowOverview;
  final double overviewPreference;
  final bool handSafeFraming;
  final AutoCameraTimelineExtensionPolicy timelineExtensionPolicy;
}

final class AutoDirectorScope {
  AutoDirectorScope.entireProject()
    : kind = AutoDirectorScopeKind.entireProject,
      sceneId = null,
      sectionIds = const {},
      interval = null;
  AutoDirectorScope.scene(this.sceneId)
    : kind = AutoDirectorScopeKind.scene,
      sectionIds = const {},
      interval = null;
  AutoDirectorScope.selectedSections(Set<SectionId> ids)
    : kind = AutoDirectorScopeKind.selectedSections,
      sectionIds = Set.unmodifiable(ids),
      sceneId = null,
      interval = null;
  AutoDirectorScope.affectedRange(this.interval)
    : kind = AutoDirectorScopeKind.affectedRange,
      sectionIds = const {},
      sceneId = null;
  AutoDirectorScope.selectedTimeRange(this.interval)
    : kind = AutoDirectorScopeKind.selectedTimeRange,
      sectionIds = const {},
      sceneId = null;
  final AutoDirectorScopeKind kind;
  final SceneId? sceneId;
  final Set<SectionId> sectionIds;
  final TimelineInterval? interval;
  String get stableKey => switch (kind) {
    AutoDirectorScopeKind.entireProject => 'all',
    AutoDirectorScopeKind.scene => 'scene:${sceneId!.value}',
    AutoDirectorScopeKind.selectedSections =>
      'sections:${(sectionIds.map((id) => id.value).toList()..sort()).join(',')}',
    AutoDirectorScopeKind.affectedRange =>
      'range:${interval!.start.microseconds}-${interval!.end.microseconds}',
    AutoDirectorScopeKind.selectedTimeRange =>
      'selected-range:${interval!.start.microseconds}-${interval!.end.microseconds}',
  };
}

final class DirectorScoreComponents {
  const DirectorScoreComponents({
    required this.readabilityScore,
    required this.contextScore,
    required this.motionCost,
    required this.occlusionPenalty,
    required this.reversalPenalty,
    required this.cutPenalty,
    required this.movementFrequencyPenalty,
    required this.constraintPenalty,
  });
  final double readabilityScore;
  final double contextScore;
  final double motionCost;
  final double occlusionPenalty;
  final double reversalPenalty;
  final double cutPenalty;
  final double movementFrequencyPenalty;
  final double constraintPenalty;
  double get total =>
      readabilityScore +
      contextScore -
      motionCost -
      occlusionPenalty -
      reversalPenalty -
      cutPenalty -
      movementFrequencyPenalty -
      constraintPenalty;
}

final class ProposedCameraKeyframe {
  const ProposedCameraKeyframe({
    required this.offset,
    required this.view,
    required this.incomingTransition,
  });
  final TimelineTime offset;
  final CameraView view;
  final CameraTransition incomingTransition;
}

final class ProposedCameraShot {
  ProposedCameraShot({
    required this.planId,
    required List<String> targetRegionIds,
    required this.interval,
    required List<ProposedCameraKeyframe> keyframes,
    required this.reasonCodes,
    required this.score,
    required List<String> constraints,
  }) : targetRegionIds = List.unmodifiable(targetRegionIds),
       keyframes = List.unmodifiable(keyframes),
       constraints = List.unmodifiable(constraints);
  final String planId;
  final List<String> targetRegionIds;
  final TimelineInterval interval;
  final List<ProposedCameraKeyframe> keyframes;
  CameraAuthorship get authorship => CameraAuthorship.auto;
  final Set<DirectorReasonCode> reasonCodes;
  final DirectorScoreComponents score;
  final List<String> constraints;
}

final class AutoDirectorDiagnostic {
  const AutoDirectorDiagnostic(this.code, this.message, {this.planShotId});
  final String code;
  final String message;
  final String? planShotId;
}

final class AutoDirectorQualityMetrics {
  const AutoDirectorQualityMetrics({
    required this.shotCount,
    required this.keyframeCount,
    required this.moveCount,
    required this.cutCount,
    required this.fadeCount,
    required this.holdCount,
    required this.movementsPerTenSeconds,
    required this.averageHold,
    required this.maximumNormalizedPanSpeed,
    required this.maximumLogZoomSpeed,
    required this.directionReversals,
    required this.uncoveredAttentionEvents,
    required this.textReadabilityWarnings,
    required this.handOcclusionWarnings,
    required this.preservedManualOrLockedCount,
  });
  final int shotCount,
      keyframeCount,
      moveCount,
      cutCount,
      fadeCount,
      holdCount,
      movementsPerTenSeconds,
      directionReversals,
      uncoveredAttentionEvents,
      textReadabilityWarnings,
      handOcclusionWarnings,
      preservedManualOrLockedCount;
  final TimelineDuration averageHold;
  final double maximumNormalizedPanSpeed, maximumLogZoomSpeed;
}

final class AutoDirectorPlan {
  AutoDirectorPlan({
    required this.inputDependencyKey,
    required this.configuration,
    required this.scope,
    required List<ProposedCameraShot> proposedShots,
    required List<CameraShot> preservedShots,
    required List<CameraShotId> removedAutoShotIds,
    required List<AutoDirectorDiagnostic> diagnostics,
    required List<AutoDirectorDiagnostic> warnings,
    required this.qualityMetrics,
    required this.status,
  }) : proposedShots = List.unmodifiable(proposedShots),
       preservedShots = List.unmodifiable(preservedShots),
       removedAutoShotIds = List.unmodifiable(removedAutoShotIds),
       diagnostics = List.unmodifiable(diagnostics),
       warnings = List.unmodifiable(warnings);
  final String inputDependencyKey;
  final AutoDirectorConfiguration configuration;
  final AutoDirectorScope scope;
  final List<ProposedCameraShot> proposedShots;
  final List<CameraShot> preservedShots;
  final List<CameraShotId> removedAutoShotIds;
  final List<AutoDirectorDiagnostic> diagnostics;
  final List<AutoDirectorDiagnostic> warnings;
  final AutoDirectorQualityMetrics qualityMetrics;
  final AutoDirectorPlanStatus status;
}

abstract interface class AutoDirectorCancellation {
  bool get isCancelled;
}

typedef AutoDirectorProgress =
    void Function(AutoDirectorProgressStage stage, double fraction);

final class AutoDirectorCancelledException implements Exception {
  const AutoDirectorCancelledException();
}
