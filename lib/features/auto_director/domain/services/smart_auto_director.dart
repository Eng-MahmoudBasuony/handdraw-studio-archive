import 'dart:math' as math;

import 'package:handdraw_studio/features/auto_director/domain/services/projected_framing_validator.dart';

import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class DirectorInput {
  const DirectorInput({
    required this.timeline,
    required this.graph,
    required this.cameraTrack,
    required this.configuration,
    required this.scope,
    required this.dependencyKey,
  });
  final CompiledTimeline timeline;
  final CompiledSemanticRegionGraph graph;
  final ProjectCameraTrack? cameraTrack;
  final AutoDirectorConfiguration configuration;
  final AutoDirectorScope scope;
  final String dependencyKey;
}

final class DirectorInputBuilder {
  const DirectorInputBuilder();
  DirectorInput build({
    required CompiledTimeline timeline,
    required CompiledSemanticRegionGraph graph,
    required ProjectCameraTrack? cameraTrack,
    required AutoDirectorConfiguration configuration,
    required AutoDirectorScope scope,
  }) => DirectorInput(
    timeline: timeline,
    graph: graph,
    cameraTrack: cameraTrack,
    configuration: configuration,
    scope: scope,
    dependencyKey: dependencyKey(
      timeline: timeline,
      graph: graph,
      cameraTrack: cameraTrack,
      configuration: configuration,
      scope: scope,
    ),
  );

  String dependencyKey({
    required CompiledTimeline timeline,
    required CompiledSemanticRegionGraph graph,
    required ProjectCameraTrack? cameraTrack,
    required AutoDirectorConfiguration configuration,
    required AutoDirectorScope scope,
  }) {
    final buffer = StringBuffer(
      'semantic:${graph.dependencyKey};scope:${scope.stableKey};duration:${timeline.duration.microseconds};content:${timeline.contentEnd.microseconds};',
    );
    for (final section
        in timeline.drawing?.sections ?? const <CompiledDrawingSection>[]) {
      buffer.write(
        'drawing:${section.sectionId.value}:${section.interval.start.microseconds}:${section.interval.end.microseconds};',
      );
    }
    for (final shot in cameraTrack?.shots ?? const <CameraShot>[]) {
      buffer.write(
        'camera:${shot.id.value}:${shot.startTime.microseconds}:${shot.duration.microseconds}:${shot.authorship.name}:${shot.isLocked};',
      );
      for (final keyframe in shot.keyframes) {
        buffer.write(
          '${keyframe.offset.microseconds}:${keyframe.view.centerX}:${keyframe.view.centerY}:${keyframe.view.viewportWidth};',
        );
      }
    }
    if (cameraTrack case final track?) {
      buffer.write(
        'track:${track.enabled}:${track.defaultView.centerX}:${track.defaultView.centerY}:${track.defaultView.viewportWidth};',
      );
    }
    buffer.write(
      'config:${configuration.minimumViewportWidth}:${configuration.maximumViewportWidth}:${configuration.safePaddingFraction}:${configuration.innerSafeFraction}:${configuration.maximumDeadZoneCenterDelta}:${configuration.maximumDeadZoneLogZoomDelta}:${configuration.minimumMeaningfulPan}:${configuration.minimumMeaningfulLogZoom}:${configuration.minimumHold.inMicroseconds}:${configuration.preferredMoveDuration.inMicroseconds}:${configuration.maximumMovementsPerWindow}:${configuration.maximumMovesPerTenSeconds}:${configuration.maximumNormalizedPanSpeed}:${configuration.maximumLogZoomSpeed}:${configuration.maximumDirectionReversals}:${configuration.minimumTextScreenFraction}:${configuration.maximumCandidatesPerEvent}:${configuration.lookAheadEvents}:${configuration.allowFade}:${configuration.allowMovementTransitions}:${configuration.allowMovementDuringDrawing}:${configuration.preferFadeForCuts}:${configuration.allowOverview}:${configuration.overviewPreference}:${configuration.handSafeFraming}:${configuration.timelineExtensionPolicy.name};',
    );
    return _hash(buffer.toString());
  }
}

final class DirectorAttention {
  const DirectorAttention({
    required this.event,
    required this.region,
    required this.order,
  });
  final SemanticAttentionEvent event;
  final SemanticRegion region;
  final int order;
}

final class AttentionSequenceBuilder {
  const AttentionSequenceBuilder();
  List<DirectorAttention> build(DirectorInput input) {
    final regions = {
      for (final region in input.graph.regions) region.id: region,
    };
    final result = <DirectorAttention>[];
    for (var i = 0; i < input.graph.attentionEvents.length; i++) {
      final event = input.graph.attentionEvents[i];
      final region = event.regionIds
          .map((id) => regions[id])
          .whereType<SemanticRegion>()
          .where((value) => value.target.kind.name == 'stroke')
          .firstOrNull;
      if (region == null ||
          region.metadata?.cameraExcluded == true ||
          !_inScope(event, input.scope)) {
        continue;
      }
      result.add(DirectorAttention(event: event, region: region, order: i));
    }
    result.sort((a, b) {
      final time = a.event.time.compareTo(b.event.time);
      if (time != 0) return time;
      final order = a.order.compareTo(b.order);
      if (order != 0) return order;
      final importance =
          (b.region.metadata?.importance.index ??
                  SemanticImportance.normal.index)
              .compareTo(
                a.region.metadata?.importance.index ??
                    SemanticImportance.normal.index,
              );
      if (importance != 0) return importance;
      if (a.region.direction == KnownTextDirection.rtl &&
          b.region.direction == KnownTextDirection.rtl) {
        return b.region.geometricBounds.left.compareTo(
          a.region.geometricBounds.left,
        );
      }
      if (a.region.direction == KnownTextDirection.ltr &&
          b.region.direction == KnownTextDirection.ltr) {
        return a.region.geometricBounds.left.compareTo(
          b.region.geometricBounds.left,
        );
      }
      return a.region.id.compareTo(b.region.id);
    });
    return List.unmodifiable(result);
  }
}

final class DirectorCluster {
  DirectorCluster(List<DirectorAttention> values)
    : attentions = List.unmodifiable(values);
  final List<DirectorAttention> attentions;
  SemanticWorldBounds get bounds => attentions
      .skip(1)
      .fold(
        attentions.first.region.visualBounds,
        (value, item) => value.union(item.region.visualBounds),
      );
  List<String> get regionIds =>
      List.unmodifiable(attentions.map((value) => value.region.id));
}

final class RegionClusterer {
  const RegionClusterer();
  List<DirectorCluster> cluster(
    DirectorInput input,
    List<DirectorAttention> sequence,
  ) {
    final result = <DirectorCluster>[];
    var index = 0;
    while (index < sequence.length) {
      final current = sequence[index];
      final values = <DirectorAttention>[current];
      while (index + 1 < sequence.length) {
        final next = sequence[index + 1];
        final nearTime =
            next.event.time.microseconds -
                values.last.event.time.microseconds <=
            input.configuration.minimumHold.inMicroseconds;
        final sameScene = next.event.sceneId == current.event.sceneId;
        final sameSection = next.event.sectionId == current.event.sectionId;
        final accumulatedBounds = values
            .skip(1)
            .fold(
              current.region.visualBounds,
              (bounds, attention) =>
                  bounds.union(attention.region.visualBounds),
            );
        final query = accumulatedBounds.inflate(
          math.max(input.graph.worldWidth, input.graph.worldHeight) * .08,
        );
        final spatiallyNear = input.graph.spatialIndex
            .intersections(query)
            .any((region) => region.id == next.region.id);
        final keep =
            current.region.metadata?.keepTogether == true ||
            next.region.metadata?.keepTogether == true;
        if (sameScene && sameSection && nearTime && (spatiallyNear || keep)) {
          final union = accumulatedBounds.union(next.region.visualBounds);
          final requiredWidth = union.right - union.left;
          final textMinimum = math.max(
            current.region.metadata?.minimumPreferredZoom?.value ?? 0,
            next.region.metadata?.minimumPreferredZoom?.value ?? 0,
          );
          final readable =
              textMinimum == 0 ||
              1 / math.max(requiredWidth / input.graph.worldWidth, .0001) >=
                  textMinimum;
          if (readable) {
            values.add(next);
            index++;
            continue;
          }
        }
        break;
      }
      result.add(DirectorCluster(values));
      index++;
    }
    return List.unmodifiable(result);
  }
}

/// Pure post-planning reduction. It removes camera churn without applying a
/// project-wide shot cap: only adjacent views in the same semantic section are
/// eligible, and text-sensitive unions must remain readable.
final class CameraPlanCompactor {
  const CameraPlanCompactor();

  List<ProposedCameraShot> compact(
    DirectorInput input,
    List<ProposedCameraShot> source,
  ) {
    if (source.length < 2) return List.unmodifiable(source);
    final regions = {
      for (final region in input.graph.regions) region.id: region,
    };
    final sectionByRegion = <String, Object?>{};
    for (final event in input.graph.attentionEvents) {
      for (final id in event.regionIds) {
        sectionByRegion[id] ??= event.sectionId;
      }
    }
    final result = <ProposedCameraShot>[];
    for (final shot in source) {
      if (result.isEmpty) {
        result.add(shot);
        continue;
      }
      final prior = result.last;
      final priorSections = prior.targetRegionIds
          .map((id) => sectionByRegion[id])
          .toSet();
      final nextSections = shot.targetRegionIds
          .map((id) => sectionByRegion[id])
          .toSet();
      final sameSection =
          priorSections.length == 1 &&
          nextSections.length == 1 &&
          priorSections.single != null &&
          priorSections.single == nextSections.single;
      final adjacent = prior.interval.end == shot.interval.start;
      final priorView = prior.keyframes.last.view;
      final nextView = shot.keyframes.last.view;
      final hasScheduledMovement =
          prior.keyframes.length > 1 || shot.keyframes.length > 1;
      final deadZone = _acceptable(priorView, nextView, input.configuration);
      final meaningless =
          (priorView.centerX - nextView.centerX).abs() <
              input.configuration.minimumMeaningfulPan &&
          (priorView.centerY - nextView.centerY).abs() <
              input.configuration.minimumMeaningfulPan &&
          (math.log(priorView.viewportWidth / nextView.viewportWidth)).abs() <
              input.configuration.minimumMeaningfulLogZoom;
      if (hasScheduledMovement ||
          !sameSection ||
          !adjacent ||
          (!deadZone && !meaningless)) {
        result.add(shot);
        continue;
      }
      final targetIds = <String>{
        ...prior.targetRegionIds,
        ...shot.targetRegionIds,
      }.toList();
      final targetRegions = targetIds
          .map((id) => regions[id])
          .whereType<SemanticRegion>()
          .toList();
      if (targetRegions.isEmpty) {
        result.add(shot);
        continue;
      }
      final union = targetRegions
          .skip(1)
          .fold(
            targetRegions.first.visualBounds,
            (bounds, region) => bounds.union(region.visualBounds),
          );
      final mergedView = _fit(
        input,
        union,
        input.configuration.safePaddingFraction,
      );
      final textReadable = targetRegions
          .where((region) => region.metadata?.textSensitive == true)
          .every(
            (region) =>
                mergedView.viewportWidth <=
                1 /
                    math.max(
                      region.metadata?.minimumPreferredZoom?.value ?? .0001,
                      .0001,
                    ),
          );
      if (!textReadable) {
        result.add(shot);
        continue;
      }
      result[result.length - 1] = ProposedCameraShot(
        planId: prior.planId,
        targetRegionIds: targetIds,
        interval: TimelineInterval(
          start: prior.interval.start,
          end: shot.interval.end,
        ),
        keyframes: [
          ProposedCameraKeyframe(
            offset: TimelineTime.zero,
            view: mergedView,
            incomingTransition: prior.keyframes.first.incomingTransition,
          ),
        ],
        reasonCodes: {...prior.reasonCodes, ...shot.reasonCodes},
        score: prior.score,
        constraints: {...prior.constraints, ...shot.constraints}.toList(),
      );
    }
    return List.unmodifiable(result);
  }
}

enum DirectorCandidateKind { fit, contextual, scene, overview, held }

final class DirectorCandidate {
  const DirectorCandidate({
    required this.kind,
    required this.view,
    required this.reasons,
  });
  final DirectorCandidateKind kind;
  final CameraView view;
  final Set<DirectorReasonCode> reasons;
}

final class CameraCandidateGenerator {
  const CameraCandidateGenerator();
  List<DirectorCandidate> generate(
    DirectorInput input,
    DirectorCluster cluster,
    CameraView current,
  ) {
    final config = input.configuration;
    final fit = _fit(input, cluster.bounds, config.safePaddingFraction);
    final values = <DirectorCandidate>[
      DirectorCandidate(
        kind: DirectorCandidateKind.fit,
        view: fit,
        reasons: const {DirectorReasonCode.fitContent},
      ),
      DirectorCandidate(
        kind: DirectorCandidateKind.contextual,
        view: CameraView(
          centerX: fit.centerX,
          centerY: fit.centerY,
          viewportWidth: math.min(
            config.maximumViewportWidth,
            fit.viewportWidth * 1.28,
          ),
        ),
        reasons: const {DirectorReasonCode.contextualView},
      ),
    ];
    final sceneId = cluster.attentions.first.event.sceneId;
    if (sceneId != null) {
      final scene = input.graph.regions
          .where((region) => region.id == 'scene:${sceneId.value}')
          .firstOrNull;
      if (scene != null) {
        values.add(
          DirectorCandidate(
            kind: DirectorCandidateKind.scene,
            view: _fit(input, scene.visualBounds, config.safePaddingFraction),
            reasons: const {DirectorReasonCode.sceneView},
          ),
        );
      }
    }
    if (_acceptable(current, fit, config)) {
      values.add(
        DirectorCandidate(
          kind: DirectorCandidateKind.held,
          view: current,
          reasons: const {DirectorReasonCode.heldDueToDeadZone},
        ),
      );
    }
    final largeJump =
        (current.centerX - fit.centerX).abs() > .55 ||
        (current.centerY - fit.centerY).abs() > .55;
    final hasSceneContext =
        sceneId != null &&
        input.graph.regions.any(
          (region) => region.id == 'scene:${sceneId.value}',
        );
    if (config.allowOverview && largeJump && hasSceneContext) {
      values.add(
        const DirectorCandidate(
          kind: DirectorCandidateKind.overview,
          view: CameraView.identity(),
          reasons: {
            DirectorReasonCode.overview,
            DirectorReasonCode.largeJumpOverview,
          },
        ),
      );
    }
    values.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return List.unmodifiable(values.take(config.maximumCandidatesPerEvent));
  }
}

final class CandidateScorer {
  const CandidateScorer();
  DirectorScoreComponents score(
    DirectorInput input,
    DirectorCluster cluster,
    DirectorCandidate candidate,
    CameraView current,
    double priorDirection,
    int recentMovements, {
    bool cutRequired = false,
  }) {
    final view = candidate.view;
    final target = _fit(
      input,
      cluster.bounds,
      input.configuration.safePaddingFraction,
    );
    final dx =
        (view.centerX - current.centerX) /
        math.max(current.viewportWidth, .001);
    final dy =
        (view.centerY - current.centerY) /
        math.max(current.viewportWidth, .001);
    final pan = math.sqrt(dx * dx + dy * dy);
    final logZoom = (math.log(
      view.viewportWidth / current.viewportWidth,
    )).abs();
    final direction = dx.sign;
    final reversal =
        priorDirection != 0 && direction != 0 && direction != priorDirection
        ? .8
        : 0.0;
    final text = cluster.attentions.any(
      (value) =>
          value.region.kind == SemanticRegionKind.text &&
          value.region.metadata?.textSensitive == true,
    );
    final containsTarget = (view.viewportWidth + .0001) >= target.viewportWidth;
    final minimumZoom = cluster.attentions
        .map((value) => value.region.metadata?.minimumPreferredZoom?.value ?? 0)
        .fold<double>(0, math.max);
    final zoom = 1 / view.viewportWidth;
    final textScreenFraction =
        math.max(
          (cluster.bounds.right - cluster.bounds.left) / input.graph.worldWidth,
          (cluster.bounds.bottom - cluster.bounds.top) /
              input.graph.worldHeight,
        ) /
        view.viewportWidth;
    final readability =
        containsTarget &&
            (minimumZoom == 0 || zoom >= minimumZoom) &&
            (!text ||
                textScreenFraction >=
                    input.configuration.minimumTextScreenFraction)
        ? (text ? 4.0 : 2.0)
        : -8.0;
    final unknownHand =
        input.graph.handFootprint.provenance == HandFootprintProvenance.unknown;
    final handScale = input.graph.handFootprint.screenScale ?? .30;
    final handWidth = handScale * .8;
    final penX = input.graph.handFootprint.penTipX ?? .5;
    final penY = input.graph.handFootprint.penTipY ?? .5;
    final targetScreenX =
        .5 +
        (cluster.bounds.centerX / input.graph.worldWidth - view.centerX) /
            view.viewportWidth;
    final targetScreenY =
        .5 +
        (cluster.bounds.centerY / input.graph.worldHeight - view.centerY) /
            view.viewportWidth;
    final handLeft = targetScreenX - penX * handWidth;
    final handRight = targetScreenX + (1 - penX) * handWidth;
    final handTop = targetScreenY - penY * handScale;
    final handBottom = targetScreenY + (1 - penY) * handScale;
    final inner = (1 - input.configuration.innerSafeFraction) / 2;
    final handOutsideSafe =
        handLeft < inner ||
        handTop < inner ||
        handRight > 1 - inner ||
        handBottom > 1 - inner;
    final targetWidth =
        (cluster.bounds.right - cluster.bounds.left) /
        input.graph.worldWidth /
        view.viewportWidth;
    final targetHeight =
        (cluster.bounds.bottom - cluster.bounds.top) /
        input.graph.worldHeight /
        view.viewportWidth;
    final targetLeft = targetScreenX - targetWidth / 2;
    final targetRight = targetScreenX + targetWidth / 2;
    final targetTop = targetScreenY - targetHeight / 2;
    final targetBottom = targetScreenY + targetHeight / 2;
    final overlapWidth = math.max(
      0,
      math.min(handRight, targetRight) - math.max(handLeft, targetLeft),
    );
    final overlapHeight = math.max(
      0,
      math.min(handBottom, targetBottom) - math.max(handTop, targetTop),
    );
    final textOcclusion = text && overlapWidth * overlapHeight > .0001;
    final occupancy = (targetWidth * targetHeight).clamp(0, 1).toDouble();
    final emptySpacePenalty = occupancy < .08 ? (0.08 - occupancy) * 10 : 0.0;
    return DirectorScoreComponents(
      readabilityScore: readability,
      contextScore:
          (candidate.kind == DirectorCandidateKind.contextual ||
                  candidate.kind == DirectorCandidateKind.scene
              ? 1.2
              : .5) +
          (candidate.kind == DirectorCandidateKind.overview
              ? input.configuration.overviewPreference
              : 0),
      motionCost: pan + logZoom,
      occlusionPenalty: input.configuration.handSafeFraming && !unknownHand
          ? (handOutsideSafe ? 2.5 : 0) + (textOcclusion ? 3.5 : 0)
          : 0,
      reversalPenalty: reversal,
      cutPenalty: cutRequired && candidate.view != current ? .6 : 0,
      movementFrequencyPenalty:
          recentMovements >= input.configuration.maximumMovementsPerWindow
          ? 2
          : 0,
      constraintPenalty: (containsTarget ? 0 : 4) + emptySpacePenalty,
    );
  }
}

final class CameraPathPlanner {
  const CameraPathPlanner({this.scorer = const CandidateScorer()});
  final CandidateScorer scorer;
  ({DirectorCandidate candidate, DirectorScoreComponents score}) choose(
    DirectorInput input,
    DirectorCluster cluster,
    List<DirectorCandidate> candidates,
    CameraView current,
    double priorDirection,
    int recentMovements,
    List<DirectorCluster> lookAhead,
    CameraCandidateGenerator generator,
    bool cutRequired,
  ) {
    final scored = [
      for (final candidate in candidates)
        (
          candidate: candidate,
          score: scorer.score(
            input,
            cluster,
            candidate,
            current,
            priorDirection,
            recentMovements,
            cutRequired: cutRequired,
          ),
          futureScore: _futureScore(
            input,
            candidate.view,
            lookAhead,
            generator,
            recentMovements,
          ),
        ),
    ];
    scored.sort((a, b) {
      final score = (b.score.total + b.futureScore).compareTo(
        a.score.total + a.futureScore,
      );
      return score != 0
          ? score
          : a.candidate.kind.index.compareTo(b.candidate.kind.index);
    });
    return (candidate: scored.first.candidate, score: scored.first.score);
  }

  double _futureScore(
    DirectorInput input,
    CameraView current,
    List<DirectorCluster> clusters,
    CameraCandidateGenerator generator,
    int recentMovements,
  ) {
    var view = current;
    var result = 0.0;
    var weight = .35;
    for (final cluster in clusters.take(input.configuration.lookAheadEvents)) {
      final candidates = generator.generate(input, cluster, view);
      final scores = [
        for (final candidate in candidates)
          scorer.score(input, cluster, candidate, view, 0, recentMovements),
      ]..sort((a, b) => b.total.compareTo(a.total));
      result += scores.first.total * weight;
      view = candidates.first.view;
      weight *= .5;
    }
    return result;
  }
}

final class CameraSchedulePlanner {
  const CameraSchedulePlanner();
  ProposedCameraShot schedule({
    required DirectorInput input,
    required DirectorCluster cluster,
    required int index,
    required TimelineTime end,
    required CameraView priorView,
    required DirectorCandidate candidate,
    required DirectorScoreComponents score,
    required TimelineTime? priorAttention,
  }) {
    final eventTime = cluster.attentions.first.event.time;
    final leadUs = priorAttention == null
        ? eventTime.microseconds
        : eventTime.microseconds - priorAttention.microseconds;
    final moved = candidate.view != priorView;
    final enoughLead =
        moved &&
        leadUs >= input.configuration.preferredMoveDuration.inMicroseconds;
    final normalizedJump =
        math.sqrt(
          math.pow(candidate.view.centerX - priorView.centerX, 2) +
              math.pow(candidate.view.centerY - priorView.centerY, 2),
        ) /
        math.max(priorView.viewportWidth, .001);
    final largeJump = normalizedJump > .65;
    final safeMove =
        enoughLead &&
        !largeJump &&
        input.configuration.allowMovementTransitions;
    final transition = !moved
        ? const CameraTransition()
        : safeMove
        ? CameraTransition(
            type: CameraTransitionType.move,
            duration: TimelineDuration.fromMicroseconds(
              input.configuration.preferredMoveDuration.inMicroseconds,
            ),
            easing: CameraEasing.easeInOut,
          )
        : input.configuration.preferFadeForCuts &&
              input.configuration.allowFade &&
              !largeJump
        ? CameraTransition(
            type: CameraTransitionType.fade,
            duration: TimelineDuration.fromMicroseconds(
              input.configuration.preferredMoveDuration.inMicroseconds,
            ),
          )
        : const CameraTransition(type: CameraTransitionType.cut);
    final start = safeMove
        ? TimelineTime.fromMicroseconds(
            eventTime.microseconds -
                input.configuration.preferredMoveDuration.inMicroseconds,
          )
        : eventTime;
    final reasons = {
      ...candidate.reasons,
      if (moved && safeMove) DirectorReasonCode.movedBeforeDrawing,
      if (moved &&
          (!enoughLead || !input.configuration.allowMovementTransitions))
        DirectorReasonCode.cutNoLeadTime,
      if (moved && largeJump) DirectorReasonCode.largeJumpCut,
    };
    return ProposedCameraShot(
      planId:
          'plan-${eventTime.microseconds}-${cluster.regionIds.join('+')}-$index',
      targetRegionIds: cluster.regionIds,
      interval: TimelineInterval(
        start: start,
        end: end,
        intervalType: 'auto-camera-proposal',
        entityId: cluster.regionIds.join('+'),
        sourceOperation: 'auto-director-schedule',
        documentRevision: input.timeline.dependencyKey.documentRevision,
      ),
      keyframes: safeMove
          ? [
              ProposedCameraKeyframe(
                offset: TimelineTime.zero,
                view: priorView,
                incomingTransition: const CameraTransition(),
              ),
              ProposedCameraKeyframe(
                offset: TimelineTime.fromMicroseconds(
                  input.configuration.preferredMoveDuration.inMicroseconds,
                ),
                view: candidate.view,
                incomingTransition: transition,
              ),
            ]
          : [
              ProposedCameraKeyframe(
                offset: TimelineTime.zero,
                view: candidate.view,
                incomingTransition: transition,
              ),
            ],
      reasonCodes: Set.unmodifiable(reasons),
      score: score,
      constraints: [
        'manual_locked_intervals',
        if (!input.configuration.allowMovementDuringDrawing)
          'no_motion_during_drawing',
      ],
    );
  }
}

final class AutoDirectorPlanValidator {
  const AutoDirectorPlanValidator();
  List<AutoDirectorDiagnostic> validate(
    DirectorInput input,
    List<ProposedCameraShot> shots,
    List<CameraShot> protected,
  ) {
    final warnings = <AutoDirectorDiagnostic>[];
    if (input.dependencyKey.isEmpty) {
      warnings.add(
        const AutoDirectorDiagnostic(
          'missing_dependency_key',
          'Plan dependency key is required.',
        ),
      );
    }
    final planIds = <String>{};
    TimelineTime? previousEnd;
    for (final shot in shots) {
      if (!planIds.add(shot.planId)) {
        warnings.add(
          AutoDirectorDiagnostic(
            'duplicate_plan_id',
            'Temporary plan IDs must be unique.',
            planShotId: shot.planId,
          ),
        );
      }
      if (shot.interval.start.microseconds < 0 ||
          shot.interval.isEmpty ||
          (previousEnd != null &&
              shot.interval.start.compareTo(previousEnd) < 0)) {
        warnings.add(
          AutoDirectorDiagnostic(
            'invalid_schedule',
            'Proposed shot intervals must be positive and non-overlapping.',
            planShotId: shot.planId,
          ),
        );
      }
      if (protected.any(
        (value) => _overlaps(
          shot.interval,
          TimelineInterval(start: value.startTime, end: value.endTime),
        ),
      )) {
        warnings.add(
          AutoDirectorDiagnostic(
            'protected_overlap',
            'A proposed shot overlaps a manual or locked camera interval.',
            planShotId: shot.planId,
          ),
        );
      }
      TimelineTime? previousOffset;
      for (final keyframe in shot.keyframes) {
        final view = keyframe.view;
        final availableUs =
            keyframe.offset.microseconds - (previousOffset?.microseconds ?? 0);
        if (!view.centerX.isFinite ||
            !view.centerY.isFinite ||
            !view.viewportWidth.isFinite ||
            view.viewportWidth < input.configuration.minimumViewportWidth ||
            view.viewportWidth > input.configuration.maximumViewportWidth ||
            (previousOffset != null &&
                keyframe.offset.compareTo(previousOffset) <= 0) ||
            keyframe.incomingTransition.duration.microseconds > availableUs) {
          warnings.add(
            AutoDirectorDiagnostic(
              'invalid_keyframe',
              'Keyframes and views must be ordered, finite, and inside safety limits.',
              planShotId: shot.planId,
            ),
          );
        }
        previousOffset = keyframe.offset;
      }
      for (final target in shot.targetRegionIds) {
        final region = input.graph.regions
            .where((value) => value.id == target)
            .firstOrNull;
        if (region?.metadata?.cameraExcluded == true) {
          warnings.add(
            AutoDirectorDiagnostic(
              'excluded_target',
              'A proposed shot cannot target camera-excluded content.',
              planShotId: shot.planId,
            ),
          );
        }
      }
      final targetRegions = shot.targetRegionIds
          .map(
            (id) => input.graph.regions
                .where((region) => region.id == id)
                .firstOrNull,
          )
          .whereType<SemanticRegion>()
          .toList(growable: false);
      if (targetRegions.isNotEmpty) {
        final targetUnion = targetRegions
            .skip(1)
            .fold(
              targetRegions.first.visualBounds,
              (bounds, region) => bounds.union(region.visualBounds),
            );
        for (final keyframe in shot.keyframes) {
          final framing = const ProjectedFramingValidator().validate(
            view: keyframe.view,
            target: targetUnion,
            worldWidth: input.graph.worldWidth,
            worldHeight: input.graph.worldHeight,
            safeOutputFraction: input.configuration.innerSafeFraction,
          );
          if (!framing.isContained) {
            warnings.add(
              AutoDirectorDiagnostic(
                'projected_target_outside_safe_area',
                'Projected target containment is '
                    '${framing.projectedSafeContainmentRatio}; expected 1.0.',
                planShotId: shot.planId,
              ),
            );
            break;
          }
        }
      }
      previousEnd = shot.interval.end;
    }
    for (final event in input.graph.attentionEvents.where(
      (value) => _inScope(value, input.scope),
    )) {
      final excluded = event.regionIds.any(
        (id) =>
            input.graph.regions
                .where((region) => region.id == id)
                .firstOrNull
                ?.metadata
                ?.cameraExcluded ==
            true,
      );
      if (excluded) continue;
      final proposal = shots
          .where((shot) => shot.targetRegionIds.any(event.regionIds.contains))
          .firstOrNull;
      final protectedCoverage = protected.any(
        (shot) =>
            shot.startTime.compareTo(event.time) <= 0 &&
            shot.endTime.compareTo(event.time) > 0,
      );
      if (proposal == null && !protectedCoverage) {
        warnings.add(
          const AutoDirectorDiagnostic(
            'uncovered_attention',
            'Every included attention event requires a shot or an uncovered diagnostic.',
          ),
        );
        continue;
      }
      if (proposal != null) {
        final arrival =
            proposal.interval.start.microseconds +
            proposal.keyframes.last.offset.microseconds;
        final transition = proposal.keyframes.last.incomingTransition.type;
        if (arrival > event.time.microseconds ||
            (proposal.interval.start == event.time &&
                transition != CameraTransitionType.cut &&
                !proposal.reasonCodes.contains(
                  DirectorReasonCode.heldDueToDeadZone,
                ))) {
          warnings.add(
            AutoDirectorDiagnostic(
              'late_camera_arrival',
              'Move/Fade must finish before attention; no lead requires Cut or Hold.',
              planShotId: proposal.planId,
            ),
          );
        }
      }
    }
    return List.unmodifiable(warnings);
  }
}

final class SmartAutoDirector {
  const SmartAutoDirector({
    this.inputBuilder = const DirectorInputBuilder(),
    this.sequenceBuilder = const AttentionSequenceBuilder(),
    this.clusterer = const RegionClusterer(),
    this.compactor = const CameraPlanCompactor(),
    this.candidateGenerator = const CameraCandidateGenerator(),
    this.pathPlanner = const CameraPathPlanner(),
    this.schedulePlanner = const CameraSchedulePlanner(),
    this.validator = const AutoDirectorPlanValidator(),
  });
  final DirectorInputBuilder inputBuilder;
  final AttentionSequenceBuilder sequenceBuilder;
  final RegionClusterer clusterer;
  final CameraPlanCompactor compactor;
  final CameraCandidateGenerator candidateGenerator;
  final CameraPathPlanner pathPlanner;
  final CameraSchedulePlanner schedulePlanner;
  final AutoDirectorPlanValidator validator;

  AutoDirectorPlan generate({
    required CompiledTimeline timeline,
    required CompiledSemanticRegionGraph graph,
    required ProjectCameraTrack? cameraTrack,
    AutoDirectorConfiguration? configuration,
    AutoDirectorScope? scope,
    AutoDirectorCancellation? cancellation,
    AutoDirectorProgress? onProgress,
  }) {
    final config = configuration ?? AutoDirectorConfiguration();
    final selectedScope = scope ?? AutoDirectorScope.entireProject();
    final watch = Stopwatch()..start();
    void stage(AutoDirectorProgressStage value, double fraction) {
      _cancel(cancellation, watch, config);
      onProgress?.call(value, fraction);
    }

    stage(AutoDirectorProgressStage.preparing, 0);
    final input = inputBuilder.build(
      timeline: timeline,
      graph: graph,
      cameraTrack: cameraTrack,
      configuration: config,
      scope: selectedScope,
    );
    final protected = (cameraTrack?.shots ?? const <CameraShot>[])
        .where(
          (shot) => shot.authorship == CameraAuthorship.manual || shot.isLocked,
        )
        .toList();
    final replaceable = (cameraTrack?.shots ?? const <CameraShot>[])
        .where(
          (shot) =>
              shot.authorship == CameraAuthorship.auto &&
              !shot.isLocked &&
              _shotInScope(shot, selectedScope, graph),
        )
        .toList();
    final outsideAuto = (cameraTrack?.shots ?? const <CameraShot>[])
        .where(
          (shot) =>
              shot.authorship == CameraAuthorship.auto &&
              !shot.isLocked &&
              !replaceable.contains(shot),
        )
        .toList();
    final preserved = [...protected, ...outsideAuto]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    stage(AutoDirectorProgressStage.analyzing, .15);
    var sequence = sequenceBuilder.build(input);
    final diagnostics = <AutoDirectorDiagnostic>[];
    final warnings = <AutoDirectorDiagnostic>[];
    if (config.timelineExtensionPolicy ==
        AutoCameraTimelineExtensionPolicy.preserveBaseDuration) {
      final baseEndUs = timeline.duration.microseconds;
      final outsideBase = sequence
          .where((entry) => entry.event.time.microseconds >= baseEndUs)
          .length;
      if (outsideBase > 0) {
        sequence = sequence
            .where((entry) => entry.event.time.microseconds < baseEndUs)
            .toList(growable: false);
        diagnostics.add(
          AutoDirectorDiagnostic(
            'attention_outside_base_timeline',
            '$outsideBase attention event(s) at or after the base timeline '
                'end were excluded from generated camera scheduling.',
          ),
        );
      }
    }
    if (sequence.length > config.maximumAttentionEvents) {
      sequence = sequence.take(config.maximumAttentionEvents).toList();
      diagnostics.add(
        const AutoDirectorDiagnostic(
          'budget_fallback',
          'Attention input exceeded the bounded planning budget.',
        ),
      );
    }
    final clusters = clusterer.cluster(input, sequence);
    stage(AutoDirectorProgressStage.generatingCandidates, .35);
    var shots = <ProposedCameraShot>[];
    var current = cameraTrack?.defaultView ?? const CameraView.identity();
    double priorDirection = 0;
    TimelineTime? priorAttention;
    var movements = 0;
    for (var i = 0; i < clusters.length; i++) {
      _cancel(cancellation, watch, config);
      final cluster = clusters[i];
      final eventTime = cluster.attentions.first.event.time;
      var nextTime = i + 1 < clusters.length
          ? clusters[i + 1].attentions.first.event.time
          : TimelineTime.fromMicroseconds(
              config.timelineExtensionPolicy ==
                      AutoCameraTimelineExtensionPolicy.allowExplicitExtension
                  ? math.max(
                      eventTime.microseconds +
                          config.minimumHold.inMicroseconds,
                      timeline.duration.microseconds,
                    )
                  : timeline.duration.microseconds,
            );
      if (config.timelineExtensionPolicy ==
              AutoCameraTimelineExtensionPolicy.preserveBaseDuration &&
          nextTime.compareTo(
                TimelineTime.fromMicroseconds(timeline.duration.microseconds),
              ) >
              0) {
        nextTime = TimelineTime.fromMicroseconds(
          timeline.duration.microseconds,
        );
      }
      for (final constraint in protected) {
        if (constraint.startTime.compareTo(eventTime) > 0 &&
            constraint.startTime.compareTo(nextTime) < 0) {
          nextTime = constraint.startTime;
        }
      }
      if (protected.any(
        (shot) =>
            shot.startTime.compareTo(eventTime) <= 0 &&
            shot.endTime.compareTo(eventTime) > 0,
      )) {
        warnings.add(
          AutoDirectorDiagnostic(
            'uncovered_protected_interval',
            'Attention event is covered by a protected camera shot and was not changed.',
          ),
        );
        continue;
      }
      final candidates = candidateGenerator.generate(input, cluster, current);
      final chosen = pathPlanner.choose(
        input,
        cluster,
        candidates,
        current,
        priorDirection,
        movements,
        clusters
            .skip(i + 1)
            .take(config.lookAheadEvents)
            .toList(growable: false),
        candidateGenerator,
        priorAttention == null ||
            eventTime.microseconds - priorAttention.microseconds <
                config.preferredMoveDuration.inMicroseconds,
      );
      if (chosen.score.occlusionPenalty > 0) {
        warnings.add(
          AutoDirectorDiagnostic(
            'hand_occlusion_risk',
            'Known hand footprint may occlude text in the selected safe view.',
            planShotId:
                'plan-${eventTime.microseconds}-${cluster.regionIds.join('+')}-$i',
          ),
        );
      }
      final shot = schedulePlanner.schedule(
        input: input,
        cluster: cluster,
        index: i,
        end: nextTime,
        priorView: current,
        candidate: chosen.candidate,
        score: chosen.score,
        priorAttention: priorAttention,
      );
      if (shots.isNotEmpty &&
          shot.interval.start.compareTo(shots.last.interval.end) < 0) {
        final prior = shots.removeLast();
        final shortenedDurationUs =
            shot.interval.start.microseconds -
            prior.interval.start.microseconds;
        final priorStillValid =
            shortenedDurationUs > 0 &&
            prior.keyframes.every(
              (keyframe) => keyframe.offset.microseconds <= shortenedDurationUs,
            );
        // A transition with enough lead can begin before the previous
        // proposal itself. In that case the previous proposal has no valid
        // half-open interval left and is superseded, rather than constructing
        // [prior.start, shot.start) with reversed endpoints.
        if (priorStillValid) {
          shots.add(
            ProposedCameraShot(
              planId: prior.planId,
              targetRegionIds: prior.targetRegionIds,
              interval: TimelineInterval(
                start: prior.interval.start,
                end: shot.interval.start,
                intervalType: 'auto-camera-overlap-truncation',
                entityId: prior.planId,
                sourceOperation: 'auto-director-generate',
                documentRevision: input.timeline.dependencyKey.documentRevision,
              ),
              keyframes: prior.keyframes,
              reasonCodes: prior.reasonCodes,
              score: prior.score,
              constraints: prior.constraints,
            ),
          );
        }
      }
      final dx = chosen.candidate.view.centerX - current.centerX;
      if (chosen.candidate.view != current) movements++;
      if (dx != 0) priorDirection = dx.sign;
      current = chosen.candidate.view;
      priorAttention = eventTime;
      shots.add(shot);
    }
    stage(AutoDirectorProgressStage.optimizing, .75);
    shots = compactor.compact(input, shots);
    shots = _repairProjectedFraming(input, shots);
    final validation = validator.validate(input, shots, protected);
    warnings.addAll(validation);
    if (graph.handFootprint.provenance == HandFootprintProvenance.unknown) {
      diagnostics.add(
        const AutoDirectorDiagnostic(
          'unknown_hand_footprint',
          'Conservative padding was used because hand footprint metadata is unknown.',
        ),
      );
    }
    stage(AutoDirectorProgressStage.validating, .9);
    final metrics = _metrics(shots, warnings, preserved, graph);
    if (metrics.maximumNormalizedPanSpeed > config.maximumNormalizedPanSpeed) {
      diagnostics.add(
        const AutoDirectorDiagnostic(
          'pan_speed_budget',
          'Normalized pan speed exceeds the soft quality budget.',
        ),
      );
    }
    if (metrics.maximumLogZoomSpeed > config.maximumLogZoomSpeed) {
      diagnostics.add(
        const AutoDirectorDiagnostic(
          'zoom_speed_budget',
          'Log zoom speed exceeds the soft quality budget.',
        ),
      );
    }
    if (metrics.directionReversals > config.maximumDirectionReversals) {
      diagnostics.add(
        const AutoDirectorDiagnostic(
          'reversal_budget',
          'Direction reversals exceed the soft quality budget.',
        ),
      );
    }
    final movingInTenSeconds = metrics.movementsPerTenSeconds;
    if (movingInTenSeconds > config.maximumMovesPerTenSeconds) {
      diagnostics.add(
        const AutoDirectorDiagnostic(
          'movement_budget',
          'Moves per ten seconds exceed the soft quality budget.',
        ),
      );
    }
    stage(AutoDirectorProgressStage.completed, 1);
    return AutoDirectorPlan(
      inputDependencyKey: input.dependencyKey,
      configuration: config,
      scope: selectedScope,
      proposedShots: shots,
      preservedShots: preserved,
      removedAutoShotIds: replaceable.map((shot) => shot.id).toList(),
      diagnostics: diagnostics,
      warnings: warnings,
      qualityMetrics: metrics,
      status: warnings.isEmpty
          ? AutoDirectorPlanStatus.completed
          : AutoDirectorPlanStatus.completedWithWarnings,
    );
  }
}

bool _inScope(SemanticAttentionEvent event, AutoDirectorScope scope) =>
    switch (scope.kind) {
      AutoDirectorScopeKind.entireProject => true,
      AutoDirectorScopeKind.scene => event.sceneId == scope.sceneId,
      AutoDirectorScopeKind.selectedSections =>
        event.sectionId != null && scope.sectionIds.contains(event.sectionId),
      AutoDirectorScopeKind.affectedRange => scope.interval!.contains(
        event.time,
      ),
      AutoDirectorScopeKind.selectedTimeRange => scope.interval!.contains(
        event.time,
      ),
    };
bool _shotInScope(
  CameraShot shot,
  AutoDirectorScope scope,
  CompiledSemanticRegionGraph graph,
) => switch (scope.kind) {
  AutoDirectorScopeKind.entireProject => true,
  AutoDirectorScopeKind.affectedRange => _overlaps(
    TimelineInterval(start: shot.startTime, end: shot.endTime),
    scope.interval!,
  ),
  AutoDirectorScopeKind.selectedTimeRange => _overlaps(
    TimelineInterval(start: shot.startTime, end: shot.endTime),
    scope.interval!,
  ),
  AutoDirectorScopeKind.scene => graph.attentionEvents.any(
    (event) =>
        event.sceneId == scope.sceneId &&
        event.time.compareTo(shot.startTime) >= 0 &&
        event.time.compareTo(shot.endTime) < 0,
  ),
  AutoDirectorScopeKind.selectedSections => graph.attentionEvents.any(
    (event) =>
        event.sectionId != null &&
        scope.sectionIds.contains(event.sectionId) &&
        event.time.compareTo(shot.startTime) >= 0 &&
        event.time.compareTo(shot.endTime) < 0,
  ),
};
bool _overlaps(TimelineInterval a, TimelineInterval b) =>
    a.start.compareTo(b.end) < 0 && b.start.compareTo(a.end) < 0;
CameraView _fit(
  DirectorInput input,
  SemanticWorldBounds bounds,
  double padding,
) {
  final width = (bounds.right - bounds.left) / input.graph.worldWidth;
  // Camera centers use independently normalized X/Y coordinates. The output
  // currently has the project aspect, therefore viewport width and normalized
  // viewport height are equal.
  final heightAsWidth = (bounds.bottom - bounds.top) / input.graph.worldHeight;
  final viewport = (math.max(width, heightAsWidth) / (1 - padding * 2)).clamp(
    input.configuration.minimumViewportWidth,
    input.configuration.maximumViewportWidth,
  );
  return CameraView(
    centerX: bounds.centerX / input.graph.worldWidth,
    centerY: bounds.centerY / input.graph.worldHeight,
    viewportWidth: viewport,
  );
}

List<ProposedCameraShot> _repairProjectedFraming(
  DirectorInput input,
  List<ProposedCameraShot> source,
) {
  const validator = ProjectedFramingValidator();
  final regions = {for (final region in input.graph.regions) region.id: region};
  return List.unmodifiable([
    for (final shot in source)
      if (shot.targetRegionIds
              .map((id) => regions[id])
              .whereType<SemanticRegion>()
              .toList()
          case final targets when targets.isNotEmpty)
        (() {
          final union = targets
              .skip(1)
              .fold(
                targets.first.visualBounds,
                (bounds, region) => bounds.union(region.visualBounds),
              );
          final repaired = [
            for (final keyframe in shot.keyframes)
              ProposedCameraKeyframe(
                offset: keyframe.offset,
                view: validator.repair(
                  view: keyframe.view,
                  target: union,
                  worldWidth: input.graph.worldWidth,
                  worldHeight: input.graph.worldHeight,
                  safeOutputFraction: input.configuration.innerSafeFraction,
                  maximumViewportWidth:
                      input.configuration.maximumViewportWidth,
                ),
                incomingTransition: keyframe.incomingTransition,
              ),
          ];
          return ProposedCameraShot(
            planId: shot.planId,
            targetRegionIds: shot.targetRegionIds,
            interval: shot.interval,
            keyframes: repaired,
            reasonCodes: shot.reasonCodes,
            score: shot.score,
            constraints: [
              ...shot.constraints,
              'projectedSafeContainmentRatio=1.0',
            ],
          );
        })()
      else
        shot,
  ]);
}

bool _acceptable(
  CameraView current,
  CameraView target,
  AutoDirectorConfiguration config,
) {
  final dx = (current.centerX - target.centerX).abs();
  final dy = (current.centerY - target.centerY).abs();
  final zoom = (math.log(current.viewportWidth / target.viewportWidth)).abs();
  return math.max(dx, dy) <= config.maximumDeadZoneCenterDelta &&
      zoom <= config.maximumDeadZoneLogZoomDelta;
}

void _cancel(
  AutoDirectorCancellation? cancellation,
  Stopwatch watch,
  AutoDirectorConfiguration config,
) {
  if (cancellation?.isCancelled ?? false) {
    throw const AutoDirectorCancelledException();
  }
  if (watch.elapsed > config.maximumPlanningTime) {
    throw const AutoDirectorCancelledException();
  }
}

AutoDirectorQualityMetrics _metrics(
  List<ProposedCameraShot> shots,
  List<AutoDirectorDiagnostic> warnings,
  List<CameraShot> preserved,
  CompiledSemanticRegionGraph graph,
) {
  var moves = 0, cuts = 0, fades = 0, reversals = 0;
  double? priorDirection;
  var maxPan = 0.0, maxZoom = 0.0;
  var totalHold = 0;
  CameraView current = const CameraView.identity();
  var targetIndex = 0;
  for (final shot in shots) {
    totalHold += shot.interval.duration.microseconds;
    final key = shot.keyframes.last;
    switch (key.incomingTransition.type) {
      case CameraTransitionType.move:
        moves++;
      case CameraTransitionType.cut:
        cuts++;
      case CameraTransitionType.fade:
        fades++;
    }
    final seconds = math.max(
      key.incomingTransition.duration.microseconds / 1000000,
      .001,
    );
    final direction = (key.view.centerX - current.centerX).sign;
    if (targetIndex > 0) {
      if (priorDirection != null &&
          direction != 0 &&
          direction != priorDirection) {
        reversals++;
      }
      if (direction != 0) priorDirection = direction;
    }
    maxPan = math.max(
      maxPan,
      math.sqrt(
            math.pow(key.view.centerX - current.centerX, 2) +
                math.pow(key.view.centerY - current.centerY, 2),
          ) /
          math.max(current.viewportWidth, .001) /
          seconds,
    );
    maxZoom = math.max(
      maxZoom,
      (math.log(key.view.viewportWidth / current.viewportWidth)).abs() /
          seconds,
    );
    current = key.view;
    targetIndex++;
  }
  return AutoDirectorQualityMetrics(
    shotCount: shots.length,
    keyframeCount: shots.fold(0, (sum, shot) => sum + shot.keyframes.length),
    moveCount: moves,
    cutCount: cuts,
    fadeCount: fades,
    holdCount: shots.where((shot) => shot.keyframes.length == 1).length,
    movementsPerTenSeconds: _maximumMovementsPerTenSeconds(shots),
    averageHold: TimelineDuration.fromMicroseconds(
      shots.isEmpty ? 0 : totalHold ~/ shots.length,
    ),
    maximumNormalizedPanSpeed: maxPan,
    maximumLogZoomSpeed: maxZoom,
    directionReversals: reversals,
    uncoveredAttentionEvents: warnings
        .where((value) => value.code.contains('uncovered'))
        .length,
    textReadabilityWarnings: warnings
        .where((value) => value.code.contains('readability'))
        .length,
    handOcclusionWarnings: warnings
        .where((value) => value.code.contains('hand'))
        .length,
    preservedManualOrLockedCount: preserved
        .where(
          (shot) => shot.authorship == CameraAuthorship.manual || shot.isLocked,
        )
        .length,
  );
}

int _maximumMovementsPerTenSeconds(List<ProposedCameraShot> shots) {
  final movementTimes = shots
      .where(
        (shot) =>
            shot.keyframes.last.incomingTransition.type !=
            CameraTransitionType.cut,
      )
      .map((shot) => shot.interval.start.microseconds)
      .toList();
  var maximum = 0;
  var left = 0;
  for (var right = 0; right < movementTimes.length; right++) {
    while (movementTimes[right] - movementTimes[left] >= 10000000) {
      left++;
    }
    maximum = math.max(maximum, right - left + 1);
  }
  return maximum;
}

String _hash(String value) {
  var hash = 0xcbf29ce484222325;
  for (final code in value.codeUnits) {
    hash ^= code;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
