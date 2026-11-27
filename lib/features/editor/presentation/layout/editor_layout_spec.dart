import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum EditorLayoutTier { wide, compact, narrow }

/// The single source of truth for editor breakpoints and responsive spacing.
/// Presentation widgets consume this value instead of inventing local width
/// checks, which keeps the desktop layout predictable as more tools are added.
class EditorLayoutSpec {
  const EditorLayoutSpec._({
    required this.tier,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  factory EditorLayoutSpec.fromConstraints(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final tier = width >= 1680
        ? EditorLayoutTier.wide
        : width >= 980
        ? EditorLayoutTier.compact
        : EditorLayoutTier.narrow;
    return EditorLayoutSpec._(
      tier: tier,
      viewportWidth: width,
      viewportHeight: constraints.maxHeight,
    );
  }

  final EditorLayoutTier tier;
  final double viewportWidth;
  final double viewportHeight;

  bool get isWide => tier == EditorLayoutTier.wide;
  bool get isCompact => tier == EditorLayoutTier.compact;
  bool get isNarrow => tier == EditorLayoutTier.narrow;
  bool get docksInspector => !isNarrow;
  bool get usesTwoRowToolbar => !isWide;
  bool get showsBrandLabel => viewportWidth >= 980;
  bool get usesFileMenu => viewportWidth < 760;
  bool get showsAssetLabels => viewportWidth >= 900;
  bool get showsToolLabels => viewportWidth >= 700;
  bool get showsStatusDetails => viewportWidth >= 720;

  double get toolbarHeight => usesTwoRowToolbar ? 108 : 62;
  double get inspectorWidth => isWide
      ? (viewportWidth * 0.23).clamp(350.0, 420.0)
      : (viewportWidth * 0.29).clamp(310.0, 360.0);
  double get inspectorDrawerWidth => math.min(420, viewportWidth * 0.92);
  double get canvasMaxWidth => isWide ? 1320 : 1180;
  EdgeInsets get workspacePadding => EdgeInsets.all(
    isWide
        ? 20
        : isCompact
        ? 12
        : 8,
  );
}
