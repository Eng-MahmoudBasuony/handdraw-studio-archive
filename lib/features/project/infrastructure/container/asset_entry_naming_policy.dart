import 'package:handdraw_studio/features/project/application/container/project_container_limits.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

final class AssetEntryMapping {
  const AssetEntryMapping({required this.path, required this.compression});

  final String path;
  final ProjectContainerCompressionMethod compression;
}

/// The only place that knows the physical ZIP layout. Persistent filenames
/// never participate in entry naming.
final class AssetEntryNamingPolicy {
  const AssetEntryNamingPolicy();

  static const _extensions = <String, String>{
    'image/svg+xml': 'svg',
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/webp': 'webp',
    'audio/mp4': 'm4a',
    'audio/mpeg': 'mp3',
    'audio/aac': 'aac',
    'audio/wav': 'wav',
    'video/quicktime': 'mov',
    'text/plain': 'txt',
    'application/json': 'json',
    'application/octet-stream': 'bin',
  };

  AssetEntryMapping map(ProjectAsset asset) {
    final id = asset.id.value;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.invalidDocument,
        'Asset ${asset.id} has an unsafe persistent ID.',
      );
    }
    final mediaType = asset.mediaType;
    final extension = mediaType == null ? null : _extensions[mediaType];
    if (extension == null) {
      throw ProjectContainerException(
        ProjectContainerFailureCode.unsupportedFeature,
        'Asset ${asset.id} has unsupported media type $mediaType.',
      );
    }
    final directory = switch (asset.kind) {
      ProjectAssetKind.artwork => 'artwork',
      ProjectAssetKind.hand => 'hands',
      ProjectAssetKind.audio => 'audio',
      ProjectAssetKind.other => 'other',
    };
    final compression = switch (mediaType) {
      'image/svg+xml' ||
      'text/plain' ||
      'application/json' => ProjectContainerCompressionMethod.deflate,
      _ => ProjectContainerCompressionMethod.store,
    };
    return AssetEntryMapping(
      path: 'assets/$directory/$id.$extension',
      compression: compression,
    );
  }
}
