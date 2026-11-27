import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';

enum StudioIconData {
  newProject('new-project'),
  openProject('open-project'),
  saveProject('save-project'),
  clearCanvas('clear-canvas'),
  drawing('drawing'),
  hand('hand'),
  penTip('pen-tip'),
  autoPath('auto-path'),
  autoReveal('auto-reveal'),
  select('select'),
  drawPath('draw-path'),
  revealText('reveal-text'),
  voice('voice'),
  preview('preview'),
  exportMovie('export'),
  inspector('inspector'),
  about('about'),
  whatsNew('whats-new'),
  copy('copy'),
  licenses('licenses'),
  undo('undo'),
  redo('redo');

  const StudioIconData(this.assetName);

  final String assetName;

  String get assetPath => 'assets/icons/$assetName.svg';
}

/// Renders the product icon language from a single, theme-aware entry point.
///
/// SVGs intentionally contain no fixed colors. This keeps disabled, selected,
/// hover and light/dark behavior under Flutter's existing button themes.
class StudioIcon extends StatelessWidget {
  const StudioIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  final StudioIconData icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? IconTheme.of(context).color;
    return SvgPicture.asset(
      icon.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: resolvedColor == null
          ? null
          : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      placeholderBuilder: (_) => SizedBox.square(dimension: size),
      errorBuilder: (_, _, _) => Icon(
        Icons.draw_rounded,
        size: size,
        color: resolvedColor ?? context.studioColors.accent,
      ),
    );
  }
}
