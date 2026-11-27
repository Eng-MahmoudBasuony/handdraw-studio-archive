import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:image/image.dart' as raster;

import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';

typedef RegionAnalysisProgress =
    void Function(int regionIndex, int regionCount, SmartPathProgress update);

/// Executes Auto Path once over the union of the confirmed scene masks, then
/// assigns the resulting paths back to their authored regions.
///
/// Running the complete OCR and raster pipeline once per region made scene
/// split cost grow linearly with the number of scenes. A seven-scene 1080p
/// title could therefore repeat the same expensive source analysis seven
/// times. The union keeps excluded pixels transparent while preserving the
/// exact region masks that Preview and MOV apply after planning.
class RegionAutoPathAnalyzer {
  const RegionAutoPathAnalyzer({
    this.cropEncoder = const IsolateRegionMaskedCropEncoder(),
  });

  final RegionMaskedCropEncoder cropEncoder;

  Future<List<SmartPathSection>> analyze({
    required ui.Image source,
    required List<SceneRegion> regions,
    required ArtworkPathFacade facade,
    RegionAnalysisProgress? onProgress,
    bool Function()? isCancelled,
    SmartPathCancellationToken? cancellationToken,
  }) async {
    if (regions.isEmpty) return const [];
    cancellationToken?.throwIfCancelled();
    final raw = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) throw StateError('Could not read artwork pixels.');
    cancellationToken?.throwIfCancelled();
    final sourceBytes = raw.buffer.asUint8List(
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    final session = await cropEncoder.open(
      rgba: sourceBytes,
      sourceWidth: source.width,
      sourceHeight: source.height,
    );
    void closeOnCancel() => unawaited(session.close());
    cancellationToken?.addListener(closeOnCancel);
    try {
      RegionEncodedCrop? crop;
      try {
        crop = await session.encode(_unionRegion(regions));
      } on Object {
        if (cancellationToken?.isCancelled == true ||
            isCancelled?.call() == true) {
          return const [];
        }
        rethrow;
      }
      if (crop == null ||
          cancellationToken?.isCancelled == true ||
          isCancelled?.call() == true) {
        return const [];
      }
      final codec = await ui.instantiateImageCodec(crop.encodedPng);
      ui.FrameInfo? frame;
      try {
        frame = await codec.getNextFrame();
        late final ArtworkPathResult result;
        try {
          result = await facade.analyze(
            ArtworkPathRequest(
              kind: ArtworkSourceKind.raster,
              previewImage: frame.image,
              previewBytes: crop.encodedPng,
              sourceBytes: crop.encodedPng,
              onProgress: onProgress == null
                  ? null
                  : (update) => onProgress(0, 1, update),
              cancellationToken: cancellationToken,
              coordinateBounds: crop.bounds,
            ),
          );
        } on SmartPathCancelledException {
          return const [];
        }
        if (cancellationToken?.isCancelled == true ||
            isCancelled?.call() == true) {
          return const [];
        }
        return _partitionSections(regions, result.analysis.sections);
      } finally {
        frame?.image.dispose();
        codec.dispose();
      }
    } finally {
      cancellationToken?.removeListener(closeOnCancel);
      await session.close();
    }
  }
}

SceneRegion _unionRegion(List<SceneRegion> regions) {
  final fragments = <ui.Rect>[];
  final polygons = <List<ui.Offset>>[];
  for (final region in regions) {
    if (region.fragments.isEmpty) {
      polygons.addAll(region.maskPolygons);
    } else {
      fragments.addAll(region.fragments);
      polygons.addAll(region.additionalPolygons);
    }
  }
  if (fragments.isNotEmpty) {
    return SceneRegion(
      id: 'scene-union',
      name: 'Scene union',
      polygon: const [],
      fragments: fragments,
      additionalPolygons: polygons,
      automatic: true,
    );
  }
  return SceneRegion(
    id: 'scene-union',
    name: 'Scene union',
    polygon: polygons.isEmpty ? const [] : polygons.first,
    additionalPolygons: polygons.skip(1),
  );
}

List<SmartPathSection> _partitionSections(
  List<SceneRegion> regions,
  List<SmartPathSection> analyzed,
) {
  final active = analyzed
      .where((section) => section.mode != SmartSectionMode.ignore)
      .toList(growable: false);
  final assigned = <String, List<_AssignedSection>>{
    for (final region in regions) region.id: [],
  };
  for (final section in active) {
    final pathsByRegion = <String, List<SmartGeneratedPath>>{};
    for (final path in section.paths) {
      if (path.points.length < 2) continue;
      final region = _bestRegionForPath(path, section.bounds, regions);
      if (region != null) {
        pathsByRegion.putIfAbsent(region.id, () => []).add(path);
      }
    }
    if (section.paths.isEmpty) {
      final region = _bestRegionForPoint(section.bounds.center, regions);
      if (region != null) pathsByRegion[region.id] = const [];
    }
    for (final entry in pathsByRegion.entries) {
      assigned[entry.key]!.add(_AssignedSection(section, entry.value));
    }
  }

  final results = <SmartPathSection>[];
  for (final region in regions) {
    final regionSections = assigned[region.id]!;
    if (regionSections.isEmpty) {
      results.add(_fallbackSection(region));
      continue;
    }
    for (var index = 0; index < regionSections.length; index++) {
      final item = regionSections[index];
      final pathBounds = _pathsBounds(item.paths);
      final bounds = (pathBounds ?? item.section.bounds)
          .intersect(region.bounds)
          .intersect(const ui.Rect.fromLTWH(0, 0, 1, 1));
      results.add(
        SmartPathSection(
          id: '${region.id}::${item.section.id}-$index',
          kind: item.section.kind,
          bounds: bounds.isEmpty ? region.bounds : bounds,
          label: '${region.name} • ${item.section.label}',
          paths: item.paths,
          recommendedRevealWidth: item.section.recommendedRevealWidth,
          mode: item.section.mode,
          confidence: item.section.confidence,
          rightToLeft: item.section.rightToLeft,
          role: item.section.role,
          hasPreciseTrace: item.section.hasPreciseTrace,
          artifactHint: item.section.artifactHint,
          artifactConfidence: item.section.artifactConfidence,
        ),
      );
    }
  }
  return List.unmodifiable(results);
}

final class _AssignedSection {
  const _AssignedSection(this.section, this.paths);

  final SmartPathSection section;
  final List<SmartGeneratedPath> paths;
}

SceneRegion? _bestRegionForPath(
  SmartGeneratedPath path,
  ui.Rect sectionBounds,
  List<SceneRegion> regions,
) {
  if (path.points.isEmpty) {
    return _bestRegionForPoint(sectionBounds.center, regions);
  }
  SceneRegion? best;
  var bestScore = -1;
  const maximumSamples = 64;
  final step = math.max(1, (path.points.length / maximumSamples).ceil());
  for (final region in regions) {
    if (!region.bounds.overlaps(sectionBounds) &&
        !region.bounds.contains(sectionBounds.center)) {
      continue;
    }
    var score = 0;
    for (var index = 0; index < path.points.length; index += step) {
      if (region.contains(path.points[index])) score++;
    }
    if (score > bestScore) {
      best = region;
      bestScore = score;
    }
  }
  if (bestScore > 0) return best;
  return _bestRegionForPoint(_pathCenter(path), regions);
}

SceneRegion? _bestRegionForPoint(ui.Offset point, List<SceneRegion> regions) {
  for (final region in regions) {
    if (region.contains(point)) return region;
  }
  SceneRegion? nearest;
  var nearestDistance = double.infinity;
  for (final region in regions) {
    final distance = (region.bounds.center - point).distanceSquared;
    if (distance < nearestDistance) {
      nearest = region;
      nearestDistance = distance;
    }
  }
  return nearest;
}

ui.Offset _pathCenter(SmartGeneratedPath path) {
  var x = 0.0;
  var y = 0.0;
  for (final point in path.points) {
    x += point.dx;
    y += point.dy;
  }
  return ui.Offset(x / path.points.length, y / path.points.length);
}

ui.Rect? _pathsBounds(List<SmartGeneratedPath> paths) {
  ui.Rect? result;
  for (final path in paths) {
    if (path.points.isEmpty) continue;
    var left = path.points.first.dx;
    var top = path.points.first.dy;
    var right = left;
    var bottom = top;
    for (final point in path.points.skip(1)) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    final bounds = ui.Rect.fromLTRB(left, top, right, bottom);
    result = result == null ? bounds : result.expandToInclude(bounds);
  }
  return result;
}

/// Opens a worker that retains the source pixels and encodes exact masked
/// crops without occupying Flutter's UI isolate.
abstract interface class RegionMaskedCropEncoder {
  Future<RegionMaskedCropEncodingSession> open({
    required Uint8List rgba,
    required int sourceWidth,
    required int sourceHeight,
  });
}

abstract interface class RegionMaskedCropEncodingSession {
  Future<RegionEncodedCrop?> encode(SceneRegion region);
  Future<void> close();
}

final class RegionEncodedCrop {
  const RegionEncodedCrop({
    required this.encodedPng,
    required this.bounds,
    this.polygonMembershipTests = 0,
  });

  final Uint8List encodedPng;
  final ui.Rect bounds;
  final int polygonMembershipTests;
}

/// Production encoder backed by one long-lived isolate per region-analysis
/// run. The source RGBA buffer crosses the isolate boundary once and is then
/// reused for every region, avoiding repeated full-image copies.
final class IsolateRegionMaskedCropEncoder implements RegionMaskedCropEncoder {
  const IsolateRegionMaskedCropEncoder();

  @override
  Future<RegionMaskedCropEncodingSession> open({
    required Uint8List rgba,
    required int sourceWidth,
    required int sourceHeight,
  }) async {
    final ready = ReceivePort();
    final exited = ReceivePort();
    final errors = ReceivePort();
    final lifecycle = _RegionCropWorkerLifecycle(exited, errors);
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<List<Object?>>(
        _regionCropWorkerMain,
        [
          ready.sendPort,
          TransferableTypedData.fromList([rgba]),
          sourceWidth,
          sourceHeight,
        ],
        debugName: 'handdraw-region-mask-encoder',
        onExit: exited.sendPort,
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
      final commandPort =
          await Future.any<SendPort>([
            ready.first.then((value) => value as SendPort),
            lifecycle.firstFailure.then<SendPort>((error) => throw error),
          ]).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'Region crop worker did not become ready.',
            ),
          );
      return _IsolateRegionMaskedCropEncodingSession(
        isolate,
        commandPort,
        lifecycle,
      );
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      await lifecycle.close();
      rethrow;
    } finally {
      ready.close();
    }
  }
}

final class _IsolateRegionMaskedCropEncodingSession
    implements RegionMaskedCropEncodingSession {
  _IsolateRegionMaskedCropEncodingSession(
    this._isolate,
    this._commandPort,
    this._lifecycle,
  ) {
    _lifecycle.attach((error) {
      if (!_closed) {
        _recordWorkerFailure(error);
      }
    });
  }

  final Isolate _isolate;
  final SendPort _commandPort;
  final _RegionCropWorkerLifecycle _lifecycle;
  final Set<_PendingCropResponse> _pending = {};
  Object? _workerFailure;
  var _closed = false;
  Future<void>? _closeFuture;

  @override
  Future<RegionEncodedCrop?> encode(SceneRegion region) async {
    if (_closed) throw StateError('Region crop encoder is closed.');
    if (_workerFailure case final failure?) throw failure;
    final pending = _PendingCropResponse();
    _pending.add(pending);
    try {
      _commandPort.send([pending.sendPort, _regionToTransfer(region)]);
      final raw = await pending.future;
      if (raw == null) return null;
      if (raw case {'error': final String error}) {
        throw StateError('Region crop encoding failed: $error');
      }
      final result = raw as List<Object?>;
      final bounds = result[0]! as List<Object?>;
      final encoded = (result[1]! as TransferableTypedData)
          .materialize()
          .asUint8List();
      return RegionEncodedCrop(
        encodedPng: encoded,
        bounds: ui.Rect.fromLTRB(
          (bounds[0]! as num).toDouble(),
          (bounds[1]! as num).toDouble(),
          (bounds[2]! as num).toDouble(),
          (bounds[3]! as num).toDouble(),
        ),
        polygonMembershipTests: result[2]! as int,
      );
    } finally {
      _pending.remove(pending);
      await pending.dispose();
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _failPending(StateError('Region crop encoder was closed.'));
    _isolate.kill(priority: Isolate.immediate);
    await _lifecycle.close();
  }

  void _failPending(Object error) {
    for (final pending in _pending.toList(growable: false)) {
      pending.fail(error);
    }
  }

  void _recordWorkerFailure(Object error) {
    _workerFailure ??= error;
    _failPending(error);
  }
}

final class _RegionCropWorkerLifecycle {
  _RegionCropWorkerLifecycle(this._exitPort, this._errorPort) {
    _exitSubscription = _exitPort.listen((_) {
      _record(StateError('Region crop worker exited unexpectedly.'));
    });
    _errorSubscription = _errorPort.listen((message) {
      final details = message is List && message.isNotEmpty
          ? message.first.toString()
          : message.toString();
      _record(StateError('Region crop worker failed: $details'));
    });
  }

  final ReceivePort _exitPort;
  final ReceivePort _errorPort;
  final Completer<Object> _firstFailure = Completer<Object>();
  late final StreamSubscription<Object?> _exitSubscription;
  late final StreamSubscription<Object?> _errorSubscription;
  Object? _failure;
  void Function(Object error)? _onFailure;
  var _closed = false;

  Future<Object> get firstFailure => _firstFailure.future;

  void attach(void Function(Object error) onFailure) {
    _onFailure = onFailure;
    if (_failure case final failure?) onFailure(failure);
  }

  void _record(Object error) {
    if (_closed) return;
    _failure ??= error;
    if (!_firstFailure.isCompleted) _firstFailure.complete(error);
    _onFailure?.call(error);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _exitSubscription.cancel();
    await _errorSubscription.cancel();
    _exitPort.close();
    _errorPort.close();
  }
}

final class _PendingCropResponse {
  _PendingCropResponse() {
    _subscription = _port.listen(
      _complete,
      onError: fail,
      onDone: () => fail(StateError('Region crop worker returned no result.')),
    );
  }

  final ReceivePort _port = ReceivePort();
  final Completer<Object?> _completer = Completer<Object?>();
  late final StreamSubscription<Object?> _subscription;

  SendPort get sendPort => _port.sendPort;
  Future<Object?> get future => _completer.future;

  void _complete(Object? value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void fail(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    _port.close();
  }
}

void _regionCropWorkerMain(List<Object?> bootstrap) {
  final readyPort = bootstrap[0]! as SendPort;
  final rgba = (bootstrap[1]! as TransferableTypedData)
      .materialize()
      .asUint8List();
  final sourceWidth = bootstrap[2]! as int;
  final sourceHeight = bootstrap[3]! as int;
  final commands = ReceivePort();
  readyPort.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      commands.close();
      return;
    }
    final request = message as List<Object?>;
    final responsePort = request[0]! as SendPort;
    try {
      final region = _regionFromTransfer(request[1]! as Map<Object?, Object?>);
      final crop = _encodeMaskedCrop(rgba, sourceWidth, sourceHeight, region);
      if (crop == null) {
        responsePort.send(null);
        return;
      }
      responsePort.send([
        [
          crop.bounds.left,
          crop.bounds.top,
          crop.bounds.right,
          crop.bounds.bottom,
        ],
        TransferableTypedData.fromList([crop.encodedPng]),
        crop.polygonMembershipTests,
      ]);
    } catch (error, stackTrace) {
      responsePort.send({
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
    }
  });
}

RegionEncodedCrop? _encodeMaskedCrop(
  Uint8List rgba,
  int sourceWidth,
  int sourceHeight,
  SceneRegion region,
) {
  final bounds = region.bounds.intersect(const ui.Rect.fromLTWH(0, 0, 1, 1));
  if (bounds.isEmpty) return null;
  final left = (bounds.left * sourceWidth).floor().clamp(0, sourceWidth - 1);
  final top = (bounds.top * sourceHeight).floor().clamp(0, sourceHeight - 1);
  final right = (bounds.right * sourceWidth).ceil().clamp(
    left + 1,
    sourceWidth,
  );
  final bottom = (bounds.bottom * sourceHeight).ceil().clamp(
    top + 1,
    sourceHeight,
  );
  final width = right - left;
  final height = bottom - top;
  final output = raster.Image(width: width, height: height, numChannels: 4);
  var membershipTests = 0;
  if (region.fragments.isNotEmpty) {
    final mask = Uint8List(width * height);
    for (final fragment in region.fragments) {
      _fillRectMask(
        mask,
        width,
        height,
        cropLeft: left,
        cropTop: top,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        rect: fragment,
      );
    }
    for (final polygon in region.additionalPolygons) {
      membershipTests += _overlayPolygonMask(
        mask,
        width,
        height,
        cropLeft: left,
        cropTop: top,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        polygon: polygon,
      );
    }
    _copyMaskedPixels(
      output,
      mask,
      rgba,
      sourceWidth,
      cropLeft: left,
      cropTop: top,
    );
  } else {
    final polygons = region.maskPolygons;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final sx = left + x;
        final sy = top + y;
        final normalized = ui.Offset(
          (sx + 0.5) / sourceWidth,
          (sy + 0.5) / sourceHeight,
        );
        var included = false;
        for (final polygon in polygons) {
          membershipTests++;
          if (_polygonContains(polygon, normalized)) {
            included = true;
            break;
          }
        }
        if (included) {
          _copySourcePixel(output, x, y, rgba, sourceWidth, sx, sy);
        }
      }
    }
  }
  return RegionEncodedCrop(
    encodedPng: raster.encodePng(output),
    bounds: ui.Rect.fromLTRB(
      left / sourceWidth,
      top / sourceHeight,
      right / sourceWidth,
      bottom / sourceHeight,
    ),
    polygonMembershipTests: membershipTests,
  );
}

void _fillRectMask(
  Uint8List mask,
  int cropWidth,
  int cropHeight, {
  required int cropLeft,
  required int cropTop,
  required int sourceWidth,
  required int sourceHeight,
  required ui.Rect rect,
}) {
  final startX = (rect.left * sourceWidth - 0.5).ceil().clamp(
    cropLeft,
    cropLeft + cropWidth,
  );
  final endX = (rect.right * sourceWidth - 0.5).ceil().clamp(
    cropLeft,
    cropLeft + cropWidth,
  );
  final startY = (rect.top * sourceHeight - 0.5).ceil().clamp(
    cropTop,
    cropTop + cropHeight,
  );
  final endY = (rect.bottom * sourceHeight - 0.5).ceil().clamp(
    cropTop,
    cropTop + cropHeight,
  );
  if (startX >= endX || startY >= endY) return;
  for (var sourceY = startY; sourceY < endY; sourceY++) {
    final row = (sourceY - cropTop) * cropWidth;
    mask.fillRange(row + startX - cropLeft, row + endX - cropLeft, 1);
  }
}

int _overlayPolygonMask(
  Uint8List mask,
  int cropWidth,
  int cropHeight, {
  required int cropLeft,
  required int cropTop,
  required int sourceWidth,
  required int sourceHeight,
  required List<ui.Offset> polygon,
}) {
  if (polygon.length < 3) return 0;
  var minX = polygon.first.dx;
  var maxX = minX;
  var minY = polygon.first.dy;
  var maxY = minY;
  for (final point in polygon.skip(1)) {
    minX = math.min(minX, point.dx);
    maxX = math.max(maxX, point.dx);
    minY = math.min(minY, point.dy);
    maxY = math.max(maxY, point.dy);
  }
  final startX = (minX * sourceWidth - 0.5).ceil().clamp(
    cropLeft,
    cropLeft + cropWidth,
  );
  final endX = (maxX * sourceWidth - 0.5).ceil().clamp(
    cropLeft,
    cropLeft + cropWidth,
  );
  final startY = (minY * sourceHeight - 0.5).ceil().clamp(
    cropTop,
    cropTop + cropHeight,
  );
  final endY = (maxY * sourceHeight - 0.5).ceil().clamp(
    cropTop,
    cropTop + cropHeight,
  );
  if (startX >= endX || startY >= endY) return 0;
  var tests = 0;
  for (var sourceY = startY; sourceY < endY; sourceY++) {
    for (var sourceX = startX; sourceX < endX; sourceX++) {
      tests++;
      if (_polygonContains(
        polygon,
        ui.Offset(
          (sourceX + 0.5) / sourceWidth,
          (sourceY + 0.5) / sourceHeight,
        ),
      )) {
        mask[(sourceY - cropTop) * cropWidth + sourceX - cropLeft] = 1;
      }
    }
  }
  return tests;
}

void _copyMaskedPixels(
  raster.Image output,
  Uint8List mask,
  Uint8List rgba,
  int sourceWidth, {
  required int cropLeft,
  required int cropTop,
}) {
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      if (mask[y * output.width + x] == 0) continue;
      final sourceX = cropLeft + x;
      final sourceY = cropTop + y;
      _copySourcePixel(output, x, y, rgba, sourceWidth, sourceX, sourceY);
    }
  }
}

void _copySourcePixel(
  raster.Image output,
  int x,
  int y,
  Uint8List rgba,
  int sourceWidth,
  int sourceX,
  int sourceY,
) {
  final offset = (sourceY * sourceWidth + sourceX) * 4;
  output.setPixelRgba(
    x,
    y,
    rgba[offset],
    rgba[offset + 1],
    rgba[offset + 2],
    rgba[offset + 3],
  );
}

bool _polygonContains(List<ui.Offset> polygon, ui.Offset point) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (
    var current = 0, previous = polygon.length - 1;
    current < polygon.length;
    previous = current++
  ) {
    final a = polygon[current];
    final b = polygon[previous];
    if ((a.dy > point.dy) == (b.dy > point.dy)) continue;
    final x = (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
    if (point.dx < x) inside = !inside;
  }
  return inside;
}

SmartPathSection _fallbackSection(SceneRegion region) => SmartPathSection(
  id: '${region.id}::fallback',
  kind: SmartSectionKind.shape,
  bounds: region.bounds,
  label: region.name,
  paths: [
    SmartGeneratedPath(
      points: [region.bounds.centerLeft, region.bounds.centerRight],
    ),
  ],
  recommendedRevealWidth: math.max(0.006, region.bounds.shortestSide * 0.08),
  mode: SmartSectionMode.revealText,
  confidence: 0.5,
);

Map<String, Object?> _regionToTransfer(SceneRegion region) => {
  'id': region.id,
  'name': region.name,
  'polygon': _polygonToTransfer(region.polygon),
  'fragments': [
    for (final rect in region.fragments)
      [rect.left, rect.top, rect.right, rect.bottom],
  ],
  'additionalPolygons': [
    for (final polygon in region.additionalPolygons)
      _polygonToTransfer(polygon),
  ],
  'automatic': region.automatic,
};

List<List<double>> _polygonToTransfer(List<ui.Offset> polygon) => [
  for (final point in polygon) [point.dx, point.dy],
];

SceneRegion _regionFromTransfer(Map<Object?, Object?> raw) => SceneRegion(
  id: raw['id']! as String,
  name: raw['name']! as String,
  polygon: _polygonFromTransfer(raw['polygon']! as List<Object?>),
  fragments: [
    for (final item in raw['fragments']! as List<Object?>)
      ui.Rect.fromLTRB(
        ((item as List<Object?>)[0]! as num).toDouble(),
        (item[1]! as num).toDouble(),
        (item[2]! as num).toDouble(),
        (item[3]! as num).toDouble(),
      ),
  ],
  additionalPolygons: [
    for (final item in raw['additionalPolygons']! as List<Object?>)
      _polygonFromTransfer(item as List<Object?>),
  ],
  automatic: raw['automatic']! as bool,
);

List<ui.Offset> _polygonFromTransfer(List<Object?> raw) => [
  for (final item in raw)
    ui.Offset(
      (((item as List<Object?>)[0])! as num).toDouble(),
      (item[1]! as num).toDouble(),
    ),
];
