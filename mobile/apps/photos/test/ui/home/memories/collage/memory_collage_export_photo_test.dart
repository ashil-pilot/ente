import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_photo.dart";

void main() {
  testWidgets("waits for the photo fade before reporting export readiness", (
    tester,
  ) async {
    late VoidCallback showFirstFrame;
    late VoidCallback showFinalImage;
    var readyNotifications = 0;

    await tester.pumpWidget(
      _testApp(
        MemoryCollageExportPhoto(
          file: EnteFile(),
          tagPrefix: "test-",
          onFinalImageLoaded: () => readyNotifications++,
          testPhotoBuilder: (context, onFirstFrame, onFinalImageLoaded) {
            showFirstFrame = onFirstFrame;
            showFinalImage = onFinalImageLoaded;
            return const ColoredBox(color: Colors.red);
          },
        ),
      ),
    );

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AnimatedOpacity),
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.black,
        ),
      ),
      findsOneWidget,
    );

    showFinalImage();
    await tester.pump();
    expect(readyNotifications, 0);

    showFirstFrame();
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    expect(readyNotifications, 0);

    await tester.pump(const Duration(milliseconds: 350));
    expect(readyNotifications, 1);

    showFirstFrame();
    showFinalImage();
    await tester.pump();
    expect(readyNotifications, 1);
  });

  testWidgets("reports readiness when the final image follows the fade", (
    tester,
  ) async {
    late VoidCallback showFirstFrame;
    late VoidCallback showFinalImage;
    var readyNotifications = 0;

    await tester.pumpWidget(
      _testApp(
        MemoryCollageExportPhoto(
          file: EnteFile(),
          tagPrefix: "test-",
          onFinalImageLoaded: () => readyNotifications++,
          testPhotoBuilder: (context, onFirstFrame, onFinalImageLoaded) {
            showFirstFrame = onFirstFrame;
            showFinalImage = onFinalImageLoaded;
            return const ColoredBox(color: Colors.red);
          },
        ),
      ),
    );

    showFirstFrame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(readyNotifications, 0);

    showFinalImage();
    await tester.pump();
    expect(readyNotifications, 1);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: SizedBox.square(dimension: 100, child: child)),
    ),
  );
}
