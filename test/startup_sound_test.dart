import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:handdraw_studio/app/startup_sound/application/startup_sound_cubit.dart';
import 'package:handdraw_studio/app/startup_sound/domain/startup_sound_repository.dart';
import 'package:handdraw_studio/app/startup_sound/infrastructure/shared_preferences_startup_sound_repository.dart';
import 'package:handdraw_studio/app/startup_sound/infrastructure/startup_sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup sound preference safely defaults on', () async {
    SharedPreferences.setMockInitialValues({});
    const repository = SharedPreferencesStartupSoundRepository();

    expect(await repository.loadEnabled(), isTrue);
  });

  test('startup sound cubit emits immutable preference state', () async {
    final repository = _MemoryStartupSoundRepository();
    final cubit = StartupSoundCubit(repository);
    addTearDown(cubit.close);

    cubit.setEnabled(false);

    expect(cubit.state.enabled, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(repository.enabled, isFalse);
  });

  test('startup player sends conservative fade and volume to macOS', () async {
    const channel = MethodChannel('handdraw_studio/startup_sound');
    MethodCall? playCall;
    MethodCall? stopCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'play') playCall = call;
          if (call.method == 'stop') stopCall = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    const service = StartupSoundService();
    await service.play();
    await service.stop();

    final arguments = Map<String, Object?>.from(playCall!.arguments as Map);
    expect(File(arguments['path']! as String).existsSync(), isTrue);
    expect(arguments['volume'], 0.3);
    expect(arguments['fadeInMilliseconds'], 220);
    expect(arguments['fadeOutMilliseconds'], 420);
    expect(stopCall?.arguments, {'fadeOutMilliseconds': 140});
  });
}

class _MemoryStartupSoundRepository implements StartupSoundRepository {
  bool enabled = true;

  @override
  Future<bool> loadEnabled() async => enabled;

  @override
  Future<void> saveEnabled(bool value) async => enabled = value;
}
