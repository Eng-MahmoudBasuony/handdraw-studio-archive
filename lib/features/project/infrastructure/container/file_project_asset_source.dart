import 'dart:io';
import 'dart:typed_data';

import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

final class FileProjectAssetByteSource implements ProjectAssetByteSource {
  const FileProjectAssetByteSource(this.path);

  final String path;

  @override
  Future<int> length() => File(path).length();

  @override
  Stream<Uint8List> openRead() => File(path).openRead().map(
    (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
  );
}

final class MapProjectAssetSourceCatalog implements ProjectAssetSourceCatalog {
  MapProjectAssetSourceCatalog(
    Map<ProjectAssetId, ProjectAssetByteSource> sources,
  ) : _sources = Map.unmodifiable(sources);

  final Map<ProjectAssetId, ProjectAssetByteSource> _sources;

  @override
  ProjectAssetByteSource? sourceFor(ProjectAssetId assetId) =>
      _sources[assetId];
}
