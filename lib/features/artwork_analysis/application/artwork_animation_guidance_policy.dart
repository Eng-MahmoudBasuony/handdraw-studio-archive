import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_animation_guidance.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/raster_alpha_bounds_scanner.dart';

/// Selects a safe animation workflow from facts gathered during import.
///
/// Opaque line art on a mostly white background remains eligible for Auto
/// Path. Only dense or colorful opaque artwork is steered to Auto Reveal.
final class ArtworkAnimationGuidancePolicy {
  const ArtworkAnimationGuidancePolicy();

  ArtworkAnimationGuidance resolve({
    required ArtworkSourceKind sourceKind,
    RasterAlphaBoundsResult? rasterAnalysis,
  }) {
    if (sourceKind == ArtworkSourceKind.svg) {
      return ArtworkAnimationGuidance.autoPathRecommended;
    }
    final analysis = rasterAnalysis;
    if (analysis == null) return ArtworkAnimationGuidance.unknown;
    switch (analysis.status) {
      case RasterAlphaBoundsStatus.visible:
        return ArtworkAnimationGuidance.flexible;
      case RasterAlphaBoundsStatus.opaque:
        final profile = analysis.pixelProfile;
        if (profile == null) return ArtworkAnimationGuidance.unknown;
        final looksLikeSparseLineArt =
            profile.nearWhiteNeutralFraction >= 0.72 &&
            profile.colorfulFraction <= 0.12;
        return looksLikeSparseLineArt
            ? ArtworkAnimationGuidance.autoPathRecommended
            : ArtworkAnimationGuidance.autoRevealRecommended;
      case RasterAlphaBoundsStatus.fullyTransparent:
      case RasterAlphaBoundsStatus.decodeFailed:
      case RasterAlphaBoundsStatus.limitExceeded:
      case RasterAlphaBoundsStatus.cancelled:
        return ArtworkAnimationGuidance.unknown;
    }
  }
}
