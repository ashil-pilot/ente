import "dart:typed_data";
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
  required MemoryCollageManifest manifest,
  String? templateID,
  String? backgroundAssetID,
  String titleText = "AUGUST 2026",
  bool verifyRasterOutput = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final template = templateID == null
      ? manifest.defaultTemplate
      : manifest.templateFor(templateID);
  final selectedBackground =
      backgroundAssetID ?? template.defaultBackgroundAssetID;
  final boundaryKey = GlobalKey();
  late BuildContext assetContext;
  final renderedSlots = <int>[];

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
    () => MemoryCollageCanvasView.precacheAssets(
      assetContext,
      manifest,
      assetIDs: memoryCollageRequiredAssetIDs(
        manifest,
        selectedBackground,
        templateID: template.id,
      ),
    ),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(2),
          boldText: true,
        ),
        child: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: MemoryCollageCanvasView(
              manifest: manifest,
              files: List.generate(7, _photo),
              title: titleText,
              backgroundAssetID: selectedBackground,
              templateID: templateID,
              photoBuilder: (context, file, slot) {
                renderedSlots.add(slot);
                expect(file.uploadedFileID, slot + 1);
                return ColoredBox(
                  key: ValueKey("memory-collage-photo-$slot"),
                  color: _photoColors[slot],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));

  expect(renderedSlots, hasLength(7));
  expect(renderedSlots.toSet(), Set.of(List.generate(7, (index) => index)));
  expect(tester.getSize(find.byKey(boundaryKey)), memoryCollageLogicalSize);
  expect(
    find.descendant(
      of: find.byKey(boundaryKey),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image == memoryCollageAssetProvider(selectedBackground),
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(boundaryKey),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image == memoryCollageAssetProvider(template.plateAssetID),
      ),
    ),
    findsOneWidget,
  );

  for (final slot in template.photoSlots) {
    final backing = tester.widget<ColoredBox>(
      find.byKey(ValueKey("memory-collage-photo-backing-${slot.slot}")),
    );
    expect(
      backing.color,
      parseMemoryCollageColor(slot.backingColor),
      reason: "${template.id} slot ${slot.slot}",
    );
  }

  final normalizedTitle = titleText.replaceAll(
    RegExp(r"[\r\n\u000B\u000C\u0085\u2028\u2029]+"),
    " ",
  );
  final titleFinder = find.text(normalizedTitle);
  final title = tester.widget<Text>(titleFinder);
  expect(title.textScaler, TextScaler.noScaling);
  expect(title.maxLines, inInclusiveRange(1, template.title.maxLines));
  expect(title.overflow, TextOverflow.clip);
  expect(title.textAlign, _textAlignFor(template.title.textAlign));
  expect(title.style!.fontStyle, FontStyle.normal);
  expect(title.style!.color, parseMemoryCollageColor(template.title.color));
  final titleBounds = tester.getSize(
    find.byKey(const ValueKey("memory-collage-title-bounds")),
  );
  expect(
    titleBounds,
    Size(
      template.title.rect.width / memoryCollageExportPixelRatio,
      template.title.rect.height / memoryCollageExportPixelRatio,
    ),
  );
  final titleContext = tester.element(titleFinder);
  final titlePainter = TextPainter(
    text: TextSpan(text: normalizedTitle, style: title.style),
    maxLines: title.maxLines,
    textAlign: title.textAlign ?? TextAlign.start,
    textDirection: title.textDirection ?? Directionality.of(titleContext),
    textScaler: title.textScaler ?? TextScaler.noScaling,
    locale: title.locale ?? Localizations.maybeLocaleOf(titleContext),
    textHeightBehavior:
        title.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(titleContext),
  )..layout(maxWidth: titleBounds.width);
  expect(titlePainter.didExceedMaxLines, isFalse);
  expect(titlePainter.height, lessThanOrEqualTo(titleBounds.height + 0.001));
  titlePainter.dispose();

  if (!verifyRasterOutput) return;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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
  expect(bytes, isA<Uint8List>());
  expect(bytes.length, greaterThan(1000));
}

EnteFile _photo(int index) {
  return EnteFile()
    ..uploadedFileID = index + 1
    ..fileType = FileType.image;
}

const _photoColors = [
  Colors.red,
  Colors.orange,
  Colors.yellow,
  Colors.green,
  Colors.blue,
  Colors.purple,
  Colors.cyan,
];

TextAlign _textAlignFor(String value) {
  return switch (value) {
    "left" => TextAlign.left,
    "center" => TextAlign.center,
    "right" => TextAlign.right,
    "start" => TextAlign.start,
    "end" => TextAlign.end,
    _ => throw StateError("Unexpected alignment: $value"),
  };
}
