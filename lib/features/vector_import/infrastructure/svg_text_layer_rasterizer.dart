import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

import 'package:handdraw_studio/features/vector_import/infrastructure/svg_render_source_builder.dart';

/// Renders an SVG's text elements on transparency for exact glyph tracing.
class SvgTextLayerRasterizer {
  const SvgTextLayerRasterizer({
    this.sourceBuilder = const SvgRenderSourceBuilder(),
  });

  final SvgRenderSourceBuilder sourceBuilder;

  static const maximumDimension = 4096;

  Future<ui.Image> rasterize(String source) async {
    final textSource = sourceBuilder.build(source).textArtwork;
    final pictureInfo = await vg.loadPicture(SvgStringLoader(textSource), null);
    final size = pictureInfo.size;
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      pictureInfo.picture.dispose();
      throw const FormatException('The SVG text layer has no valid size.');
    }
    final scale = maximumDimension / size.longestSide;
    final width = (size.width * scale).round().clamp(1, maximumDimension);
    final height = (size.height * scale).round().clamp(1, maximumDimension);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    canvas.drawPicture(pictureInfo.picture);
    final rasterPicture = recorder.endRecording();
    pictureInfo.picture.dispose();
    final image = await rasterPicture.toImage(width, height);
    rasterPicture.dispose();
    return image;
  }
}
