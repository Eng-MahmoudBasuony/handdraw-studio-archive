import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:handdraw_studio/core/platform/native_launch_service.dart';
import 'package:handdraw_studio/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS reaches the editor and dismisses its native splash', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    expect(find.byKey(const ValueKey('editor-timeline-dock')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(await NativeLaunchService.isLaunchSplashVisible(), isFalse);
  });
}
