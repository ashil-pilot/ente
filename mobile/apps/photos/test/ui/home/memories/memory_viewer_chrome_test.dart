import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/memory_viewer_chrome.dart";
import "package:photos/ui/home/memories/memory_viewer_constants.dart";

void main() {
  testWidgets("preserves the memory viewer top chrome geometry", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(320, 640));

    await tester.pumpWidget(
      _testApp(
        MemoryViewerTopChrome(
          totalSteps: 4,
          currentIndex: 1,
          header: Row(
            children: [
              MemoryViewerCloseButton(onPressed: () {}),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Memory title",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(memoryViewerProgressIndicatorKey)),
      const Offset(16, 40),
    );
    expect(
      tester.getSize(find.byKey(memoryViewerProgressIndicatorKey)),
      const Size(288, 4),
    );
    expect(
      tester.getTopLeft(find.byKey(memoryViewerHeaderKey)),
      const Offset(16, 56),
    );
    expect(
      tester.getSize(find.byKey(memoryViewerHeaderKey)),
      const Size(288, 52),
    );
    expect(
      tester.getSize(find.byKey(memoryViewerCloseButtonKey)),
      const Size.square(48),
    );
  });

  testWidgets("close and action buttons keep exact 48 point targets", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(320, 640));
    var closeTaps = 0;
    var shareTaps = 0;

    await tester.pumpWidget(
      _testApp(
        Stack(
          fit: StackFit.expand,
          children: [
            MemoryViewerTopChrome(
              totalSteps: 1,
              currentIndex: 0,
              header: Align(
                alignment: Alignment.centerLeft,
                child: MemoryViewerCloseButton(onPressed: () => closeTaps++),
              ),
            ),
            MemoryViewerActionBar(
              actions: [
                MemoryViewerActionButton(
                  key: const ValueKey("share-action"),
                  tooltip: "Share",
                  icon: const Icon(Icons.share, size: 24),
                  onPressed: () => shareTaps++,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(memoryViewerCloseButtonKey)),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey("share-action"))),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byKey(memoryViewerActionBarKey)),
      const Size(320, kMemoryBottomActionBarHeight),
    );

    await tester.tap(find.byKey(memoryViewerCloseButtonKey));
    await tester.tap(find.byKey(const ValueKey("share-action")));
    expect(closeTaps, 1);
    expect(shareTaps, 1);
  });

  testWidgets("chrome stays overflow-free on a narrow large-text viewport", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(240, 480));

    await tester.pumpWidget(
      _testApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(240, 480),
            textScaler: TextScaler.linear(3),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MemoryViewerTopChrome(
                totalSteps: 20,
                currentIndex: 19,
                currentStepProgress: 1,
                header: Row(
                  children: [
                    MemoryViewerCloseButton(onPressed: () {}),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "A deliberately long memory title",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              MemoryViewerActionBar(
                actions: [
                  for (var index = 0; index < 3; index++)
                    MemoryViewerActionButton(
                      tooltip: "Action $index",
                      icon: const Icon(Icons.circle_outlined, size: 24),
                      onPressed: () {},
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(memoryViewerCloseButtonKey)),
      const Size.square(48),
    );
    expect(find.byType(MemoryViewerActionButton), findsNWidgets(3));
  });

  testWidgets("scrims preserve their fixed viewer heights", (tester) async {
    await _setSurfaceSize(tester, const Size(320, 640));
    final socialControlsVisible = ValueNotifier(false);
    addTearDown(socialControlsVisible.dispose);

    await tester.pumpWidget(
      _testApp(
        Stack(
          fit: StackFit.expand,
          children: [
            MemoryViewerScrims(socialControlsVisible: socialControlsVisible),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byKey(memoryViewerTopScrimKey)).height, 104);
    expect(
      tester.getSize(find.byKey(memoryViewerBottomScrimKey)).height,
      kMemoryBottomActionBarHeight,
    );

    socialControlsVisible.value = true;
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(memoryViewerBottomScrimKey)).height,
      kMemorySocialScrimHeight,
    );
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    home: Scaffold(backgroundColor: Colors.black, body: child),
  );
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
}
