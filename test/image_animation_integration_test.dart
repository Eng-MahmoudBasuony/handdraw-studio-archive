import 'package:handdraw_studio/features/image_animation/domain/image_parts_failure.dart';
import 'package:handdraw_studio/features/codex_assistant/domain/codex_drawing_plan.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'codex_assistant_test.dart' as fixture;
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:flutter/material.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/image_animation/application/saved_drawing_import.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';
import 'support/legacy_editor_state_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pixels = img.Image(width: 80, height: 60, numChannels: 4);
  img.fillRect(
    pixels,
    x1: 10,
    y1: 10,
    x2: 60,
    y2: 40,
    color: img.ColorRgba8(20, 60, 180, 200),
  );
  final png = img.encodePng(pixels);
  Future<ui.Image> image() async {
    final c = await ui.instantiateImageCodec(png);
    final i = (await c.getNextFrame()).image;
    c.dispose();
    return i;
  }

  test(
    'Codex plan keeps a solid panel beneath timed original text with preview/export parity',
    () async {
      final pixels = img.Image(width: 200, height: 100, numChannels: 4);
      img.fillRect(
        pixels,
        x1: 20,
        y1: 10,
        x2: 179,
        y2: 89,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      // A compact glyph fixture inside the measured text line.
      img.fillRect(
        pixels,
        x1: 55,
        y1: 34,
        x2: 58,
        y2: 38,
        color: img.ColorRgba8(0, 0, 0, 255),
      );
      final bytes = img.encodePng(pixels);
      final codec = await ui.instantiateImageCodec(bytes);
      final source = (await codec.getNextFrame()).image;
      codec.dispose();
      final c = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            canvasWidth: 200,
            canvasHeight: 100,
            canvasBackground: const CanvasBackground.solid(0xff334455),
            drawingImageBase64: base64Encode(bytes),
          ),
          drawingImage: source,
        ),
      );
      addTearDown(c.close);
      addTearDown(source.dispose);
      final before = c.state.document;
      final plan = CodexDrawingPlan.parse(fixture.planJson(), [
        SmartTextRegion(
          text: 'a',
          confidence: 1,
          bounds: const Rect.fromLTRB(.2, .3, .7, .42),
        ),
      ]);
      expect(
        await c.applyCodexDrawingPlan(plan, before),
        isTrue,
        reason: c.state.statusMessage,
      );
      expect(c.state.document.sections, hasLength(2));
      expect(
        c.state.document.sections.map(
          (s) => s.timing.animationDuration!.microseconds,
        ),
        [500000, 2000000],
      );
      expect(c.project.showDrawingHand, isTrue);
      expect(c.project.strokes.first.fillColorValue, 0xffffffff);
      expect(c.project.strokes.any((s) => s.isTextShape), isTrue);
      expect(
        await c.applyCodexDrawingPlan(plan, before),
        isFalse,
        reason: 'Stale plans cannot replace later changes',
      );
      for (final progress in [.2, 1.0]) {
        final output = await const FrameRenderer().render(
          project: c.project,
          drawing: source,
          hand: null,
          progress: progress,
        );
        final rgba = (await output.toByteData())!.buffer.asUint8List();
        final pixel = rgba.sublist(
          (36 * 200 + 56) * 4,
          (36 * 200 + 56) * 4 + 4,
        );
        expect(
          pixel,
          progress == 1 ? [0, 0, 0, 255] : [255, 255, 255, 255],
          reason: 'Background first, source glyph later at $progress',
        );
        final recorder = ui.PictureRecorder();
        EditorCanvasPainter(
          state: c.state,
          project: c.project,
          previewProgress: progress,
          isPreviewing: true,
          interfaceTextDirection: TextDirection.ltr,
          emptyStateLabel: '',
          handModeLabel: '',
          revealModeLabel: '',
          ignoreModeLabel: '',
          pathsLabel: '',
          colors: AppPalette.dark,
        ).paint(ui.Canvas(recorder), const ui.Size(200, 100));
        final picture = recorder.endRecording();
        final preview = await picture.toImage(200, 100);
        picture.dispose();
        expect((await preview.toByteData())!.buffer.asUint8List(), rgba);
        preview.dispose();
        output.dispose();
      }
      final firstApplied = c.state.document;
      expect(
        await c.applyCodexDrawingPlan(
          plan,
          firstApplied,
          replacementBase: before,
        ),
        isTrue,
      );
      expect(
        c.state.document.sections,
        hasLength(2),
        reason: 'Follow-up replaces its prior plan without duplicates',
      );
      c.undoStroke();
      expect(c.state.document.strokes, firstApplied.strokes);
      c.undoStroke();
      expect(c.state.document.strokes, before.strokes);
      expect(c.state.document.sectionOrder, before.sectionOrder);
    },
  );

  test(
    'unsupported local background reports its cause and leaves the document intact',
    () async {
      final source = await image();
      final c = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            canvasWidth: 80,
            canvasHeight: 60,
            drawingImageBase64: base64Encode(png),
          ),
          drawingImage: source,
        ),
      );
      addTearDown(c.close);
      addTearDown(source.dispose);
      final before = c.state.document;
      final plan = CodexDrawingPlan.parse(fixture.planJson(), fixture.texts);
      Object? failure;
      expect(
        await c.applyCodexDrawingPlan(
          plan,
          before,
          onFailure: (e) => failure = e,
        ),
        isFalse,
      );
      expect(
        failure,
        isA<ImagePartsFailure>().having(
          (e) => e.code,
          'code',
          'unsupportedBackground',
        ),
      );
      expect(c.state.document, same(before));
      expect(c.state.isAnalyzingSmartPaths, isFalse);
    },
  );

  test('four authored parts preserve order, masks and undo', () async {
    final source = await image();
    final c = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          canvasWidth: 80,
          canvasHeight: 60,
          drawingImageBase64: base64Encode(png),
        ),
        drawingImage: source,
      ),
    );
    addTearDown(c.close);
    addTearDown(source.dispose);
    c.setImageAnimationEffect('drawPaint');
    await c.prepareImageAnimation();
    final before = c.state.document;
    final parts = [
      for (var i = 0; i < 4; i++)
        SceneRegion(
          id: 'part-$i',
          name: 'Part $i',
          polygon: rectPolygon(
            Rect.fromLTWH((10 + i * 12) / 80, 10 / 60, 12 / 80, 30 / 60),
          ),
        ),
    ];
    await c.prepareImageAnimation(regions: parts);
    expect(
      c.state.document.sections,
      hasLength(4),
      reason: c.state.statusMessage,
    );
    final ids = c.timelineSectionOrder;
    expect(ids, hasLength(4));
    for (var i = 0; i < 4; i++) {
      final strokes = c.project.strokes
          .where((s) => s.sectionId == ids[i])
          .toList();
      expect(strokes, isNotEmpty);
      expect(strokes.every((s) => s.clipPolygons.isNotEmpty), isTrue);
      expect(
        strokes.first.clipBounds!.left,
        closeTo(parts[i].bounds.left, .02),
      );
      for (final region in strokes.map((s) => s.paintRegion).toSet()) {
        final regional = strokes.where((s) => s.paintRegion == region).toList();
        final paints = regional.where((s) => s.isPaintStroke).toList();
        expect(paints.length, lessThanOrEqualTo(1));
        if (paints.isNotEmpty) expect(regional.last, paints.single);
      }
    }
    final rendered = await FrameRenderer().render(
      project: c.project,
      drawing: source,
      hand: null,
      progress: 1,
    );
    final bytes = (await rendered.toByteData())!.buffer.asUint8List();
    expect(bytes[(25 * 80 + 5) * 4 + 3], 0);
    expect(
      bytes[(25 * 80 + 59) * 4 + 3],
      0,
      reason: 'Pixels outside the authored regions stay hidden',
    );
    for (final x in [15, 27, 39, 51]) {
      expect(
        bytes[(25 * 80 + x) * 4 + 3],
        greaterThan(0),
        reason: 'Each part is drawn in the exported final frame',
      );
    }
    rendered.dispose();
    const codec = DevelopmentProjectManifestCodec();
    expect(codec.decode(codec.encode(c.state.document)).sections, hasLength(4));
    c.undoStroke();
    expect(c.state.document.strokes, before.strokes);
    expect(c.state.document.sectionOrder, before.sectionOrder);
  });

  test(
    'single pen reveal keeps color and alpha and covers without a terminal jump',
    () async {
      final source = await image();
      final c = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            canvasWidth: 80,
            canvasHeight: 60,
            drawingImageBase64: base64Encode(png),
          ),
          drawingImage: source,
        ),
      );
      addTearDown(c.close);
      c.setImageAnimationEffect('penReveal');
      expect(c.project.imageAnimationEffect, 'penReveal');
      await c.prepareImageAnimation();
      expect(c.project.strokes, hasLength(1));
      expect(
        c.project.strokes.single.revealStyle,
        RevealMaskStyle.directionalWipe,
      );
      expect(c.setImageAnimationDuration(2), isTrue);
      const codec = DevelopmentProjectManifestCodec();
      expect(
        codec
            .decode(codec.encode(c.state.document))
            .motionConfiguration
            .imageAnimationEffect,
        'penReveal',
      );
      for (final progress in [0.0, .25, .5, .75, .999, 1.0]) {
        final rendered = await FrameRenderer().render(
          project: c.project,
          drawing: source,
          hand: null,
          progress: progress,
        );
        final bytes = (await rendered.toByteData())!.buffer.asUint8List();
        int alpha(int x, int y) => bytes[(y * 80 + x) * 4 + 3];
        expect(alpha(5, 5), 0, reason: 'Original transparency survives');
        if (progress == 0) expect(alpha(20, 25), 0);
        if (progress == .5) {
          expect(alpha(20, 25), 200);
          expect(alpha(55, 25), 0);
        }
        if (progress >= .999) expect(alpha(60, 40), 200);
        rendered.dispose();
      }
    },
  );

  test(
    'real source import prepares, saves and reopens a project container',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'integrated-project',
      );
      final files = _ImageFiles(
        '${folder.path}/project.koni',
        await File('test/fixtures/00-title.png').readAsBytes(),
      );
      final c = EditorCubit(fileService: files);
      try {
        await c.importDrawing();
        await c.prepareImageAnimation();
        expect(c.project.strokes, isNotEmpty, reason: c.state.statusMessage);
        c.reverseStroke(1);
        await c.saveProject();
        expect(await File(files.path).exists(), isTrue);
        await c.openProject();
        expect(c.project.imageAnimationEffect, 'drawPaint');
        expect(c.project.strokes[1].reversed, isTrue);
      } finally {
        await c.close();
        await folder.delete(recursive: true);
      }
    },
  );
  test(
    'analysis commits one section, keeps other paths and timing, supports undo and native manifest',
    () async {
      final source = await image();
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: 'source.png',
            drawingSourceBase64: base64Encode(png),
            durationSeconds: 9,
            startDelaySeconds: .3,
            endHoldSeconds: 1,
            canvasBackground: const CanvasBackground.solid(0xff123456),
            strokes: [
              DrawingStroke(
                id: 'one',
                sectionId: 'first',
                name: 'first',
                points: const [ui.Offset(.1, .1), ui.Offset(.2, .2)],
              ),
              DrawingStroke(
                id: 'keep',
                sectionId: 'other',
                name: 'keep',
                reversed: true,
                points: const [ui.Offset(.5, .5), ui.Offset(.8, .8)],
              ),
            ],
          ),
          drawingImage: source,
        ),
      );
      final before = cubit.state.document;
      await cubit.prepareImageAnimation();
      expect(
        cubit.project.imageAnimationEffect,
        'drawPaint',
        reason: cubit.state.statusMessage,
      );
      expect(cubit.state.document.sections.length, 2);
      expect(cubit.state.document.strokes.last, same(before.strokes.last));
      expect(cubit.state.document.duration, before.duration);
      expect(cubit.state.document.canvas.background, before.canvas.background);
      expect(cubit.project.startDelaySeconds, .3);
      expect(cubit.project.endHoldSeconds, 1);
      expect(cubit.project.strokes.any((s) => s.isPaintStroke), isTrue);
      const codec = DevelopmentProjectManifestCodec();
      final saved = codec.encode(cubit.state.document);
      final reopened = codec.decode(saved);
      expect(codec.encode(reopened), saved);
      cubit.undoStroke();
      expect(cubit.state.document.strokes, before.strokes);
      expect(cubit.project.imageAnimationEffect, 'legacy');
      cubit.redoStroke();
      expect(cubit.project.imageAnimationEffect, 'drawPaint');
      final geometry = cubit.state.document.strokes;
      cubit.setShowDrawingHand(false);
      expect(cubit.state.document.strokes, geometry);
      for (var i = 0; i < geometry.length; i++) {
        expect(cubit.state.document.strokes[i], same(geometry[i]));
      }
      expect(cubit.isImageAnimationAnalyzing, isFalse);
      expect(cubit.project.showDrawingHand, isFalse);
      await cubit.close();
      source.dispose();
    },
  );
  test('manual press to lift is one editable stroke in one section', () async {
    final source = await image();
    final c = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: 'source.png',
          imageAnimationEffect: 'drawPaint',
        ),
        drawingImage: source,
      ),
    );
    c.setTool(EditorTool.drawPath);
    for (final y in [10.0, 40.0]) {
      c.beginStroke(ui.Offset(10, y), const ui.Rect.fromLTWH(0, 0, 80, 60));
      c.updateStroke(ui.Offset(50, y), const ui.Rect.fromLTWH(0, 0, 80, 60));
      c.endStroke();
    }
    expect(c.project.strokes.length, 2);
    expect(c.state.document.sections.length, 1);
    final id = c.project.strokes.last.id;
    c.reverseStroke(1);
    c.setStrokePainting(1, true);
    c.moveStroke(1, -1);
    expect(c.project.strokes.first.id, id);
    expect(c.project.strokes.first.reversed, isTrue);
    expect(c.project.strokes.first.isPaintStroke, isTrue);
    c.deleteStroke(0);
    expect(c.project.strokes.length, 1);
    c.undoStroke();
    expect(c.project.strokes.length, 2);
    await c.close();
    source.dispose();
  });
  test('cancelled analysis never replaces authored paths', () async {
    final source = await image();
    final c = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: 'source.png',
          drawingSourceBase64: base64Encode(png),
        ),
        drawingImage: source,
      ),
    );
    final before = c.state.document;
    final pending = c.prepareImageAnimation();
    c.cancelImageAnimation();
    await pending;
    expect(c.state.document, same(before));
    expect(c.state.isAnalyzingSmartPaths, isFalse);
    await c.close();
    source.dispose();
  });
  test(
    'main canvas and export paint identical authored frames on the chosen background',
    () async {
      final source = await image();
      final c = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            canvasWidth: 80,
            canvasHeight: 60,
            drawingImagePath: 'source.png',
            drawingSourceBase64: base64Encode(png),
            canvasBackground: const CanvasBackground.solid(0xff334455),
          ),
          drawingImage: source,
        ),
      );
      await c.prepareImageAnimation();
      for (final progress in [0.0, .25, .5, .75, 1.0]) {
        final recorder = ui.PictureRecorder();
        EditorCanvasPainter(
          state: c.state,
          project: c.project,
          previewProgress: progress,
          isPreviewing: true,
          interfaceTextDirection: TextDirection.ltr,
          emptyStateLabel: '',
          handModeLabel: '',
          revealModeLabel: '',
          ignoreModeLabel: '',
          pathsLabel: '',
          colors: AppPalette.dark,
        ).paint(ui.Canvas(recorder), const ui.Size(80, 60));
        final picture = recorder.endRecording();
        final preview = await picture.toImage(80, 60);
        picture.dispose();
        final output = await const FrameRenderer().render(
          project: c.project,
          drawing: source,
          hand: null,
          progress: progress,
        );
        final a = (await preview.toByteData())!.buffer.asUint8List(),
            b = (await output.toByteData())!.buffer.asUint8List();
        expect(a, b, reason: 'Frame at $progress');
        expect(b.sublist(0, 4), [0x33, 0x44, 0x55, 255]);
        preview.dispose();
        output.dispose();
      }
      await c.close();
      source.dispose();
    },
  );
  test(
    'retired experiment imports source, stroke edits and background into a normal manifest',
    () {
      final data = jsonEncode({
        'format': 'handdraw-drawing-lab',
        'version': 1,
        'source': base64Encode(png),
        'showHand': false,
        'paintEffect': true,
        'project': HandDrawProject(
          canvasBackground: const CanvasBackground.solid(0xff334455),
        ).toJson(),
        'strokes': [
          {
            'stroke': DrawingStroke(
              id: 'edited',
              name: 'edited',
              reversed: true,
              points: const [ui.Offset(.1, .1), ui.Offset(.8, .8)],
            ).toJson(),
            'role': 'paint',
            'region': 3,
          },
        ],
      });
      final result = SavedDrawingImport.decode(data);
      const codec = DevelopmentProjectManifestCodec();
      final roundtrip = codec.decode(codec.encode(result.document));
      expect(roundtrip.strokes.single.reversed, isTrue);
      expect(roundtrip.strokes.single.isPaintStroke, isTrue);
      expect(roundtrip.strokes.single.paintRegion, 3);
      expect(roundtrip.motionConfiguration.showDrawingHand, isFalse);
      expect(result.sources.values.single, png);
      expect(roundtrip.canvas.background.colorValue, 0xff334455);
    },
  );
}

class _ImageFiles extends EditorFileService {
  const _ImageFiles(this.path, this.bytes);
  final String path;
  final Uint8List bytes;
  @override
  Future<ImportedEditorAsset?> pickDrawing({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) => loadImageBytes(path: 'title.png', bytes: bytes);
  @override
  Future<String?> pickProjectSavePath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => path;
  @override
  Future<String?> pickProjectOpenPath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => path;
}
