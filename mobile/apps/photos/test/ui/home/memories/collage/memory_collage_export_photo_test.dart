import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_photo.dart";

void main() {
  testWidgets(
    "renders transparently without a hidden fade or loading indicator",
    (tester) async {
      late VoidCallback reportFinalImage;
      var readyNotifications = 0;

      await tester.pumpWidget(
        _testApp(
          MemoryCollageExportPhoto(
            file: EnteFile(),
            tagPrefix: "test-",
            targetPixelSize: const Size(300, 400),
            onFinalImageLoaded: () => readyNotifications++,
            testPhotoBuilder: (context, onFinalImageLoaded) {
              reportFinalImage = onFinalImageLoaded;
              return const ColoredBox(color: Colors.red);
            },
          ),
        ),
      );

      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == Colors.black,
        ),
        findsNothing,
      );
      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(MemoryCollageExportPhoto),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointer.ignoring, isTrue);

      reportFinalImage();
      expect(readyNotifications, 1);
    },
  );

  group("export decode target", () {
    test("covers authored slots for landscape originals", () {
      final file = _fileWithDimensions(width: 4000, height: 2000);

      expect(memoryCollageExportDecodeTarget(file, const Size(894, 768)), (
        cacheWidth: null,
        cacheHeight: 768,
      ));
      expect(memoryCollageExportDecodeTarget(file, const Size(894, 300)), (
        cacheWidth: null,
        cacheHeight: 447,
      ));
    });

    test("covers authored slots for portrait originals", () {
      final file = _fileWithDimensions(width: 2000, height: 4000);

      expect(memoryCollageExportDecodeTarget(file, const Size(894, 768)), (
        cacheWidth: 894,
        cacheHeight: null,
      ));
      expect(memoryCollageExportDecodeTarget(file, const Size(300, 894)), (
        cacheWidth: 447,
        cacheHeight: null,
      ));
    });

    test("keeps a canvas-width fallback when dimensions are unavailable", () {
      expect(
        memoryCollageExportDecodeTarget(EnteFile(), const Size(894, 768)),
        (cacheWidth: 1080, cacheHeight: null),
      );
      expect(
        memoryCollageExportDecodeTarget(EnteFile(), const Size(1200, 768)),
        (cacheWidth: 1200, cacheHeight: null),
      );
    });
  });
}

EnteFile _fileWithDimensions({required int width, required int height}) {
  return EnteFile()..pubMagicMetadata = PubMagicMetadata(w: width, h: height);
}

Widget _testApp(Widget child) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: SizedBox.square(dimension: 100, child: child)),
    ),
  );
}
