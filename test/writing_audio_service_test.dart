import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_audio_service.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_sound_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('handdraw_studio/exporter');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('preview host receives Voice Guide and shared clock position', () async {
    MethodCall? playCall;
    MethodCall? volumeCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'playPreviewAudio') playCall = call;
          if (call.method == 'setPreviewAudioVolume') volumeCall = call;
          if (call.method == 'getPreviewPosition') return 4.25;
          return null;
        });
    final service = WritingAudioService();
    addTearDown(service.stop);
    final guide = VoiceGuide(
      path: '/tmp/voice.mp3',
      name: 'voice.mp3',
      durationSeconds: 12,
      waveform: const [0.1, 0.9],
      securityBookmark: 'bookmark',
    );

    await service.play(
      HandDrawProject(writingSoundEnabled: false),
      voiceGuide: guide,
      positionSeconds: 3.5,
      previewDurationSeconds: 12,
      volume: .8,
    );
    await service.setVolume(.35);

    expect(playCall?.method, 'playPreviewAudio');
    final arguments = Map<Object?, Object?>.from(playCall?.arguments as Map);
    expect(arguments['voicePath'], guide.path);
    expect(arguments['voiceBookmark'], guide.securityBookmark);
    expect(arguments['positionSeconds'], 3.5);
    expect(arguments['durationSeconds'], 12);
    expect(arguments['volume'], .8);
    expect(arguments.containsKey('writingPath'), isFalse);
    expect(await service.position(), 4.25);
    expect(volumeCall?.method, 'setPreviewAudioVolume');
    expect(
      Map<Object?, Object?>.from(volumeCall?.arguments as Map)['volume'],
      .35,
    );
  });

  test('preview audio fallback uses the calculated drawing timeline', () async {
    MethodCall? playCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'playPreviewAudio') playCall = call;
          return null;
        });
    final service = WritingAudioService();
    addTearDown(service.stop);
    final project = HandDrawProject(
      drawingSpeed: 0.5,
      strokes: [
        DrawingStroke(
          id: 'line',
          name: 'Line',
          points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
        ),
      ],
    );

    await service.play(project);

    final arguments = Map<Object?, Object?>.from(playCall?.arguments as Map);
    expect(arguments['durationSeconds'], closeTo(10.7, 0.0001));
  });

  test('sound picker renders and plays the selected export texture', () async {
    Uint8List? waveBytes;
    var stopped = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'playWritingAudio') {
            final arguments = Map<Object?, Object?>.from(call.arguments as Map);
            waveBytes = await File(arguments['path'] as String).readAsBytes();
          }
          if (call.method == 'stopWritingAudio') stopped = true;
          return null;
        });
    final service = WritingSoundPreviewService();
    addTearDown(service.stop);

    await service.play(preset: WritingSoundPreset.technicalPen, volume: 0.65);

    expect(String.fromCharCodes(waveBytes!.sublist(0, 4)), 'RIFF');
    expect(waveBytes!.length, greaterThan(44));
    await service.stop();
    expect(stopped, isTrue);
  });
}
