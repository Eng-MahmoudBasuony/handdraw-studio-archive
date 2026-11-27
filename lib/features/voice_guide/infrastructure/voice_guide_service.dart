import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'package:handdraw_studio/core/storage/recent_directory_store.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';

class VoiceGuidePickerCopy {
  const VoiceGuidePickerCopy({
    required this.recordings,
    required this.importVoice,
  });

  static const english = VoiceGuidePickerCopy(
    recordings: 'Voice recordings',
    importVoice: 'Import Voice',
  );

  final String recordings;
  final String importVoice;
}

class VoiceGuideService {
  const VoiceGuideService();

  static const _channel = MethodChannel('handdraw_studio/exporter');

  Future<VoiceGuide?> importVoiceGuide({
    VoiceGuidePickerCopy copy = VoiceGuidePickerCopy.english,
  }) async {
    final initialDirectory = await RecentDirectoryStore.instance.directoryFor(
      RecentDirectoryKey.voiceGuide,
    );
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: copy.recordings,
          extensions: const ['wav', 'm4a', 'mp3'],
        ),
      ],
      initialDirectory: initialDirectory,
      confirmButtonText: copy.importVoice,
    );
    if (file == null) return null;
    await RecentDirectoryStore.instance.rememberFile(
      RecentDirectoryKey.voiceGuide,
      file.path,
    );
    return inspect(path: file.path);
  }

  Future<VoiceGuide?> locateVoiceGuide({
    VoiceGuidePickerCopy copy = VoiceGuidePickerCopy.english,
  }) => importVoiceGuide(copy: copy);

  Future<VoiceGuide> inspect({
    required String path,
    String? securityBookmark,
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'inspectVoiceGuide',
      {'path': path, 'securityBookmark': securityBookmark},
    );
    if (raw == null) {
      throw StateError('The selected voice file could not be inspected.');
    }
    return VoiceGuide(
      path: raw['path'] as String? ?? path,
      name: raw['name'] as String? ?? fileName(path),
      durationSeconds: (raw['durationSeconds'] as num? ?? 0).toDouble(),
      waveform: (raw['waveform'] as List<dynamic>? ?? const [])
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      securityBookmark: raw['securityBookmark'] as String?,
    );
  }

  Future<bool> canAccess(VoiceGuide guide) async {
    try {
      await inspect(path: guide.path, securityBookmark: guide.securityBookmark);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String fileName(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .last;
}
