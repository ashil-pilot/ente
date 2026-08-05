import "dart:io";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("lays out the authored canvas with the exact export contract", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final manifest = await MemoryCollageManifest.load();
    final boundaryKey = GlobalKey();
    late BuildContext assetContext;
    final colors = <Color>[
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            assetContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.runAsync(
      () => MemoryCollageCanvasView.precacheAssets(assetContext, manifest),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: MemoryCollageCanvasView(
                  manifest: manifest,
                  files: List.generate(6, _photo),
                  title: "AUGUST 2026",
                  backgroundAssetID: "paper-washi",
                  photoBuilder: (context, file, slot) =>
                      ColoredBox(color: colors[slot]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Image streams can keep scheduling housekeeping frames in a widget test;
    // a bounded pair of pumps is enough for the bundled raster assets.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    expect(boundary.size, memoryCollageLogicalSize);
    final title = tester.widget<Text>(find.text("AUGUST 2026"));
    expect(title.textScaler, TextScaler.noScaling);
    final image = await boundary.toImage(
      pixelRatio: memoryCollageExportPixelRatio,
    );
    addTearDown(image.dispose);
    expect(image.width, 1080);
    expect(image.height, 1920);
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    final bytes = data!.buffer.asUint8List();
    expect(bytes.length, greaterThan(500000));
    final outputPath = Platform.environment["MEMORY_COLLAGE_TEST_OUTPUT"];
    if (outputPath != null) {
      await tester.runAsync(
        () => File(outputPath).writeAsBytes(bytes, flush: true),
      );
    }
  });

  test("parses the authored CSS color formats", () {
    expect(parseMemoryCollageColor("#f4e7cf"), const Color(0xFFF4E7CF));
    expect(
      parseMemoryCollageColor("rgba(90,40,15,0.5)"),
      const Color.fromRGBO(90, 40, 15, 0.5),
    );
  });
}

EnteFile _photo(int index) {
  return EnteFile()
    ..uploadedFileID = index + 1
    ..generatedID = index + 100
    ..fileType = FileType.image;
}
