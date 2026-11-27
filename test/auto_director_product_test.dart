import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_ui_cubit.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_ui_state.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_application_service.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/auto_director/presentation/auto_director_dialog.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_factory.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

void main() {
  test('every typed preset maps to a complete validated configuration', () {
    const mapper = AutoDirectorPresetMapper();
    final configurations = <AutoDirectorPresetId, AutoDirectorConfiguration>{};
    for (final id in AutoDirectorPresetCatalog.presets.keys) {
      final preset = AutoDirectorPresetCatalog.presets[id]!;
      expect(preset.version, AutoDirectorPresetCatalog.currentVersion);
      configurations[id] = mapper.configuration(
        ProjectAutoDirectorSettings(presetId: id),
      );
    }
    expect(
      configurations[AutoDirectorPresetId.educationalCalm]!.minimumHold,
      greaterThan(
        configurations[AutoDirectorPresetId.dynamicExplainer]!.minimumHold,
      ),
    );
    expect(
      configurations[AutoDirectorPresetId.educationalCalm]!
          .allowMovementDuringDrawing,
      isFalse,
    );
    expect(
      configurations[AutoDirectorPresetId.dynamicExplainer]!
          .allowMovementDuringDrawing,
      isTrue,
    );
    expect(
      configurations[AutoDirectorPresetId.noMotion]!.allowMovementTransitions,
      isFalse,
    );
    expect(
      configurations[AutoDirectorPresetId.presentation]!.preferFadeForCuts,
      isTrue,
    );
    expect(
      configurations[AutoDirectorPresetId.presentation]!.overviewPreference,
      greaterThan(0),
    );
    expect(
      configurations[AutoDirectorPresetId.noMotion]!.allowOverview,
      isFalse,
    );
  });

  test('No Motion produces no spatial Move transition', () {
    final fixture = _directorFixture();
    final plan = const SmartAutoDirector().generate(
      timeline: fixture.$1,
      graph: fixture.$2,
      cameraTrack: null,
      configuration: const AutoDirectorPresetMapper().configuration(
        const ProjectAutoDirectorSettings(
          presetId: AutoDirectorPresetId.noMotion,
        ),
      ),
    );
    expect(plan.qualityMetrics.moveCount, 0);
    expect(
      plan.proposedShots
          .expand((shot) => shot.keyframes)
          .map((frame) => frame.incomingTransition.type),
      isNot(contains(CameraTransitionType.move)),
    );
  });

  test(
    'custom edits retain provenance and persist through Save/Open codec',
    () {
      final document = const ProjectDocumentFactory().createEmpty(
        ids: SecureRandomIdGenerator(),
        duration: TimelineDuration.fromMicroseconds(2000000),
      );
      const settings = ProjectAutoDirectorSettings(
        presetId: AutoDirectorPresetId.custom,
        presetVersion: 1,
        customOverrides: AutoDirectorCustomOverrides(
          motionAmount: DirectorMotionAmount.dynamic,
          framing: DirectorFraming.close,
          textEmphasis: .85,
          minimumHold: Duration(milliseconds: 720),
          transitionPreference: DirectorTransitionPreference.move,
          allowMovementDuringDrawing: true,
          overviewFrequency: DirectorOverviewFrequency.periodic,
          handSafeFraming: true,
        ),
      );
      const codec = DevelopmentProjectManifestCodec();
      final manifest = codec.encode(
        document.copyWith(autoDirectorSettings: settings),
      );
      final decoded = codec.decode(manifest).autoDirectorSettings;
      expect(decoded.presetId, AutoDirectorPresetId.custom);
      expect(decoded.presetVersion, 1);
      expect(
        decoded.customOverrides.motionAmount,
        DirectorMotionAmount.dynamic,
      );
      expect(
        decoded.customOverrides.minimumHold,
        const Duration(milliseconds: 720),
      );
      expect(decoded.customOverrides.allowMovementDuringDrawing, isTrue);
    },
  );

  test(
    'UI lifecycle emits low-frequency progress and keeps plan runtime-only',
    () async {
      final editor = EditorCubit();
      final cubit = AutoDirectorUiCubit(
        initialSettings: editor.state.document.autoDirectorSettings,
      );
      final original = editor.state.document;
      await cubit.generate(
        timeline: editor.compileTimeline(),
        graph: editor.compileSemanticGraph(),
        cameraTrack: null,
      );
      expect(cubit.state.phase, AutoDirectorUiPhase.ready);
      expect(cubit.state.progressUpdateCount, lessThanOrEqualTo(8));
      expect(editor.state.document, same(original));
      cubit.setCustomOverrides(
        const AutoDirectorCustomOverrides(
          motionAmount: DirectorMotionAmount.dynamic,
        ),
      );
      expect(cubit.state.settings.presetId, AutoDirectorPresetId.custom);
      expect(cubit.state.plan, isNull);
      await cubit.close();
      await editor.close();
    },
  );

  test('project edits invalidate an in-flight generation', () async {
    final editor = EditorCubit();
    final cubit = AutoDirectorUiCubit(
      initialSettings: editor.state.document.autoDirectorSettings,
    );
    addTearDown(editor.close);
    addTearDown(cubit.close);
    final pending = cubit.generate(
      timeline: editor.compileTimeline(),
      graph: editor.compileSemanticGraph(),
      cameraTrack: editor.state.document.cameraTrack,
    );
    cubit.markStale();
    await pending;
    expect(cubit.state.phase, AutoDirectorUiPhase.stale);
    expect(cubit.state.plan, isNull);
  });

  test(
    'a second Generate cancels the first and publishes only the latest',
    () async {
      final editor = EditorCubit();
      final cubit = AutoDirectorUiCubit(
        initialSettings: editor.state.document.autoDirectorSettings,
      );
      addTearDown(editor.close);
      addTearDown(cubit.close);
      final first = cubit.generate(
        timeline: editor.compileTimeline(),
        graph: editor.compileSemanticGraph(),
        cameraTrack: editor.state.document.cameraTrack,
      );
      final second = cubit.generate(
        timeline: editor.compileTimeline(),
        graph: editor.compileSemanticGraph(),
        cameraTrack: editor.state.document.cameraTrack,
      );
      await Future.wait([first, second]);
      expect(cubit.state.phase, AutoDirectorUiPhase.ready);
      expect(cubit.state.plan, isNotNull);
    },
  );

  test(
    'Apply stores settings with camera in one revision and history entry',
    () async {
      final editor = EditorCubit();
      final before = editor.state.document;
      final revision = editor.state.documentRevision.value;
      final plan = AutoDirectorApplicationService().generatePlan(
        timeline: editor.compileTimeline(),
        graph: editor.compileSemanticGraph(),
        cameraTrack: null,
        configuration: const AutoDirectorPresetMapper().configuration(
          const ProjectAutoDirectorSettings(
            presetId: AutoDirectorPresetId.noMotion,
          ),
        ),
      );
      final result = editor.applyAutoDirectorPlan(
        plan,
        settings: const ProjectAutoDirectorSettings(
          presetId: AutoDirectorPresetId.noMotion,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(editor.state.documentRevision.value, revision + 1);
      expect(editor.history.undoEntries, hasLength(1));
      expect(
        editor.state.document.autoDirectorSettings.presetId,
        AutoDirectorPresetId.noMotion,
      );
      editor.undoStroke();
      expect(editor.state.document.cameraTrack, before.cameraTrack);
      expect(
        editor.state.document.autoDirectorSettings.presetId,
        before.autoDirectorSettings.presetId,
      );
      editor.redoStroke();
      expect(
        editor.state.document.autoDirectorSettings.presetId,
        AutoDirectorPresetId.noMotion,
      );
      await editor.close();
    },
  );

  testWidgets(
    'progressive Auto Camera flow is bilingual and keyboard reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = EditorCubit();
      final camera = CameraEditingCubit();
      addTearDown(editor.close);
      addTearDown(camera.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showAutoDirectorDialog(
                    context: context,
                    editor: editor,
                    cameraEditing: camera,
                    onPreviewPlan: (_) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('auto-director-dialog')),
        findsOneWidget,
      );
      expect(find.text('كاميرا تلقائية'), findsWidgets);
      expect(find.text('تعليمي هادئ'), findsOneWidget);
      expect(find.text('المشروع بالكامل'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auto-director-generate')),
        findsOneWidget,
      );
      expect(find.text('كاميرا سريعة'), findsNothing);
      expect(find.text('كاميرا متقدمة'), findsNothing);
      expect(find.text('إنشاء ومعاينة'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('auto-director-advanced-link')),
      );
      await tester.pumpAndSettle();
      expect(find.text('السماح بالحركة أثناء الرسم'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auto-director-dialog')), findsNothing);
    },
  );

  testWidgets(
    'real Generate handler ignores decoded drawing and custom-hand ui.Image',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final image = await _testImage();
      final customHand = image.clone();
      addTearDown(image.dispose);
      addTearDown(customHand.dispose);
      final editor = EditorCubit(
        initialState: EditorState.initial().copyWith(
          drawingImage: image,
          handImage: customHand,
        ),
      );
      final camera = CameraEditingCubit();
      addTearDown(editor.close);
      addTearDown(camera.close);
      final document = editor.state.document;
      final revision = editor.state.documentRevision;
      final history = editor.history.undoEntries.length;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showAutoDirectorDialog(
                  context: context,
                  editor: editor,
                  cameraEditing: camera,
                  onPreviewPlan: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auto-director-generate')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await _pumpUntil(
        tester,
        () =>
            find
                .byKey(const ValueKey('auto-director-preview'))
                .evaluate()
                .isNotEmpty ||
            find
                .text('Could not create the camera plan.')
                .evaluate()
                .isNotEmpty,
      );

      expect(find.text('Could not create the camera plan.'), findsNothing);
      expect(
        find.byKey(const ValueKey('auto-director-preview')),
        findsOneWidget,
      );
      expect(editor.state.document, same(document));
      expect(editor.state.documentRevision, revision);
      expect(editor.history.undoEntries.length, history);
    },
  );

  testWidgets('generation failure is safe, concise, and retryable', (
    tester,
  ) async {
    final editor = EditorCubit();
    final camera = CameraEditingCubit();
    final service = _FailingAutoDirectorService();
    addTearDown(editor.close);
    addTearDown(camera.close);
    final document = editor.state.document;
    final revision = editor.state.documentRevision;
    final history = editor.history.undoEntries.length;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showAutoDirectorDialog(
                context: context,
                editor: editor,
                cameraEditing: camera,
                onPreviewPlan: (_) {},
                service: service,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auto-director-generate')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Could not create the camera plan.'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('#0'), findsNothing);
    expect(find.byKey(const ValueKey('auto-director-retry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auto-director-copy-details')),
      findsOneWidget,
    );
    expect(editor.state.document, same(document));
    expect(editor.state.documentRevision, revision);
    expect(editor.history.undoEntries.length, history);

    await tester.tap(find.byKey(const ValueKey('auto-director-retry')));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(editor.state.document, same(document));
  });

  testWidgets('Auto Camera beginner review surface remains visually stable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = EditorCubit();
    final camera = CameraEditingCubit();
    addTearDown(editor.close);
    addTearDown(camera.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showAutoDirectorDialog(
                  context: context,
                  editor: editor,
                  cameraEditing: camera,
                  onPreviewPlan: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('auto-director-dialog')),
      matchesGoldenFile('goldens/auto_director_dialog.png'),
    );
  });
}

Future<ui.Image> _testImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    ui.Paint()..color = const Color(0xFF336699),
  );
  return recorder.endRecording().toImage(8, 8);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

final class _FailingAutoDirectorService extends AutoDirectorApplicationService {
  int calls = 0;

  @override
  Future<AutoDirectorPlan> generatePlanAsync({
    required CompiledTimeline timeline,
    required CompiledSemanticRegionGraph graph,
    required ProjectCameraTrack? cameraTrack,
    AutoDirectorConfiguration? configuration,
    AutoDirectorScope? scope,
    AutoDirectorProgress? onProgress,
  }) async {
    calls++;
    throw StateError('technical worker stack must stay hidden');
  }
}

(CompiledTimeline, CompiledSemanticRegionGraph) _directorFixture() {
  final timeline = CompiledTimeline(
    dependencyKey: TimelineDependencyKey(
      projectId: ProjectId('preset-test'),
      documentRevision: 1,
    ),
    duration: TimelineDuration.fromMicroseconds(3000000),
    contentEnd: TimelineTime.fromMicroseconds(3000000),
    drawing: null,
    camera: null,
    audio: const [],
    voiceGuide: null,
    sceneMarkers: const [],
  );
  final targets = [
    SemanticTargetReference.stroke(StrokeId('left')),
    SemanticTargetReference.stroke(StrokeId('right')),
  ];
  final bounds = [
    const SemanticWorldBounds(50, 400, 150, 500),
    const SemanticWorldBounds(850, 400, 950, 500),
  ];
  return (
    timeline,
    CompiledSemanticRegionGraph(
      dependencyKey: 'preset-graph',
      worldWidth: 1000,
      worldHeight: 1000,
      regions: [
        for (var i = 0; i < 2; i++)
          SemanticRegion(
            id: targets[i].stableKey,
            target: targets[i],
            kind: SemanticRegionKind.vector,
            geometricBounds: bounds[i],
            visualBounds: bounds[i],
            direction: KnownTextDirection.unknown,
            directionProvenance: DirectionProvenance.unknown,
            metadata: null,
          ),
      ],
      containment: const [],
      drawingOrder: const [],
      adjacency: const [],
      attentionEvents: [
        SemanticAttentionEvent(
          time: TimelineTime.zero,
          regionIds: [targets[0].stableKey],
          activeBounds: bounds[0],
          strokeId: StrokeId('left'),
          sectionId: SectionId('left-section'),
        ),
        SemanticAttentionEvent(
          time: TimelineTime.fromMicroseconds(1500000),
          regionIds: [targets[1].stableKey],
          activeBounds: bounds[1],
          strokeId: StrokeId('right'),
          sectionId: SectionId('right-section'),
        ),
      ],
      handFootprint: const HandFootprintDescriptor(
        provenance: HandFootprintProvenance.unknown,
      ),
    ),
  );
}
