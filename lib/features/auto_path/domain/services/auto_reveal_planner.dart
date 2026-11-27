import 'dart:ui';

import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';

class AutoRevealPlan {
  const AutoRevealPlan({required this.strokes, required this.usedFallback});

  final List<DrawingStroke> strokes;
  final bool usedFallback;
}

/// Builds a hand-free reveal animation from the same platform-neutral
/// analysis used by Auto Path. Detection and animation policy remain separate,
/// so other platforms can reuse the planner without macOS APIs.
class AutoRevealPlanner {
  const AutoRevealPlanner([this._pathPlanner = const AutoPathStrokePlanner()]);

  final AutoPathStrokePlanner _pathPlanner;

  AutoRevealPlan build({
    required List<SmartPathSection> sections,
    required HandDrawProject project,
  }) {
    if (sections.isNotEmpty) {
      final revealSections = sections
          .map((section) => section.copyWith(mode: SmartSectionMode.revealText))
          .toList(growable: false);
      final plan = _pathPlanner.build(
        sections: revealSections,
        project: project,
        useDirectionalWipes: true,
      );
      if (plan.strokes.isNotEmpty) {
        return AutoRevealPlan(strokes: plan.strokes, usedFallback: false);
      }
    }

    return AutoRevealPlan(
      strokes: [
        DrawingStroke(
          id: 'auto-reveal-all-${DateTime.now().microsecondsSinceEpoch}',
          name: 'Entire Artwork • Auto Reveal',
          points: const [Offset(0.001, 0.5), Offset(0.999, 0.5)],
          revealOnly: true,
          revealStyle: RevealMaskStyle.directionalWipe,
          sectionId: 'auto-reveal-all',
          clipBounds: const Rect.fromLTWH(0, 0, 1, 1),
          revealWidth: project.canvasHeight.toDouble(),
        ),
      ],
      usedFallback: true,
    );
  }
}
