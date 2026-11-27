import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/branding/app_brand_assets.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final darkTheme = Theme.of(context).brightness == Brightness.dark;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Image.asset(
        darkTheme
            ? AppBrandAssets.logoForDarkTheme
            : AppBrandAssets.logoForLightTheme,
        key: ValueKey(darkTheme),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'HandDraw Studio',
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.draw_rounded,
          size: size,
          color: context.studioColors.accent,
        ),
      ),
    );
  }
}
