import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/features/export/application/export_status_state.dart';

class ExportStatusCubit extends Cubit<ExportStatusState> {
  ExportStatusCubit({this.autoDismissDelay = const Duration(seconds: 8)})
    : super(const ExportStatusState());

  final Duration autoDismissDelay;
  Timer? _dismissTimer;

  void start(String stage) {
    _dismissTimer?.cancel();
    emit(
      ExportStatusState(
        phase: ExportStatusPhase.rendering,
        stage: stage,
        canCancel: true,
      ),
    );
  }

  void update({
    required double progress,
    required String stage,
    bool? canCancel,
  }) {
    if (state.phase != ExportStatusPhase.rendering) return;
    emit(
      state.copyWith(
        progress: progress.clamp(0, 1),
        stage: stage,
        canCancel: canCancel,
      ),
    );
  }

  void succeed({
    required String path,
    required int fileSizeBytes,
    required double durationSeconds,
  }) {
    emit(
      ExportStatusState(
        phase: ExportStatusPhase.success,
        progress: 1,
        outputPath: path,
        fileSizeBytes: fileSizeBytes,
        durationSeconds: durationSeconds,
      ),
    );
    resumeAutoDismiss();
  }

  void fail(String message) {
    _dismissTimer?.cancel();
    emit(
      ExportStatusState(
        phase: ExportStatusPhase.failure,
        errorMessage: message,
      ),
    );
  }

  void markPathCopied() => emit(state.copyWith(pathCopied: true));

  void pauseAutoDismiss() => _dismissTimer?.cancel();

  void resumeAutoDismiss() {
    _dismissTimer?.cancel();
    if (state.phase != ExportStatusPhase.success) return;
    _dismissTimer = Timer(autoDismissDelay, dismiss);
  }

  void dismiss() {
    _dismissTimer?.cancel();
    emit(const ExportStatusState());
  }

  @override
  Future<void> close() {
    _dismissTimer?.cancel();
    return super.close();
  }
}
