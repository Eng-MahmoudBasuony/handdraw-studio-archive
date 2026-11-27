import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/export/infrastructure/video_export_service.dart';
import 'package:handdraw_studio/features/export/domain/video_export_contract.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  test('Voice Guide never enters the ProRes export payload', () {
    final project = HandDrawProject(
      writingSoundEnabled: true,
      voiceGuide: VoiceGuide(
        path: '/private/lesson-voice.m4a',
        name: 'lesson-voice.m4a',
        durationSeconds: 20,
        waveform: const [0.2, 0.8],
        securityBookmark: 'voice-bookmark',
      ),
    );

    final arguments = buildProResEncodeArguments(
      project: project,
      framesDirectory: '/tmp/frames',
      outputPath: '/tmp/output.mov',
      frameCount: 180,
      writingAudioPath: '/tmp/writing-sound.wav',
    );

    expect(arguments['audioPath'], '/tmp/writing-sound.wav');
    expect(arguments.containsKey('voicePath'), isFalse);
    expect(arguments.containsKey('voiceBookmark'), isFalse);
    expect(arguments.values, isNot(contains(project.voiceGuide!.path)));
    expect(arguments['alphaMode'], ExportAlphaMode.premultiplied.name);
    expect(arguments['colorSpace'], 'rec709');
  });

  test('streaming ProRes payload preserves full resolution and alpha', () {
    final project = HandDrawProject(
      canvasWidth: 1920,
      canvasHeight: 1080,
      frameRate: 30,
      exportAlphaMode: ExportAlphaMode.straight,
    );

    final arguments = buildProResStreamStartArguments(
      project: project,
      outputPath: '/tmp/output.mov',
      frameCount: 180,
      expectsAudio: true,
    );

    expect(arguments, containsPair('width', 1920));
    expect(arguments, containsPair('height', 1080));
    expect(arguments, containsPair('frameRate', 30));
    expect(arguments, containsPair('frameCount', 180));
    expect(arguments, containsPair('expectsAudio', true));
    expect(arguments, containsPair('alphaMode', 'straight'));
    expect(arguments.containsKey('framesDirectory'), isFalse);
  });

  test('Final Cut contract accepts compliant ProRes 4444 media', () {
    const contract = VideoExportContract(
      width: 3840,
      height: 2160,
      frameRate: 30,
      durationSeconds: 6,
    );
    const inspection = VideoExportInspection(
      codec: 'ap4h',
      width: 3840,
      height: 2160,
      frameRate: 30,
      durationSeconds: 6,
      hasAlpha: true,
      orientationDegrees: 0,
      hasAudio: false,
    );

    expect(contract.validate(inspection), isEmpty);
  });

  test('Final Cut contract rejects wrong codec, alpha, and orientation', () {
    const contract = VideoExportContract(
      width: 1920,
      height: 1080,
      frameRate: 25,
      durationSeconds: 4,
    );
    const inspection = VideoExportInspection(
      codec: 'h264',
      width: 1080,
      height: 1920,
      frameRate: 30,
      durationSeconds: 3.5,
      hasAlpha: false,
      orientationDegrees: 90,
      hasAudio: false,
    );

    expect(contract.validate(inspection), hasLength(6));
  });

  test('Final Cut contract verifies audio presence and one-frame sync', () {
    const contract = VideoExportContract(
      width: 1920,
      height: 1080,
      frameRate: 30,
      durationSeconds: 5,
      expectsAudio: true,
    );
    const inspection = VideoExportInspection(
      codec: 'ap4h',
      width: 1920,
      height: 1080,
      frameRate: 30,
      durationSeconds: 5,
      hasAlpha: true,
      orientationDegrees: 0,
      hasAudio: true,
      audioDurationSeconds: 5.02,
    );

    expect(contract.validate(inspection), isEmpty);
    expect(
      contract.validate(
        const VideoExportInspection(
          codec: 'ap4h',
          width: 1920,
          height: 1080,
          frameRate: 30,
          durationSeconds: 5,
          hasAlpha: true,
          orientationDegrees: 0,
          hasAudio: true,
          audioDurationSeconds: 4.8,
        ),
      ),
      hasLength(1),
    );
  });
}
