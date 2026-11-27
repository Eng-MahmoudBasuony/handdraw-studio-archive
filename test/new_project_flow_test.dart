import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/application/new_project_request.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

void main() {
  testWidgets('clean project opens wizard and Cancel changes nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = EditorCubit(initialState: EditorState.initial());
    addTearDown(cubit.close);
    expect(cubit.isDirty, isFalse);
    final id = cubit.state.document.id;
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.tap(find.byTooltip('New'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-project-dialog')), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(cubit.state.document.id, id);
  });

  testWidgets(
    'dirty project requires explicit discard then creates atomic project',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cubit = EditorCubit();
      addTearDown(cubit.close);
      cubit.addCameraShotAt(TimelineTime.zero);
      final prior = cubit.state.document.id;
      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      await tester.tap(find.byTooltip('New'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dirty-project-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.text("Don't Save"));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('new-project-title')),
        'Course Project',
      );
      await tester.tap(find.byKey(const ValueKey('create-new-project')));
      await tester.pumpAndSettle();
      expect(cubit.state.document.id, isNot(prior));
      expect(cubit.state.document.title, 'Course Project');
      expect(cubit.state.document.canvas.width, 1920);
      expect(cubit.state.document.canvas.height, 1080);
      expect(cubit.canUndo, isFalse);
    },
  );

  testWidgets('dirty project Cancel preserves document and history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    final before = cubit.state.document;
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.tap(find.byTooltip('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(cubit.state.document, same(before));
    expect(cubit.canUndo, isTrue);
  });

  test('creation choices persist on the new document', () async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    final created = await cubit.createNewProject(
      const NewProjectRequest(
        title: 'Portrait element',
        width: 1080,
        height: 1920,
        frameRate: FrameRate.fps60,
        background: NewProjectBackground.color,
        defaultImportIntent: ArtworkImportIntent.element,
      ),
    );
    expect(created, isTrue);
    expect(
      cubit.state.document.creationDefaults.background,
      ProjectCanvasBackground.color,
    );
    expect(
      cubit.state.document.creationDefaults.importIntent,
      ArtworkImportIntent.element,
    );
    expect(
      cubit.state.document.canvas.background,
      const CanvasBackground.solid(0xFFFFFFFF),
    );
    expect(cubit.state.document.frameRate, FrameRate.fps60);
    final reopened = const DevelopmentProjectManifestCodec().decode(
      const DevelopmentProjectManifestCodec().encode(cubit.state.document),
    );
    expect(reopened.creationDefaults.background, ProjectCanvasBackground.color);
    expect(
      reopened.canvas.background,
      const CanvasBackground.solid(0xFFFFFFFF),
    );
    expect(reopened.creationDefaults.importIntent, ArtworkImportIntent.element);
  });
}
