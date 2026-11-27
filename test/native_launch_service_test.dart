import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/core/platform/native_dialog_focus_service.dart';
import 'package:handdraw_studio/core/platform/native_launch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notifies the native launch surface after Flutter renders', () async {
    const channel = MethodChannel('handdraw_studio/lifecycle');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await NativeLaunchService.notifyFirstFrameRendered();

    expect(receivedCall?.method, 'appReady');
    expect(receivedCall?.arguments, isNull);
  });

  test('platforms without a launch coordinator remain safe', () async {
    const channel = MethodChannel('handdraw_studio/lifecycle');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    await expectLater(
      NativeLaunchService.notifyFirstFrameRendered(),
      completes,
    );
  });

  test('retries a transient launch channel failure', () async {
    const channel = MethodChannel('handdraw_studio/lifecycle');
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          attempts++;
          if (attempts == 1) {
            throw PlatformException(code: 'channel_not_ready');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await NativeLaunchService.notifyFirstFrameRendered(
      retryDelay: Duration.zero,
    );

    expect(attempts, 2);
  });

  test('reports the native launch surface visibility', () async {
    const channel = MethodChannel('handdraw_studio/lifecycle');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(await NativeLaunchService.isLaunchSplashVisible(), isTrue);
  });

  test('distinguishes a missing native launch coordinator', () async {
    const channel = MethodChannel('handdraw_studio/lifecycle');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(await NativeLaunchService.isLaunchSplashVisible(), isNull);
  });

  test('prepares the native host before presenting a file dialog', () async {
    const channel = MethodChannel('handdraw_studio/lifecycle');
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await const NativeDialogFocusService().prepareForPresentation();

    expect(receivedCall?.method, 'prepareForNativeDialog');
    expect(receivedCall?.arguments, isNull);
  });

  test(
    'missing native dialog focus coordinator never blocks a picker',
    () async {
      const channel = MethodChannel('handdraw_studio/lifecycle');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      await expectLater(
        const NativeDialogFocusService().prepareForPresentation(),
        completes,
      );
    },
  );
}
