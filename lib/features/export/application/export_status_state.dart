import 'package:flutter/foundation.dart';

enum ExportStatusPhase { idle, rendering, success, failure }

@immutable
class ExportStatusState {
  const ExportStatusState({
    this.phase = ExportStatusPhase.idle,
    this.progress = 0,
    this.stage = '',
    this.outputPath,
    this.fileSizeBytes,
    this.durationSeconds,
    this.errorMessage,
    this.canCancel = false,
    this.pathCopied = false,
  });

  final ExportStatusPhase phase;
  final double progress;
  final String stage;
  final String? outputPath;
  final int? fileSizeBytes;
  final double? durationSeconds;
  final String? errorMessage;
  final bool canCancel;
  final bool pathCopied;

  bool get isVisible => phase != ExportStatusPhase.idle;

  ExportStatusState copyWith({
    ExportStatusPhase? phase,
    double? progress,
    String? stage,
    String? outputPath,
    int? fileSizeBytes,
    double? durationSeconds,
    String? errorMessage,
    bool? canCancel,
    bool? pathCopied,
  }) => ExportStatusState(
    phase: phase ?? this.phase,
    progress: progress ?? this.progress,
    stage: stage ?? this.stage,
    outputPath: outputPath ?? this.outputPath,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    errorMessage: errorMessage ?? this.errorMessage,
    canCancel: canCancel ?? this.canCancel,
    pathCopied: pathCopied ?? this.pathCopied,
  );
}
