import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";

import "memory_collage_canvas_test_support.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryCollageManifest manifest;

  setUpAll(() async {
    await Future.wait([
      (FontLoader(
        "Lora",
      )..addFont(rootBundle.load("fonts/Lora-SemiBold.ttf"))).load(),
      (FontLoader(
        "Inter",
      )..addFont(rootBundle.load("fonts/Inter-Medium.ttf"))).load(),
    ]);
    final sourceJson =
        jsonDecode(await rootBundle.loadString(memoryCollageManifestAsset))
            as Map<String, dynamic>;
    manifest = MemoryCollageManifest.fromJson(sourceJson);
  });

  test("resolves only each plate, background, and narrow finish assets", () {
    for (final template in manifest.templates) {
      for (final backgroundAssetID in manifest.backgroundAssetIDs) {
        final required = memoryCollageRequiredAssetIDs(
          manifest,
          backgroundAssetID,
          templateID: template.id,
        );
        final base = {backgroundAssetID, template.plateAssetID};
        switch (template.finishPreset) {
          case MemoryCollageFinishPreset.scrapbook:
          case MemoryCollageFinishPreset.calm:
            expect(required, {
              ...base,
              "sun-streak",
              "vignette",
              "grain-overlay",
            });
          case MemoryCollageFinishPreset.minimal:
            expect(required, {
              ...base,
              if (_editorialBackgrounds.contains(backgroundAssetID))
                "grain-overlay",
            });
        }
      }
    }

    final defaultTemplate = manifest.defaultTemplate;
    expect(
      memoryCollageRequiredAssetIDs(
        manifest,
        defaultTemplate.defaultBackgroundAssetID,
      ),
      memoryCollageRequiredAssetIDs(
        manifest,
        defaultTemplate.defaultBackgroundAssetID,
        templateID: defaultTemplate.id,
      ),
    );
  });

  for (final templateID in _templateIDs) {
    testWidgets("$templateID renders its frozen seven-photo plate", (
      tester,
    ) async {
      await verifyMemoryCollageCanvas(
        tester,
        manifest: manifest,
        templateID: templateID,
        verifyRasterOutput: templateID == manifest.defaultTemplateID,
      );
    });
  }

  testWidgets("renders every approved manifest empty-photo backing color", (
    tester,
  ) async {
    for (final template in manifest.templates) {
      await _pumpCanvas(
        tester,
        manifest: manifest,
        templateID: template.id,
        photoBuilder: (_, _, _) => const SizedBox.shrink(),
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
    }
  });

  testWidgets("extends each photo two authored pixels beneath its plate", (
    tester,
  ) async {
    final template = manifest.defaultTemplate;
    await _pumpCanvas(
      tester,
      manifest: manifest,
      templateID: template.id,
      photoBuilder: (_, _, _) => const SizedBox.expand(),
    );

    for (final slot in template.photoSlots) {
      final positioned = tester
          .widgetList<Positioned>(
            find.ancestor(
              of: find.byKey(
                ValueKey("memory-collage-photo-backing-${slot.slot}"),
              ),
              matching: find.byType(Positioned),
            ),
          )
          .singleWhere(
            (widget) =>
                widget.left ==
                    (slot.rect.x - memoryCollagePhotoBleedCanvasPixels) /
                        memoryCollageExportPixelRatio &&
                widget.top ==
                    (slot.rect.y - memoryCollagePhotoBleedCanvasPixels) /
                        memoryCollageExportPixelRatio,
          );
      expect(
        positioned.width,
        (slot.rect.width + memoryCollagePhotoBleedCanvasPixels * 2) /
            memoryCollageExportPixelRatio,
      );
      expect(
        positioned.height,
        (slot.rect.height + memoryCollagePhotoBleedCanvasPixels * 2) /
            memoryCollageExportPixelRatio,
      );
    }
  });

  testWidgets("uses minimal grain only on editorial backgrounds", (
    tester,
  ) async {
    await _pumpCanvas(
      tester,
      manifest: manifest,
      templateID: "minimal-rows",
      backgroundAssetID: "paper-cream-fiber",
      photoBuilder: (_, _, _) => const SizedBox.expand(),
    );
    expect(_blendPaints(), findsNothing);

    await _pumpCanvas(
      tester,
      manifest: manifest,
      templateID: "minimal-rows",
      backgroundAssetID: "editorial-sand",
      photoBuilder: (_, _, _) => const SizedBox.expand(),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(_blendPaints(), findsOneWidget);
  });

  testWidgets("places the title after the plate and before finish effects", (
    tester,
  ) async {
    final template = manifest.defaultTemplate;
    await _pumpCanvas(
      tester,
      manifest: manifest,
      templateID: template.id,
      photoBuilder: (_, _, _) => const SizedBox.expand(),
    );
    final stack = tester
        .widgetList<Stack>(
          find.descendant(
            of: find.byType(MemoryCollageCanvasView),
            matching: find.byType(Stack),
          ),
        )
        .single;
    final plateIndex = stack.children.indexWhere(
      (child) =>
          child is Positioned &&
          child.child is Image &&
          (child.child as Image).image ==
              memoryCollageAssetProvider(template.plateAssetID),
    );
    final titleIndex = stack.children.indexWhere(
      (child) =>
          child is Positioned &&
          find
              .descendant(
                of: find.byWidget(child),
                matching: find.byKey(
                  const ValueKey("memory-collage-title-bounds"),
                ),
              )
              .evaluate()
              .isNotEmpty,
    );
    final firstFinishIndex = stack.children.indexWhere(
      (child) =>
          child is Positioned &&
          child.child.runtimeType.toString().contains("_BlendAssetImage"),
    );
    expect(plateIndex, isNonNegative);
    expect(titleIndex, greaterThan(plateIndex));
    expect(firstFinishIndex, greaterThan(titleIndex));
  });

  testWidgets("rejects six photos before rendering", (tester) async {
    final template = manifest.defaultTemplate;
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryCollageCanvasView(
          manifest: manifest,
          files: List.generate(6, (_) => EnteFile()),
          title: "AUGUST 2026",
          backgroundAssetID: template.defaultBackgroundAssetID,
          photoBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
    expect(
      tester.takeException(),
      isA<StateError>().having(
        (error) => error.toString(),
        "message",
        contains("Memory collage requires 7 photos, got 6"),
      ),
    );
  });

  testWidgets("uses the manifest default template when none is supplied", (
    tester,
  ) async {
    await verifyMemoryCollageCanvas(tester, manifest: manifest);
  });

  for (final templateID in _titleTemplateIDs) {
    testWidgets("$templateID keeps a short title at its preferred size", (
      tester,
    ) async {
      const title = "JOY";
      await verifyMemoryCollageCanvas(
        tester,
        manifest: manifest,
        templateID: templateID,
        titleText: title,
      );
      final template = manifest.templateFor(templateID);
      final rendered = tester.widget<Text>(find.text(title));
      expect(rendered.maxLines, 1);
      expect(rendered.style!.fontFamily, template.title.fontFamily);
      expect(
        rendered.style!.fontSize,
        template.title.fontSize / memoryCollageExportPixelRatio,
      );
    });

    testWidgets("$templateID shrinks a very long title until it fits", (
      tester,
    ) async {
      await verifyMemoryCollageCanvas(
        tester,
        manifest: manifest,
        templateID: templateID,
        titleText: _veryLongTitle,
      );
      final template = manifest.templateFor(templateID);
      final rendered = tester.widget<Text>(find.text(_veryLongTitle));
      expect(rendered.maxLines, template.title.maxLines);
      expect(
        rendered.style!.fontSize,
        lessThan(template.title.minFontSize / memoryCollageExportPixelRatio),
      );
    });
  }

  testWidgets("normalizes title line breaks without dropping words", (
    tester,
  ) async {
    const titleWithBreaks = "August\r\nthrough\n\nthe\u000Byears";
    const normalized = "August through the years";
    await verifyMemoryCollageCanvas(
      tester,
      manifest: manifest,
      templateID: "scrapbook-maximal",
      titleText: titleWithBreaks,
    );
    expect(find.text(titleWithBreaks), findsNothing);
    expect(find.text(normalized), findsOneWidget);
  });

  testWidgets("rejects an unknown background", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryCollageCanvasView(
          manifest: manifest,
          files: List.generate(7, (_) => EnteFile()),
          title: "AUGUST 2026",
          backgroundAssetID: "missing",
          photoBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
    expect(
      () => memoryCollageRequiredAssetIDs(manifest, "missing"),
      throwsArgumentError,
    );
  });

  test("parses the authored color formats", () {
    expect(parseMemoryCollageColor("#E7E1D4"), const Color(0xFFE7E1D4));
    expect(
      parseMemoryCollageColor("rgba(90,40,15,0.5)"),
      const Color.fromRGBO(90, 40, 15, 0.5),
    );
  });
}

Future<void> _pumpCanvas(
  WidgetTester tester, {
  required MemoryCollageManifest manifest,
  required String templateID,
  String? backgroundAssetID,
  required MemoryCollagePhotoBuilder photoBuilder,
}) async {
  final template = manifest.templateFor(templateID);
  await tester.pumpWidget(
    MaterialApp(
      home: MemoryCollageCanvasView(
        manifest: manifest,
        files: List.generate(7, (_) => EnteFile()),
        title: "AUGUST 2026",
        backgroundAssetID:
            backgroundAssetID ?? template.defaultBackgroundAssetID,
        templateID: templateID,
        photoBuilder: photoBuilder,
      ),
    ),
  );
  await tester.pump();
}

Finder _blendPaints() {
  return find.descendant(
    of: find.byType(MemoryCollageCanvasView),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == "_BlendAssetPainter",
    ),
  );
}

const _templateIDs = [
  "scrapbook-maximal",
  "calm-classic",
  "calm-film-trio",
  "calm-accent-print",
  "minimal-classic",
  "minimal-rows",
  "minimal-grid",
];

const _titleTemplateIDs = [
  "scrapbook-maximal",
  "calm-film-trio",
  "minimal-rows",
];

const _editorialBackgrounds = {"editorial-sand", "editorial-sage"};

const _veryLongTitle =
    "An extraordinarily long collection of memories from our family journey "
    "through Thiruvananthapuram, Reykjavík, and San Francisco across many "
    "wonderful years";
