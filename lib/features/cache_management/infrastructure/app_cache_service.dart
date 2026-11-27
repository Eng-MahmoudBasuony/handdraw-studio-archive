import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';

class CacheCleanupResult {
  const CacheCleanupResult(this.removedSessions, this.failedRoots);
  final int removedSessions;
  final int failedRoots;
}

/// Only owned, old staging sessions with an obtainable ownership lock qualify.
/// No user assets, projects, hand libraries or unrecognized temp folders.
class AppCacheService {
  AppCacheService({Directory? temporaryRoot, this.now})
    : root = temporaryRoot ?? Directory.systemTemp;
  final Directory root;
  final DateTime Function()? now;

  Future<CacheCleanupResult> clear() async {
    PaintingBinding.instance.imageCache.clear();
    clearMotionRenderingCaches();
    clearIdleRevealRenderingCaches();
    var removed = 0;
    var failures = 0;
    if (!await root.exists()) return const CacheCleanupResult(0, 0);
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (!RegExp(r'^handdraw-studio-runtime-staging-[0-9]+$').hasMatch(name)) {
        continue;
      }
      try {
        removed += await FileEditorAssetStagingStore(
          entry,
          now: now,
        ).cleanupStaleSessions();
      } on FileSystemException {
        failures++;
      }
    }
    return CacheCleanupResult(removed, failures);
  }
}
