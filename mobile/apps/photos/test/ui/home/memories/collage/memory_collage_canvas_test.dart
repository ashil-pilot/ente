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
  late MemoryCollageManifest editorialManifest;

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
    editorialManifest = _manifestWithEditorialTestTemplate(sourceJson);
  });

  test("declares the exact seven-photo runtime template contracts", () {
    expect(
      manifest.templates.map((template) => template.id),
      _runtimeTemplateIDs,
    );
    for (final templateID in _runtimeTemplateIDs) {
      final template = manifest.templateFor(templateID);
      expect(
        template.photoSlots.map((slot) => slot.slot),
        List.generate(7, (index) => index),
      );
      expect(
        template.background.assetIDs,
        _backgroundAssetIDsByTemplate[templateID],
      );

      for (final backgroundAssetID in template.background.assetIDs) {
        final expectedAssetIDs = {
          backgroundAssetID,
          for (final layer in template.layers)
            if (layer.layerID != template.background.layerID &&
                layer.appliesToBackground(backgroundAssetID))
              layer.assetID,
        };
        expect(
          memoryCollageRequiredAssetIDs(
            manifest,
            backgroundAssetID,
            templateID: templateID,
          ),
          expectedAssetIDs,
        );
      }
    }
  });

  testWidgets("uses material-aware empty photo colors", (tester) async {
    final expectedColorsByTemplate = {
      "scrapbook-maximal": [
        const Color(0xFF3A2A1C),
        const Color(0xFF3A2A1C),
        const Color(0xFF3A2A1C),
        const Color(0xFF2E2318),
        const Color(0xFF2E2318),
        const Color(0xFF2E2318),
        const Color(0xFF3A2A1C),
      ],
      "scrapbook-calm": [
        const Color(0xFF2E2318),
        const Color(0xFF2E2318),
        const Color(0xFF2E2318),
        const Color(0xFF33241A),
        const Color(0xFF33241A),
        const Color(0xFF33241A),
        const Color(0xFF33241A),
      ],
      "minimal-editorial": List.filled(7, const Color(0xFFE7E1D4)),
    };

    for (final templateID in _runtimeTemplateIDs) {
      final template = manifest.templateFor(templateID);
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryCollageCanvasView(
            manifest: manifest,
            files: List.generate(7, (_) => EnteFile()),
            title: "AUGUST 2026",
            backgroundAssetID: template.background.defaultAssetID,
            templateID: templateID,
            photoBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );

      final colors = <Color>[
        for (var slot = 0; slot < 7; slot++)
          tester
              .widget<ColoredBox>(
                find.byKey(ValueKey("memory-collage-photo-backing-$slot")),
              )
              .color,
      ];
      expect(colors, expectedColorsByTemplate[templateID]);
    }
  });

  for (final templateID in _runtimeTemplateIDs) {
    testWidgets(
      "$templateID renders its seven-photo runtime contract",
      (tester) => verifyMemoryCollageCanvas(
        tester,
        loadedManifest: manifest,
        templateID: templateID,
        expectedRequiredAssetIDs: _requiredAssetIDsByTemplate[templateID],
        minimumEncodedByteLength: templateID == "scrapbook-maximal"
            ? 500000
            : 1000,
      ),
    );

    testWidgets("$templateID rejects six photos", (tester) async {
      final template = manifest.templateFor(templateID);
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryCollageCanvasView(
            manifest: manifest,
            files: List.generate(6, (_) => EnteFile()),
            title: "AUGUST 2026",
            backgroundAssetID: template.background.defaultAssetID,
            templateID: templateID,
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
  }

  testWidgets("uses the manifest default when no template is specified", (
    tester,
  ) async {
    await verifyMemoryCollageCanvas(
      tester,
      loadedManifest: manifest,
      verifyRasterOutput: false,
    );
  });

  for (final templateID in _runtimeTemplateIDs) {
    testWidgets("$templateID keeps a short title at its preferred size", (
      tester,
    ) async {
      const shortTitle = "JOY";
      await _verifyTitleLayout(
        tester,
        manifest: manifest,
        templateID: templateID,
        title: shortTitle,
      );

      final template = manifest.templateFor(templateID);
      final renderedTitle = tester.widget<Text>(find.text(shortTitle));
      expect(renderedTitle.maxLines, 1);
      expect(renderedTitle.softWrap, isTrue);
      expect(renderedTitle.textWidthBasis, TextWidthBasis.parent);
      expect(renderedTitle.style!.inherit, isFalse);
      expect(renderedTitle.style!.fontFamily, template.titleStyle.fontFamily);
      expect(
        renderedTitle.style!.fontWeight,
        _expectedFontWeight(template.titleStyle.fontWeight),
      );
      expect(
        renderedTitle.style!.fontStyle,
        template.titleStyle.fontStyle == "italic"
            ? FontStyle.italic
            : FontStyle.normal,
      );
      expect(renderedTitle.style!.height, template.titleStyle.lineHeight);
      expect(
        renderedTitle.style!.fontSize,
        template.titleStyle.fontSize / memoryCollageExportPixelRatio,
      );
      _expectProportionallyScaledTitleStyle(
        renderedTitle.style!,
        template.titleStyle,
      );

      if (templateID == "scrapbook-maximal") {
        expect(
          tester.getSize(
            find.byKey(const ValueKey("memory-collage-title-bounds")),
          ),
          const Size(206, 38),
        );
      }
    });

    testWidgets("$templateID shrinks a very long title below its size floor", (
      tester,
    ) async {
      await _verifyTitleLayout(
        tester,
        manifest: manifest,
        templateID: templateID,
        title: _veryLongTitle,
      );

      final template = manifest.templateFor(templateID);
      final renderedTitle = tester.widget<Text>(find.text(_veryLongTitle));
      expect(renderedTitle.maxLines, template.titleStyle.maxLines);
      expect(
        renderedTitle.style!.fontSize,
        lessThan(
          template.titleStyle.minFontSize / memoryCollageExportPixelRatio,
        ),
      );
      _expectProportionallyScaledTitleStyle(
        renderedTitle.style!,
        template.titleStyle,
      );
    });

    testWidgets("$templateID fits an unbroken non-Latin title", (tester) async {
      await _verifyTitleLayout(
        tester,
        manifest: manifest,
        templateID: templateID,
        title: _unbrokenNonLatinTitle,
      );

      final template = manifest.templateFor(templateID);
      final renderedTitle = tester.widget<Text>(
        find.text(_unbrokenNonLatinTitle),
      );
      expect(
        renderedTitle.style!.fontSize,
        lessThan(
          template.titleStyle.minFontSize / memoryCollageExportPixelRatio,
        ),
      );
    });
  }

  testWidgets("normalizes title line breaks without dropping words", (
    tester,
  ) async {
    const titleWithBreaks =
        "August\r\nthrough\n\nthe\u000Byears\u000Cwe\u0085remember\u2028with\u2029joy";
    const normalizedTitle = "August through the years we remember with joy";
    await _verifyTitleLayout(
      tester,
      manifest: manifest,
      templateID: "scrapbook-maximal",
      title: titleWithBreaks,
    );

    expect(find.text(titleWithBreaks), findsNothing);
    expect(find.text(normalizedTitle), findsOneWidget);
  });

  testWidgets("minimal editorial uses its dark title and rule colors", (
    tester,
  ) async {
    await verifyMemoryCollageCanvas(
      tester,
      loadedManifest: manifest,
      templateID: "minimal-editorial",
      backgroundAssetIDOverride: "editorial-charcoal",
      expectedRequiredAssetIDs: const {"editorial-charcoal", "grain-overlay"},
      minimumEncodedByteLength: 1000,
    );
  });

  testWidgets("minimal editorial retains flat-background grain and rules", (
    tester,
  ) async {
    await verifyMemoryCollageCanvas(
      tester,
      loadedManifest: manifest,
      templateID: "minimal-editorial",
      backgroundAssetIDOverride: "editorial-sand",
      expectedRequiredAssetIDs: const {"editorial-sand", "grain-overlay"},
      minimumEncodedByteLength: 1000,
    );
  });

  testWidgets("calm long titles wrap only at the configured size floor", (
    tester,
  ) async {
    const longTitle = "Trip to Pondicherry 2024";
    await verifyMemoryCollageCanvas(
      tester,
      loadedManifest: manifest,
      templateID: "scrapbook-calm",
      titleText: longTitle,
    );

    final title = tester.widget<Text>(find.text(longTitle));
    expect(title.maxLines, 2);
    expect(
      title.style!.fontSize,
      manifest.templateFor("scrapbook-calm").titleStyle.minFontSize /
          memoryCollageExportPixelRatio,
    );
  });

  testWidgets("lays out direct photo and title placements", (tester) async {
    await verifyMemoryCollageCanvas(
      tester,
      loadedManifest: editorialManifest,
      templateID: "editorial-test",
    );
  });

  test("required assets default to the manifest's default template", () {
    final defaultTemplate = manifest.defaultTemplate;
    final defaultAssetIDs = memoryCollageRequiredAssetIDs(
      manifest,
      defaultTemplate.background.defaultAssetID,
    );
    for (final template in manifest.templates) {
      final explicitAssetIDs = memoryCollageRequiredAssetIDs(
        manifest,
        template.background.defaultAssetID,
        templateID: template.id,
      );
      expect(explicitAssetIDs, {
        template.background.defaultAssetID,
        for (final layer in template.layers)
          if (layer.layerID != template.background.layerID &&
              layer.appliesToBackground(template.background.defaultAssetID))
            layer.assetID,
      });
      if (template.id == manifest.defaultTemplateID) {
        expect(defaultAssetIDs, explicitAssetIDs);
      }
    }
    expect(
      () =>
          memoryCollageRequiredAssetIDs(manifest, "not-a-template-background"),
      throwsArgumentError,
    );
  });

  testWidgets("rejects a background outside the selected template", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryCollageCanvasView(
          manifest: manifest,
          files: List.generate(
            manifest.defaultTemplate.photoSlots.length,
            (_) => EnteFile(),
          ),
          title: "AUGUST 2026",
          backgroundAssetID: "not-a-template-background",
          photoBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
  });

  test("parses the authored CSS color formats", () {
    expect(parseMemoryCollageColor("#f4e7cf"), const Color(0xFFF4E7CF));
    expect(
      parseMemoryCollageColor("rgba(90,40,15,0.5)"),
      const Color.fromRGBO(90, 40, 15, 0.5),
    );
  });
}

const _runtimeTemplateIDs = [
  "scrapbook-maximal",
  "scrapbook-calm",
  "minimal-editorial",
];

const _veryLongTitle =
    "An extraordinarily long collection of memories from our family journey "
    "through Thiruvananthapuram, Reykjavík, and San Francisco across many "
    "wonderful years";

const _unbrokenNonLatinTitle =
    "तिरुवनंतपुरमकीअविस्मरणीयपारिवारिकयात्राओंकीयादें"
    "तिरुवनंतपुरमकीअविस्मरणीयपारिवारिकयात्राओंकीयादें"
    "तिरुवनंतपुरमकीअविस्मरणीयपारिवारिकयात्राओंकीयादें";

const _requiredAssetIDsByTemplate = <String, Set<String>>{
  "scrapbook-maximal": {
    "paper-washi",
    "paper-torn",
    "coffee-ring",
    "fern",
    "star",
    "film-strip-four",
    "polaroid-frame",
    "banner-wide",
    "tape-mustard",
    "tape-blush",
    "tape-sage",
    "stamp-postmark",
    "sun-streak",
    "vignette",
    "grain-overlay",
  },
  "scrapbook-calm": {
    "paper-cream-fiber",
    "fern",
    "film-strip-four-horizontal",
    "print-frame-hero",
    "polaroid-frame",
    "tape-blush",
    "tape-sage",
    "stamp-postmark",
    "sun-streak",
    "vignette",
    "grain-overlay",
  },
  "minimal-editorial": {"paper-cream-fiber"},
};

const _backgroundAssetIDsByTemplate = <String, List<String>>{
  "scrapbook-maximal": [
    "paper-washi",
    "paper-cream-fiber",
    "paper-blush-stripe",
    "paper-sage-stripe",
    "paper-terracotta-mottle",
  ],
  "scrapbook-calm": [
    "paper-washi",
    "paper-cream-fiber",
    "paper-blush-stripe",
    "paper-sage-stripe",
  ],
  "minimal-editorial": [
    "paper-cream-fiber",
    "editorial-sand",
    "editorial-sage",
    "editorial-charcoal",
  ],
};

Future<void> _verifyTitleLayout(
  WidgetTester tester, {
  required MemoryCollageManifest manifest,
  required String templateID,
  required String title,
}) {
  return verifyMemoryCollageCanvas(
    tester,
    loadedManifest: manifest,
    templateID: templateID,
    titleText: title,
    verifyRasterOutput: false,
  );
}

void _expectProportionallyScaledTitleStyle(
  TextStyle rendered,
  MemoryCollageTitleStyle authored,
) {
  final preferredFontSize = authored.fontSize / memoryCollageExportPixelRatio;
  final scale = rendered.fontSize! / preferredFontSize;
  expect(
    rendered.letterSpacing,
    closeTo(
      authored.letterSpacing / memoryCollageExportPixelRatio * scale,
      0.000001,
    ),
  );
  expect(rendered.shadows, hasLength(1));
  final shadow = rendered.shadows!.single;
  expect(
    shadow.offset.dx,
    closeTo(
      authored.shadow.dx / memoryCollageExportPixelRatio * scale,
      0.000001,
    ),
  );
  expect(
    shadow.offset.dy,
    closeTo(
      authored.shadow.dy / memoryCollageExportPixelRatio * scale,
      0.000001,
    ),
  );
  expect(
    shadow.blurRadius,
    closeTo(
      authored.shadow.blur / memoryCollageExportPixelRatio * scale,
      0.000001,
    ),
  );
}

FontWeight _expectedFontWeight(int weight) => switch (weight) {
  100 => FontWeight.w100,
  200 => FontWeight.w200,
  300 => FontWeight.w300,
  400 => FontWeight.w400,
  500 => FontWeight.w500,
  600 => FontWeight.w600,
  700 => FontWeight.w700,
  800 => FontWeight.w800,
  900 => FontWeight.w900,
  _ => FontWeight.normal,
};

MemoryCollageManifest _manifestWithEditorialTestTemplate(
  Map<String, dynamic> sourceJson,
) {
  final decoded = jsonDecode(jsonEncode(sourceJson)) as Map<String, dynamic>;
  final templates = List<Map<String, dynamic>>.from(
    (decoded["templates"] as List).map(
      (value) => Map<String, dynamic>.from(value as Map),
    ),
  );
  final editorial =
      jsonDecode(jsonEncode(templates.first)) as Map<String, dynamic>;
  editorial["id"] = "editorial-test";
  editorial["photoSlots"] = [
    _rectSlot(0, x: 60, y: 420, rotation: -4),
    _rectSlot(1, x: 405, y: 420, rotation: 2),
    _rectSlot(2, x: 750, y: 420, rotation: -2),
    _rectSlot(3, x: 60, y: 870, rotation: 3),
    _rectSlot(4, x: 405, y: 870, rotation: -3),
    _rectSlot(5, x: 750, y: 870, rotation: 4),
    _rectSlot(6, x: 300, y: 1320, width: 480, height: 390, rotation: -1),
  ];
  final titleStyle = Map<String, dynamic>.from(editorial["titleStyle"] as Map);
  titleStyle
    ..["placement"] = {
      "kind": "rect",
      "x": 60,
      "y": 1710,
      "width": 960,
      "height": 150,
      "z": 40,
      "rotation": 0,
    }
    ..["fontStyle"] = "italic"
    ..["textAlign"] = "left"
    ..["verticalAlign"] = "bottom";
  editorial["titleStyle"] = titleStyle;
  decoded["templates"] = [...templates, editorial];
  return MemoryCollageManifest.fromJson(decoded);
}

Map<String, dynamic> _rectSlot(
  int slot, {
  required int x,
  required int y,
  int width = 270,
  int height = 360,
  required double rotation,
}) => {
  "slot": slot,
  "kind": "rect",
  "x": x,
  "y": y,
  "width": width,
  "height": height,
  "z": 5 + slot,
  "rotation": rotation,
  "radius": 24,
  "border": {"width": 9, "color": "#f4e7cf"},
  "shadows": [
    {
      "kind": "dropShadow",
      "dx": 0,
      "dy": 12,
      "blur": 24,
      "color": "rgba(80,40,15,0.35)",
    },
  ],
};
