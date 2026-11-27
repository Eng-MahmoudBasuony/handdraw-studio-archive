import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';

enum AutoDirectorPresetId {
  educationalCalm,
  classicWhiteboard,
  dynamicExplainer,
  presentation,
  noMotion,
  custom,
}

enum DirectorMotionAmount { minimal, balanced, dynamic, none }

enum DirectorFraming { wide, balanced, close }

enum DirectorTransitionPreference { cut, fade, move, balanced }

enum DirectorOverviewFrequency { never, groupsOnly, periodic }

final class AutoDirectorCustomOverrides {
  const AutoDirectorCustomOverrides({
    this.motionAmount,
    this.framing,
    this.textEmphasis,
    this.minimumHold,
    this.transitionPreference,
    this.allowMovementDuringDrawing,
    this.overviewFrequency,
    this.handSafeFraming,
  });

  final DirectorMotionAmount? motionAmount;
  final DirectorFraming? framing;
  final double? textEmphasis;
  final Duration? minimumHold;
  final DirectorTransitionPreference? transitionPreference;
  final bool? allowMovementDuringDrawing;
  final DirectorOverviewFrequency? overviewFrequency;
  final bool? handSafeFraming;

  bool get isEmpty =>
      motionAmount == null &&
      framing == null &&
      textEmphasis == null &&
      minimumHold == null &&
      transitionPreference == null &&
      allowMovementDuringDrawing == null &&
      overviewFrequency == null &&
      handSafeFraming == null;
}

final class ProjectAutoDirectorSettings {
  const ProjectAutoDirectorSettings({
    this.presetId = AutoDirectorPresetId.educationalCalm,
    this.presetVersion = AutoDirectorPresetCatalog.currentVersion,
    this.customOverrides = const AutoDirectorCustomOverrides(),
  });

  final AutoDirectorPresetId presetId;
  final int presetVersion;
  final AutoDirectorCustomOverrides customOverrides;
}

final class AutoDirectorPreset {
  const AutoDirectorPreset({
    required this.id,
    required this.version,
    required this.motionAmount,
    required this.framing,
    required this.textEmphasis,
    required this.minimumHold,
    required this.transitionPreference,
    required this.allowMovementDuringDrawing,
    required this.overviewFrequency,
    required this.handSafeFraming,
  });

  final AutoDirectorPresetId id;
  final int version;
  final DirectorMotionAmount motionAmount;
  final DirectorFraming framing;
  final double textEmphasis;
  final Duration minimumHold;
  final DirectorTransitionPreference transitionPreference;
  final bool allowMovementDuringDrawing;
  final DirectorOverviewFrequency overviewFrequency;
  final bool handSafeFraming;
}

final class AutoDirectorPresetCatalog {
  const AutoDirectorPresetCatalog();
  static const currentVersion = 1;

  static const presets = <AutoDirectorPresetId, AutoDirectorPreset>{
    AutoDirectorPresetId.educationalCalm: AutoDirectorPreset(
      id: AutoDirectorPresetId.educationalCalm,
      version: currentVersion,
      motionAmount: DirectorMotionAmount.minimal,
      framing: DirectorFraming.balanced,
      textEmphasis: .9,
      minimumHold: Duration(milliseconds: 1100),
      transitionPreference: DirectorTransitionPreference.cut,
      allowMovementDuringDrawing: false,
      overviewFrequency: DirectorOverviewFrequency.groupsOnly,
      handSafeFraming: true,
    ),
    AutoDirectorPresetId.classicWhiteboard: AutoDirectorPreset(
      id: AutoDirectorPresetId.classicWhiteboard,
      version: currentVersion,
      motionAmount: DirectorMotionAmount.balanced,
      framing: DirectorFraming.balanced,
      textEmphasis: .75,
      minimumHold: Duration(milliseconds: 850),
      transitionPreference: DirectorTransitionPreference.balanced,
      allowMovementDuringDrawing: false,
      overviewFrequency: DirectorOverviewFrequency.groupsOnly,
      handSafeFraming: true,
    ),
    AutoDirectorPresetId.dynamicExplainer: AutoDirectorPreset(
      id: AutoDirectorPresetId.dynamicExplainer,
      version: currentVersion,
      motionAmount: DirectorMotionAmount.dynamic,
      framing: DirectorFraming.close,
      textEmphasis: .65,
      minimumHold: Duration(milliseconds: 650),
      transitionPreference: DirectorTransitionPreference.move,
      allowMovementDuringDrawing: true,
      overviewFrequency: DirectorOverviewFrequency.groupsOnly,
      handSafeFraming: true,
    ),
    AutoDirectorPresetId.presentation: AutoDirectorPreset(
      id: AutoDirectorPresetId.presentation,
      version: currentVersion,
      motionAmount: DirectorMotionAmount.minimal,
      framing: DirectorFraming.wide,
      textEmphasis: .7,
      minimumHold: Duration(milliseconds: 1000),
      transitionPreference: DirectorTransitionPreference.fade,
      allowMovementDuringDrawing: false,
      overviewFrequency: DirectorOverviewFrequency.periodic,
      handSafeFraming: true,
    ),
    AutoDirectorPresetId.noMotion: AutoDirectorPreset(
      id: AutoDirectorPresetId.noMotion,
      version: currentVersion,
      motionAmount: DirectorMotionAmount.none,
      framing: DirectorFraming.wide,
      textEmphasis: .8,
      minimumHold: Duration(milliseconds: 1200),
      transitionPreference: DirectorTransitionPreference.cut,
      allowMovementDuringDrawing: false,
      overviewFrequency: DirectorOverviewFrequency.never,
      handSafeFraming: true,
    ),
  };
}

final class AutoDirectorPresetMapper {
  const AutoDirectorPresetMapper();

  AutoDirectorConfiguration configuration(
    ProjectAutoDirectorSettings settings,
  ) {
    final base =
        AutoDirectorPresetCatalog.presets[settings.presetId ==
                AutoDirectorPresetId.custom
            ? AutoDirectorPresetId.educationalCalm
            : settings.presetId]!;
    final overrides = settings.customOverrides;
    final motion = overrides.motionAmount ?? base.motionAmount;
    final framing = overrides.framing ?? base.framing;
    final transition =
        overrides.transitionPreference ?? base.transitionPreference;
    final hold = overrides.minimumHold ?? base.minimumHold;
    final overview = overrides.overviewFrequency ?? base.overviewFrequency;
    final handSafe = overrides.handSafeFraming ?? base.handSafeFraming;
    return AutoDirectorConfiguration(
      safePaddingFraction: !handSafe
          ? .06
          : framing == DirectorFraming.wide
          ? .18
          : framing == DirectorFraming.close
          ? .08
          : .12,
      innerSafeFraction: motion == DirectorMotionAmount.dynamic ? .82 : .68,
      maximumDeadZoneCenterDelta: motion == DirectorMotionAmount.dynamic
          ? .045
          : motion == DirectorMotionAmount.balanced
          ? .08
          : .13,
      maximumDeadZoneLogZoomDelta: motion == DirectorMotionAmount.dynamic
          ? .08
          : .16,
      minimumHold: hold,
      preferredMoveDuration: motion == DirectorMotionAmount.dynamic
          ? const Duration(milliseconds: 320)
          : const Duration(milliseconds: 520),
      maximumMovementsPerWindow: motion == DirectorMotionAmount.dynamic
          ? 4
          : motion == DirectorMotionAmount.none
          ? 1
          : 2,
      maximumMovesPerTenSeconds: motion == DirectorMotionAmount.dynamic
          ? 8
          : motion == DirectorMotionAmount.none
          ? 1
          : 4,
      maximumNormalizedPanSpeed: motion == DirectorMotionAmount.dynamic
          ? 1.5
          : .9,
      maximumLogZoomSpeed: motion == DirectorMotionAmount.dynamic ? 1.2 : .8,
      maximumDirectionReversals: motion == DirectorMotionAmount.dynamic ? 4 : 2,
      minimumTextScreenFraction:
          .10 + ((overrides.textEmphasis ?? base.textEmphasis) * .08),
      allowFade:
          transition == DirectorTransitionPreference.fade ||
          transition == DirectorTransitionPreference.balanced,
      allowMovementTransitions:
          motion != DirectorMotionAmount.none &&
          transition != DirectorTransitionPreference.cut &&
          transition != DirectorTransitionPreference.fade,
      allowMovementDuringDrawing:
          overrides.allowMovementDuringDrawing ??
          base.allowMovementDuringDrawing,
      preferFadeForCuts: transition == DirectorTransitionPreference.fade,
      allowOverview: overview != DirectorOverviewFrequency.never,
      overviewPreference: overview == DirectorOverviewFrequency.periodic
          ? .9
          : 0,
      handSafeFraming: handSafe,
    );
  }
}
