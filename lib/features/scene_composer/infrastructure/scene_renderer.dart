import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';

class SceneRenderer {
  SceneRenderer(this.design, {this.selected, this.selectionColor});
  final SceneDesign design;
  final int? selected;
  final Color? selectionColor;
  void paint(Canvas canvas, Size size) {
    for (final (index, element) in design.elements.indexed) {
      final b = element.bounds;
      final rect = Rect.fromLTWH(
        b.left * size.width,
        b.top * size.height,
        b.width * size.width,
        b.height * size.height,
      );
      canvas.save();
      canvas.clipRect(rect);
      canvas.translate(rect.left, rect.top);
      if (element.isText) {
        final rtl = RegExp(r'[\u0590-\u08ff]').hasMatch(element.text);
        final painter = TextPainter(
          text: TextSpan(
            text: element.text,
            style: TextStyle(
              color: const Color(0xff102333),
              fontSize: rect.height * .78,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final scale = painter.width > rect.width
            ? rect.width / painter.width
            : 1.0;
        canvas.scale(scale);
        painter.paint(canvas, Offset.zero);
        painter.dispose();
      } else {
        canvas.scale(rect.width / 100, rect.height / 100);
        for (final spec in element.paths) {
          final path = scenePath(spec['d']!);
          Color color(String value) =>
              Color(int.parse(value.substring(1), radix: 16) | 0xff000000);
          if (spec['fill'] != 'none') {
            canvas.drawPath(path, Paint()..color = color(spec['fill']!));
          }
          if (spec['stroke'] != 'none') {
            canvas.drawPath(
              path,
              Paint()
                ..color = color(spec['stroke']!)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2
                ..strokeJoin = StrokeJoin.round,
            );
          }
        }
      }
      canvas.restore();
      if (selected == index && selectionColor != null) {
        canvas.drawRect(
          rect,
          Paint()
            ..color = selectionColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  Future<ui.Image> rasterize({int width = 1920, int height = 1080}) async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }
}
