import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_renderer.dart';

class SceneDesignPainter extends CustomPainter {
  SceneDesignPainter(this.design, {this.selected, this.selectionColor});
  final SceneDesign design;
  final int? selected;
  final Color? selectionColor;
  @override
  void paint(Canvas canvas, Size size) => SceneRenderer(
    design,
    selected: selected,
    selectionColor: selectionColor,
  ).paint(canvas, size);
  Future<ui.Image> rasterize({int width = 1920, int height = 1080}) =>
      SceneRenderer(
        design,
        selected: selected,
        selectionColor: selectionColor,
      ).rasterize(width: width, height: height);
  @override
  bool shouldRepaint(SceneDesignPainter old) =>
      old.design != design ||
      old.selected != selected ||
      old.selectionColor != selectionColor;
}
