import "dart:convert";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> sourceJson;
  late MemoryCollageManifest manifest;

  setUpAll(() async {
    sourceJson =
        jsonDecode(await rootBundle.loadString(memoryCollageManifestAsset))
            as Map<String, dynamic>;
    manifest = MemoryCollageManifest.fromJson(sourceJson);
  });

  test("loads the v2 template collection contract", () {
    expect(manifest.version, 2);
    expect(manifest.canvas.width, 1080);
    expect(manifest.canvas.height, 1920);
    expect(manifest.assets, hasLength(24));
    expect(manifest.backgroundAssets, hasLength(8));
    expect(manifest.defaultTemplateID, "scrapbook-calm");
    expect(manifest.templates.map((template) => template.id), [
      "scrapbook-maximal",
      "scrapbook-calm",
      "minimal-editorial",
    ]);
    expect(
      manifest.templateFor("scrapbook-calm"),
      same(manifest.defaultTemplate),
    );
    expect(manifest.defaultTemplate.layers, hasLength(12));
    expect(manifest.templateFor("scrapbook-maximal").layers, hasLength(17));
    for (final template in manifest.templates) {
      expect(template.photoSlots, hasLength(7));
    }
  });

  test("scopes ordered background choices to the template", () {
    final background = manifest.templateFor("scrapbook-maximal").background;

    expect(background.layerID, "bg");
    expect(background.defaultAssetID, "paper-washi");
    expect(background.assetIDs, [
      "paper-washi",
      "paper-cream-fiber",
      "paper-blush-stripe",
      "paper-sage-stripe",
      "paper-terracotta-mottle",
    ]);
    for (final assetID in background.assetIDs) {
      expect(
        manifest.assetFor(assetID).role,
        MemoryCollageAssetRole.background,
      );
    }
  });

  test("sorts layers by z and preserves source order for ties", () {
    final layers = manifest.templateFor("scrapbook-maximal").layers;

    for (var index = 1; index < layers.length; index++) {
      expect(layers[index - 1].z, lessThanOrEqualTo(layers[index].z));
    }
    expect(
      layers.where((layer) => layer.z == 15).map((layer) => layer.layerID),
      orderedEquals(["tapeB", "tapeC"]),
    );
    expect(
      layers.where((layer) => layer.z == 17).map((layer) => layer.layerID),
      orderedEquals(["tapeA", "stamp"]),
    );
  });

  test("every template resolves seven unique photo slots", () {
    for (final template in manifest.templates) {
      for (final layer in template.layers) {
        expect(() => manifest.assetFor(layer.assetID), returnsNormally);
      }
      expect(
        template.photoSlots.map((slot) => slot.slot),
        orderedEquals(List.generate(7, (index) => index)),
      );
      for (final slot in template.photoSlots) {
        if (slot is! MemoryCollageAssetWindowPhotoSlot) continue;
        final layer = template.layerFor(slot.layerID);
        final asset = manifest.assetFor(layer.assetID);
        expect(asset.emptyWindowColor, isNotEmpty);
        expect(
          slot.windowIndex,
          inInclusiveRange(0, asset.photoWindows.length - 1),
        );
      }
    }
  });

  test("parses the exact seven-photo layout", () {
    expect(
      manifest.templateFor("scrapbook-maximal").photoSlots.map(_slotContract),
      orderedEquals([
        (0, "strip", 0),
        (1, "strip", 1),
        (2, "strip", 2),
        (3, "p1", 0),
        (4, "p2", 0),
        (5, "p3", 0),
        (6, "strip", 3),
      ]),
    );
    expect(
      manifest.templateFor("scrapbook-maximal").layerFor("strip").assetID,
      "film-strip-four",
    );
  });

  test("parses the four-frame film and polaroid windows", () {
    final filmWindows = manifest.assetFor("film-strip-four").photoWindows;
    final polaroidWindows = manifest.assetFor("polaroid-frame").photoWindows;

    expect(filmWindows, hasLength(4));
    expect(filmWindows.map((window) => window.y), [69, 453, 837, 1221]);
    for (final window in filmWindows) {
      expect(window.x, 57);
      expect(window.width, 276);
      expect(window.height, 318);
    }
    expect(() => manifest.assetFor("film-strip"), throwsFormatException);
    expect(polaroidWindows, hasLength(1));
    expect(polaroidWindows.single.width, 414);
    expect(polaroidWindows.single.height, 420);
  });

  test("parses the wider maximal banner and explicit title safe rect", () {
    final template = manifest.templateFor("scrapbook-maximal");
    final title = template.titleStyle;
    final bannerAsset = manifest.assetFor("banner-wide");
    final bannerLayer = template.layerFor("banner");
    final tape = template.layerFor("tapeA");
    final stamp = template.layerFor("stamp");

    expect((bannerAsset.width, bannerAsset.height), (900, 150));
    expect(bannerAsset.safetyMarginPx, 18);
    expect(() => manifest.assetFor("banner"), throwsFormatException);
    expect(bannerLayer.assetID, "banner-wide");
    expect(
      (
        bannerLayer.x,
        bannerLayer.y,
        bannerLayer.width,
        bannerLayer.height,
        bannerLayer.rotation,
      ),
      (90, 180, 900, 150, -2.5),
    );
    expect((tape.x, tape.y), (54, 120));
    expect((stamp.x, stamp.y), (786, 114));

    expect(title.placement, isA<MemoryCollageTitleRect>());
    final titlePlacement = title.placement as MemoryCollageTitleRect;
    expect(
      (
        titlePlacement.rect.x,
        titlePlacement.rect.y,
        titlePlacement.rect.width,
        titlePlacement.rect.height,
      ),
      (144, 198, 618, 114),
    );
    expect(titlePlacement.z, 20);
    expect(titlePlacement.rotation, -2.5);
    expect(title.fontFamily, "Lora");
    expect(title.fontWeight, 600);
    expect(title.fontSize, 45);
    expect(title.minFontSize, 27);
    expect(title.maxLines, 1);
    expect(title.letterSpacing, 12);
    expect(title.memoryTitleCasing, "preserve");
    expect(template.layerFor("sunStreak").blendMode, "soft-light");
    expect(template.layerFor("vignette").blendMode, "multiply");
    expect(template.layerFor("grain").blendMode, "overlay");
    expect(template.layerFor("grain").opacity, 0.55);
  });

  test("parses calm and richer minimal editorial template contracts", () {
    final calm = manifest.templateFor("scrapbook-calm");
    final minimal = manifest.templateFor("minimal-editorial");

    expect(calm.titleStyle.fontFamily, "Lora");
    expect(calm.titleStyle.fontAsset, "fonts/Lora-SemiBold.ttf");
    expect(calm.titleStyle.fontStyle, "normal");
    expect(calm.titleStyle.fontWeight, 600);
    expect(calm.titleStyle.fontSize, 96);
    expect(calm.titleStyle.minFontSize, 60);
    expect(calm.titleStyle.maxLines, 2);
    expect(calm.titleStyle.lineHeight, 1.06);
    expect(calm.titleStyle.letterSpacing, -0.5);
    expect(
      (calm.titleStyle.placement as MemoryCollageTitleRect).rotation,
      -1.5,
    );
    expect(calm.background.defaultAssetID, "paper-cream-fiber");
    expect(calm.background.assetIDs, [
      "paper-washi",
      "paper-cream-fiber",
      "paper-blush-stripe",
      "paper-sage-stripe",
    ]);
    expect(
      () => manifest.assetFor("paper-notebook-blush"),
      throwsFormatException,
    );
    expect(
      () => manifest.assetFor("paper-notebook-sage"),
      throwsFormatException,
    );
    expect(
      calm.photoSlots.whereType<MemoryCollageAssetWindowPhotoSlot>(),
      hasLength(7),
    );

    expect(minimal.titleStyle.fontFamily, "Inter");
    expect(minimal.titleStyle.fontAsset, "fonts/Inter-Medium.ttf");
    expect(minimal.titleStyle.fontStyle, "normal");
    expect(minimal.titleStyle.fontWeight, 500);
    expect(minimal.titleStyle.minFontSize, 66);
    expect(minimal.titleStyle.maxLines, 2);
    expect(minimal.titleStyle.colorOnDark, "#f2ede2");
    expect(minimal.background.defaultAssetID, "paper-cream-fiber");
    expect(minimal.background.assetIDs, [
      "paper-cream-fiber",
      "editorial-sand",
      "editorial-sage",
      "editorial-charcoal",
    ]);
    expect(() => manifest.assetFor("editorial-bone"), throwsFormatException);
    expect(() => manifest.assetFor("editorial-paper"), throwsFormatException);
    expect(minimal.rules, hasLength(2));
    expect(
      minimal.rules.map(
        (rule) => (
          rule.rect.x,
          rule.rect.y,
          rule.rect.width,
          rule.rect.height,
          rule.color,
          rule.colorOnDark,
        ),
      ),
      orderedEquals([
        (78, 288, 924, 3, "#cfc5ae", "rgba(244,240,232,0.3)"),
        (78, 1842, 924, 3, "#cfc5ae", "rgba(244,240,232,0.3)"),
      ]),
    );
    for (final rule in minimal.rules) {
      expect(rule.colorsByBackground, {
        "editorial-sand": "#d8cfbc",
        "editorial-sage": "#d8cfbc",
      });
    }
    expect(
      minimal.photoSlots.whereType<MemoryCollageMattedRectPhotoSlot>(),
      hasLength(7),
    );
    expect(
      minimal.photoSlots.map((slot) {
        final matted = slot as MemoryCollageMattedRectPhotoSlot;
        return (
          matted.matRect.x,
          matted.matRect.y,
          matted.matRect.width,
          matted.matRect.height,
        );
      }),
      orderedEquals([
        (78, 390, 924, 798),
        (78, 1212, 450, 318),
        (552, 1212, 450, 318),
        (78, 1554, 213, 252),
        (315, 1554, 213, 252),
        (552, 1554, 213, 252),
        (789, 1554, 213, 252),
      ]),
    );
    for (final slot
        in minimal.photoSlots.whereType<MemoryCollageMattedRectPhotoSlot>()) {
      expect(slot.photoRect.x, slot.matRect.x + 15);
      expect(slot.photoRect.y, slot.matRect.y + 15);
      expect(slot.photoRect.width, slot.matRect.width - 30);
      expect(slot.photoRect.height, slot.matRect.height - 30);
      expect(slot.z, 4);
      expect(slot.rotation, 0);
      expect(slot.radius ?? 0, 0);
    }
    expect(minimal.matStyle, isNotNull);
    expect(minimal.matStyle!.fill, "#faf6ec");
    expect(minimal.matStyle!.fillOnDark, "#faf6ec");
    expect(minimal.matStyle!.photoFill, "#e7e1d4");
    expect(minimal.matStyle!.photoInset, 15);
    expect(minimal.matStyle!.border.width, 3);
    expect(minimal.matStyle!.border.color, "rgba(90,75,55,0.20)");
    expect(minimal.matStyle!.shadows, hasLength(1));
    final matShadow = minimal.matStyle!.shadows.single;
    expect(
      (
        matShadow.kind,
        matShadow.dx,
        matShadow.dy,
        matShadow.blur,
        matShadow.color,
      ),
      ("dropShadow", 0, 3, 9, "rgba(90,70,45,0.12)"),
    );
    final titlePlacement =
        minimal.titleStyle.placement as MemoryCollageTitleRect;
    expect(
      (
        titlePlacement.rect.x,
        titlePlacement.rect.y,
        titlePlacement.rect.width,
        titlePlacement.rect.height,
      ),
      (78, 84, 924, 186),
    );
    expect(minimal.titleStyle.fontSize, 102);
    expect(minimal.titleStyle.lineHeight, 1.04);
    expect(minimal.titleStyle.letterSpacing, -1.5);
    expect(minimal.titleStyle.color, "#24201a");
    final grain = minimal.layerFor("grain");
    expect(grain.assetID, "grain-overlay");
    expect((grain.x, grain.y, grain.width, grain.height), (0, 0, 1080, 1920));
    expect(grain.blendMode, "overlay");
    expect(grain.opacity, 0.12);
    expect(grain.backgroundAssetIDs, [
      "editorial-sand",
      "editorial-sage",
      "editorial-charcoal",
    ]);
    expect(grain.appliesToBackground("paper-cream-fiber"), isFalse);
    expect(grain.appliesToBackground("editorial-sand"), isTrue);
    expect(
      minimal.photoSlots.whereType<MemoryCollageMattedRectPhotoSlot>().every(
        (slot) => slot.z < 10,
      ),
      isTrue,
    );
    expect(minimal.rules.every((rule) => rule.z == 10), isTrue);
    expect(titlePlacement.z, 20);
    expect(grain.z, 38);
    final minimalJson = _template(sourceJson, "minimal-editorial");
    for (final slot in minimalJson["photoSlots"]! as List<dynamic>) {
      final slotJson = slot as Map<String, dynamic>;
      expect(slotJson["kind"], "mattedRect");
      expect(slotJson, isNot(contains("shadows")));
    }
    expect(manifest.assetFor("editorial-charcoal").dark, isTrue);
  });

  test("parses direct rect photo and title placements", () {
    final json = _copyJson(sourceJson);
    final template = _firstTemplate(json);
    final slots = template["photoSlots"]! as List<dynamic>;
    slots[0] = {
      "slot": 0,
      "kind": "rect",
      "x": 60,
      "y": 90,
      "width": 300,
      "height": 420,
      "z": 11,
      "rotation": -3,
      "radius": 18,
      "border": {"width": 12, "color": "#ffffff"},
      "shadows": [
        {"dx": 0, "dy": 9, "blur": 18, "color": "rgba(0,0,0,0.2)"},
      ],
    };
    final titleStyle = template["titleStyle"]! as Map<String, dynamic>;
    titleStyle["placement"] = {
      "kind": "rect",
      "x": 120,
      "y": 90,
      "width": 840,
      "height": 150,
      "z": 20,
      "rotation": 1,
    };

    final parsed = MemoryCollageManifest.fromJson(json);
    final parsedTemplate = parsed.templateFor("scrapbook-maximal");
    final rectSlot =
        parsedTemplate.photoSlots.first as MemoryCollageRectPhotoSlot;
    final titleRect =
        parsedTemplate.titleStyle.placement as MemoryCollageTitleRect;

    expect(rectSlot.rect.width, 300);
    expect(rectSlot.z, 11);
    expect(rectSlot.rotation, -3);
    expect(rectSlot.radius, 18);
    expect(rectSlot.border?.width, 12);
    expect(rectSlot.shadows, hasLength(1));
    expect(titleRect.rect.width, 840);
    expect(titleRect.z, 20);
    expect(titleRect.rotation, 1);
  });

  test("exposes immutable manifest collections", () {
    final template = manifest.defaultTemplate;
    expect(
      () => manifest.assets.add(manifest.assets.first),
      throwsUnsupportedError,
    );
    expect(() => manifest.templates.add(template), throwsUnsupportedError);
    expect(
      () => template.background.assetIDs.add("another-background"),
      throwsUnsupportedError,
    );
    expect(
      () => template.layers.add(template.layers.first),
      throwsUnsupportedError,
    );
    expect(
      () => template.photoSlots.add(template.photoSlots.first),
      throwsUnsupportedError,
    );
    final minimal = manifest.templateFor("minimal-editorial");
    expect(
      () => minimal.rules.add(minimal.rules.first),
      throwsUnsupportedError,
    );
    expect(
      () => minimal.matStyle!.shadows.add(minimal.matStyle!.shadows.first),
      throwsUnsupportedError,
    );
    expect(
      () =>
          minimal.rules.first.colorsByBackground["editorial-sand"] = "#ffffff",
      throwsUnsupportedError,
    );
    expect(
      () => minimal.layerFor("grain").backgroundAssetIDs!.add("paper-washi"),
      throwsUnsupportedError,
    );
  });

  group("v2 validation", () {
    test("rejects unsupported versions and duplicate IDs", () {
      final oldVersion = _copyJson(sourceJson)..["version"] = 1;
      expect(
        () => MemoryCollageManifest.fromJson(oldVersion),
        throwsFormatException,
      );

      final duplicateAsset = _copyJson(sourceJson);
      final assets = duplicateAsset["assets"]! as List<dynamic>;
      assets.add(_copyJson(assets.first as Map<String, dynamic>));
      expect(
        () => MemoryCollageManifest.fromJson(duplicateAsset),
        throwsFormatException,
      );

      final duplicateTemplate = _copyJson(sourceJson);
      final templates = duplicateTemplate["templates"]! as List<dynamic>;
      templates.add(_copyJson(templates.first as Map<String, dynamic>));
      expect(
        () => MemoryCollageManifest.fromJson(duplicateTemplate),
        throwsFormatException,
      );
    });

    test("rejects missing template, layer, and asset references", () {
      final missingDefault = _copyJson(sourceJson)
        ..["defaultTemplateId"] = "missing";
      expect(
        () => MemoryCollageManifest.fromJson(missingDefault),
        throwsFormatException,
      );

      final missingAsset = _copyJson(sourceJson);
      final layer =
          (_firstTemplate(missingAsset)["layers"]! as List<dynamic>).last
              as Map<String, dynamic>;
      layer["asset"] = "missing";
      expect(
        () => MemoryCollageManifest.fromJson(missingAsset),
        throwsFormatException,
      );

      final missingLayer = _copyJson(sourceJson);
      final slot =
          (_firstTemplate(missingLayer)["photoSlots"]! as List<dynamic>)[0]
              as Map<String, dynamic>;
      slot["layerId"] = "missing";
      expect(
        () => MemoryCollageManifest.fromJson(missingLayer),
        throwsFormatException,
      );
    });

    test("rejects invalid scoped backgrounds", () {
      final missingBackground = _copyJson(sourceJson);
      final background =
          _firstTemplate(missingBackground)["background"]!
              as Map<String, dynamic>;
      (background["assetIds"]! as List<dynamic>).add("missing");
      expect(
        () => MemoryCollageManifest.fromJson(missingBackground),
        throwsFormatException,
      );

      final nonBackground = _copyJson(sourceJson);
      final nonBackgroundConfig =
          _firstTemplate(nonBackground)["background"]! as Map<String, dynamic>;
      (nonBackgroundConfig["assetIds"]! as List<dynamic>).add("paper-torn");
      expect(
        () => MemoryCollageManifest.fromJson(nonBackground),
        throwsFormatException,
      );

      final invalidConditionalLayer = _copyJson(sourceJson);
      final minimal = _template(invalidConditionalLayer, "minimal-editorial");
      final grain = (minimal["layers"]! as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((layer) => layer["layerId"] == "grain");
      grain["backgroundAssetIds"] = ["paper-washi"];
      expect(
        () => MemoryCollageManifest.fromJson(invalidConditionalLayer),
        throwsFormatException,
      );

      final invalidRuleBackground = _copyJson(sourceJson);
      final rule =
          (_template(invalidRuleBackground, "minimal-editorial")["rules"]!
                      as List<dynamic>)
                  .first
              as Map<String, dynamic>;
      rule["colorsByBackground"] = {"paper-washi": "#ffffff"};
      expect(
        () => MemoryCollageManifest.fromJson(invalidRuleBackground),
        throwsFormatException,
      );
    });

    test("requires each slot from zero through six exactly once", () {
      final json = _copyJson(sourceJson);
      final slots = _firstTemplate(json)["photoSlots"]! as List<dynamic>;
      (slots.last as Map<String, dynamic>)["slot"] = 5;

      expect(() => MemoryCollageManifest.fromJson(json), throwsFormatException);
    });

    test("rejects duplicate asset-window targets", () {
      final json = _copyJson(sourceJson);
      final slots = _firstTemplate(json)["photoSlots"]! as List<dynamic>;
      final first = slots.first as Map<String, dynamic>;
      final second = slots[1] as Map<String, dynamic>;
      second["layerId"] = first["layerId"];
      second["windowIndex"] = first["windowIndex"];

      expect(() => MemoryCollageManifest.fromJson(json), throwsFormatException);
    });

    test("rejects invalid asset window indices and bounds", () {
      final invalidIndex = _copyJson(sourceJson);
      final slot =
          (_firstTemplate(invalidIndex)["photoSlots"]! as List<dynamic>)[0]
              as Map<String, dynamic>;
      slot["windowIndex"] = 99;
      expect(
        () => MemoryCollageManifest.fromJson(invalidIndex),
        throwsFormatException,
      );

      final invalidBounds = _copyJson(sourceJson);
      final film = (invalidBounds["assets"]! as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((asset) => asset["id"] == "film-strip-four");
      final window =
          (film["photoWindows"]! as List<dynamic>).first
              as Map<String, dynamic>;
      window["width"] = 1000;
      expect(
        () => MemoryCollageManifest.fromJson(invalidBounds),
        throwsFormatException,
      );
    });

    test("rejects invalid direct rect geometry", () {
      final invalidPhotoRect = _copyJson(sourceJson);
      final slots =
          _firstTemplate(invalidPhotoRect)["photoSlots"]! as List<dynamic>;
      slots[0] = {
        "slot": 0,
        "kind": "rect",
        "x": -1,
        "y": 0,
        "width": 100,
        "height": 100,
        "z": 1,
      };
      expect(
        () => MemoryCollageManifest.fromJson(invalidPhotoRect),
        throwsFormatException,
      );

      final invalidTitleRect = _copyJson(sourceJson);
      final titleStyle =
          _firstTemplate(invalidTitleRect)["titleStyle"]!
              as Map<String, dynamic>;
      titleStyle["placement"] = {
        "kind": "rect",
        "x": 1000,
        "y": 0,
        "width": 100,
        "height": 100,
        "z": 1,
      };
      expect(
        () => MemoryCollageManifest.fromJson(invalidTitleRect),
        throwsFormatException,
      );
    });

    test("rejects incomplete or incorrectly inset matted rect contracts", () {
      final missingStyle = _copyJson(sourceJson);
      _template(missingStyle, "minimal-editorial").remove("matStyle");
      expect(
        () => MemoryCollageManifest.fromJson(missingStyle),
        throwsFormatException,
      );

      final incorrectInset = _copyJson(sourceJson);
      final minimal = _template(incorrectInset, "minimal-editorial");
      final firstSlot =
          (minimal["photoSlots"]! as List<dynamic>).first
              as Map<String, dynamic>;
      final photoRect = firstSlot["rect"]! as Map<String, dynamic>;
      photoRect["x"] = (photoRect["x"]! as num) + 1;
      expect(
        () => MemoryCollageManifest.fromJson(incorrectInset),
        throwsFormatException,
      );

      final invalidMatBorder = _copyJson(sourceJson);
      final style =
          _template(invalidMatBorder, "minimal-editorial")["matStyle"]!
              as Map<String, dynamic>;
      (style["border"]! as Map<String, dynamic>)["width"] = 0;
      expect(
        () => MemoryCollageManifest.fromJson(invalidMatBorder),
        throwsFormatException,
      );

      final invalidMatShadow = _copyJson(sourceJson);
      final shadows =
          (_template(invalidMatShadow, "minimal-editorial")["matStyle"]!
                  as Map<String, dynamic>)["shadows"]!
              as List<dynamic>;
      (shadows.first as Map<String, dynamic>)["blur"] = -1;
      expect(
        () => MemoryCollageManifest.fromJson(invalidMatShadow),
        throwsFormatException,
      );
    });

    test("rejects invalid title enumerations and anchors", () {
      final invalidAlign = _copyJson(sourceJson);
      final titleStyle =
          _firstTemplate(invalidAlign)["titleStyle"]! as Map<String, dynamic>;
      titleStyle["textAlign"] = "diagonal";
      expect(
        () => MemoryCollageManifest.fromJson(invalidAlign),
        throwsFormatException,
      );

      final invalidAnchor = _copyJson(sourceJson);
      final invalidAnchorTitle =
          _firstTemplate(invalidAnchor)["titleStyle"]! as Map<String, dynamic>;
      invalidAnchorTitle["placement"] = {"kind": "layer", "layerId": "missing"};
      expect(
        () => MemoryCollageManifest.fromJson(invalidAnchor),
        throwsFormatException,
      );
    });
  });
}

(int, String, int) _slotContract(MemoryCollagePhotoSlot slot) {
  final windowSlot = slot as MemoryCollageAssetWindowPhotoSlot;
  return (windowSlot.slot, windowSlot.layerID, windowSlot.windowIndex);
}

Map<String, dynamic> _copyJson(Map<String, dynamic> source) {
  return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
}

Map<String, dynamic> _firstTemplate(Map<String, dynamic> json) {
  return (json["templates"]! as List<dynamic>).first as Map<String, dynamic>;
}

Map<String, dynamic> _template(Map<String, dynamic> json, String id) {
  return (json["templates"]! as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((template) => template["id"] == id);
}
