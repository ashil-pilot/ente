import "dart:io";
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
  MemoryCollageManifest? loadedManifest,
  String? templateID,
  String? backgroundAssetIDOverride,
  int minimumEncodedByteLength = 500000,
  String titleText = "AUGUST 2026",
  bool verifyRasterOutput = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final manifest = loadedManifest ?? await MemoryCollageManifest.load();
  final template = templateID == null
      ? manifest.defaultTemplate
      : manifest.templateFor(templateID);
  final backgroundAssetID =
      backgroundAssetIDOverride ?? template.background.defaultAssetID;
  final photoCount = template.photoSlots.length;
  final boundaryKey = GlobalKey();
  late BuildContext assetContext;
  final renderedSlots = <int>[];
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
    backgroundAssetID,
    templateID: templateID,
  );
  expect(requiredAssetIDs, {
    backgroundAssetID,
    for (final layer in template.layers)
      if (layer.layerID != template.background.layerID &&
          layer.appliesToBackground(backgroundAssetID))
        layer.assetID,
  });
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
        // Authored collage typography ignores both accessibility text scaling
        // and Bold Text so preview and export geometry stay identical.
        data: const MediaQueryData(
          textScaler: TextScaler.linear(2),
          boldText: true,
        ),
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: MemoryCollageCanvasView(
                manifest: manifest,
                files: List.generate(photoCount, _photo),
                title: titleText,
                backgroundAssetID: backgroundAssetID,
                templateID: templateID,
                photoBuilder: (context, file, slot) {
                  renderedSlots.add(slot);
                  expect(file.uploadedFileID, slot + 1);
                  return ColoredBox(
                    key: ValueKey("memory-collage-photo-$slot"),
                    color: colors[slot],
                  );
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

  expect(photoCount, 7);
  expect(renderedSlots, hasLength(7));
  expect(renderedSlots.toSet(), equals(Set.of(List.generate(7, (i) => i))));
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  expect(boundary.size, memoryCollageLogicalSize);
  final renderedTitleText = titleText.replaceAll(
    RegExp(r"[\r\n\u000B\u000C\u0085\u2028\u2029]+"),
    " ",
  );
  final titleFinder = find.text(renderedTitleText);
  final title = tester.widget<Text>(titleFinder);
  expect(title.textScaler, TextScaler.noScaling);
  expect(title.maxLines, inInclusiveRange(1, template.titleStyle.maxLines));
  expect(title.overflow, TextOverflow.clip);
  expect(title.textAlign, _textAlignFor(template.titleStyle.textAlign));
  expect(
    title.style!.fontStyle,
    template.titleStyle.fontStyle == "italic"
        ? FontStyle.italic
        : FontStyle.normal,
  );
  expect(
    title.style!.color,
    parseMemoryCollageColor(template.titleStyle.color),
  );
  final titleAlignments = tester
      .widgetList<Align>(
        find.ancestor(of: titleFinder, matching: find.byType(Align)),
      )
      .map((align) => align.alignment);
  expect(
    titleAlignments,
    contains(
      _titleAlignment(
        template.titleStyle.textAlign,
        template.titleStyle.verticalAlign,
      ),
    ),
  );
  final titlePlacement = template.titleStyle.placement;
  final titleBoundsFinder = find.byKey(
    const ValueKey("memory-collage-title-bounds"),
  );
  expect(titleBoundsFinder, findsOneWidget);
  final titleBounds = tester.getSize(titleBoundsFinder);
  final titleContext = tester.element(titleFinder);
  final titlePainter = TextPainter(
    text: TextSpan(text: renderedTitleText, style: title.style),
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
  _expectPositionedRect(tester, titleFinder, titlePlacement.rect);
  for (final slot in template.photoSlots) {
    if (slot is MemoryCollageMattedRectPhotoSlot) {
      _expectMattedRectSlot(tester, slot, template.matStyle!);
    }
  }
  for (final rule in template.rules) {
    final rulePositioned = tester
        .widgetList<Positioned>(find.byType(Positioned))
        .singleWhere(
          (positioned) =>
              _matchesRect(positioned, rule.rect) &&
              positioned.child is Transform &&
              (positioned.child as Transform).child is ColoredBox,
        );
    final transform = rulePositioned.child as Transform;
    final coloredBox = transform.child! as ColoredBox;
    expect(
      coloredBox.color,
      parseMemoryCollageColor(rule.colorFor(backgroundAssetID)),
    );
  }
  if (template.matStyle != null) {
    _expectMattedTemplateDrawOrder(
      tester,
      boundaryKey: boundaryKey,
      template: template,
      backgroundAssetID: backgroundAssetID,
      titleFinder: titleFinder,
    );
  }
  if (!verifyRasterOutput) return;
  final image = await boundary.toImage(
    pixelRatio: memoryCollageExportPixelRatio,
  );
  addTearDown(image.dispose);
  expect(image.width, 1080);
  expect(image.height, 1920);
  if (template.matStyle != null) {
    final rawRgba = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    _expectMattedPhotoCenterColors(
      rawRgba!,
      imageWidth: image.width,
      slots: template.photoSlots.whereType<MemoryCollageMattedRectPhotoSlot>(),
      colors: colors,
    );
  }
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  final bytes = data!.buffer.asUint8List();
  expect(bytes.length, greaterThan(minimumEncodedByteLength));
  final outputTemplate = Platform.environment["MEMORY_COLLAGE_TEST_OUTPUT"];
  if (outputTemplate != null) {
    await tester.runAsync(
      () => File(
        _variantOutputPath(outputTemplate, template.id),
      ).writeAsBytes(bytes, flush: true),
    );
  }
}

void _expectMattedPhotoCenterColors(
  ByteData rawRgba, {
  required int imageWidth,
  required Iterable<MemoryCollageMattedRectPhotoSlot> slots,
  required List<Color> colors,
}) {
  for (final slot in slots) {
    final x = (slot.photoRect.x + slot.photoRect.width / 2).floor();
    final y = (slot.photoRect.y + slot.photoRect.height / 2).floor();
    final offset = (y * imageWidth + x) * 4;
    final actual = [
      rawRgba.getUint8(offset),
      rawRgba.getUint8(offset + 1),
      rawRgba.getUint8(offset + 2),
      rawRgba.getUint8(offset + 3),
    ];
    final expectedArgb = colors[slot.slot].toARGB32();
    final expected = [
      (expectedArgb >> 16) & 0xff,
      (expectedArgb >> 8) & 0xff,
      expectedArgb & 0xff,
      (expectedArgb >> 24) & 0xff,
    ];
    for (var channel = 0; channel < 4; channel++) {
      expect(
        actual[channel],
        closeTo(expected[channel], channel == 3 ? 0 : 64),
        reason: "matted photo ${slot.slot} channel $channel was obscured",
      );
    }
  }
}

void _expectMattedTemplateDrawOrder(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
  required MemoryCollageTemplate template,
  required String backgroundAssetID,
  required Finder titleFinder,
}) {
  final backgroundFinder = find.descendant(
    of: find.byKey(boundaryKey),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image == memoryCollageAssetProvider(backgroundAssetID),
    ),
  );
  expect(backgroundFinder, findsOneWidget);
  final backgroundPositioned = _positionedAncestorMatching(
    tester,
    backgroundFinder,
    const MemoryCollageRect(x: 0, y: 0, width: 1080, height: 1920),
  );

  final matPositioneds = [
    for (final slot
        in template.photoSlots.whereType<MemoryCollageMattedRectPhotoSlot>())
      _positionedAncestorMatching(
        tester,
        find.byKey(ValueKey("memory-collage-mat-${slot.slot}")),
        slot.matRect,
      ),
  ];
  final rulePositioneds = [
    for (final rule in template.rules)
      _positionedAncestorMatching(
        tester,
        find.descendant(
          of: find.byKey(boundaryKey),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox &&
                widget.color ==
                    parseMemoryCollageColor(rule.colorFor(backgroundAssetID)),
          ),
        ),
        rule.rect,
      ),
  ];
  final titlePlacement = template.titleStyle.placement;
  final titlePositioned = _positionedAncestorMatching(
    tester,
    titleFinder,
    titlePlacement.rect,
  );
  final activeGrainLayers = template.layers
      .where(
        (layer) =>
            layer.layerID == "grain" &&
            layer.appliesToBackground(backgroundAssetID),
      )
      .toList(growable: false);
  expect(activeGrainLayers.length, lessThanOrEqualTo(1));
  final grainFinder = find.descendant(
    of: find.byKey(boundaryKey),
    matching: find.byType(CustomPaint),
  );
  expect(
    grainFinder,
    activeGrainLayers.isEmpty ? findsNothing : findsOneWidget,
  );

  final orderedEntries = <Widget>[
    backgroundPositioned,
    ...matPositioneds,
    ...rulePositioneds,
    titlePositioned,
    if (activeGrainLayers.isNotEmpty)
      _positionedAncestorMatching(
        tester,
        grainFinder,
        activeGrainLayers.single.rect,
      ),
  ];
  final rootStack = tester
      .widgetList<Stack>(
        find.descendant(
          of: find.byKey(boundaryKey),
          matching: find.byType(Stack),
        ),
      )
      .singleWhere((stack) => orderedEntries.every(stack.children.contains));
  final indices = orderedEntries.map(rootStack.children.indexOf).toList();
  for (var index = 1; index < indices.length; index++) {
    expect(indices[index], greaterThan(indices[index - 1]));
  }
}

void _expectMattedRectSlot(
  WidgetTester tester,
  MemoryCollageMattedRectPhotoSlot slot,
  MemoryCollageMatStyle style,
) {
  final matFinder = find.byKey(ValueKey("memory-collage-mat-${slot.slot}"));
  final photoFinder = find.byKey(
    ValueKey("memory-collage-matted-photo-${slot.slot}"),
  );
  expect(matFinder, findsOneWidget);
  expect(photoFinder, findsOneWidget);
  _expectPositionedRect(tester, matFinder, slot.matRect);

  final mat = tester.widget<DecoratedBox>(matFinder);
  final decoration = mat.decoration as BoxDecoration;
  expect(decoration.color, parseMemoryCollageColor(style.fill));
  if (style.shadows.isEmpty) {
    expect(decoration.boxShadow, isNull);
  } else {
    expect(decoration.boxShadow, hasLength(style.shadows.length));
    for (var index = 0; index < style.shadows.length; index++) {
      final authored = style.shadows[index];
      final rendered = decoration.boxShadow![index];
      expect(rendered.color, parseMemoryCollageColor(authored.color));
      expect(
        rendered.offset,
        Offset(
          authored.dx / memoryCollageExportPixelRatio,
          authored.dy / memoryCollageExportPixelRatio,
        ),
      );
      expect(
        rendered.blurRadius,
        authored.blur / memoryCollageExportPixelRatio,
      );
      expect(rendered.spreadRadius, 0);
    }
  }
  expect(
    decoration.border,
    Border.all(
      color: parseMemoryCollageColor(style.border.color),
      width: style.border.width / memoryCollageExportPixelRatio,
    ),
  );

  final photoPositioned = tester
      .widgetList<Positioned>(
        find.ancestor(of: photoFinder, matching: find.byType(Positioned)),
      )
      .firstWhere(
        (positioned) =>
            positioned.left ==
                (slot.photoRect.x - slot.matRect.x) /
                    memoryCollageExportPixelRatio &&
            positioned.top ==
                (slot.photoRect.y - slot.matRect.y) /
                    memoryCollageExportPixelRatio,
      );
  expect(
    photoPositioned.width,
    slot.photoRect.width / memoryCollageExportPixelRatio,
  );
  expect(
    photoPositioned.height,
    slot.photoRect.height / memoryCollageExportPixelRatio,
  );
  expect(tester.widget<ClipRect>(photoFinder), isA<ClipRect>());
}

void _expectPositionedRect(
  WidgetTester tester,
  Finder descendant,
  MemoryCollageRect rect,
) {
  const scale = memoryCollageExportPixelRatio;
  final matches = tester
      .widgetList<Positioned>(
        find.ancestor(of: descendant, matching: find.byType(Positioned)),
      )
      .where(
        (positioned) =>
            positioned.left == rect.x / scale &&
            positioned.top == rect.y / scale &&
            positioned.width == rect.width / scale &&
            positioned.height == rect.height / scale,
      );
  expect(matches, isNotEmpty);
}

Positioned _positionedAncestorMatching(
  WidgetTester tester,
  Finder descendant,
  MemoryCollageRect rect,
) {
  return tester
      .widgetList<Positioned>(
        find.ancestor(of: descendant, matching: find.byType(Positioned)),
      )
      .singleWhere((positioned) => _matchesRect(positioned, rect));
}

bool _matchesRect(Positioned positioned, MemoryCollageRect rect) {
  const scale = memoryCollageExportPixelRatio;
  return positioned.left == rect.x / scale &&
      positioned.top == rect.y / scale &&
      positioned.width == rect.width / scale &&
      positioned.height == rect.height / scale;
}

String _variantOutputPath(String template, String templateID) {
  if (template.contains("{templateID}")) {
    return template.replaceAll("{templateID}", templateID);
  }
  final extensionIndex = template.lastIndexOf(".");
  if (extensionIndex < 0) return "$template-$templateID";
  return "${template.substring(0, extensionIndex)}-$templateID"
      "${template.substring(extensionIndex)}";
}

TextAlign _textAlignFor(String value) => switch (value) {
  "left" => TextAlign.left,
  "center" => TextAlign.center,
  "right" => TextAlign.right,
  "start" => TextAlign.start,
  "end" => TextAlign.end,
  "justify" => TextAlign.justify,
  _ => throw StateError("Unexpected test text alignment: $value"),
};

AlignmentGeometry _titleAlignment(String textAlign, String verticalAlign) {
  final y = switch (verticalAlign) {
    "top" => -1.0,
    "center" => 0.0,
    "bottom" => 1.0,
    _ => throw StateError("Unexpected test vertical alignment: $verticalAlign"),
  };
  return switch (textAlign) {
    "left" => Alignment(-1, y),
    "center" || "justify" => Alignment(0, y),
    "right" => Alignment(1, y),
    "start" => AlignmentDirectional(-1, y),
    "end" => AlignmentDirectional(1, y),
    _ => throw StateError("Unexpected test text alignment: $textAlign"),
  };
}

EnteFile _photo(int index) {
  return EnteFile()
    ..uploadedFileID = index + 1
    ..generatedID = index + 100
    ..fileType = FileType.image;
}
