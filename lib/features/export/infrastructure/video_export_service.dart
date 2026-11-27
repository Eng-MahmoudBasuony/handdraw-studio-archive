import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_render_project_transform.dart';
import 'package:handdraw_studio/features/writing_sound/application/writing_sound_synthesizer.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_sound_library.dart';
import 'package:handdraw_studio/core/storage/recent_directory_store.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';
import 'package:handdraw_studio/features/export/domain/video_export_cancellation.dart';
import 'package:handdraw_studio/features/export/domain/video_export_contract.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/services/frame_sampling_policy.dart';
import 'package:handdraw_studio/features/timeline/domain/services/unified_project_frame_resolver.dart';

enum VideoExportStage {
  renderingFrame,
  generatingWritingSound,
  encodingProRes,
  complete,
}

class VideoExportProgress {
  const VideoExportProgress({
    required this.progress,
    required this.stage,
    this.currentFrame,
    this.totalFrames,
  });

  final double progress;
  final VideoExportStage stage;
  final int? currentFrame;
  final int? totalFrames;
}

typedef ExportProgressCallback = void Function(VideoExportProgress update);

/// Aggregate wall-clock stage costs for a successfully validated export.
/// Native append includes channel transfer and encoder backpressure. Readback
/// includes PNG encoding when using the legacy file-based encoder. Streaming
/// stages overlap, so their totals must not be summed as export wall time.
final class ExportTimingMetrics {
  const ExportTimingMetrics({
    required this.frameCount,
    required this.renderMicroseconds,
    required this.readbackMicroseconds,
    required this.nativeAppendMicroseconds,
  });

  final int frameCount;
  final int renderMicroseconds;
  final int readbackMicroseconds;
  final int nativeAppendMicroseconds;
}

class VideoExportPickerCopy {
  const VideoExportPickerCopy({
    required this.quickTimeMovie,
    required this.exportMovie,
  });

  static const english = VideoExportPickerCopy(
    quickTimeMovie: 'QuickTime Movie',
    exportMovie: 'Export Movie',
  );

  final String quickTimeMovie;
  final String exportMovie;
}

class VideoExportService {
  const VideoExportService();

  static const _channel = MethodChannel('handdraw_studio/exporter');
  static const _renderer = FrameRenderer();
  static const _soundSynthesizer = WritingSoundSynthesizer();

  Future<String?> exportProRes4444({
    required HandDrawProject project,
    required CompiledTimeline timeline,
    required FrameRate frameRate,
    required bool transparent,
    required ui.Image drawing,
    ui.Image? drawingRevealBase,
    SvgRevealLayers? svgRevealLayers,
    required ui.Image? hand,
    required ExportProgressCallback onProgress,
    VideoExportPickerCopy copy = VideoExportPickerCopy.english,
    VideoExportCancellationToken? cancellationToken,
    // Automated exports use the same encoder/validation without a save panel.
    // Explicit destinations do not change the user's recent-folder preference.
    String? destinationPath,
    void Function(ExportTimingMetrics metrics)? onTimingMetrics,
  }) async {
    if (destinationPath != null && destinationPath.trim().isEmpty) {
      throw ArgumentError.value(
        destinationPath,
        'destinationPath',
        'Must not be empty',
      );
    }
    if (project.strokes.isEmpty) {
      throw StateError('A drawing and at least one stroke are required.');
    }
    final exporterVersion = await _verifyNativeExporter();

    var outputPath = destinationPath;
    if (outputPath == null) {
      final initialDirectory = await RecentDirectoryStore.instance.directoryFor(
        RecentDirectoryKey.movieExport,
      );
      final location = await getSaveLocation(
        suggestedName: 'handdraw-animation.mov',
        acceptedTypeGroups: [
          XTypeGroup(label: copy.quickTimeMovie, extensions: const ['mov']),
        ],
        initialDirectory: initialDirectory,
        confirmButtonText: copy.exportMovie,
      );
      if (location == null) return null;
      outputPath = location.path;
    }
    if (!outputPath.toLowerCase().endsWith('.mov')) {
      outputPath = '$outputPath.mov';
    }
    if (destinationPath == null) {
      await RecentDirectoryStore.instance.rememberFile(
        RecentDirectoryKey.movieExport,
        outputPath,
      );
    }

    final tempDirectory = await Directory.systemTemp.createTemp(
      'handdraw-frames-',
    );
    await _channel.invokeMethod<void>('beginExportAccess', {
      'outputPath': outputPath,
    });
    String? streamingSessionId;
    _PendingFrameAppend? pendingAppend;
    try {
      final exportProject = _resolveExportProject(project);
      cancellationToken?.throwIfCancelled();
      const sampling = FrameSamplingPolicy();
      const resolver = UnifiedProjectFrameResolver();
      final frameCount = sampling.frameCount(
        duration: timeline.duration,
        frameRate: frameRate,
      );
      final renderWatch = onTimingMetrics == null ? null : Stopwatch();
      final readbackWatch = onTimingMetrics == null ? null : Stopwatch();
      final appendWatch = onTimingMetrics == null ? null : Stopwatch();
      final usesStreamingEncoder = exporterVersion >= 9;
      if (usesStreamingEncoder) {
        streamingSessionId = await _channel.invokeMethod<String>(
          'startProRes4444Stream',
          buildProResStreamStartArguments(
            project: exportProject,
            outputPath: outputPath,
            frameCount: frameCount,
            expectsAudio: project.writingSoundEnabled,
          ),
        );
        if (streamingSessionId == null) {
          throw StateError('The native video encoder did not start.');
        }
      }
      void reportFrame(int frameIndex) {
        onProgress(
          VideoExportProgress(
            progress: (frameIndex + 1) / frameCount * 0.82,
            stage: VideoExportStage.renderingFrame,
            currentFrame: frameIndex + 1,
            totalFrames: frameCount,
          ),
        );
      }

      Future<void> drainAppend() async {
        final pending = pendingAppend;
        if (pending == null) return;
        await pending.settled;
        pendingAppend = null;
        pending.throwIfFailed();
        reportFrame(pending.frameIndex);
      }

      for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        cancellationToken?.throwIfCancelled();
        final resolved = resolver.resolveForExportFrame(
          timeline: timeline,
          frameIndex: frameIndex,
          frameRate: frameRate,
        );
        renderWatch?.start();
        final frame = await _renderer.renderResolved(
          frame: resolved,
          project: exportProject,
          drawing: drawing,
          drawingRevealBase: drawingRevealBase,
          svgRevealLayers: svgRevealLayers,
          hand: hand,
          target: transparent
              ? const RenderTarget.transparent()
              : const RenderTarget.opaque(ui.Color(0xFFFFFFFF)),
        );
        renderWatch?.stop();
        readbackWatch?.start();
        ByteData? data;
        try {
          data = await frame.toByteData(
            format: usesStreamingEncoder
                ? ui.ImageByteFormat.rawRgba
                : ui.ImageByteFormat.png,
          );
        } finally {
          readbackWatch?.stop();
          frame.dispose();
        }
        if (data == null) {
          throw StateError('Could not render frame $frameIndex.');
        }
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (usesStreamingEncoder) {
          // Render/read back only one frame ahead of the encoder. Never queue
          // another native append until the previous one has acknowledged.
          await drainAppend();
          cancellationToken?.throwIfCancelled();
          appendWatch?.start();
          pendingAppend = _PendingFrameAppend(
            frameIndex: frameIndex,
            request: _channel.invokeMethod<void>('appendProRes4444Frame', {
              'sessionId': streamingSessionId,
              'frameIndex': frameIndex,
              'rgba': bytes,
            }),
            watch: appendWatch,
          );
        } else {
          final fileName = 'frame_${frameIndex.toString().padLeft(6, '0')}.png';
          await File(
            '${tempDirectory.path}/$fileName',
          ).writeAsBytes(bytes, flush: false);
        }
        if (!usesStreamingEncoder) reportFrame(frameIndex);
      }
      await drainAppend();

      String? audioPath;
      if (project.writingSoundEnabled) {
        cancellationToken?.throwIfCancelled();
        onProgress(
          const VideoExportProgress(
            progress: 0.83,
            stage: VideoExportStage.generatingWritingSound,
          ),
        );
        final audioFile = File('${tempDirectory.path}/writing-sound.wav');
        final recordedClip = await WritingSoundLibrary.load(
          project.writingSoundPreset,
        );
        await audioFile.writeAsBytes(
          _soundSynthesizer.synthesize(
            project,
            recordedClip: recordedClip,
            timeline: timeline,
          ),
          flush: true,
        );
        audioPath = audioFile.path;
      }

      onProgress(
        const VideoExportProgress(
          progress: 0.84,
          stage: VideoExportStage.encodingProRes,
        ),
      );
      cancellationToken?.throwIfCancelled();
      final result = usesStreamingEncoder
          ? await _channel.invokeMethod<String>('finishProRes4444Stream', {
              'sessionId': streamingSessionId,
              'audioPath': audioPath,
            })
          : await _channel.invokeMethod<String>(
              'encodeProRes4444',
              buildProResEncodeArguments(
                project: exportProject,
                framesDirectory: tempDirectory.path,
                outputPath: outputPath,
                frameCount: frameCount,
                writingAudioPath: audioPath,
              ),
            );
      streamingSessionId = null;
      onProgress(
        const VideoExportProgress(
          progress: 1,
          stage: VideoExportStage.complete,
        ),
      );
      final resolvedPath = result ?? outputPath;
      final inspection = await _channel.invokeMapMethod<Object?, Object?>(
        'inspectExport',
        {'path': resolvedPath},
      );
      if (inspection == null) {
        throw StateError('The completed movie could not be inspected.');
      }
      final errors = VideoExportContract(
        width: exportProject.canvasWidth,
        height: exportProject.canvasHeight,
        frameRate: exportProject.frameRate,
        durationSeconds:
            timeline.duration.microseconds / Duration.microsecondsPerSecond,
        expectsAudio: project.writingSoundEnabled,
      ).validate(VideoExportInspection.fromMap(inspection));
      if (errors.isNotEmpty) {
        throw StateError('Export contract failed: ${errors.join(' ')}');
      }
      onTimingMetrics?.call(
        ExportTimingMetrics(
          frameCount: frameCount,
          renderMicroseconds: renderWatch!.elapsedMicroseconds,
          readbackMicroseconds: readbackWatch!.elapsedMicroseconds,
          nativeAppendMicroseconds: appendWatch!.elapsedMicroseconds,
        ),
      );
      return resolvedPath;
    } finally {
      // A render/readback/progress/cancellation failure can occur while the
      // previous append is active. Settle it before disposing its native stream.
      await pendingAppend?.settled;
      if (streamingSessionId != null) {
        try {
          await _channel.invokeMethod<void>('cancelProRes4444Stream', {
            'sessionId': streamingSessionId,
          });
        } on PlatformException {
          // Preserve the original export/cancellation error. The native
          // session also removes its partial movie when the app exits.
        }
      }
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
      await _channel.invokeMethod<void>('endExportAccess');
    }
  }

  Future<int> _verifyNativeExporter() async {
    try {
      final version = await _channel.invokeMethod<int>('getExporterVersion');
      if ((version ?? 0) < 8) {
        throw StateError(
          'The video exporter is out of date. Save the project, close the app completely, then open the newest build.',
        );
      }
      return version!;
    } on MissingPluginException {
      throw StateError(
        'The old video exporter is still running. Save the project, close the app completely, then open the newest build before exporting.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'channel-error' || error.code == 'unimplemented') {
        throw StateError(
          'The old video exporter is still running. Save the project, close the app completely, then open the newest build before exporting.',
        );
      }
      rethrow;
    }
  }
}

/// Installs the error handler immediately, before the next frame yields during
/// rendering. The settled future never fails; the owner rethrows at the drain.
final class _PendingFrameAppend {
  _PendingFrameAppend({
    required this.frameIndex,
    required Future<void> request,
    Stopwatch? watch,
  }) {
    settled = request.then<void>(
      (_) {
        watch?.stop();
      },
      onError: (Object error, StackTrace stack) {
        watch?.stop();
        _error = error;
        _stack = stack;
      },
    );
  }

  final int frameIndex;
  late final Future<void> settled;
  Object? _error;
  StackTrace? _stack;

  void throwIfFailed() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stack!);
  }
}

Map<String, Object?> buildProResStreamStartArguments({
  required HandDrawProject project,
  required String outputPath,
  required int frameCount,
  required bool expectsAudio,
}) => {
  'outputPath': outputPath,
  'width': project.canvasWidth,
  'height': project.canvasHeight,
  'frameRate': project.frameRate,
  'frameCount': frameCount,
  'expectsAudio': expectsAudio,
  'alphaMode': project.exportAlphaMode.name,
  'colorSpace': 'rec709',
};

HandDrawProject _resolveExportProject(HandDrawProject project) {
  return const LegacyRenderProjectTransform().forExport(project);
}

/// Builds the native encoder payload. Voice Guide media is intentionally not
/// accepted here: it is a preview-only synchronization reference. Keeping the
/// boundary explicit prevents a future project-model field from leaking into
/// the exported movie.
Map<String, Object?> buildProResEncodeArguments({
  required HandDrawProject project,
  required String framesDirectory,
  required String outputPath,
  required int frameCount,
  required String? writingAudioPath,
}) => {
  'framesDirectory': framesDirectory,
  'outputPath': outputPath,
  'width': project.canvasWidth,
  'height': project.canvasHeight,
  'frameRate': project.frameRate,
  'frameCount': frameCount,
  'audioPath': writingAudioPath,
  'alphaMode': project.exportAlphaMode.name,
  'colorSpace': 'rec709',
};
