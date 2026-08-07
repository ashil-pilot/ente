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
  MemoryCollageManifest? loadedManifest,
  String? templateID,
  String? backgroundAssetIDOverride,
  Set<String>? expectedRequiredAssetIDs,
  int minimumEncodedByteLength = 500000,
  String titleText = "AUGUST 2026",
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
      if (layer.layerID != template.background.layerID) layer.assetID,
  });
  if (expectedRequiredAssetIDs != null) {
    expect(requiredAssetIDs, expectedRequiredAssetIDs);
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
  final titleFinder = find.text(titleText);
  final title = tester.widget<Text>(titleFinder);
  expect(title.textScaler, TextScaler.noScaling);
  expect(title.maxLines, inInclusiveRange(1, template.titleStyle.maxLines));
  expect(title.textAlign, _textAlignFor(template.titleStyle.textAlign));
  expect(
    title.style!.fontStyle,
    template.titleStyle.fontStyle == "italic"
        ? FontStyle.italic
        : FontStyle.normal,
  );
  final useDarkColors = manifest.assetFor(backgroundAssetID).dark;
  expect(
    title.style!.color,
    parseMemoryCollageColor(
      useDarkColors
          ? template.titleStyle.colorOnDark ?? template.titleStyle.color
          : template.titleStyle.color,
    ),
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
  final titlePadding = tester
      .widgetList<Padding>(
        find.ancestor(of: titleFinder, matching: find.byType(Padding)),
      )
      .singleWhere((padding) => padding.child is LayoutBuilder);
  expect(
    titlePadding.padding,
    template.titleStyle.placement is MemoryCollageTitleAnchor
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
        : EdgeInsets.zero,
  );
  final titlePlacement = template.titleStyle.placement;
  if (titlePlacement is MemoryCollageTitleRect) {
    _expectPositionedRect(tester, titleFinder, titlePlacement.rect);
  }
  for (final slot in template.photoSlots) {
    if (slot is! MemoryCollageRectPhotoSlot) continue;
    final photoFinder = find.byKey(
      ValueKey("memory-collage-photo-${slot.slot}"),
    );
    _expectPositionedRect(tester, photoFinder, slot.rect);
    final clip = tester.widget<ClipRRect>(
      find.ancestor(of: photoFinder, matching: find.byType(ClipRRect)).first,
    );
    expect(
      clip.borderRadius,
      BorderRadius.circular((slot.radius ?? 0) / memoryCollageExportPixelRatio),
    );
    final border = slot.border;
    if (border != null) {
      final borderColor = parseMemoryCollageColor(border.color);
      final borderWidth = border.width / memoryCollageExportPixelRatio;
      expect(
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((box) {
          if (box.position != DecorationPosition.foreground ||
              box.decoration is! BoxDecoration) {
            return false;
          }
          final decoration = box.decoration as BoxDecoration;
          final renderedBorder = decoration.border;
          return renderedBorder is Border &&
              renderedBorder.top.color == borderColor &&
              renderedBorder.top.width == borderWidth;
        }),
        isTrue,
      );
    }
    _expectRectShadows(tester, slot);
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
      parseMemoryCollageColor(
        useDarkColors ? rule.colorOnDark ?? rule.color : rule.color,
      ),
    );
  }
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

void _expectRectShadows(WidgetTester tester, MemoryCollageRectPhotoSlot slot) {
  if (slot.shadows.isEmpty) return;
  final positioneds = tester
      .widgetList<Positioned>(find.byType(Positioned))
      .toList(growable: false);
  final photoIndex = positioneds.indexWhere(
    (positioned) =>
        _matchesRect(positioned, slot.rect) && !_isFilteredShadow(positioned),
  );
  expect(photoIndex, greaterThanOrEqualTo(0));
  for (final shadow in slot.shadows) {
    final shadowRect = MemoryCollageRect(
      x: slot.rect.x + shadow.dx,
      y: slot.rect.y + shadow.dy,
      width: slot.rect.width,
      height: slot.rect.height,
    );
    final shadowIndex = positioneds.indexWhere(
      (positioned) =>
          _matchesRect(positioned, shadowRect) && _isFilteredShadow(positioned),
    );
    expect(shadowIndex, greaterThanOrEqualTo(0));
    expect(shadowIndex, lessThan(photoIndex));
    final transform = positioneds[shadowIndex].child as Transform;
    final imageFiltered = transform.child! as ImageFiltered;
    final silhouette = imageFiltered.child! as DecoratedBox;
    final decoration = silhouette.decoration as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular((slot.radius ?? 0) / memoryCollageExportPixelRatio),
    );
  }
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

bool _matchesRect(Positioned positioned, MemoryCollageRect rect) {
  const scale = memoryCollageExportPixelRatio;
  return positioned.left == rect.x / scale &&
      positioned.top == rect.y / scale &&
      positioned.width == rect.width / scale &&
      positioned.height == rect.height / scale;
}

bool _isFilteredShadow(Positioned positioned) {
  final child = positioned.child;
  return child is Transform && child.child is ImageFiltered;
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
