import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/export/domain/video_export_cancellation.dart';
import 'package:handdraw_studio/features/export/infrastructure/video_export_service.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'support/legacy_editor_state_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('handdraw_studio/exporter');
  late EditorCubit cubit;
  late ui.Image source;
  late List<MethodCall> calls;
  var rejectAppend = false;
  var rejectInspection = false;
  Future<void> Function(int)? appendHandler;
  setUp(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 64, 36),
      ui.Paint()..color = const ui.Color(0x80ff0000),
    );
    final picture = recorder.endRecording();
    source = await picture.toImage(64, 36);
    picture.dispose();
    cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          canvasWidth: 64,
          canvasHeight: 36,
          durationSeconds: .1,
          drawingDurationSeconds: .1,
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          strokes: [
            DrawingStroke(
              id: 'fixture',
              name: 'fixture',
              points: const [ui.Offset(.1, .5), ui.Offset(.9, .5)],
            ),
          ],
        ),
      ),
    );
    calls = [];
    rejectAppend = false;
    rejectInspection = false;
    appendHandler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'getExporterVersion':
              return 9;
            case 'startProRes4444Stream':
              return 'session';
            case 'appendProRes4444Frame':
              if (rejectAppend) throw PlatformException(code: 'encoder_failed');
              await appendHandler?.call(
                (call.arguments as Map)['frameIndex'] as int,
              );
              return null;
            case 'finishProRes4444Stream':
              return '/tmp/handdraw-benchmark.mov';
            case 'inspectExport':
              return {
                'codec': rejectInspection ? 'wrong' : 'ap4h',
                'width': 64,
                'height': 36,
                'frameRate': 30,
                'durationSeconds': .1,
                'hasAlpha': true,
                'orientationDegrees': 0,
              };
            default:
              return null;
          }
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    source.dispose();
    await cubit.close();
  });

  Future<String?> export({
    VideoExportCancellationToken? token,
    String path = '/tmp/handdraw-benchmark',
    void Function(ExportTimingMetrics)? onTimingMetrics,
    ExportProgressCallback? onProgress,
    ui.Image? drawing,
  }) => const VideoExportService().exportProRes4444(
    project: cubit.project,
    timeline: cubit.compileTimeline(),
    frameRate: FrameRate.fps30,
    transparent: true,
    drawing: drawing ?? source,
    hand: null,
    onProgress: onProgress ?? (_) {},
    destinationPath: path,
    cancellationToken: token,
    onTimingMetrics: onTimingMetrics,
  );

  test(
    'explicit destination uses full validated streaming export without picker',
    () async {
      expect(await export(), '/tmp/handdraw-benchmark.mov');
      final start =
          calls
                  .singleWhere((c) => c.method == 'startProRes4444Stream')
                  .arguments
              as Map;
      expect(start['outputPath'], '/tmp/handdraw-benchmark.mov');
      expect(start['width'], 64);
      expect(start['height'], 36);
      expect(start['frameCount'], 3);
      final frames = calls
          .where((c) => c.method == 'appendProRes4444Frame')
          .toList();
      expect(frames.map((c) => (c.arguments as Map)['frameIndex']), [0, 1, 2]);
      for (final frame in frames) {
        expect(
          ((frame.arguments as Map)['rgba'] as Uint8List).length,
          64 * 36 * 4,
        );
      }
      expect(calls.last.method, 'endExportAccess');
      expect(calls.any((c) => c.method == 'inspectExport'), isTrue);
    },
  );
  test(
    'timing observer preserves frame bytes and reports only validated export',
    () async {
      await export();
      final originalFrames = calls
          .where((c) => c.method == 'appendProRes4444Frame')
          .map(
            (c) =>
                Uint8List.fromList((c.arguments as Map)['rgba'] as Uint8List),
          )
          .toList();
      final originalMethods = calls.map((c) => c.method).toList();
      calls.clear();
      final reports = <ExportTimingMetrics>[];
      await export(
        onTimingMetrics: (metrics) {
          expect(calls.last.method, 'inspectExport');
          reports.add(metrics);
        },
      );
      expect(reports, hasLength(1));
      expect(reports.single.frameCount, 3);
      expect(reports.single.renderMicroseconds, greaterThanOrEqualTo(0));
      expect(reports.single.readbackMicroseconds, greaterThanOrEqualTo(0));
      expect(reports.single.nativeAppendMicroseconds, greaterThanOrEqualTo(0));
      expect(calls.map((c) => c.method), originalMethods);
      final measuredFrames = calls
          .where((c) => c.method == 'appendProRes4444Frame')
          .toList();
      for (var i = 0; i < originalFrames.length; i++) {
        expect(
          (measuredFrames[i].arguments as Map)['rgba'],
          orderedEquals(originalFrames[i]),
        );
      }
    },
  );

  test(
    'failed validation does not publish successful timing metrics',
    () async {
      rejectInspection = true;
      final reports = <ExportTimingMetrics>[];
      await expectLater(export(onTimingMetrics: reports.add), throwsStateError);
      expect(reports, isEmpty);
    },
  );

  test(
    'stream backpressure keeps one append pending and drains final frame',
    () async {
      final entered = List.generate(3, (_) => Completer<void>());
      final release = List.generate(3, (_) => Completer<void>());
      var active = 0;
      var peak = 0;
      appendHandler = (index) async {
        active++;
        if (active > peak) peak = active;
        entered[index].complete();
        await release[index].future;
        active--;
      };
      final completed = <int>[];
      final result = export(
        onProgress: (update) {
          if (update.currentFrame case final int frame) completed.add(frame);
        },
      );
      await entered[0].future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(completed, isEmpty);
      expect(
        calls.where((c) => c.method == 'appendProRes4444Frame'),
        hasLength(1),
      );
      for (var i = 0; i < 3; i++) {
        await entered[i].future;
        expect(calls.any((c) => c.method == 'finishProRes4444Stream'), isFalse);
        release[i].complete();
      }
      expect(await result, isNotNull);
      expect(completed, [1, 2, 3]);
      expect(peak, 1);
      expect(active, 0);
    },
  );

  test(
    'cancellation drains pending append before cancelling native stream',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      appendHandler = (_) async {
        entered.complete();
        await release.future;
      };
      final token = VideoExportCancellationToken();
      final result = export(token: token);
      final check = expectLater(
        result,
        throwsA(isA<VideoExportCancelledException>()),
      );
      await entered.future;
      token.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls.any((c) => c.method == 'cancelProRes4444Stream'), isFalse);
      release.complete();
      await check;
      expect(
        calls.where((c) => c.method == 'appendProRes4444Frame'),
        hasLength(1),
      );
      expect(calls.any((c) => c.method == 'cancelProRes4444Stream'), isTrue);
      expect(calls.any((c) => c.method == 'finishProRes4444Stream'), isFalse);
    },
  );

  test(
    'render failure drains the outstanding append before stream cleanup',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final disposedSource = source.clone();
      appendHandler = (_) async {
        disposedSource.dispose();
        entered.complete();
        await release.future;
      };
      final result = export(drawing: disposedSource);
      final check = expectLater(result, throwsA(anything));
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls.any((c) => c.method == 'cancelProRes4444Stream'), isFalse);
      release.complete();
      await check;
      expect(
        calls.where((c) => c.method == 'appendProRes4444Frame'),
        hasLength(1),
      );
      expect(calls.any((c) => c.method == 'cancelProRes4444Stream'), isTrue);
      expect(calls.any((c) => c.method == 'finishProRes4444Stream'), isFalse);
      expect(calls.last.method, 'endExportAccess');
    },
  );

  test(
    'delayed append error is handled while the next frame is prepared',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      appendHandler = (_) async {
        entered.complete();
        await release.future;
        throw PlatformException(code: 'delayed_encoder_failure');
      };
      final result = export();
      final check = expectLater(result, throwsA(isA<PlatformException>()));
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      release.complete();
      await check;
      expect(
        calls.where((c) => c.method == 'appendProRes4444Frame'),
        hasLength(1),
      );
      expect(calls.any((c) => c.method == 'finishProRes4444Stream'), isFalse);
      expect(calls.last.method, 'endExportAccess');
    },
  );

  test('encoder failure cancels stream and releases access', () async {
    rejectAppend = true;
    await expectLater(export(), throwsA(isA<PlatformException>()));
    expect(calls.any((c) => c.method == 'cancelProRes4444Stream'), isTrue);
    expect(calls.any((c) => c.method == 'finishProRes4444Stream'), isFalse);
    expect(calls.last.method, 'endExportAccess');
  });
  test('cancelled export does not start encoder', () async {
    final token = VideoExportCancellationToken()..cancel();
    await expectLater(
      export(token: token),
      throwsA(isA<VideoExportCancelledException>()),
    );
    expect(calls.any((c) => c.method == 'startProRes4444Stream'), isFalse);
    expect(calls.last.method, 'endExportAccess');
  });
  test('blank destination is rejected before native calls', () async {
    await expectLater(export(path: ' '), throwsArgumentError);
    expect(calls, isEmpty);
  });
}
