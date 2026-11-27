import 'dart:isolate';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as raster;

import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';

/// Alpha-first scene segmentation for transparent artwork.
///
/// Work happens away from the UI isolate. A compact morphology pass joins the
/// letters and strokes that visually form one card, then spatial grouping joins
/// aligned fragments without changing the original pixels used by Auto Path.
class SmartSceneSplitter {
  const SmartSceneSplitter({
    this.maximumDimension = 560,
    this.useBackgroundIsolate,
  });

  final int maximumDimension;
  final bool? useBackgroundIsolate;

  SmartSceneProposalHandle start(Uint8List encoded) {
    final underFlutterTest =
        const bool.fromEnvironment('FLUTTER_TEST') ||
        Platform.environment['FLUTTER_TEST'] == 'true';
    final background = useBackgroundIsolate ?? !underFlutterTest;
    return background
        ? SmartSceneProposalHandle._background(encoded, maximumDimension)
        : SmartSceneProposalHandle._inline(encoded, maximumDimension);
  }

  Future<List<SceneRegion>> propose(Uint8List encoded) => start(encoded).result;
}

/// A single cancellable scene-proposal operation.
///
/// Production work owns a dedicated isolate. [cancel] kills that isolate even
/// when cancellation happens while it is still being spawned, and [stopped]
/// only completes after its resources have been released.
final class SmartSceneProposalHandle {
  SmartSceneProposalHandle._();

  /// Creates a cancellable adapter for alternate splitter implementations.
  ///
  /// This keeps Cubit tests and future segmentation engines on the same
  /// lifecycle contract as the production isolate worker.
  factory SmartSceneProposalHandle.fromFuture(
    Future<List<SceneRegion>> result, {
    FutureOr<void> Function()? onCancel,
  }) {
    final handle = SmartSceneProposalHandle._();
    handle._cancelCallback = onCancel;
    unawaited(
      result.then(handle._complete).catchError((
        Object error,
        StackTrace stack,
      ) {
        handle._completeError(error, stack);
      }),
    );
    return handle;
  }

  factory SmartSceneProposalHandle._background(
    Uint8List encoded,
    int maximumDimension,
  ) {
    final handle = SmartSceneProposalHandle._();
    handle._launch(encoded, maximumDimension);
    return handle;
  }

  factory SmartSceneProposalHandle._inline(
    Uint8List encoded,
    int maximumDimension,
  ) {
    final handle = SmartSceneProposalHandle._();
    scheduleMicrotask(() {
      if (handle._cancelled) return;
      try {
        handle._complete(_propose(encoded, maximumDimension));
      } catch (error, stackTrace) {
        handle._completeError(error, stackTrace);
      }
    });
    return handle;
  }

  final Completer<List<SceneRegion>> _result = Completer<List<SceneRegion>>();
  final Completer<void> _stopped = Completer<void>();
  ReceivePort? _receivePort;
  Future<Isolate>? _spawnFuture;
  Isolate? _isolate;
  FutureOr<void> Function()? _cancelCallback;
  var _cancelled = false;

  Future<List<SceneRegion>> get result => _result.future;
  Future<void> get stopped => _stopped.future;
  bool get isCancelled => _cancelled;

  void _launch(Uint8List encoded, int maximumDimension) {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen(_receive);
    final request = _ProposalRequest(
      receivePort.sendPort,
      TransferableTypedData.fromList([encoded]),
      maximumDimension,
    );
    final spawning = Isolate.spawn<_ProposalRequest>(
      _proposalWorker,
      request,
      onError: receivePort.sendPort,
      onExit: receivePort.sendPort,
      errorsAreFatal: true,
      debugName: 'handdraw-smart-scene-split',
    );
    _spawnFuture = spawning;
    unawaited(
      spawning
          .then((isolate) {
            _isolate = isolate;
            if (_cancelled) {
              isolate.kill(priority: Isolate.immediate);
              _release();
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!_cancelled) _completeError(error, stackTrace);
            _release();
          }),
    );
  }

  void _receive(Object? message) {
    if (_cancelled) return;
    if (message case _ProposalSuccess(:final regions)) {
      _complete(regions);
      _release();
      return;
    }
    if (message case _ProposalFailure(:final error, :final stackTrace)) {
      _completeError(StateError(error), StackTrace.fromString(stackTrace));
      _release();
      return;
    }
    if (message is List && message.length >= 2) {
      _completeError(
        StateError('${message.first}'),
        StackTrace.fromString('${message[1]}'),
      );
      _release();
      return;
    }
    if (message == null && !_result.isCompleted) {
      _completeError(
        StateError('Smart scene proposal worker exited without a result.'),
        StackTrace.current,
      );
      _release();
    }
  }

  Future<void> cancel() async {
    if (_cancelled) return stopped;
    _cancelled = true;
    if (!_result.isCompleted) {
      _result.completeError(const SmartSceneProposalCancelled());
    }
    await _cancelCallback?.call();
    _cancelCallback = null;
    final spawning = _spawnFuture;
    if (spawning != null) {
      try {
        final isolate = _isolate ?? await spawning;
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {
        // Spawn failures are already delivered to the operation result.
      }
    }
    _release();
    return stopped;
  }

  void _complete(List<SceneRegion> regions) {
    if (!_result.isCompleted) _result.complete(List.unmodifiable(regions));
    _releaseInline();
  }

  void _completeError(Object error, StackTrace stackTrace) {
    if (!_result.isCompleted) _result.completeError(error, stackTrace);
    _releaseInline();
  }

  void _releaseInline() {
    if (_spawnFuture == null && !_stopped.isCompleted) _stopped.complete();
  }

  void _release() {
    _receivePort?.close();
    _receivePort = null;
    _isolate = null;
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

final class SmartSceneProposalCancelled implements Exception {
  const SmartSceneProposalCancelled();

  @override
  String toString() => 'Smart scene proposal cancelled.';
}

final class _ProposalRequest {
  const _ProposalRequest(this.replyTo, this.encoded, this.maximumDimension);
  final SendPort replyTo;
  final TransferableTypedData encoded;
  final int maximumDimension;
}

final class _ProposalSuccess {
  const _ProposalSuccess(this.regions);
  final List<SceneRegion> regions;
}

final class _ProposalFailure {
  const _ProposalFailure(this.error, this.stackTrace);
  final String error;
  final String stackTrace;
}

void _proposalWorker(_ProposalRequest request) {
  try {
    final encoded = request.encoded.materialize().asUint8List();
    Isolate.exit(
      request.replyTo,
      _ProposalSuccess(_propose(encoded, request.maximumDimension)),
    );
  } catch (error, stackTrace) {
    Isolate.exit(request.replyTo, _ProposalFailure('$error', '$stackTrace'));
  }
}

List<SceneRegion> _propose(Uint8List encoded, int maximumDimension) {
  final decoded = raster.decodeImage(encoded);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    return const [];
  }
  final scale = math.min(
    1.0,
    maximumDimension / math.max(decoded.width, decoded.height),
  );
  final image = scale < 1
      ? raster.copyResize(
          decoded,
          width: math.max(1, (decoded.width * scale).round()),
          height: math.max(1, (decoded.height * scale).round()),
          interpolation: raster.Interpolation.average,
        )
      : decoded;
  final width = image.width;
  final height = image.height;
  final alpha = Uint8List(width * height);
  var transparent = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final visible = image.getPixel(x, y).a.toInt() >= 24;
      alpha[y * width + x] = visible ? 1 : 0;
      if (!visible) transparent++;
    }
  }
  // Version one is intentionally alpha-first. Fully opaque art remains fully
  // editable through Lasso instead of guessing a destructive background mask.
  if (transparent < width * height * 0.01) return const [];

  // Join short gaps inside letters, labels and card outlines. Avoid a second
  // transitive proximity merge: arrows and aligned captions can otherwise
  // chain an entire infographic into one scene.
  final radius = math.max(1, (math.min(width, height) * 0.0045).round());
  final joined = _dilate(alpha, width, height, radius);
  final components = _components(joined, width, height)
      .where((item) => item.area >= math.max(6, width * height ~/ 25000))
      .toList(growable: false);
  if (components.isEmpty) return const [];

  final seeds = <_Component>[];
  final details = <_Component>[];
  for (final component in components) {
    final rect = component.rect;
    final wideDecoration =
        rect.width > width * 0.65 && rect.height < height * 0.18;
    final substantial =
        rect.width >= width * 0.075 ||
        rect.height >= height * 0.065 ||
        component.area >= width * height * 0.002;
    if (substantial && !wideDecoration) {
      seeds.add(component);
    } else if (!wideDecoration) {
      details.add(component);
    }
  }
  final groups = <List<_Component>>[
    for (final seed in seeds) [seed],
  ];
  final loose = <_Component>[];
  for (final detail in details) {
    List<_Component>? best;
    var bestDistance = double.infinity;
    for (final group in groups) {
      final anchor = group.first.rect;
      final union = _componentBounds([...group, detail]);
      final distance = _distanceToRect(detail.rect.center, anchor);
      final close = anchor
          .inflate(math.max(width, height) * 0.035)
          .contains(detail.rect.center);
      final horizontalAllowance = anchor.width > width * 0.35
          ? width * 0.035
          : width * 0.12;
      final verticalAllowance = anchor.height > height * 0.35
          ? height * 0.035
          : height * 0.12;
      final safeExtent =
          union.width <=
              math.max(anchor.width + horizontalAllowance, width * 0.30) &&
          union.height <=
              math.max(anchor.height + verticalAllowance, height * 0.34);
      if ((!close && distance > math.max(width, height) * 0.055) ||
          !safeExtent ||
          distance >= bestDistance) {
        continue;
      }
      best = group;
      bestDistance = distance;
    }
    if (best == null) {
      loose.add(detail);
    } else {
      best.add(detail);
    }
  }
  final looseBuckets = <(int, int), List<_Component>>{};
  for (final component in loose) {
    final center = component.rect.center;
    final key = (
      (center.dy / (height * 0.18)).floor(),
      (center.dx / (width * 0.25)).floor(),
    );
    looseBuckets.putIfAbsent(key, () => []).add(component);
  }
  groups.addAll(looseBuckets.values);

  groups.sort((a, b) {
    final aa = _componentBounds(a);
    final bb = _componentBounds(b);
    final row = (aa.top * 12).round().compareTo((bb.top * 12).round());
    return row != 0 ? row : aa.left.compareTo(bb.left);
  });
  return List.unmodifiable([
    for (var index = 0; index < groups.length; index++)
      _toRegion(groups[index], index, width, height),
  ]);
}

Uint8List _dilate(Uint8List source, int width, int height, int radius) {
  final horizontal = Uint8List(source.length);
  for (var y = 0; y < height; y++) {
    var count = 0;
    for (var x = -radius; x < width + radius; x++) {
      final entering = x + radius;
      final leaving = x - radius - 1;
      if (entering >= 0 && entering < width) {
        count += source[y * width + entering];
      }
      if (leaving >= 0 && leaving < width) {
        count -= source[y * width + leaving];
      }
      if (x >= 0 && x < width && count > 0) {
        horizontal[y * width + x] = 1;
      }
    }
  }
  final result = Uint8List(source.length);
  for (var x = 0; x < width; x++) {
    var count = 0;
    for (var y = -radius; y < height + radius; y++) {
      final entering = y + radius;
      final leaving = y - radius - 1;
      if (entering >= 0 && entering < height) {
        count += horizontal[entering * width + x];
      }
      if (leaving >= 0 && leaving < height) {
        count -= horizontal[leaving * width + x];
      }
      if (y >= 0 && y < height && count > 0) {
        result[y * width + x] = 1;
      }
    }
  }
  return result;
}

List<_Component> _components(Uint8List mask, int width, int height) {
  final seen = Uint8List(mask.length);
  final queue = Int32List(mask.length);
  final result = <_Component>[];
  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || seen[start] != 0) continue;
    var read = 0;
    var write = 0;
    queue[write++] = start;
    seen[start] = 1;
    var left = start % width;
    var right = left;
    var top = start ~/ width;
    var bottom = top;
    while (read < write) {
      final index = queue[read++];
      final x = index % width;
      final y = index ~/ width;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
          final next = ny * width + nx;
          if (mask[next] == 0 || seen[next] != 0) continue;
          seen[next] = 1;
          queue[write++] = next;
        }
      }
    }
    result.add(_Component(left, top, right + 1, bottom + 1, write));
  }
  return result;
}

Rect _componentBounds(List<_Component> items) => items
    .map((item) => item.rect)
    .reduce((value, item) => value.expandToInclude(item));

double _distanceToRect(Offset point, Rect rect) {
  final dx = math.max(rect.left - point.dx, point.dx - rect.right);
  final dy = math.max(rect.top - point.dy, point.dy - rect.bottom);
  return math.sqrt(
    math.max(0, dx) * math.max(0, dx) + math.max(0, dy) * math.max(0, dy),
  );
}

SceneRegion _toRegion(
  List<_Component> group,
  int index,
  int width,
  int height,
) {
  final fragments = [
    for (final item in group)
      Rect.fromLTRB(
        item.left / width,
        item.top / height,
        item.right / width,
        item.bottom / height,
      ).inflate(0.004).intersect(const Rect.fromLTWH(0, 0, 1, 1)),
  ];
  final bounds = fragments.reduce((a, b) => a.expandToInclude(b));
  return SceneRegion(
    id: 'smart-scene-${index + 1}',
    name: 'Scene ${index + 1}',
    polygon: rectPolygon(bounds),
    fragments: fragments,
    automatic: true,
  );
}

final class _Component {
  const _Component(this.left, this.top, this.right, this.bottom, this.area);
  final int left;
  final int top;
  final int right;
  final int bottom;
  final int area;
  Rect get rect => Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right.toDouble(),
    bottom.toDouble(),
  );
}
