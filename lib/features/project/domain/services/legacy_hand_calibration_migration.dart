import 'dart:ui' show Offset;

import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

/// Replaces only pen-tip coordinates that were previously shipped for bundled
/// hands. Deliberate/user calibration and every custom hand are preserved.
final class LegacyHandCalibrationMigration {
  const LegacyHandCalibrationMigration();

  static const _technicalPresetId = 'marker-technical-wheat-right';
  static const _technicalFileName = 'technical-pen-wheat-right-v1.png';
  static const _genericMarkerTip = DocumentPoint(0.18, 0.72);

  ProjectDocument migrate(ProjectDocument document) {
    final hand = document.handConfiguration;
    final asset = document.assets
        .where((candidate) => candidate.id == hand.assetId)
        .firstOrNull;
    // Old empty projects had no explicit hand reference, while the runtime
    // still displayed the bundled Technical Pen. Their generic marker anchor
    // therefore appeared well below the visible nib. With no configured hand,
    // the selected built-in default is the Technical Pen and can be repaired
    // safely without overriding a deliberate custom calibration.
    final usesBundledDefault = hand.presetId == null && hand.assetId == null;
    final isTechnicalPen =
        hand.presetId == _technicalPresetId ||
        asset?.originalFileName.toLowerCase() == _technicalFileName ||
        usesBundledDefault;
    final preset = _preset(hand.presetId);
    final replacementTip =
        preset != null &&
            hand.penTip != _point(preset.penTip) &&
            _isPreviouslyShippedTip(hand.penTip)
        ? _point(preset.penTip)
        : isTechnicalPen &&
              (hand.penTip == _genericMarkerTip ||
                  hand.penTip == const DocumentPoint(0.115, 0.488))
        ? _point(BuiltInHands.wheatTechnicalPenRight.penTip)
        : null;
    if (replacementTip == null) return document;

    return document.copyWith(
      handConfiguration: hand.copyWith(penTip: replacementTip),
    );
  }

  HandPreset? _preset(String? id) =>
      BuiltInHands.all.where((preset) => preset.id == id).firstOrNull;

  bool _isPreviouslyShippedTip(DocumentPoint point) =>
      point == _genericMarkerTip ||
      const [
        DocumentPoint(0.115, 0.642),
        DocumentPoint(0.150, 0.563),
        DocumentPoint(0.190, 0.563),
        DocumentPoint(0.376, 0.045),
        DocumentPoint(0.115, 0.488),
      ].contains(point) ||
      BuiltInHands.all.any((preset) => point == _point(preset.penTip));

  DocumentPoint _point(Offset point) => DocumentPoint(point.dx, point.dy);
}
