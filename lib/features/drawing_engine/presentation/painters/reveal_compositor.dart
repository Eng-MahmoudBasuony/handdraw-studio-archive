import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_mask_painter.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_rect_list.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';

enum _RevealLayer { all, filled, strokes, global, nonText, text }

const denseRevealPrewarmPathThreshold = 512;
const _revealPrewarmSliceBudget = Duration(milliseconds: 4);

/// Prepares the exact brush chunks consumed by [drawRevealedArtwork].
///
/// Work is yielded in short slices and never runs from a paint callback. Dense
/// projects therefore pay the path-combination cost while idle (Preview), or
/// before frame recording begins (MOV), without introducing a second renderer.
Future<void> prewarmRevealedArtwork({
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required double defaultRevealWidth,
  double projectPixelScale = 1,
  SvgRevealLayers? svgRevealLayers,
  bool hasRevealBaseImage = false,
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() == true) return;
  final sequence = snapshot.stableRevealSequence;
  if (sequence == null ||
      sequence.paths.length < denseRevealPrewarmPathThreshold) {
    return;
  }
  final layers = svgRevealLayers != null
      ? const [
          _RevealLayer.filled,
          _RevealLayer.strokes,
          _RevealLayer.global,
          _RevealLayer.text,
        ]
      : hasRevealBaseImage
      ? const [_RevealLayer.nonText, _RevealLayer.text]
      : const [_RevealLayer.all];
  for (final layer in layers) {
    if (isCancelled?.call() == true) return;
    await _prewarmStableRevealLayer(
      sequence: sequence,
      artworkRect: artworkRect,
      sectionClips: snapshot.sectionClips,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
      layer: layer,
      targetVisibleCount: sequence.paths.length,
      isCancelled: isCancelled,
    );
  }
}

/// Composites revealed artwork identically in Preview and offline export.
void drawRevealedArtwork({
  required Canvas canvas,
  required Image image,
  Image? revealBaseImage,
  SvgRevealLayers? svgRevealLayers,
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required double defaultRevealWidth,
  double projectPixelScale = 1,
  FilterQuality rasterFilterQuality = FilterQuality.high,
}) {
  if (snapshot.revealedPaths.isEmpty) return;
  if (svgRevealLayers != null || revealBaseImage != null) {
    _drawLayeredSvgReveal(
      canvas: canvas,
      completeImage: image,
      legacyBaseImage: revealBaseImage,
      svgRevealLayers: svgRevealLayers,
      artworkRect: artworkRect,
      snapshot: snapshot,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
    );
    return;
  }
  final source = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  canvas.saveLayer(artworkRect, Paint());
  final stable = snapshot.stableRevealSequence;
  if (stable != null) {
    _drawStableRasterReveal(
      canvas: canvas,
      artworkRect: artworkRect,
      snapshot: snapshot,
      sequence: stable,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
    );
  } else {
    _drawLegacyRasterReveal(
      canvas: canvas,
      artworkRect: artworkRect,
      snapshot: snapshot,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
    );
  }
  canvas.drawImageRect(
    image,
    source,
    artworkRect,
    Paint()
      ..isAntiAlias = true
      ..filterQuality = rasterFilterQuality
      ..blendMode = BlendMode.srcIn,
  );
  if (stable != null) {
    _drawStableFillPatches(
      canvas: canvas,
      artworkRect: artworkRect,
      snapshot: snapshot,
      sequence: stable,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
    );
  } else {
    _drawFillPatches(
      canvas: canvas,
      artworkRect: artworkRect,
      sectionClips: snapshot.sectionClips,
      paths: snapshot.revealedPaths,
      projectPixelScale: projectPixelScale,
    );
  }
  // Flat raster backgrounds fill excluded OCR areas. Reveal original letters
  // above those patches only as their own text paths become visible.
  final patches = snapshot.revealedPaths
      .where(_hasFillPatch)
      .toList(growable: false);
  if (patches.isNotEmpty && snapshot.revealedPaths.any((p) => p.isTextShape)) {
    final patchClip = Path();
    for (final patch in patches) {
      for (final rect in patch.exclusionRects) {
        patchClip.addRect(rect.intersect(patch.clipRect ?? artworkRect));
      }
    }
    canvas.save();
    canvas.clipPath(patchClip);
    if (stable != null) {
      _drawStableMaskedSource(
        canvas: canvas,
        sourceImage: image,
        artworkRect: artworkRect,
        snapshot: snapshot,
        sequence: stable,
        layer: _RevealLayer.text,
        defaultRevealWidth: defaultRevealWidth,
        projectPixelScale: projectPixelScale,
      );
    } else {
      _drawMaskedSource(
        canvas: canvas,
        sourceImage: image,
        artworkRect: artworkRect,
        snapshot: snapshot,
        paths: snapshot.revealedPaths
            .where((p) => p.isTextShape)
            .toList(growable: false),
        defaultRevealWidth: defaultRevealWidth,
        projectPixelScale: projectPixelScale,
      );
    }
    canvas.restore();
  }
  canvas.restore();
}

void _drawLegacyRasterReveal({
  required Canvas canvas,
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required double defaultRevealWidth,
  required double projectPixelScale,
}) {
  final brushBatches = <_BrushRevealBatchKey, List<RevealedPath>>{};
  for (final revealed in snapshot.revealedPaths) {
    final clip =
        revealed.clipRect ??
        (revealed.sectionIndex < snapshot.sectionClips.length
            ? snapshot.sectionClips[revealed.sectionIndex]
            : artworkRect);
    final brushWidth =
        (revealed.revealWidth ?? defaultRevealWidth) * projectPixelScale;
    if (_isBatchableBrush(revealed)) {
      final key = _BrushRevealBatchKey(
        clip: revealed.clipPath == null ? clip : Rect.zero,
        clipPath: revealed.clipPath,
        exclusions: revealed.exclusionRects,
        brushWidth: brushWidth,
      );
      brushBatches.putIfAbsent(key, () => []).add(revealed);
      continue;
    }
    canvas.save();
    canvas.clipPath(
      _clipWithExclusions(clip, revealed.exclusionRects, revealed.clipPath),
    );
    drawRevealMask(
      canvas: canvas,
      revealed: revealed,
      clip: clip,
      brushWidth: brushWidth,
      featherWidth: 28 * projectPixelScale,
    );
    for (final mask in revealed.vectorMaskStrokes.where(
      (item) =>
          item.operation == VectorMaskOperation.reveal && item.clipToLayer,
    )) {
      _drawVectorMaskStroke(
        canvas: canvas,
        mask: mask,
        artworkRect: artworkRect,
        progress: revealed.strokeProgress,
        erase: false,
      );
    }
    canvas.restore();
    // Non-clipped reveal additions are order-independent white additions to
    // the same mask layer, so apply them while this path is already hot. Erase
    // masks deliberately remain in the following pass and therefore still
    // win over every reveal addition exactly as before.
    for (final mask in revealed.vectorMaskStrokes.where(
      (item) =>
          item.operation == VectorMaskOperation.reveal && !item.clipToLayer,
    )) {
      _drawVectorMaskStroke(
        canvas: canvas,
        mask: mask,
        artworkRect: artworkRect,
        progress: revealed.strokeProgress,
        erase: false,
      );
    }
  }
  for (final MapEntry(key: key, value: paths) in brushBatches.entries) {
    canvas.save();
    canvas.clipPath(
      _clipWithExclusions(key.clip, key.exclusions, key.clipPath),
    );
    final paint = _brushRevealPaint(key.brushWidth);
    for (var start = 0; start < paths.length; start += _brushPathChunkSize) {
      final end = math.min(start + _brushPathChunkSize, paths.length);
      canvas.drawPath(_combinedBrushChunk(paths, start, end), paint);
    }
    canvas.restore();
  }
  for (final revealed in snapshot.revealedPaths) {
    final clip =
        revealed.clipRect ??
        (revealed.sectionIndex < snapshot.sectionClips.length
            ? snapshot.sectionClips[revealed.sectionIndex]
            : artworkRect);
    for (final mask in revealed.vectorMaskStrokes.where(
      (item) => item.operation == VectorMaskOperation.erase,
    )) {
      canvas.save();
      if (mask.clipToLayer) {
        canvas.clipPath(
          _clipWithExclusions(clip, revealed.exclusionRects, revealed.clipPath),
        );
      }
      _drawVectorMaskStroke(
        canvas: canvas,
        mask: mask,
        artworkRect: artworkRect,
        progress: revealed.strokeProgress,
        erase: true,
      );
      canvas.restore();
    }
  }
}

void _drawFillPatches({
  required Canvas canvas,
  required Rect artworkRect,
  required List<Rect> sectionClips,
  required Iterable<RevealedPath> paths,
  required double projectPixelScale,
}) {
  for (final revealed in paths) {
    final fillColor = revealed.fillColorValue;
    if (fillColor == null ||
        revealed.revealStyle != RevealMaskStyle.directionalWipe ||
        revealed.exclusionRects.isEmpty) {
      continue;
    }
    final clip =
        revealed.clipRect ??
        (revealed.sectionIndex < sectionClips.length
            ? sectionClips[revealed.sectionIndex]
            : artworkRect);
    _drawFilledShapeExclusionPatches(
      canvas: canvas,
      revealed: revealed,
      clip: clip,
      color: Color(fillColor),
      featherWidth: 28 * projectPixelScale,
    );
  }
}

void _drawStableRasterReveal({
  required Canvas canvas,
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required StableRevealSequence sequence,
  required double defaultRevealWidth,
  required double projectPixelScale,
  _RevealLayer layer = _RevealLayer.all,
}) {
  final compiled = _compiledStableRevealSequence(
    sequence: sequence,
    artworkRect: artworkRect,
    sectionClips: snapshot.sectionClips,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  final visibleCount = sequence.visibleCount.clamp(0, sequence.paths.length);

  for (final entry in compiled.specialReveals) {
    if (entry.ordinal >= visibleCount) break;
    _drawSpecialReveal(
      canvas: canvas,
      artworkRect: artworkRect,
      entry: entry,
      projectPixelScale: projectPixelScale,
    );
  }
  final active = sequence.activePath;
  final activeInLayer = active != null && _belongsToLayer(active, layer);
  if (activeInLayer && !_isBatchableBrush(active)) {
    _drawSpecialReveal(
      canvas: canvas,
      artworkRect: artworkRect,
      entry: _compileRevealEntry(
        ordinal: visibleCount,
        revealed: active,
        artworkRect: artworkRect,
        sectionClips: snapshot.sectionClips,
        defaultRevealWidth: defaultRevealWidth,
        projectPixelScale: projectPixelScale,
        includeExclusions: layer == _RevealLayer.all,
      ),
      projectPixelScale: projectPixelScale,
    );
  }

  for (final batch in compiled.brushBatches) {
    batch.drawVisible(canvas, visibleCount);
  }
  if (activeInLayer && _isBatchableBrush(active)) {
    final entry = _compileRevealEntry(
      ordinal: visibleCount,
      revealed: active,
      artworkRect: artworkRect,
      sectionClips: snapshot.sectionClips,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
      includeExclusions: layer == _RevealLayer.all,
    );
    canvas.save();
    canvas.clipPath(entry.effectiveClip);
    drawRevealMask(
      canvas: canvas,
      revealed: active,
      clip: entry.clip,
      brushWidth: entry.brushWidth,
      featherWidth: 28 * projectPixelScale,
    );
    canvas.restore();
  }

  for (final entry in compiled.eraseReveals) {
    if (entry.ordinal >= visibleCount) break;
    _drawEraseMasks(canvas: canvas, artworkRect: artworkRect, entry: entry);
  }
  if (activeInLayer && _hasEraseMask(active)) {
    _drawEraseMasks(
      canvas: canvas,
      artworkRect: artworkRect,
      entry: _compileRevealEntry(
        ordinal: visibleCount,
        revealed: active,
        artworkRect: artworkRect,
        sectionClips: snapshot.sectionClips,
        defaultRevealWidth: defaultRevealWidth,
        projectPixelScale: projectPixelScale,
        includeExclusions: layer == _RevealLayer.all,
      ),
    );
  }
}

void _drawStableFillPatches({
  required Canvas canvas,
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required StableRevealSequence sequence,
  required double defaultRevealWidth,
  required double projectPixelScale,
}) {
  final compiled = _compiledStableRevealSequence(
    sequence: sequence,
    artworkRect: artworkRect,
    sectionClips: snapshot.sectionClips,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
  );
  final visibleCount = sequence.visibleCount.clamp(0, sequence.paths.length);
  for (final entry in compiled.fillReveals) {
    if (entry.ordinal >= visibleCount) break;
    _drawFillPatchEntry(
      canvas: canvas,
      entry: entry,
      projectPixelScale: projectPixelScale,
    );
  }
  final active = sequence.activePath;
  if (active != null && _hasFillPatch(active)) {
    _drawFillPatchEntry(
      canvas: canvas,
      entry: _compileRevealEntry(
        ordinal: visibleCount,
        revealed: active,
        artworkRect: artworkRect,
        sectionClips: snapshot.sectionClips,
        defaultRevealWidth: defaultRevealWidth,
        projectPixelScale: projectPixelScale,
      ),
      projectPixelScale: projectPixelScale,
    );
  }
}

void _drawSpecialReveal({
  required Canvas canvas,
  required Rect artworkRect,
  required _CompiledRevealEntry entry,
  required double projectPixelScale,
}) {
  final revealed = entry.revealed;
  canvas.save();
  canvas.clipPath(entry.effectiveClip);
  drawRevealMask(
    canvas: canvas,
    revealed: revealed,
    clip: entry.clip,
    brushWidth: entry.brushWidth,
    featherWidth: 28 * projectPixelScale,
  );
  for (final mask in revealed.vectorMaskStrokes.where(
    (item) => item.operation == VectorMaskOperation.reveal && item.clipToLayer,
  )) {
    _drawVectorMaskStroke(
      canvas: canvas,
      mask: mask,
      artworkRect: artworkRect,
      progress: revealed.strokeProgress,
      erase: false,
    );
  }
  canvas.restore();
  for (final mask in revealed.vectorMaskStrokes.where(
    (item) => item.operation == VectorMaskOperation.reveal && !item.clipToLayer,
  )) {
    _drawVectorMaskStroke(
      canvas: canvas,
      mask: mask,
      artworkRect: artworkRect,
      progress: revealed.strokeProgress,
      erase: false,
    );
  }
}

void _drawEraseMasks({
  required Canvas canvas,
  required Rect artworkRect,
  required _CompiledRevealEntry entry,
}) {
  final revealed = entry.revealed;
  for (final mask in revealed.vectorMaskStrokes.where(
    (item) => item.operation == VectorMaskOperation.erase,
  )) {
    canvas.save();
    if (mask.clipToLayer) canvas.clipPath(entry.effectiveClip);
    _drawVectorMaskStroke(
      canvas: canvas,
      mask: mask,
      artworkRect: artworkRect,
      progress: revealed.strokeProgress,
      erase: true,
    );
    canvas.restore();
  }
}

void _drawFillPatchEntry({
  required Canvas canvas,
  required _CompiledRevealEntry entry,
  required double projectPixelScale,
}) {
  _drawFilledShapeExclusionPatches(
    canvas: canvas,
    revealed: entry.revealed,
    clip: entry.clip,
    color: Color(entry.revealed.fillColorValue!),
    featherWidth: 28 * projectPixelScale,
  );
}

bool _isBatchableBrush(RevealedPath revealed) =>
    revealed.revealStyle == RevealMaskStyle.brush &&
    revealed.vectorMaskStrokes.isEmpty;

bool _hasEraseMask(RevealedPath revealed) => revealed.vectorMaskStrokes.any(
  (item) => item.operation == VectorMaskOperation.erase,
);

bool _hasFillPatch(RevealedPath revealed) =>
    revealed.fillColorValue != null &&
    revealed.revealStyle == RevealMaskStyle.directionalWipe &&
    revealed.exclusionRects.isNotEmpty;

const _maximumStableRevealCacheEntries = 8;
const _maximumStableRevealCachePaths = 24000;
final LinkedHashMap<_StableRevealCacheKey, _CompiledStableRevealSequence>
_stableRevealCache = LinkedHashMap();
final Map<_StableRevealCacheKey, Future<bool>> _stableRevealPrewarmTasks = {};
final Set<_StableRevealCacheKey> _stableRevealPrewarmedKeys = {};

Future<void> _prewarmStableRevealLayer({
  required StableRevealSequence sequence,
  required Rect artworkRect,
  required List<Rect> sectionClips,
  required double defaultRevealWidth,
  required double projectPixelScale,
  required _RevealLayer layer,
  required int targetVisibleCount,
  bool Function()? isCancelled,
}) async {
  final key = _StableRevealCacheKey(
    paths: sequence.paths,
    sectionClips: sectionClips,
    artworkRect: artworkRect,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  if (isCancelled?.call() == true) return;
  final running = _stableRevealPrewarmTasks[key];
  if (running != null) {
    final completed = await running;
    if (completed || isCancelled?.call() == true) return;
    // The previous requester was superseded while this caller still needs the
    // same cache entry (for example MOV starting during a Preview resize).
    return _prewarmStableRevealLayer(
      sequence: sequence,
      artworkRect: artworkRect,
      sectionClips: sectionClips,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
      layer: layer,
      targetVisibleCount: targetVisibleCount,
      isCancelled: isCancelled,
    );
  }
  if (_stableRevealPrewarmedKeys.contains(key)) return;
  late final Future<bool> task;
  task =
      _runPrewarmStableRevealLayer(
            key: key,
            sequence: sequence,
            artworkRect: artworkRect,
            sectionClips: sectionClips,
            defaultRevealWidth: defaultRevealWidth,
            projectPixelScale: projectPixelScale,
            layer: layer,
            targetVisibleCount: targetVisibleCount,
            isCancelled: isCancelled,
          )
          .then((completed) {
            if (completed) _stableRevealPrewarmedKeys.add(key);
            return completed;
          })
          .whenComplete(() {
            if (identical(_stableRevealPrewarmTasks[key], task)) {
              _stableRevealPrewarmTasks.remove(key);
            }
          });
  _stableRevealPrewarmTasks[key] = task;
  await task;
}

Future<bool> _runPrewarmStableRevealLayer({
  required _StableRevealCacheKey key,
  required StableRevealSequence sequence,
  required Rect artworkRect,
  required List<Rect> sectionClips,
  required double defaultRevealWidth,
  required double projectPixelScale,
  required _RevealLayer layer,
  required int targetVisibleCount,
  bool Function()? isCancelled,
}) async {
  // Let the frame that requested prewarm finish before compiling metadata.
  await Future<void>.delayed(Duration.zero);
  if (isCancelled?.call() == true) return false;
  final compiled = await _compiledStableRevealSequenceAsync(
    sequence: sequence,
    artworkRect: artworkRect,
    sectionClips: sectionClips,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
    isCancelled: isCancelled,
  );
  if (compiled == null || compiled.isDisposed) return false;
  for (final batch in compiled.brushBatches) {
    final completed = await batch.prewarm(
      targetVisibleCount: targetVisibleCount,
      sliceBudget: _revealPrewarmSliceBudget,
      isCancelled: () => compiled.isDisposed || isCancelled?.call() == true,
    );
    if (!completed) return false;
  }
  return !compiled.isDisposed &&
      identical(_stableRevealCache[key], compiled) &&
      isCancelled?.call() != true;
}

@visibleForTesting
void debugResetRevealCompositorCaches() {
  for (final compiled in _stableRevealCache.values) {
    compiled.dispose();
  }
  _stableRevealCache.clear();
  _stableRevealPrewarmTasks.clear();
  _stableRevealPrewarmedKeys.clear();
  _brushChunkCache.clear();
  debugRevealBrushChunkBuildCount = 0;
}

@visibleForTesting
int debugRevealBrushChunkBuildCount = 0;

@visibleForTesting
int get debugRevealStableCacheEntryCount => _stableRevealCache.length;

@visibleForTesting
int get debugRevealPrewarmedKeyCount => _stableRevealPrewarmedKeys.length;

_CompiledStableRevealSequence _compiledStableRevealSequence({
  required StableRevealSequence sequence,
  required Rect artworkRect,
  required List<Rect> sectionClips,
  required double defaultRevealWidth,
  required double projectPixelScale,
  _RevealLayer layer = _RevealLayer.all,
}) {
  final key = _StableRevealCacheKey(
    paths: sequence.paths,
    sectionClips: sectionClips,
    artworkRect: artworkRect,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  final cached = _takeCompiledStableReveal(key);
  if (cached != null) return cached;
  final compiler = _StableRevealCompiler(
    sequence: sequence,
    artworkRect: artworkRect,
    sectionClips: sectionClips,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  while (compiler.hasNext) {
    compiler.compileNext();
  }
  final result = compiler.finish();
  _storeCompiledStableReveal(key, result);
  return result;
}

Future<_CompiledStableRevealSequence?> _compiledStableRevealSequenceAsync({
  required StableRevealSequence sequence,
  required Rect artworkRect,
  required List<Rect> sectionClips,
  required double defaultRevealWidth,
  required double projectPixelScale,
  required _RevealLayer layer,
  bool Function()? isCancelled,
}) async {
  final key = _StableRevealCacheKey(
    paths: sequence.paths,
    sectionClips: sectionClips,
    artworkRect: artworkRect,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  final cached = _takeCompiledStableReveal(key);
  if (cached != null) return cached;
  final compiler = _StableRevealCompiler(
    sequence: sequence,
    artworkRect: artworkRect,
    sectionClips: sectionClips,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  final stopwatch = Stopwatch()..start();
  while (compiler.hasNext) {
    if (isCancelled?.call() == true) return null;
    compiler.compileNext();
    if (stopwatch.elapsed >= _revealPrewarmSliceBudget) {
      await Future<void>.delayed(Duration.zero);
      if (isCancelled?.call() == true) return null;
      final concurrentlyCompiled = _takeCompiledStableReveal(key);
      if (concurrentlyCompiled != null) return concurrentlyCompiled;
      stopwatch.reset();
    }
  }
  if (isCancelled?.call() == true) return null;
  final result = compiler.finish();
  _storeCompiledStableReveal(key, result);
  return result;
}

_CompiledStableRevealSequence? _takeCompiledStableReveal(
  _StableRevealCacheKey key,
) {
  final cached = _stableRevealCache.remove(key);
  if (cached != null) _stableRevealCache[key] = cached;
  return cached;
}

void _storeCompiledStableReveal(
  _StableRevealCacheKey key,
  _CompiledStableRevealSequence result,
) {
  _stableRevealCache[key] = result;
  while (_stableRevealCache.length > _maximumStableRevealCacheEntries ||
      (_stableRevealCache.length > 1 &&
          _stableRevealCache.values.fold<int>(
                0,
                (total, item) => total + item.pathWeight,
              ) >
              _maximumStableRevealCachePaths)) {
    final evictedKey = _stableRevealCache.keys.first;
    _stableRevealCache.remove(evictedKey)?.dispose();
    _stableRevealPrewarmedKeys.remove(evictedKey);
  }
}

class _StableRevealCompiler {
  _StableRevealCompiler({
    required this.sequence,
    required this.artworkRect,
    required this.sectionClips,
    required this.defaultRevealWidth,
    required this.projectPixelScale,
    required this.layer,
  });

  final StableRevealSequence sequence;
  final Rect artworkRect;
  final List<Rect> sectionClips;
  final double defaultRevealWidth;
  final double projectPixelScale;
  final _RevealLayer layer;
  final Map<_BrushRevealBatchKey, _StableBrushBatchBuilder> brushBuilders = {};
  final List<_CompiledRevealEntry> specials = [];
  final List<_CompiledRevealEntry> erasers = [];
  final List<_CompiledRevealEntry> fills = [];
  int ordinal = 0;

  bool get hasNext => ordinal < sequence.paths.length;

  void compileNext() {
    final currentOrdinal = ordinal++;
    final revealed = sequence.paths[currentOrdinal];
    if (!_belongsToLayer(revealed, layer)) return;
    final exclusions = layer == _RevealLayer.all
        ? revealed.exclusionRects
        : const <Rect>[];
    if (_isBatchableBrush(revealed)) {
      final clip = _resolveRevealClip(
        revealed,
        artworkRect: artworkRect,
        sectionClips: sectionClips,
      );
      final brushWidth = _resolveBrushWidth(
        revealed,
        defaultRevealWidth: defaultRevealWidth,
        projectPixelScale: projectPixelScale,
      );
      final key = _BrushRevealBatchKey(
        clip: revealed.clipPath == null ? clip : Rect.zero,
        clipPath: revealed.clipPath,
        exclusions: exclusions,
        brushWidth: brushWidth,
      );
      brushBuilders
          .putIfAbsent(
            key,
            () => _StableBrushBatchBuilder(
              effectiveClip: _clipWithExclusions(
                clip,
                exclusions,
                revealed.clipPath,
              ),
              brushWidth: brushWidth,
              preserveIndividualAlpha: layer != _RevealLayer.all,
            ),
          )
          .add(currentOrdinal, revealed);
      return;
    }
    final entry = _compileRevealEntry(
      ordinal: currentOrdinal,
      revealed: revealed,
      artworkRect: artworkRect,
      sectionClips: sectionClips,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
      includeExclusions: layer == _RevealLayer.all,
    );
    specials.add(entry);
    if (_hasEraseMask(revealed)) erasers.add(entry);
    if (_hasFillPatch(revealed)) fills.add(entry);
  }

  _CompiledStableRevealSequence finish() => _CompiledStableRevealSequence(
    brushBatches: List.unmodifiable([
      for (final builder in brushBuilders.values) builder.build(),
    ]),
    specialReveals: List.unmodifiable(specials),
    eraseReveals: List.unmodifiable(erasers),
    fillReveals: List.unmodifiable(fills),
  );
}

_CompiledRevealEntry _compileRevealEntry({
  required int ordinal,
  required RevealedPath revealed,
  required Rect artworkRect,
  required List<Rect> sectionClips,
  required double defaultRevealWidth,
  required double projectPixelScale,
  bool includeExclusions = true,
}) {
  final clip = _resolveRevealClip(
    revealed,
    artworkRect: artworkRect,
    sectionClips: sectionClips,
  );
  return _CompiledRevealEntry(
    ordinal: ordinal,
    revealed: revealed,
    clip: clip,
    effectiveClip: _clipWithExclusions(
      clip,
      includeExclusions ? revealed.exclusionRects : const <Rect>[],
      revealed.clipPath,
    ),
    brushWidth: _resolveBrushWidth(
      revealed,
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
    ),
  );
}

Rect _resolveRevealClip(
  RevealedPath revealed, {
  required Rect artworkRect,
  required List<Rect> sectionClips,
}) =>
    revealed.clipRect ??
    (revealed.sectionIndex < sectionClips.length
        ? sectionClips[revealed.sectionIndex]
        : artworkRect);

double _resolveBrushWidth(
  RevealedPath revealed, {
  required double defaultRevealWidth,
  required double projectPixelScale,
}) => (revealed.revealWidth ?? defaultRevealWidth) * projectPixelScale;

class _StableRevealCacheKey {
  const _StableRevealCacheKey({
    required this.paths,
    required this.sectionClips,
    required this.artworkRect,
    required this.defaultRevealWidth,
    required this.projectPixelScale,
    required this.layer,
  });

  final List<RevealedPath> paths;
  final List<Rect> sectionClips;
  final Rect artworkRect;
  final double defaultRevealWidth;
  final double projectPixelScale;
  final _RevealLayer layer;

  @override
  int get hashCode => Object.hash(
    identityHashCode(paths),
    identityHashCode(sectionClips),
    artworkRect,
    defaultRevealWidth,
    projectPixelScale,
    layer,
  );

  @override
  bool operator ==(Object other) =>
      other is _StableRevealCacheKey &&
      identical(other.paths, paths) &&
      identical(other.sectionClips, sectionClips) &&
      other.artworkRect == artworkRect &&
      other.defaultRevealWidth == defaultRevealWidth &&
      other.projectPixelScale == projectPixelScale &&
      other.layer == layer;
}

class _CompiledStableRevealSequence {
  _CompiledStableRevealSequence({
    required this.brushBatches,
    required this.specialReveals,
    required this.eraseReveals,
    required this.fillReveals,
  });

  final List<_CompiledBrushBatch> brushBatches;
  final List<_CompiledRevealEntry> specialReveals;
  final List<_CompiledRevealEntry> eraseReveals;
  final List<_CompiledRevealEntry> fillReveals;
  var _isDisposed = false;

  bool get isDisposed => _isDisposed;

  int get pathWeight =>
      specialReveals.length +
      brushBatches.fold<int>(0, (total, batch) => total + batch.paths.length);

  bool get isEmpty => pathWeight == 0;

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final batch in brushBatches) {
      batch.dispose();
    }
  }
}

class _CompiledRevealEntry {
  const _CompiledRevealEntry({
    required this.ordinal,
    required this.revealed,
    required this.clip,
    required this.effectiveClip,
    required this.brushWidth,
  });

  final int ordinal;
  final RevealedPath revealed;
  final Rect clip;
  final Path effectiveClip;
  final double brushWidth;
}

class _StableBrushBatchBuilder {
  _StableBrushBatchBuilder({
    required this.effectiveClip,
    required this.brushWidth,
    required this.preserveIndividualAlpha,
  });

  final Path effectiveClip;
  final double brushWidth;
  final bool preserveIndividualAlpha;
  final List<int> ordinals = [];
  final List<RevealedPath> paths = [];

  void add(int ordinal, RevealedPath path) {
    ordinals.add(ordinal);
    paths.add(path);
  }

  _CompiledBrushBatch build() => _CompiledBrushBatch(
    effectiveClip: effectiveClip,
    brushWidth: brushWidth,
    preserveIndividualAlpha: preserveIndividualAlpha,
    ordinals: List.unmodifiable(ordinals),
    paths: List.unmodifiable(paths),
  );
}

class _CompiledBrushBatch {
  _CompiledBrushBatch({
    required this.effectiveClip,
    required this.brushWidth,
    required this.preserveIndividualAlpha,
    required this.ordinals,
    required this.paths,
  }) : paint = _brushRevealPaint(brushWidth);

  final Path effectiveClip;
  final double brushWidth;
  final bool preserveIndividualAlpha;
  final List<int> ordinals;
  final List<RevealedPath> paths;
  final Paint paint;
  final Map<int, Path> _fullChunks = {};
  final Map<int, Picture> _fullPictures = {};
  final LinkedHashMap<int, Path> _partialChunks = LinkedHashMap();
  final LinkedHashMap<int, Picture> _partialPictures = LinkedHashMap();
  var _isDisposed = false;

  Future<bool> prewarm({
    required int targetVisibleCount,
    required Duration sliceBudget,
    bool Function()? isCancelled,
  }) async {
    final stopwatch = Stopwatch()..start();
    // Prepare every complete chunk so a later arbitrary 50-100% seek only has
    // to combine the bounded (<64 path) tail of each visual batch.
    final fullChunkCount = paths.length ~/ _brushPathChunkSize;
    for (var index = 0; index < fullChunkCount; index++) {
      if (_isDisposed || isCancelled?.call() == true) return false;
      final start = index * _brushPathChunkSize;
      final end = start + _brushPathChunkSize;
      if (preserveIndividualAlpha) {
        _fullPictures[index] ??= _recordBrushPicture(paths, start, end, paint);
      } else {
        _fullChunks[index] ??= _combineBrushPaths(paths, start, end);
      }
      if (stopwatch.elapsed >= sliceBudget) {
        await Future<void>.delayed(Duration.zero);
        if (_isDisposed || isCancelled?.call() == true) return false;
        stopwatch.reset();
      }
    }
    // Also cache the exact requested seek tail (important to MOV's first
    // frame); Preview still remains bounded for any other seek position.
    final visible = _visiblePathCount(targetVisibleCount);
    final remainderStart =
        (visible ~/ _brushPathChunkSize) * _brushPathChunkSize;
    if (remainderStart >= visible) return true;
    if (_isDisposed || isCancelled?.call() == true) return false;
    if (preserveIndividualAlpha) {
      _partialPictures[visible] ??= _recordBrushPicture(
        paths,
        remainderStart,
        visible,
        paint,
      );
    } else {
      _partialChunks[visible] ??= _combineBrushPaths(
        paths,
        remainderStart,
        visible,
      );
    }
    return !_isDisposed && isCancelled?.call() != true;
  }

  void drawVisible(Canvas canvas, int globalVisibleCount) {
    final visible = _visiblePathCount(globalVisibleCount);
    if (visible == 0) return;
    canvas.save();
    canvas.clipPath(effectiveClip);
    final fullChunkCount = visible ~/ _brushPathChunkSize;
    for (var index = 0; index < fullChunkCount; index++) {
      final start = index * _brushPathChunkSize;
      final end = start + _brushPathChunkSize;
      if (preserveIndividualAlpha) {
        final picture = _fullPictures[index] ??= _recordBrushPicture(
          paths,
          start,
          end,
          paint,
        );
        canvas.drawPicture(picture);
      } else {
        final chunk = _fullChunks[index] ??= _combineBrushPaths(
          paths,
          start,
          end,
        );
        canvas.drawPath(chunk, paint);
      }
    }
    final remainderStart = fullChunkCount * _brushPathChunkSize;
    if (remainderStart < visible) {
      if (preserveIndividualAlpha) {
        final cached = _partialPictures.remove(visible);
        final partial =
            cached ??
            _recordBrushPicture(paths, remainderStart, visible, paint);
        _partialPictures[visible] = partial;
        if (_partialPictures.length > 12) {
          _partialPictures.remove(_partialPictures.keys.first)?.dispose();
        }
        canvas.drawPicture(partial);
      } else {
        final cached = _partialChunks.remove(visible);
        final partial =
            cached ?? _combineBrushPaths(paths, remainderStart, visible);
        _partialChunks[visible] = partial;
        if (_partialChunks.length > 12) {
          _partialChunks.remove(_partialChunks.keys.first);
        }
        canvas.drawPath(partial, paint);
      }
    }
    canvas.restore();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final picture in _fullPictures.values) {
      picture.dispose();
    }
    for (final picture in _partialPictures.values) {
      picture.dispose();
    }
    _fullPictures.clear();
    _fullChunks.clear();
    _partialPictures.clear();
    _partialChunks.clear();
  }

  int _visiblePathCount(int globalVisibleCount) {
    var low = 0;
    var high = ordinals.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (ordinals[middle] < globalVisibleCount) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

Picture _recordBrushPicture(
  List<RevealedPath> paths,
  int start,
  int end,
  Paint paint,
) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  for (var index = start; index < end; index++) {
    canvas.drawPath(paths[index].path, paint);
  }
  return recorder.endRecording();
}

Paint _brushRevealPaint(double width) => Paint()
  ..color = const Color(0xFFFFFFFF)
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..strokeWidth = width;

const _brushPathChunkSize = 64;
const _maximumBrushChunkCacheEntries = 512;
final LinkedHashMap<_BrushChunkKey, Path> _brushChunkCache = LinkedHashMap();

Path _combinedBrushChunk(List<RevealedPath> paths, int start, int end) {
  var canCache = end - start == _brushPathChunkSize;
  var identitySignature = 0;
  for (var index = start; index < end; index++) {
    canCache = canCache && paths[index].strokeProgress >= 1;
    identitySignature = Object.hash(identitySignature, paths[index].path);
  }
  if (!canCache) return _combineBrushPaths(paths, start, end);
  final key = _BrushChunkKey(
    first: paths[start].path,
    last: paths[end - 1].path,
    identitySignature: identitySignature,
  );
  final cached = _brushChunkCache.remove(key);
  if (cached != null) {
    _brushChunkCache[key] = cached;
    return cached;
  }
  final combined = _combineBrushPaths(paths, start, end);
  _brushChunkCache[key] = combined;
  if (_brushChunkCache.length > _maximumBrushChunkCacheEntries) {
    _brushChunkCache.remove(_brushChunkCache.keys.first);
  }
  return combined;
}

Path _combineBrushPaths(List<RevealedPath> paths, int start, int end) {
  debugRevealBrushChunkBuildCount += 1;
  final result = Path();
  for (var index = start; index < end; index++) {
    result.addPath(paths[index].path, Offset.zero);
  }
  return result;
}

class _BrushChunkKey {
  const _BrushChunkKey({
    required this.first,
    required this.last,
    required this.identitySignature,
  });

  final Path first;
  final Path last;
  final int identitySignature;

  @override
  int get hashCode => Object.hash(first, last, identitySignature);

  @override
  bool operator ==(Object other) =>
      other is _BrushChunkKey &&
      identical(other.first, first) &&
      identical(other.last, last) &&
      other.identitySignature == identitySignature;
}

class _BrushRevealBatchKey {
  const _BrushRevealBatchKey({
    required this.clip,
    required this.clipPath,
    required this.exclusions,
    required this.brushWidth,
  });

  final Rect clip;
  final Path? clipPath;
  final List<Rect> exclusions;
  final double brushWidth;

  @override
  int get hashCode => Object.hash(
    clip,
    identityHashCode(clipPath),
    brushWidth,
    exclusions is ImmutableRectList
        ? (exclusions as ImmutableRectList).contentHash
        : Object.hashAll(exclusions),
  );

  @override
  bool operator ==(Object other) =>
      other is _BrushRevealBatchKey &&
      other.clip == clip &&
      identical(other.clipPath, clipPath) &&
      other.brushWidth == brushWidth &&
      _rectListsEqual(other.exclusions, exclusions);
}

bool _rectListsEqual(List<Rect> a, List<Rect> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _belongsToLayer(RevealedPath path, _RevealLayer layer) => switch (layer) {
  _RevealLayer.all => true,
  _RevealLayer.filled => path.isFilledShape,
  _RevealLayer.strokes =>
    !path.isFilledShape && !path.isTextShape && !path.isGlobalDecoration,
  _RevealLayer.global => path.isGlobalDecoration,
  _RevealLayer.nonText => !path.isTextShape,
  _RevealLayer.text => path.isTextShape,
};

void _drawLayeredSvgReveal({
  required Canvas canvas,
  required Image completeImage,
  required Image? legacyBaseImage,
  required SvgRevealLayers? svgRevealLayers,
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required double defaultRevealWidth,
  required double projectPixelScale,
}) {
  void drawLayer({required Image sourceImage, required _RevealLayer layer}) {
    final stable = snapshot.stableRevealSequence;
    if (stable != null) {
      _drawStableMaskedSource(
        canvas: canvas,
        sourceImage: sourceImage,
        artworkRect: artworkRect,
        snapshot: snapshot,
        sequence: stable,
        layer: layer,
        defaultRevealWidth: defaultRevealWidth,
        projectPixelScale: projectPixelScale,
      );
      return;
    }
    _drawMaskedSource(
      canvas: canvas,
      sourceImage: sourceImage,
      artworkRect: artworkRect,
      snapshot: snapshot,
      paths: snapshot.revealedPaths
          .where((path) => _belongsToLayer(path, layer))
          .toList(growable: false),
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
    );
  }

  if (svgRevealLayers != null) {
    drawLayer(sourceImage: svgRevealLayers.fills, layer: _RevealLayer.filled);
    drawLayer(
      sourceImage: svgRevealLayers.strokes,
      layer: _RevealLayer.strokes,
    );
    drawLayer(
      sourceImage: svgRevealLayers.globalStrokes ?? completeImage,
      layer: _RevealLayer.global,
    );
  } else if (legacyBaseImage != null) {
    drawLayer(sourceImage: legacyBaseImage, layer: _RevealLayer.nonText);
  }
  drawLayer(sourceImage: completeImage, layer: _RevealLayer.text);
}

void _drawStableMaskedSource({
  required Canvas canvas,
  required Image sourceImage,
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required StableRevealSequence sequence,
  required _RevealLayer layer,
  required double defaultRevealWidth,
  required double projectPixelScale,
}) {
  final compiled = _compiledStableRevealSequence(
    sequence: sequence,
    artworkRect: artworkRect,
    sectionClips: snapshot.sectionClips,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  final active = sequence.activePath;
  final activeInLayer = active != null && _belongsToLayer(active, layer);
  if (compiled.isEmpty && !activeInLayer) return;

  // The legacy layered compositor applies an erase before later paths. Keep
  // that order-sensitive rare case on its exact path while dense ordinary
  // Auto Path brushes use the compiled fast path.
  if (compiled.eraseReveals.isNotEmpty ||
      (activeInLayer && _hasEraseMask(active))) {
    _drawMaskedSource(
      canvas: canvas,
      sourceImage: sourceImage,
      artworkRect: artworkRect,
      snapshot: snapshot,
      paths: snapshot.revealedPaths
          .where((path) => _belongsToLayer(path, layer))
          .toList(growable: false),
      defaultRevealWidth: defaultRevealWidth,
      projectPixelScale: projectPixelScale,
    );
    return;
  }

  canvas.saveLayer(artworkRect, Paint());
  _drawStableRasterReveal(
    canvas: canvas,
    artworkRect: artworkRect,
    snapshot: snapshot,
    sequence: sequence,
    defaultRevealWidth: defaultRevealWidth,
    projectPixelScale: projectPixelScale,
    layer: layer,
  );
  canvas.drawImageRect(
    sourceImage,
    Rect.fromLTWH(
      0,
      0,
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    ),
    artworkRect,
    Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..blendMode = BlendMode.srcIn,
  );
  canvas.restore();
}

void _drawMaskedSource({
  required Canvas canvas,
  required Image sourceImage,
  required Rect artworkRect,
  required TimelineSnapshot snapshot,
  required List<RevealedPath> paths,
  required double defaultRevealWidth,
  required double projectPixelScale,
}) {
  if (paths.isEmpty) return;
  canvas.saveLayer(artworkRect, Paint());
  for (final revealed in paths) {
    final clip =
        revealed.clipRect ??
        (revealed.sectionIndex < snapshot.sectionClips.length
            ? snapshot.sectionClips[revealed.sectionIndex]
            : artworkRect);
    canvas.save();
    canvas.clipPath(
      _clipWithExclusions(clip, const [], revealed.clipPath),
      doAntiAlias: true,
    );
    drawRevealMask(
      canvas: canvas,
      revealed: revealed,
      clip: clip,
      brushWidth:
          (revealed.revealWidth ?? defaultRevealWidth) * projectPixelScale,
      featherWidth: 28 * projectPixelScale,
    );
    for (final mask in revealed.vectorMaskStrokes.where(
      (item) => item.operation == VectorMaskOperation.reveal,
    )) {
      _drawVectorMaskStroke(
        canvas: canvas,
        mask: mask,
        artworkRect: artworkRect,
        progress: revealed.strokeProgress,
        erase: false,
      );
    }
    for (final mask in revealed.vectorMaskStrokes.where(
      (item) => item.operation == VectorMaskOperation.erase,
    )) {
      _drawVectorMaskStroke(
        canvas: canvas,
        mask: mask,
        artworkRect: artworkRect,
        progress: revealed.strokeProgress,
        erase: true,
      );
    }
    canvas.restore();
  }
  canvas.drawImageRect(
    sourceImage,
    Rect.fromLTWH(
      0,
      0,
      sourceImage.width.toDouble(),
      sourceImage.height.toDouble(),
    ),
    artworkRect,
    Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..blendMode = BlendMode.srcIn,
  );
  canvas.restore();
}

void _drawFilledShapeExclusionPatches({
  required Canvas canvas,
  required RevealedPath revealed,
  required Rect clip,
  required Color color,
  required double featherWidth,
}) {
  final metrics = revealed.path.computeMetrics().toList(growable: false);
  if (metrics.isEmpty) return;
  final metric = metrics.last;
  final endpoint = metric.getTangentForOffset(metric.length)?.position;
  if (endpoint == null) return;
  final edge = endpoint.dx.clamp(clip.left, clip.right);
  final feather = featherWidth.clamp(0.0, clip.width * 0.12);
  for (final exclusion in revealed.exclusionRects) {
    final patch = exclusion.intersect(clip);
    if (patch.isEmpty) continue;
    canvas.save();
    canvas.clipRect(patch);
    if (revealed.rightToLeft) {
      canvas.drawRect(
        Rect.fromLTRB(edge, clip.top, clip.right, clip.bottom),
        Paint()..color = color,
      );
      final start = math.max(clip.left, edge - feather);
      if (edge > start) {
        canvas.drawRect(
          Rect.fromLTRB(start, clip.top, edge, clip.bottom),
          Paint()
            ..shader = Gradient.linear(
              Offset(start, clip.center.dy),
              Offset(edge, clip.center.dy),
              [color.withValues(alpha: 0), color],
            ),
        );
      }
    } else {
      canvas.drawRect(
        Rect.fromLTRB(clip.left, clip.top, edge, clip.bottom),
        Paint()..color = color,
      );
      final end = math.min(clip.right, edge + feather);
      if (end > edge) {
        canvas.drawRect(
          Rect.fromLTRB(edge, clip.top, end, clip.bottom),
          Paint()
            ..shader = Gradient.linear(
              Offset(edge, clip.center.dy),
              Offset(end, clip.center.dy),
              [color, color.withValues(alpha: 0)],
            ),
        );
      }
    }
    canvas.restore();
  }
}

void _drawVectorMaskStroke({
  required Canvas canvas,
  required VectorMaskStroke mask,
  required Rect artworkRect,
  required double progress,
  required bool erase,
}) {
  final path = mask.geometry.toPath(artworkRect);
  final metrics = path.computeMetrics().toList(growable: false);
  if (metrics.isEmpty) return;
  final metric = metrics.first;
  final visible = metric.extractPath(
    0,
    metric.length * progress.clamp(0.0, 1.0),
  );
  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..blendMode = erase ? BlendMode.clear : BlendMode.srcOver
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = mask.widthFraction * artworkRect.height;
  final feather = mask.featherFraction * artworkRect.height;
  if (feather > 0.01) {
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, feather / 2);
  }
  canvas.drawPath(visible, paint);
}

Path _clipWithExclusions(
  Rect clip,
  List<Rect> exclusions, [
  Path? preciseClip,
]) {
  var result = preciseClip ?? (Path()..addRect(clip));
  for (final exclusion in exclusions) {
    result = Path.combine(
      PathOperation.difference,
      result,
      Path()..addRect(exclusion),
    );
  }
  return result;
}

/// In-flight prewarming retains its pictures until the operation finishes.
void clearIdleRevealRenderingCaches() {
  final idleKeys = _stableRevealCache.keys
      .where((key) => !_stableRevealPrewarmTasks.containsKey(key))
      .toList(growable: false);
  for (final key in idleKeys) {
    _stableRevealCache.remove(key)?.dispose();
    _stableRevealPrewarmedKeys.remove(key);
  }
  _brushChunkCache.clear();
}
