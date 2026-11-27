import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:handdraw_studio/core/platform/native_dialog_focus_service.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/raster_alpha_bounds_scanner.dart';
import 'package:handdraw_studio/core/storage/recent_directory_store.dart';
import 'package:handdraw_studio/features/path_document/domain/repositories/artwork_importer.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_artwork_import.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_artwork_importer.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_render_source_builder.dart';

class ImportedEditorAsset {
  const ImportedEditorAsset({
    required this.path,
    required this.encoded,
    required this.image,
    this.sourceKind = ArtworkSourceKind.raster,
    this.sourceEncoded,
    this.revealBaseEncoded,
    this.revealBaseImage,
    this.revealStrokeEncoded,
    this.svgRevealLayers,
    this.vectorPaths = const [],
    this.importWarnings = const [],
    this.svgImportReport,
    this.rasterAlphaBounds,
  });

  final String path;
  final String encoded;
  final ui.Image image;
  final ArtworkSourceKind sourceKind;
  final String? sourceEncoded;
  final String? revealBaseEncoded;
  final ui.Image? revealBaseImage;
  final String? revealStrokeEncoded;
  final SvgRevealLayers? svgRevealLayers;
  final List<SvgImportedPath> vectorPaths;
  final List<String> importWarnings;
  final SvgImportReport? svgImportReport;
  final RasterAlphaBoundsResult? rasterAlphaBounds;
}

class EditorFilePickerCopy {
  const EditorFilePickerCopy({
    required this.chooseDrawing,
    required this.chooseHand,
    required this.images,
    required this.project,
    required this.saveProject,
    required this.openProject,
  });

  static const english = EditorFilePickerCopy(
    chooseDrawing: 'Choose Drawing',
    chooseHand: 'Choose Hand',
    images: 'Images',
    project: 'HandDraw project',
    saveProject: 'Save Project',
    openProject: 'Open Project',
  );

  final String chooseDrawing;
  final String chooseHand;
  final String images;
  final String project;
  final String saveProject;
  final String openProject;
}

/// Owns native file-pickers and serialization so EditorCubit only coordinates
/// state transitions and can be tested without touching the filesystem.
class EditorFileService {
  const EditorFileService({
    this._dialogFocusService = const NativeDialogFocusService(),
    this._svgImporter = const SvgArtworkImporter(),
    this._svgRenderSourceBuilder = const SvgRenderSourceBuilder(),
    this.rasterAlphaBoundsScanner = const RasterAlphaBoundsScanner(),
  });

  final NativeDialogFocusService _dialogFocusService;
  final ArtworkImporter<SvgArtworkImport> _svgImporter;
  final SvgRenderSourceBuilder _svgRenderSourceBuilder;
  final RasterAlphaBoundsScanner rasterAlphaBoundsScanner;

  static const _maximumSvgBytes = 10 * 1024 * 1024;
  static const _maximumSvgRasterDimension = 4096;

  Future<ImportedEditorAsset?> pickDrawing({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) => _pickImage(
    recentKey: RecentDirectoryKey.drawing,
    confirmButtonText: copy.chooseDrawing,
    imagesLabel: copy.images,
  );

  Future<ImportedEditorAsset?> pickHand({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) => _pickImage(
    recentKey: RecentDirectoryKey.hand,
    confirmButtonText: copy.chooseHand,
    imagesLabel: copy.images,
  );

  Future<ImportedEditorAsset?> _pickImage({
    required String recentKey,
    required String confirmButtonText,
    required String imagesLabel,
  }) async {
    final initialDirectory = await RecentDirectoryStore.instance.directoryFor(
      recentKey,
    );
    await _dialogFocusService.prepareForPresentation();
    final result = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: imagesLabel,
          extensions: const ['png', 'jpg', 'jpeg', 'webp', 'svg'],
        ),
      ],
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
    );
    final path = result?.path;
    if (path == null) return null;
    await RecentDirectoryStore.instance.rememberFile(recentKey, path);
    return loadImage(path);
  }

  /// Decodes a supported editor asset independently from native picker state.
  /// This is also the extension point for drag-and-drop and recent-file import.
  Future<ImportedEditorAsset> loadImage(String path) async {
    final bytes = await File(path).readAsBytes();
    return loadImageBytes(path: path, bytes: bytes);
  }

  Future<ImportedEditorAsset> loadImageBytes({
    required String path,
    required Uint8List bytes,
  }) async {
    if (path.toLowerCase().endsWith('.svg')) {
      if (bytes.length > _maximumSvgBytes) {
        throw const FormatException('SVG files are limited to 10 MB.');
      }
      final source = utf8.decode(bytes);
      final imported = await _svgImporter.import(
        ArtworkSource(path: path, bytes: bytes, extension: 'svg'),
      );
      final renderSources = _svgRenderSourceBuilder.build(source);
      final image = await _rasterizeSvg(renderSources.complete);
      final revealBaseImage = await _rasterizeSvg(renderSources.filledArtwork);
      final revealStrokeImage = await _rasterizeSvg(
        renderSources.strokeArtwork,
      );
      final globalStrokeImage = renderSources.hasGlobalStrokes
          ? await _rasterizeSvg(renderSources.globalStrokeArtwork)
          : null;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final revealBasePng = await revealBaseImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final revealStrokePng = await revealStrokeImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (png == null || revealBasePng == null || revealStrokePng == null) {
        image.dispose();
        revealBaseImage.dispose();
        revealStrokeImage.dispose();
        globalStrokeImage?.dispose();
        throw StateError('The SVG preview could not be encoded.');
      }
      return ImportedEditorAsset(
        path: path,
        encoded: base64Encode(png.buffer.asUint8List()),
        image: image,
        sourceKind: ArtworkSourceKind.svg,
        sourceEncoded: base64Encode(bytes),
        revealBaseEncoded: base64Encode(revealBasePng.buffer.asUint8List()),
        revealBaseImage: revealBaseImage,
        revealStrokeEncoded: base64Encode(revealStrokePng.buffer.asUint8List()),
        svgRevealLayers: SvgRevealLayers(
          fills: revealBaseImage,
          strokes: revealStrokeImage,
          globalStrokes: globalStrokeImage,
        ),
        vectorPaths: imported.paths,
        importWarnings: imported.warnings,
        svgImportReport: imported.report,
      );
    }
    final alphaBounds = await rasterAlphaBoundsScanner.scan(bytes);
    return ImportedEditorAsset(
      path: path,
      encoded: base64Encode(bytes),
      image: await _decodeBytes(bytes),
      sourceKind: ArtworkSourceKind.raster,
      sourceEncoded: base64Encode(bytes),
      rasterAlphaBounds: alphaBounds,
    );
  }

  Future<String?> pickProjectSavePath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async {
    final initialDirectory = await RecentDirectoryStore.instance.directoryFor(
      RecentDirectoryKey.projectSave,
    );
    await _dialogFocusService.prepareForPresentation();
    final location = await getSaveLocation(
      suggestedName: 'untitled.koni',
      acceptedTypeGroups: [
        XTypeGroup(label: copy.project, extensions: const ['koni']),
      ],
      initialDirectory: initialDirectory,
      confirmButtonText: copy.saveProject,
    );
    if (location == null) return null;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.koni')) path = '$path.koni';
    await RecentDirectoryStore.instance.rememberFile(
      RecentDirectoryKey.projectSave,
      path,
    );
    return path;
  }

  Future<String?> pickProjectOpenPath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async {
    final initialDirectory = await RecentDirectoryStore.instance.directoryFor(
      RecentDirectoryKey.projectOpen,
    );
    await _dialogFocusService.prepareForPresentation();
    final result = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: copy.project, extensions: const ['koni', 'hdrawlab']),
      ],
      initialDirectory: initialDirectory,
      confirmButtonText: copy.openProject,
    );
    final path = result?.path;
    if (path != null) {
      await RecentDirectoryStore.instance.rememberFile(
        RecentDirectoryKey.projectOpen,
        path,
      );
    }
    return path;
  }

  Future<ui.Image> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<ui.Image> _rasterizeSvg(String source) async {
    final pictureInfo = await vg.loadPicture(SvgStringLoader(source), null);
    final sourceSize = pictureInfo.size;
    if (!sourceSize.width.isFinite ||
        !sourceSize.height.isFinite ||
        sourceSize.width <= 0 ||
        sourceSize.height <= 0) {
      pictureInfo.picture.dispose();
      throw const FormatException('The SVG has no valid drawing size.');
    }
    final scale =
        _maximumSvgRasterDimension /
        (sourceSize.width > sourceSize.height
            ? sourceSize.width
            : sourceSize.height);
    final width = (sourceSize.width * scale).round().clamp(
      1,
      _maximumSvgRasterDimension,
    );
    final height = (sourceSize.height * scale).round().clamp(
      1,
      _maximumSvgRasterDimension,
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(scale);
    canvas.drawPicture(pictureInfo.picture);
    final rasterPicture = recorder.endRecording();
    pictureInfo.picture.dispose();
    final image = await rasterPicture.toImage(width, height);
    rasterPicture.dispose();
    return image;
  }
}
