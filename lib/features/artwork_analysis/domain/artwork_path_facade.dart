import 'dart:typed_data';
import 'dart:ui';

import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_artwork_import.dart';

class ArtworkPathRequest {
  const ArtworkPathRequest({
    required this.kind,
    required this.previewImage,
    required this.previewBytes,
    required this.sourceBytes,
    this.cachedSvgPaths = const [],
    this.onProgress,
    this.cancellationToken,
    this.coordinateBounds = const Rect.fromLTWH(0, 0, 1, 1),
  });

  final ArtworkSourceKind kind;
  final Image previewImage;
  final Uint8List previewBytes;
  final Uint8List sourceBytes;
  final List<SvgImportedPath> cachedSvgPaths;
  final SmartPathProgressCallback? onProgress;
  final SmartPathCancellationToken? cancellationToken;
  final Rect coordinateBounds;
}

class ArtworkPathResult {
  ArtworkPathResult({
    required this.analysis,
    List<SvgImportedPath> nativePaths = const [],
  }) : nativePaths = List.unmodifiable(nativePaths);

  final SmartPathAnalysis analysis;
  final List<SvgImportedPath> nativePaths;
}

abstract interface class ArtworkPathStrategy {
  ArtworkSourceKind get kind;

  Future<ArtworkPathResult> analyze(ArtworkPathRequest request);
}

/// Stable API used by editor actions regardless of the imported file type.
abstract interface class ArtworkPathFacade {
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request);
}
