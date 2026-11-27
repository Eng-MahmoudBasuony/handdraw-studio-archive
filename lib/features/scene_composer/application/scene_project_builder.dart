import 'dart:convert';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';
import 'dart:ui' as ui;
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/codex_assistant/domain/codex_drawing_plan.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_renderer.dart';

class SceneProjectBuilder {
  const SceneProjectBuilder();
  Future<EditorCubit> build(SceneDesign design) async {
    design = SceneDesign.parse(design.toJson());
    // Separate source bounds prevent another element from leaking into a reveal.
    for (var i = 0; i < design.elements.length; i++) {
      for (var j = i + 1; j < design.elements.length; j++) {
        if (design.elements[i].bounds.overlaps(design.elements[j].bounds)) {
          throw const FormatException(
            'باعد بين العناصر المتداخلة قبل التنفيذ / Separate overlapping elements before applying',
          );
        }
      }
    }
    final editor = EditorCubit();
    try {
      await editor.initializeHandLibrary();
      if (editor.state.handImage == null) {
        throw StateError(editor.state.statusMessage);
      }
      final image = await SceneRenderer(design).rasterize();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      await editor.importDrawing(
        preparedAsset: ImportedEditorAsset(
          path: '${design.title}.png',
          encoded: base64Encode(bytes),
          image: image,
        ),
      );
      editor.setCanvasBackground(const CanvasBackground.solid(0xffffffff));
      final texts = <SmartTextRegion>[];
      final parts = <CodexDrawingPart>[];
      for (final e in design.elements) {
        if (e.isText) {
          texts.add(
            SmartTextRegion(text: e.text, bounds: e.bounds, confidence: 1),
          );
        }
        parts.add(
          CodexDrawingPart(
            id: 'scene-part-${parts.length}',
            name: e.name,
            bounds: e.bounds,
            mode: e.isText ? 'write' : 'drawPaint',
            seconds: e.seconds,
            excludeText: false,
          ),
        );
      }
      final plan = CodexDrawingPlan(
        summary: design.title,
        confidence: 1,
        showHand: true,
        parts: parts,
        textRegions: texts,
      );
      if (!await editor.applyCodexDrawingPlan(plan, editor.state.document)) {
        throw StateError(editor.state.statusMessage);
      }
      return editor;
    } catch (_) {
      await editor.close();
      rethrow;
    }
  }
}
