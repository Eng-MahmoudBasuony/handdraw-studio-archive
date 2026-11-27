import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

/// Import-only compatibility for files created by the retired experiment.
/// Subsequent saves use the normal project container; no second editor remains.
class SavedDrawingImport {
  const SavedDrawingImport(this.document, this.sources);
  final ProjectDocument document;
  final Map<ProjectAssetId, Uint8List> sources;
  static SavedDrawingImport decode(String encoded) {
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    if (data['format'] != 'handdraw-drawing-lab' || data['version'] != 1) {
      throw const FormatException('Unsupported drawing experiment');
    }
    final settings = HandDrawProject.fromJson(
      data['project'] as Map<String, dynamic>,
    );
    final artwork = ProjectAssetId('imported-artwork');
    final hand = data['hand'] is String
        ? ProjectAssetId('imported-hand')
        : null;
    final section = SectionId('image-animation');
    final sources = <ProjectAssetId, Uint8List>{
      artwork: base64Decode(data['source'] as String),
      ?hand: base64Decode(data['hand'] as String),
    };
    TimelineDuration duration(double s) =>
        TimelineDuration.fromMicroseconds((s * 1000000).round());
    DocumentRect rect(Rect r) => DocumentRect(
      left: r.left,
      top: r.top,
      right: r.right,
      bottom: r.bottom,
    );
    final strokes = <ProjectStroke>[];
    for (final raw in data['strokes'] as List) {
      final s = DrawingStroke.fromJson(raw['stroke'] as Map<String, dynamic>);
      strokes.add(
        ProjectStroke(
          id: StrokeId(s.id),
          sectionId: section,
          name: s.name,
          assetId: artwork,
          points: [for (final p in s.points) DocumentPoint(p.dx, p.dy)],
          geometry: s.geometry,
          animationGeometry: s.animationGeometry,
          isFilledShape: s.isFilledShape,
          isTextShape: s.isTextShape,
          isGlobalDecoration: s.isGlobalDecoration,
          fillColorValue: s.fillColorValue,
          hidden: s.hidden,
          reversed: s.reversed,
          revealOnly: s.revealOnly,
          isPaintStroke: raw['role'] == 'paint',
          paintRegion: raw['region'] as int,
          revealStyle: s.revealStyle == RevealMaskStyle.directionalWipe
              ? DocumentRevealStyle.directionalWipe
              : DocumentRevealStyle.brush,
          revealWidth: s.revealWidth,
          clipBounds: s.clipBounds == null ? null : rect(s.clipBounds!),
          clipPolygons: [
            for (final polygon in s.clipPolygons)
              [for (final p in polygon) DocumentPoint(p.dx, p.dy)],
          ],
          exclusionBounds: s.exclusionBounds.map(rect).toList(),
          pausePoints: [
            for (final p in s.pausePoints)
              DocumentStrokePause(
                id: StrokePauseId(p.id),
                progress: p.progress,
                duration: duration(p.durationSeconds),
                keepHandVisible: p.keepHandVisible,
              ),
          ],
          vectorMaskStrokes: [
            for (final m in s.vectorMaskStrokes)
              DocumentVectorMaskStroke(
                geometry: m.geometry,
                width: m.widthFraction,
                erase: m.operation == VectorMaskOperation.erase,
                feather: m.featherFraction,
                clipToLayer: m.clipToLayer,
              ),
          ],
        ),
      );
    }
    if (strokes.map((s) => s.id).toSet().length != strokes.length) {
      throw const FormatException('Duplicate stroke IDs');
    }
    return SavedDrawingImport(
      ProjectDocument(
        id: ProjectId('imported-drawing'),
        title: 'Image animation',
        canvas: ProjectCanvas(
          width: settings.canvasWidth,
          height: settings.canvasHeight,
          background: settings.canvasBackground,
        ),
        frameRate: FrameRate(numerator: settings.frameRate),
        duration: duration(settings.durationSeconds),
        artworkAssetId: artwork,
        motionConfiguration: ProjectMotionConfiguration(
          imageAnimationEffect: data['paintEffect'] == true
              ? 'drawPaint'
              : 'reveal',
          showDrawingHand: data['showHand'] as bool,
          drawingDuration: duration(settings.drawingDurationSeconds),
          drawingSpeed: settings.drawingSpeed,
          penTravelSpeed: settings.penTravelSpeed,
          startDelay: duration(settings.startDelaySeconds),
          endHold: duration(settings.endHoldSeconds),
          revealWidth: settings.revealWidth,
        ),
        exportConfiguration: ProjectExportConfiguration(
          presetId: settings.exportPresetId,
          alphaMode: settings.exportAlphaMode,
          renderQuality: settings.exportRenderQuality,
        ),
        handConfiguration: ProjectHandConfiguration(
          assetId: hand,
          presetId: settings.handPresetId,
          scale: settings.handScale,
          rotationDegrees: settings.handRotationDegrees,
          flipX: settings.handFlipX,
          penTip: DocumentPoint(settings.penTip.dx, settings.penTip.dy),
        ),
        assets: [
          for (final entry in sources.entries)
            ProjectAsset(
              id: entry.key,
              kind: entry.key == artwork
                  ? ProjectAssetKind.artwork
                  : ProjectAssetKind.hand,
              originalFileName: entry.key == artwork
                  ? 'drawing.png'
                  : 'hand.png',
              storagePolicy: ProjectAssetStoragePolicy.embedded,
              contentHash: 'sha256:${sha256.convert(entry.value)}',
              mediaType: 'image/png',
              artworkSourceType: entry.key == artwork
                  ? ArtworkSourceType.raster
                  : null,
            ),
        ],
        strokes: strokes,
        sections: [
          ProjectSection(
            id: section,
            name: 'Image animation',
            strokeIds: strokes.map((s) => s.id).toList(),
            assetId: artwork,
          ),
        ],
        sectionOrder: [section],
        scenes: const [],
        audioTracks: const [],
      ),
      sources,
    );
  }
}
