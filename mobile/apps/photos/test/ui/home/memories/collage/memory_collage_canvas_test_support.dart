import "dart:io";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";

Future<void> verifyMemoryCollageCanvas(
  WidgetTester tester, {
  required int photoCount,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final manifest = await MemoryCollageManifest.load();
  final boundaryKey = GlobalKey();
  late BuildContext assetContext;
  final renderedSlots = <int>{};
  final colors = <Color>[
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.cyan,
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
  final requiredAssetIDs = memoryCollageRequiredAssetIDs(
    manifest,
    "paper-washi",
    photoCount: photoCount,
  );
  expect(requiredAssetIDs, contains("paper-washi"));
  if (photoCount == 6) {
    expect(requiredAssetIDs, contains("film-strip"));
    expect(requiredAssetIDs, isNot(contains("film-strip-four")));
  } else {
    expect(requiredAssetIDs, contains("film-strip-four"));
    expect(requiredAssetIDs, isNot(contains("film-strip")));
  }
  await tester.runAsync(
    () => MemoryCollageCanvasView.precacheAssets(
      assetContext,
      manifest,
      assetIDs: requiredAssetIDs,
    ),
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
                files: List.generate(photoCount, _photo),
                title: "AUGUST 2026",
                backgroundAssetID: "paper-washi",
                photoBuilder: (context, file, slot) {
                  renderedSlots.add(slot);
                  expect(file.uploadedFileID, slot + 1);
                  return ColoredBox(color: colors[slot]);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Image streams can keep scheduling housekeeping frames in a widget test; a
  // bounded pair of pumps is enough for the bundled assets.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));

  expect(
    renderedSlots,
    equals(Set.of(List.generate(photoCount, (index) => index))),
  );
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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
  final outputTemplate = Platform.environment["MEMORY_COLLAGE_TEST_OUTPUT"];
  if (outputTemplate != null) {
    await tester.runAsync(
      () => File(
        _variantOutputPath(outputTemplate, photoCount),
      ).writeAsBytes(bytes, flush: true),
    );
  }
}

String _variantOutputPath(String template, int photoCount) {
  if (template.contains("{photoCount}")) {
    return template.replaceAll("{photoCount}", "$photoCount");
  }
  final extensionIndex = template.lastIndexOf(".");
  if (extensionIndex < 0) return "$template-$photoCount";
  return "${template.substring(0, extensionIndex)}-$photoCount"
      "${template.substring(extensionIndex)}";
}

EnteFile _photo(int index) {
  return EnteFile()
    ..uploadedFileID = index + 1
    ..generatedID = index + 100
    ..fileType = FileType.image;
}
