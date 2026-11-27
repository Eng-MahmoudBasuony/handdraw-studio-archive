import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';

/// Decoded, disposable resources never persisted in ProjectDocument.
final class ResolvedEditorAssetResource {
  const ResolvedEditorAssetResource({
    required this.assetId,
    this.image,
    this.revealBaseImage,
    this.svgRevealLayers,
    this.localReadablePath,
  });

  final ProjectAssetId assetId;
  final Image? image;
  final Image? revealBaseImage;
  final SvgRevealLayers? svgRevealLayers;
  final String? localReadablePath;
}

/// Runtime lifecycle boundary. The Project Store chosen after 3A will resolve
/// embedded/external references into these resources. Implementations own and
/// dispose decoded resources when evicted or cleared.
abstract interface class EditorRuntimeAssetResources {
  ResolvedEditorAssetResource? lookup(ProjectAssetId assetId);
  void bind(ResolvedEditorAssetResource resource);
  void evict(ProjectAssetId assetId);
  void clear();
}
