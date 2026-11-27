import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_application_service.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_operation_policy.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_transaction_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_scoped_document_change_detector.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';

void main() {
  const director = SmartAutoDirector();

  test('canonical A-J plan snapshots remain reviewable and stable', () {
    final fixtures = <String, _Fixture>{
      'a_educational_rtl': _fixture([
        _event(
          'title',
          0,
          .5,
          .1,
          text: true,
          direction: KnownTextDirection.rtl,
        ),
        _event(
          'explain-right',
          1000000,
          .8,
          .4,
          text: true,
          direction: KnownTextDirection.rtl,
        ),
        _event(
          'code-left',
          2200000,
          .2,
          .45,
          text: true,
          direction: KnownTextDirection.ltr,
        ),
        _event(
          'summary',
          3500000,
          .5,
          .85,
          text: true,
          direction: KnownTextDirection.rtl,
        ),
      ]),
      'b_ltr_code': _fixture([
        _event(
          'heading',
          0,
          .5,
          .1,
          text: true,
          direction: KnownTextDirection.ltr,
        ),
        _event(
          'code-left',
          1000000,
          .2,
          .45,
          text: true,
          direction: KnownTextDirection.ltr,
        ),
        _event('diagram-right', 2200000, .8, .45),
        _event(
          'summary',
          3500000,
          .5,
          .85,
          text: true,
          direction: KnownTextDirection.ltr,
        ),
      ]),
      'c_nearby_cluster': _fixture([
        _event('near-1', 0, .45, .45),
        _event('near-2', 400000, .48, .46),
        _event('near-3', 800000, .5, .48),
      ]),
      'd_distant_islands': _fixture([
        _event('island-left', 0, .05, .5),
        _event('island-right', 1200000, .95, .5),
      ]),
      'e_manual_locked': _fixture(
        [
          _event('before', 0, .2, .3),
          _event('manual-covered', 1000000, .5, .3),
          _event('after', 2000000, .8, .3),
        ],
        camera: _track([
          _shot('manual', 1000000, CameraAuthorship.manual),
          _shot('locked', 3000000, CameraAuthorship.auto, locked: true),
        ]),
      ),
      'f_readability_conflict': _fixture([
        _event('small-text', 0, .1, .2, text: true),
        _event('far-shape', 300000, .9, .8),
      ]),
      'g_hand_occlusion': _fixture([
        _event('text-at-hand', 0, .85, .5, text: true),
      ]),
      'h_no_lead': _fixture([_event('instant', 0, .1, .5)]),
      'i_dead_zone': _fixture([
        _event('base', 0, .4, .4),
        _event('inside', 1000000, .43, .4),
      ]),
      'j_ping_pong': _fixture([
        _event('left', 0, .15, .5),
        _event('right-1', 1000000, .85, .5),
        _event('slightly-left', 2000000, .79, .5),
        _event('right-2', 3000000, .85, .5),
      ]),
    };
    for (final entry in fixtures.entries) {
      final plan = director.generate(
        timeline: entry.value.timeline,
        graph: entry.value.graph,
        cameraTrack: entry.value.document.cameraTrack,
        configuration: entry.key == 'i_dead_zone'
            ? AutoDirectorConfiguration(maximumDeadZoneLogZoomDelta: .3)
            : null,
      );
      final snapshot = _planSnapshot(plan);
      final file = File('test/fixtures/auto_director_plans/${entry.key}.json');
      if (const bool.fromEnvironment('UPDATE_AUTO_DIRECTOR_SNAPSHOTS')) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('$snapshot\n');
      }
      expect(snapshot, file.readAsStringSync().trim(), reason: entry.key);
    }
  });

  test('many strokes in one semantic region compact to a held view', () {
    final fixture = _fixture([
      for (var index = 0; index < 30; index++)
        _event(
          'near-$index',
          index * 250000,
          .45 + (index % 3) * .005,
          .45 + (index % 2) * .005,
          section: 'one-region',
        ),
    ]);
    final plan = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    expect(plan.proposedShots.length, lessThanOrEqualTo(3));
    expect(plan.qualityMetrics.averageHold.microseconds, greaterThan(1000000));
    expect(plan.qualityMetrics.directionReversals, 0);
  });

  test('default Auto Camera never extends a six-second base timeline', () {
    final fixture = _fixture([
      _event('opening', 0, .2, .2),
      _event('final', 5000000, .8, .8),
    ]);
    final plan = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
      configuration: AutoDirectorConfiguration(
        minimumHold: const Duration(seconds: 5),
      ),
    );
    expect(fixture.timeline.duration.microseconds, 6000000);
    expect(
      plan.proposedShots.map((shot) => shot.interval.end.microseconds),
      everyElement(lessThanOrEqualTo(6000000)),
    );
  });

  test(
    'preserve policy excludes real-project attention beyond the 6s base end',
    () {
      final fixture = _fixture([
        _event('title', 0, .2, .2),
        _event('underline', 3700000, .5, .45),
        // Reproduces the rounded semantic event that previously produced
        // [6000001us, 6000000us) after camera generation.
        _event('subtitle-tail', 6000001, .8, .7),
      ]);
      final sixSecondTimeline = CompiledTimeline(
        dependencyKey: fixture.timeline.dependencyKey,
        duration: TimelineDuration.fromMicroseconds(6000000),
        contentEnd: TimelineTime.fromMicroseconds(6000000),
        drawing: fixture.timeline.drawing,
        camera: fixture.timeline.camera,
        audio: fixture.timeline.audio,
        voiceGuide: fixture.timeline.voiceGuide,
        sceneMarkers: fixture.timeline.sceneMarkers,
      );
      late final AutoDirectorPlan plan;
      expect(
        () => plan = director.generate(
          timeline: sixSecondTimeline,
          graph: fixture.graph,
          cameraTrack: null,
        ),
        returnsNormally,
      );
      expect(
        plan.proposedShots,
        everyElement(
          isA<ProposedCameraShot>().having(
            (shot) => shot.interval.end.microseconds,
            'end',
            lessThanOrEqualTo(6000000),
          ),
        ),
      );
      expect(
        plan.diagnostics.map((diagnostic) => diagnostic.code),
        contains('attention_outside_base_timeline'),
      );
    },
  );

  test('79 nearby auto paths in three sections do not become 46 shots', () {
    final events = <_Event>[];
    for (var section = 0; section < 3; section++) {
      for (var index = 0; index < (section == 0 ? 27 : 26); index++) {
        events.add(
          _event(
            'section-$section-path-$index',
            (section * 26 + index) * 200000,
            .2 + section * .3 + (index % 3) * .004,
            .45 + (index % 2) * .004,
            scene: 'lesson',
            section: 'section-$section',
          ),
        );
      }
    }
    final fixture = _fixture(events);
    final plan = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    expect(events, hasLength(79));
    expect(plan.proposedShots.length, lessThan(12));
    expect(plan.proposedShots.length, isNot(anyOf(46, 79)));
    expect(plan.qualityMetrics.movementsPerTenSeconds, lessThanOrEqualTo(4));
  });

  test(
    'fixed-seed property plans are invariant to collection insertion order',
    () {
      for (final count in [1, 7, 40, 200, 1000]) {
        final random = Random(7000 + count);
        final source = [
          for (var index = 0; index < count; index++)
            _event(
              'property-$index',
              index * (50000 + random.nextInt(200000)),
              -.15 + random.nextDouble() * 1.3,
              -.15 + random.nextDouble() * 1.3,
              scene: 'scene-${index % 4}',
              section: 'section-$index',
              text: index % 5 == 0,
              direction: KnownTextDirection
                  .values[index % KnownTextDirection.values.length],
            ),
        ];
        final fixture = _fixture(source);
        final reorderedGraph = _graph(source, reverseRegionInsertion: true);
        final first = director.generate(
          timeline: fixture.timeline,
          graph: fixture.graph,
          cameraTrack: null,
        );
        final second = director.generate(
          timeline: fixture.timeline,
          graph: reorderedGraph,
          cameraTrack: null,
        );
        expect(
          _planSnapshot(second),
          _planSnapshot(first),
          reason: 'count=$count',
        );
        expect(
          first.warnings.where(
            (warning) => const {
              'invalid_schedule',
              'invalid_keyframe',
              'excluded_target',
              'duplicate_plan_id',
              'late_camera_arrival',
            }.contains(warning.code),
          ),
          isEmpty,
          reason: 'count=$count',
        );
      }
    },
  );

  test('every score component changes the candidate decision total', () {
    final source = [_event('text', 0, .85, .5, text: true)];
    final fixture = _fixture(source);
    final knownHandGraph = _graph(
      source,
      hand: const HandFootprintDescriptor(
        provenance: HandFootprintProvenance.configuredAsset,
        screenScale: .3,
        penTipX: .95,
        penTipY: .5,
      ),
    );
    final input = const DirectorInputBuilder().build(
      timeline: fixture.timeline,
      graph: knownHandGraph,
      cameraTrack: null,
      configuration: AutoDirectorConfiguration(maximumMovementsPerWindow: 1),
      scope: AutoDirectorScope.entireProject(),
    );
    final attention = const AttentionSequenceBuilder().build(input);
    final cluster = const RegionClusterer().cluster(input, attention).single;
    final candidates = const CameraCandidateGenerator().generate(
      input,
      cluster,
      const CameraView.identity(),
    );
    const scorer = CandidateScorer();
    final fit = scorer.score(
      input,
      cluster,
      candidates.first,
      const CameraView.identity(),
      -1,
      1,
      cutRequired: true,
    );
    final contextual = scorer.score(
      input,
      cluster,
      candidates[1],
      const CameraView.identity(),
      0,
      0,
    );
    final unsafe = scorer.score(
      input,
      cluster,
      const DirectorCandidate(
        kind: DirectorCandidateKind.fit,
        view: CameraView(centerX: .1, centerY: .1, viewportWidth: .02),
        reasons: {DirectorReasonCode.fitContent},
      ),
      const CameraView.identity(),
      0,
      0,
    );
    expect(fit.readabilityScore, greaterThan(0));
    expect(contextual.contextScore, isNot(fit.contextScore));
    expect(fit.motionCost, greaterThan(0));
    expect(fit.occlusionPenalty, greaterThan(0));
    expect(fit.reversalPenalty, greaterThan(0));
    expect(fit.cutPenalty, greaterThan(0));
    expect(fit.movementFrequencyPenalty, greaterThan(0));
    expect(unsafe.constraintPenalty, greaterThan(0));
    expect({fit.total, contextual.total, unsafe.total}, hasLength(3));
  });

  test(
    'known and unknown hand footprints produce distinct safety evidence',
    () {
      final source = [_event('edge-text', 0, .86, .5, text: true)];
      final fixture = _fixture(source);
      final known = director.generate(
        timeline: fixture.timeline,
        graph: _graph(
          source,
          hand: const HandFootprintDescriptor(
            provenance: HandFootprintProvenance.configuredAsset,
            screenScale: .3,
            penTipX: .95,
            penTipY: .5,
          ),
        ),
        cameraTrack: null,
      );
      final unknown = director.generate(
        timeline: fixture.timeline,
        graph: fixture.graph,
        cameraTrack: null,
      );
      expect(
        known.warnings.map((value) => value.code),
        contains('hand_occlusion_risk'),
      );
      expect(
        unknown.diagnostics.map((value) => value.code),
        contains('unknown_hand_footprint'),
      );
      expect(
        known.proposedShots.single.score.occlusionPenalty,
        greaterThan(unknown.proposedShots.single.score.occlusionPenalty),
      );
    },
  );

  test('single target plan is deterministic, reviewable, and non-mutating', () {
    final fixture = _fixture([_event('one', 0, .2, .3)]);
    final before = const DevelopmentProjectManifestCodec()
        .encode(fixture.document)
        .toString();
    final a = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    final b = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    expect(a.proposedShots.single.planId, b.proposedShots.single.planId);
    expect(a.proposedShots.single.authorship, CameraAuthorship.auto);
    expect(a.proposedShots.single.score.readabilityScore, greaterThan(0));
    expect(
      const DevelopmentProjectManifestCodec()
          .encode(fixture.document)
          .toString(),
      before,
    );
  });

  test('dead zone holds and left-right-slight-left avoids a third move', () {
    final close = _fixture([
      _event('a', 0, .4, .4),
      _event('b', 1000000, .43, .4),
    ]);
    final held = director.generate(
      timeline: close.timeline,
      graph: close.graph,
      cameraTrack: null,
      configuration: AutoDirectorConfiguration(maximumDeadZoneLogZoomDelta: .3),
    );
    expect(
      held.proposedShots.last.reasonCodes,
      contains(DirectorReasonCode.heldDueToDeadZone),
    );

    final pingPong = _fixture([
      _event('left', 0, .15, .5),
      _event('right', 1000000, .85, .5),
      _event('slightly-left', 2000000, .79, .5),
    ]);
    final plan = director.generate(
      timeline: pingPong.timeline,
      graph: pingPong.graph,
      cameraTrack: null,
      configuration: AutoDirectorConfiguration(maximumDeadZoneLogZoomDelta: .3),
    );
    expect(plan.qualityMetrics.directionReversals, lessThanOrEqualTo(1));
    expect(
      plan.proposedShots.last.reasonCodes,
      contains(DirectorReasonCode.heldDueToDeadZone),
    );
  });

  test(
    'no lead time cuts; sufficient lead schedules arrival before drawing',
    () {
      final fixture = _fixture([
        _event('a', 0, .1, .5),
        _event('b', 1000000, .16, .5),
      ]);
      final plan = director.generate(
        timeline: fixture.timeline,
        graph: fixture.graph,
        cameraTrack: null,
      );
      expect(
        plan.proposedShots.first.reasonCodes,
        contains(DirectorReasonCode.cutNoLeadTime),
      );
      expect(
        plan.proposedShots.last.reasonCodes,
        contains(DirectorReasonCode.movedBeforeDrawing),
      );
      expect(
        plan.proposedShots.last.interval.start.microseconds,
        1000000 - 450000,
      );
      expect(plan.proposedShots.last.keyframes, hasLength(2));
      expect(
        plan.proposedShots.last.keyframes.last.offset.microseconds,
        450000,
      );
    },
  );

  test('manual and locked shots survive; only unlocked auto is replaced', () {
    final manual = _shot('manual', 0, CameraAuthorship.manual);
    final locked = _shot(
      'locked',
      1000000,
      CameraAuthorship.auto,
      locked: true,
    );
    final replaceable = _shot('replace', 2000000, CameraAuthorship.auto);
    final fixture = _fixture([
      _event('a', 0, .2, .3),
      _event('b', 1000000, .5, .3),
      _event('c', 2000000, .8, .3),
    ], camera: _track([manual, locked, replaceable]));
    final plan = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: fixture.document.cameraTrack,
    );
    expect(plan.preservedShots, containsAll([manual, locked]));
    expect(plan.removedAutoShotIds, [replaceable.id]);
    expect(
      plan.warnings.map((value) => value.code),
      contains('uncovered_protected_interval'),
    );
  });

  test('cameraExcluded, scene and selected-section scopes are respected', () {
    final events = [
      _event('a', 0, .2, .3, scene: 'one', section: 'a'),
      _event('b', 1000000, .8, .3, scene: 'two', section: 'b', excluded: true),
      _event('c', 2000000, .5, .8, scene: 'two', section: 'c'),
    ];
    final fixture = _fixture(events);
    final scene = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
      configuration: AutoDirectorConfiguration(maximumDeadZoneCenterDelta: .02),
      scope: AutoDirectorScope.scene(SceneId('two')),
    );
    expect(scene.proposedShots.expand((shot) => shot.targetRegionIds), [
      'stroke:c',
    ]);
    final selected = director.generate(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
      scope: AutoDirectorScope.selectedSections({SectionId('a')}),
    );
    expect(selected.proposedShots.single.targetRegionIds, ['stroke:a']);
  });

  test(
    'partial range preserves every protected and out-of-scope shot field',
    () {
      final manual = _shot('manual-rich', 0, CameraAuthorship.manual).copyWith(
        label: 'Do not touch',
        duration: TimelineDuration.fromMicroseconds(700000),
      );
      final locked = _shot(
        'locked-rich',
        1000000,
        CameraAuthorship.auto,
        locked: true,
      ).copyWith(label: 'Locked');
      final outside = _shot(
        'outside',
        3000000,
        CameraAuthorship.auto,
      ).copyWith(label: 'Outside scope');
      final inside = _shot('inside', 2000000, CameraAuthorship.auto);
      final track = _track([manual, locked, inside, outside]);
      final fixture = _fixture([
        _event('manual-event', 0, .1, .2, section: 'manual'),
        _event('locked-event', 1000000, .3, .2, section: 'locked'),
        _event('inside-event', 2000000, .6, .2, section: 'inside'),
        _event('outside-event', 3000000, .9, .2, section: 'outside'),
      ], camera: track);
      final scope = AutoDirectorScope.affectedRange(
        TimelineInterval(
          start: TimelineTime.fromMicroseconds(1800000),
          end: TimelineTime.fromMicroseconds(2800000),
        ),
      );
      final service = AutoDirectorApplicationService();
      final plan = service.generatePlan(
        timeline: fixture.timeline,
        graph: fixture.graph,
        cameraTrack: track,
        scope: scope,
      );
      expect(plan.removedAutoShotIds, [inside.id]);
      expect(plan.preservedShots, containsAll([manual, locked, outside]));
      final applied = service.applyPlan(
        plan: plan,
        currentDocument: fixture.document,
        currentTimeline: fixture.timeline,
        currentGraph: fixture.graph,
        allocation: IdAllocationContext(generator: SequentialIdGenerator()),
      );
      expect(applied.isSuccess, isTrue);
      final byId = {
        for (final shot in applied.operation!.document.cameraTrack!.shots)
          shot.id: shot,
      };
      expect(byId[manual.id], manual);
      expect(byId[locked.id], locked);
      expect(byId[outside.id], outside);
    },
  );

  test(
    'Arabic/LTR/mixed retain drawing order and trusted readability only',
    () {
      final fixture = _fixture([
        _event('rtl', 0, .8, .2, direction: KnownTextDirection.rtl, text: true),
        _event('ltr', 0, .2, .2, direction: KnownTextDirection.ltr, text: true),
        _event('outlined', 1000000, .5, .5),
      ]);
      final plan = director.generate(
        timeline: fixture.timeline,
        graph: fixture.graph,
        cameraTrack: null,
      );
      expect(plan.proposedShots.first.targetRegionIds.first, 'stroke:rtl');
      expect(plan.proposedShots.last.score.readabilityScore, 2);
    },
  );

  test(
    'Mahmoud teaching fixture stays readable without needless ping-pong',
    () {
      final fixture = _fixture([
        _event(
          'title-ar',
          0,
          .72,
          .12,
          text: true,
          direction: KnownTextDirection.rtl,
        ),
        _event(
          'explanation-left',
          1000000,
          .22,
          .42,
          text: true,
          direction: KnownTextDirection.rtl,
        ),
        _event(
          'code-right',
          2200000,
          .76,
          .43,
          text: true,
          direction: KnownTextDirection.ltr,
        ),
        _event(
          'summary-bottom',
          3600000,
          .5,
          .82,
          text: true,
          direction: KnownTextDirection.rtl,
        ),
      ]);
      final plan = director.generate(
        timeline: fixture.timeline,
        graph: fixture.graph,
        cameraTrack: null,
      );
      expect(plan.proposedShots.map((shot) => shot.targetRegionIds.first), [
        'stroke:title-ar',
        'stroke:explanation-left',
        'stroke:code-right',
        'stroke:summary-bottom',
      ]);
      expect(plan.qualityMetrics.directionReversals, lessThanOrEqualTo(2));
      expect(
        plan.proposedShots
            .skip(1)
            .every(
              (shot) =>
                  shot.reasonCodes.contains(
                    DirectorReasonCode.movedBeforeDrawing,
                  ) ||
                  shot.reasonCodes.contains(DirectorReasonCode.cutNoLeadTime) ||
                  shot.reasonCodes.contains(DirectorReasonCode.largeJumpCut) ||
                  shot.reasonCodes.contains(
                    DirectorReasonCode.heldDueToDeadZone,
                  ),
            ),
        isTrue,
      );
    },
  );

  test('application preview is disposable and apply rejects stale plans', () {
    final fixture = _fixture([_event('a', 0, .2, .2)]);
    final service = AutoDirectorApplicationService();
    final plan = service.generatePlan(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    final preview = service.previewPlan(plan);
    expect(preview.isDisposed, isFalse);
    preview.dispose();
    expect(preview.isDisposed, isTrue);
    final staleGraph = _graph([_event('changed', 0, .2, .2)]);
    final result = service.applyPlan(
      plan: plan,
      currentDocument: fixture.document,
      currentTimeline: fixture.timeline,
      currentGraph: staleGraph,
      allocation: IdAllocationContext(generator: SequentialIdGenerator()),
    );
    expect(result.failureCode, AutoDirectorApplyFailureCode.stalePlan);
    expect(fixture.document.cameraTrack, isNull);
  });

  test('ID allocation failure is typed and leaves the document unchanged', () {
    final fixture = _fixture([_event('a', 0, .2, .2)]);
    final service = AutoDirectorApplicationService();
    final plan = service.generatePlan(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    final result = service.applyPlan(
      plan: plan,
      currentDocument: fixture.document,
      currentTimeline: fixture.timeline,
      currentGraph: fixture.graph,
      allocation: IdAllocationContext(generator: const _ThrowingIds()),
    );
    expect(result.failureCode, AutoDirectorApplyFailureCode.allocationFailed);
    expect(fixture.document.cameraTrack, isNull);
  });

  test('apply allocates IDs once and save/open preserves applied plan', () {
    final fixture = _fixture([
      _event('a', 0, .2, .2),
      _event('b', 1000000, .8, .8),
    ]);
    final service = AutoDirectorApplicationService();
    final plan = service.generatePlan(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    final applied = service.applyPlan(
      plan: plan,
      currentDocument: fixture.document,
      currentTimeline: fixture.timeline,
      currentGraph: fixture.graph,
      allocation: IdAllocationContext(generator: SequentialIdGenerator()),
    );
    expect(applied.isSuccess, isTrue);
    final document = applied.operation!.document;
    expect(document.cameraTrack!.shots, hasLength(2));
    final ids = document.cameraTrack!.shots.map((shot) => shot.id).toList();
    final decoded = const DevelopmentProjectManifestCodec().decode(
      const DevelopmentProjectManifestCodec().encode(document),
    );
    expect(decoded.cameraTrack!.shots.map((shot) => shot.id), ids);
  });

  test('apply commits once and undo/redo preserve allocated IDs', () {
    final fixture = _fixture([
      _event('a', 0, .2, .2),
      _event('b', 1000000, .8, .8),
    ]);
    final service = AutoDirectorApplicationService();
    final plan = service.generatePlan(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    final applied = service.applyPlan(
      plan: plan,
      currentDocument: fixture.document,
      currentTimeline: fixture.timeline,
      currentGraph: fixture.graph,
      allocation: IdAllocationContext(generator: SequentialIdGenerator()),
    );
    final history = EditorHistory();
    const coordinator = DocumentTransactionCoordinator(
      changeDetector: CanonicalScopedDocumentChangeDetector(),
    );
    final initial = EditorDocumentState(document: fixture.document);
    final committed = coordinator.execute(
      current: initial,
      history: history,
      expectedProjectId: initial.document.id,
      expectedRevision: initial.revision,
      kind: DocumentOperationKind.cameraEdit,
      operation: (_) => applied.operation!,
    );
    expect(committed.isSuccess, isTrue);
    expect(history.undoEntries, hasLength(1));
    expect(committed.state.revision.value, initial.revision.value + 1);
    final ids = committed.state.document.cameraTrack!.shots
        .map((shot) => shot.id)
        .toList();
    final undone = coordinator.undo(current: committed.state, history: history);
    expect(undone.state.document.cameraTrack, isNull);
    final redone = coordinator.redo(current: undone.state, history: history);
    expect(
      redone.state.document.cameraTrack!.shots.map((shot) => shot.id),
      ids,
    );
  });

  test('transaction commit failure rolls back plan publication completely', () {
    final fixture = _fixture([_event('a', 0, .2, .2)]);
    final service = AutoDirectorApplicationService();
    final plan = service.generatePlan(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    final applied = service.applyPlan(
      plan: plan,
      currentDocument: fixture.document,
      currentTimeline: fixture.timeline,
      currentGraph: fixture.graph,
      allocation: IdAllocationContext(generator: SequentialIdGenerator()),
    );
    final history = EditorHistory();
    const coordinator = DocumentTransactionCoordinator(
      changeDetector: CanonicalScopedDocumentChangeDetector(),
      failureInjector: _FailureInjector(
        DocumentTransactionFailurePoint.historyCommit,
      ),
    );
    final initial = EditorDocumentState(document: fixture.document);
    final result = coordinator.execute(
      current: initial,
      history: history,
      expectedProjectId: initial.document.id,
      expectedRevision: initial.revision,
      kind: DocumentOperationKind.cameraEdit,
      operation: (_) => applied.operation!,
    );
    expect(result.isSuccess, isFalse);
    expect(result.state.document, same(fixture.document));
    expect(result.state.revision, initial.revision);
    expect(history.undoEntries, isEmpty);
    expect(history.hasActiveTransaction, isFalse);
  });

  test('apply rejects an independently invalidated plan before allocation', () {
    final fixture = _fixture([
      _event('a', 0, .2, .2),
      _event('b', 800000, .8, .8),
    ]);
    final service = AutoDirectorApplicationService();
    final generated = service.generatePlan(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    expect(generated.proposedShots, hasLength(greaterThan(1)));
    final invalid = AutoDirectorPlan(
      inputDependencyKey: generated.inputDependencyKey,
      configuration: generated.configuration,
      scope: generated.scope,
      proposedShots: [
        generated.proposedShots.first,
        ProposedCameraShot(
          planId: generated.proposedShots.first.planId,
          targetRegionIds: generated.proposedShots[1].targetRegionIds,
          interval: generated.proposedShots[1].interval,
          keyframes: generated.proposedShots[1].keyframes,
          reasonCodes: generated.proposedShots[1].reasonCodes,
          score: generated.proposedShots[1].score,
          constraints: generated.proposedShots[1].constraints,
        ),
      ],
      preservedShots: generated.preservedShots,
      removedAutoShotIds: generated.removedAutoShotIds,
      diagnostics: generated.diagnostics,
      warnings: generated.warnings,
      qualityMetrics: generated.qualityMetrics,
      status: generated.status,
    );
    final result = service.applyPlan(
      plan: invalid,
      currentDocument: fixture.document,
      currentTimeline: fixture.timeline,
      currentGraph: fixture.graph,
      allocation: IdAllocationContext(generator: const _ThrowingIds()),
    );
    expect(result.failureCode, AutoDirectorApplyFailureCode.invalidPlan);
    expect(result.operation, isNull);
    expect(fixture.document.cameraTrack, isNull);
  });

  test(
    'cancellation publishes no partial plan and progress is low-frequency',
    () {
      final fixture = _fixture([
        for (var i = 0; i < 40; i++) _event('$i', i * 100000, i / 40, .5),
      ]);
      final cancellation = _Cancellation();
      final stages = <AutoDirectorProgressStage>[];
      expect(
        () => director.generate(
          timeline: fixture.timeline,
          graph: fixture.graph,
          cameraTrack: null,
          cancellation: cancellation,
          onProgress: (stage, _) {
            stages.add(stage);
            if (stage == AutoDirectorProgressStage.analyzing) {
              cancellation.cancelled = true;
            }
          },
        ),
        throwsA(isA<AutoDirectorCancelledException>()),
      );
      expect(stages, [
        AutoDirectorProgressStage.preparing,
        AutoDirectorProgressStage.analyzing,
      ]);
    },
  );

  test('worker boundary ignores a late result after cancellation', () async {
    final fixture = _fixture([
      for (var index = 0; index < 1000; index++)
        _event('$index', index * 10000, (index % 20) / 20, .5),
    ]);
    final service = AutoDirectorApplicationService();
    final pending = service.generatePlanAsync(
      timeline: fixture.timeline,
      graph: fixture.graph,
      cameraTrack: null,
    );
    service.cancel();
    await expectLater(pending, throwsA(isA<AutoDirectorCancelledException>()));
    expect(fixture.document.cameraTrack, isNull);
  });

  test(
    'cancellation after optimization suppresses validation and publication',
    () {
      final fixture = _fixture([
        for (var i = 0; i < 40; i++) _event('$i', i * 100000, i / 40, .5),
      ]);
      final cancellation = _Cancellation();
      final stages = <AutoDirectorProgressStage>[];
      expect(
        () => director.generate(
          timeline: fixture.timeline,
          graph: fixture.graph,
          cameraTrack: null,
          cancellation: cancellation,
          onProgress: (stage, _) {
            stages.add(stage);
            if (stage == AutoDirectorProgressStage.optimizing) {
              cancellation.cancelled = true;
            }
          },
        ),
        throwsA(isA<AutoDirectorCancelledException>()),
      );
      expect(stages, contains(AutoDirectorProgressStage.optimizing));
      expect(stages, isNot(contains(AutoDirectorProgressStage.validating)));
      expect(fixture.document.cameraTrack, isNull);
    },
  );
}

final class _Cancellation implements AutoDirectorCancellation {
  bool cancelled = false;
  @override
  bool get isCancelled => cancelled;
}

final class _FailureInjector implements DocumentTransactionFailureInjector {
  const _FailureInjector(this.point);
  final DocumentTransactionFailurePoint point;
  @override
  void check(DocumentTransactionFailurePoint value) {
    if (value == point) throw StateError('injected $value');
  }
}

final class _ThrowingIds implements IdGenerator {
  const _ThrowingIds();
  Never _fail() => throw StateError('injected allocation failure');
  @override
  ProjectId projectId() => _fail();
  @override
  StrokeId strokeId() => _fail();
  @override
  StrokePauseId strokePauseId() => _fail();
  @override
  SectionId sectionId() => _fail();
  @override
  SceneId sceneId() => _fail();
  @override
  AudioTrackId audioTrackId() => _fail();
  @override
  ProjectAssetId projectAssetId() => _fail();
  @override
  CameraTrackId cameraTrackId() => _fail();
  @override
  CameraShotId cameraShotId() => _fail();
  @override
  CameraKeyframeId cameraKeyframeId() => _fail();
}

typedef _Fixture = ({
  ProjectDocument document,
  CompiledTimeline timeline,
  CompiledSemanticRegionGraph graph,
});
typedef _Event = ({
  String id,
  int us,
  double x,
  double y,
  String scene,
  String section,
  bool excluded,
  bool text,
  KnownTextDirection direction,
});
_Event _event(
  String id,
  int us,
  double x,
  double y, {
  String scene = 'scene',
  String section = 'section',
  bool excluded = false,
  bool text = false,
  KnownTextDirection direction = KnownTextDirection.unknown,
}) => (
  id: id,
  us: us,
  x: x,
  y: y,
  scene: scene,
  section: section,
  excluded: excluded,
  text: text,
  direction: direction,
);

_Fixture _fixture(List<_Event> events, {ProjectCameraTrack? camera}) {
  final durationUs = events.isEmpty
      ? 0
      : events.map((event) => event.us).reduce((a, b) => a > b ? a : b) +
            1000000;
  final document = ProjectDocument(
    id: ProjectId('project'),
    title: 'Director',
    canvas: const ProjectCanvas(width: 1000, height: 1000),
    frameRate: FrameRate(numerator: 30),
    duration: TimelineDuration.fromMicroseconds(durationUs),
    assets: const [],
    strokes: const [],
    sections: const [],
    sectionOrder: const [],
    scenes: const [],
    audioTracks: const [],
    cameraTrack: camera,
  );
  final timeline = CompiledTimeline(
    dependencyKey: TimelineDependencyKey(
      projectId: document.id,
      documentRevision: 1,
    ),
    duration: TimelineDuration.fromMicroseconds(durationUs),
    contentEnd: TimelineTime.fromMicroseconds(durationUs),
    drawing: null,
    camera: null,
    audio: const [],
    voiceGuide: null,
    sceneMarkers: const [],
  );
  return (document: document, timeline: timeline, graph: _graph(events));
}

CompiledSemanticRegionGraph _graph(
  List<_Event> events, {
  bool reverseRegionInsertion = false,
  HandFootprintDescriptor hand = const HandFootprintDescriptor(
    provenance: HandFootprintProvenance.unknown,
  ),
}) {
  final regions = <SemanticRegion>[];
  final attention = <SemanticAttentionEvent>[];
  for (final event in events) {
    final bounds = SemanticWorldBounds(
      event.x * 1000 - 30,
      event.y * 1000 - 25,
      event.x * 1000 + 30,
      event.y * 1000 + 25,
    );
    final target = SemanticTargetReference.stroke(StrokeId(event.id));
    final metadata = EntitySemanticMetadata(
      target: target,
      cameraExcluded: event.excluded,
      textSensitive: event.text,
      minimumPreferredZoom: event.text ? PreferredSemanticZoom(1.5) : null,
      textMetadata: event.text
          ? ImportedTextMetadata(
              originalText: event.direction == KnownTextDirection.rtl
                  ? 'عنوان'
                  : 'Title',
              direction: event.direction,
              directionProvenance: DirectionProvenance.sourceMetadata,
              sourceKind: TextSourceKind.svgText,
              sourceProvenance: 'fixture',
            )
          : null,
    );
    regions.add(
      SemanticRegion(
        id: target.stableKey,
        target: target,
        kind: event.text ? SemanticRegionKind.text : SemanticRegionKind.vector,
        geometricBounds: bounds,
        visualBounds: bounds,
        direction: event.direction,
        directionProvenance: event.text
            ? DirectionProvenance.sourceMetadata
            : DirectionProvenance.unknown,
        metadata: metadata,
      ),
    );
    attention.add(
      SemanticAttentionEvent(
        time: TimelineTime.fromMicroseconds(event.us),
        regionIds: [target.stableKey],
        activeBounds: bounds,
        strokeId: StrokeId(event.id),
        sectionId: SectionId(event.section),
        sceneId: SceneId(event.scene),
      ),
    );
  }
  final stableIds = events.map((event) => event.id).toList()..sort();
  return CompiledSemanticRegionGraph(
    dependencyKey: stableIds.join('|'),
    worldWidth: 1000,
    worldHeight: 1000,
    regions: reverseRegionInsertion ? regions.reversed.toList() : regions,
    containment: const [],
    drawingOrder: const [],
    adjacency: const [],
    attentionEvents: attention,
    handFootprint: hand,
  );
}

ProjectCameraTrack _track(List<CameraShot> shots) =>
    ProjectCameraTrack(id: CameraTrackId('track'), shots: shots);
CameraShot _shot(
  String id,
  int startUs,
  CameraAuthorship authorship, {
  bool locked = false,
}) => CameraShot(
  id: CameraShotId(id),
  startTime: TimelineTime.fromMicroseconds(startUs),
  duration: TimelineDuration.fromMicroseconds(500000),
  authorship: authorship,
  isLocked: locked,
  keyframes: [
    CameraKeyframe(
      id: CameraKeyframeId('key-$id'),
      offset: TimelineTime.zero,
      view: const CameraView.identity(),
    ),
  ],
);

String _planSnapshot(AutoDirectorPlan plan) =>
    const JsonEncoder.withIndent('  ').convert({
      'dependencyKey': plan.inputDependencyKey,
      'status': plan.status.name,
      'shots': [
        for (final shot in plan.proposedShots)
          {
            'planId': shot.planId,
            'targets': shot.targetRegionIds,
            'intervalUs': [
              shot.interval.start.microseconds,
              shot.interval.end.microseconds,
            ],
            'keyframes': [
              for (final keyframe in shot.keyframes)
                {
                  'offsetUs': keyframe.offset.microseconds,
                  'view': [
                    keyframe.view.centerX,
                    keyframe.view.centerY,
                    keyframe.view.viewportWidth,
                  ],
                  'transition': keyframe.incomingTransition.type.name,
                  'durationUs':
                      keyframe.incomingTransition.duration.microseconds,
                },
            ],
            'reasons': shot.reasonCodes.map((reason) => reason.name).toList()
              ..sort(),
            'score': {
              'readability': shot.score.readabilityScore,
              'context': shot.score.contextScore,
              'motion': shot.score.motionCost,
              'occlusion': shot.score.occlusionPenalty,
              'reversal': shot.score.reversalPenalty,
              'cut': shot.score.cutPenalty,
              'frequency': shot.score.movementFrequencyPenalty,
              'constraint': shot.score.constraintPenalty,
            },
          },
      ],
      'preserved': [for (final shot in plan.preservedShots) shot.id.value],
      'removedAuto': [for (final id in plan.removedAutoShotIds) id.value],
      'diagnostics': [for (final value in plan.diagnostics) value.code],
      'warnings': [for (final value in plan.warnings) value.code],
      'metrics': {
        'shots': plan.qualityMetrics.shotCount,
        'moves': plan.qualityMetrics.moveCount,
        'cuts': plan.qualityMetrics.cutCount,
        'fades': plan.qualityMetrics.fadeCount,
        'averageHoldUs': plan.qualityMetrics.averageHold.microseconds,
        'reversals': plan.qualityMetrics.directionReversals,
        'uncovered': plan.qualityMetrics.uncoveredAttentionEvents,
        'readabilityWarnings': plan.qualityMetrics.textReadabilityWarnings,
        'occlusionWarnings': plan.qualityMetrics.handOcclusionWarnings,
      },
    });
