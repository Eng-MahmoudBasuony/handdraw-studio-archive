import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';

/// Owns only analysis work. The editor owns pixels, history and accepted paths.
class ImageAnimationAnalyzer {
  Isolate? _worker;
  ReceivePort? _port;
  Completer<RegionDrawingPlan?>? _result;
  Future<RegionDrawingPlan?> analyze(
    Uint8List bytes, {
    bool textOnly = false,
    int? backgroundColor,
  }) async {
    cancel();
    final result = Completer<RegionDrawingPlan?>();
    final port = ReceivePort();
    _result = result;
    _port = port;
    port.listen((message) {
      if (result.isCompleted) return;
      if (message is RegionDrawingPlan) {
        result.complete(message);
      } else {
        result.completeError(StateError('$message'));
      }
    });
    try {
      final worker = await Isolate.spawn(runRegionPlanner, (
        port.sendPort,
        bytes,
        textOnly,
        backgroundColor,
      ));
      if (!identical(_result, result)) {
        worker.kill(priority: Isolate.immediate);
        return null;
      }
      _worker = worker;
      return await result.future;
    } finally {
      if (identical(_result, result)) cancel();
    }
  }

  void cancel() {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _port?.close();
    _port = null;
    if (_result != null && !_result!.isCompleted) _result!.complete(null);
    _result = null;
  }
}
