import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/home/memories/collage/memory_collage_preview_photo.dart";

void main() {
  testWidgets("fades in a decoded thumbnail before reporting readiness", (
    tester,
  ) async {
    late VoidCallback showThumbnail;
    var readyNotifications = 0;

    await tester.pumpWidget(
      _testApp(
        MemoryCollagePreviewPhoto(
          file: EnteFile(),
          onReady: () => readyNotifications++,
          testPhotoBuilder: (context, onThumbnailLoaded) {
            showThumbnail = onThumbnailLoaded;
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

    showThumbnail();
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    expect(readyNotifications, 0);

    await tester.pump(const Duration(milliseconds: 350));
    expect(readyNotifications, 1);

    showThumbnail();
    await tester.pump();
    expect(readyNotifications, 1);
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox.square(dimension: 100, child: child)),
    ),
  );
}
