class VideoExportCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;

  void throwIfCancelled() {
    if (_isCancelled) throw const VideoExportCancelledException();
  }
}

class VideoExportCancelledException implements Exception {
  const VideoExportCancelledException();

  @override
  String toString() => 'Video export was cancelled.';
}
