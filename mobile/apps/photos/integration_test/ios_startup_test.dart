import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:rive/rive.dart" as rive;
import "package:shared_preferences/shared_preferences.dart";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("iOS starts Rive and maintains its foreground heartbeat", (
    tester,
  ) async {
    await rive.RiveNative.init();
    final file = await rive.File.asset(
      "assets/onboarding.riv",
      riveFactory: rive.Factory.flutter,
    );
    expect(file, isNotNull);
    final controller = rive.RiveWidgetController(file!);
    addTearDown(() {
      controller.dispose();
      file.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: rive.RiveWidget(controller: controller)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(rive.RiveWidget), findsOneWidget);
    expect(tester.takeException(), isNull);

    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final firstHeartbeat = preferences.getInt("native_fg_task_hb_time");
    expect(firstHeartbeat, isNotNull);
    await Future<void>.delayed(const Duration(seconds: 2));
    await preferences.reload();
    expect(
      preferences.getInt("native_fg_task_hb_time"),
      greaterThan(firstHeartbeat!),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isIOS);
}
