import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'camera runtime remains pure and renderer remains camera-free in 6B',
    () {
      final domain = Directory('lib/features/camera/domain')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final forbidden in [
        'package:flutter/',
        'dart:ui',
        'Matrix4',
        'FrameRenderer',
        'AutoDirector',
      ]) {
        expect(domain, isNot(contains(forbidden)));
      }
      final renderer = File(
        'lib/features/export/infrastructure/frame_renderer.dart',
      ).readAsStringSync();
      expect(renderer, isNot(contains('CameraResolver')));
      for (final forbidden in [
        'CameraShot',
        'CameraKeyframe',
        'CameraEasing',
        'CameraTimelineCompiler',
      ]) {
        expect(renderer, isNot(contains(forbidden)));
      }
      final resolver = File(
        'lib/features/camera/domain/services/camera_resolver.dart',
      ).readAsStringSync();
      expect(resolver, isNot(contains('CameraTimelineCompiler')));
    },
  );
}
