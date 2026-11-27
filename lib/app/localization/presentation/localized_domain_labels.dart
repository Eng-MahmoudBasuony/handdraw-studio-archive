import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

extension LocalizedWritingSoundPreset on WritingSoundPreset {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    WritingSoundPreset.pencil => l10n.pencilOnPaper,
    WritingSoundPreset.marker => l10n.markerOnPaper,
    WritingSoundPreset.technicalPen => l10n.technicalPen,
    WritingSoundPreset.recordedSoftPaper => l10n.realPaperSoft,
    WritingSoundPreset.recordedPencilPaper => l10n.realPaperPencil,
    WritingSoundPreset.recordedNaturalPaper => l10n.realPaperNatural,
    WritingSoundPreset.recordedQuickPaper => l10n.realPaperQuick,
  };
}

extension LocalizedHandPreset on HandPreset {
  String localizedName(AppLocalizations l10n) => switch (id) {
    'marker-right' => l10n.handMarkerRight,
    'marker-left' => l10n.handMarkerLeft,
    'marker-compact' => l10n.handMarkerCompact,
    'marker-dark-right' => l10n.handDarkMarkerRight,
    'marker-fineliner-right' => l10n.handFineLinerRight,
    'marker-blue-right' => l10n.handBlueMarkerRight,
    'marker-front-black-right' => l10n.handFrontBlackMarkerRight,
    'marker-technical-wheat-right' => l10n.handTechnicalPenWheat,
    _ => name,
  };
}
