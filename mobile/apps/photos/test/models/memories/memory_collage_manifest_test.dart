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
    expect(manifest.assets, hasLength(27));
    expect(manifest.backgroundAssets, hasLength(11));
    expect(manifest.defaultTemplateID, "scrapbook-maximal");
    expect(manifest.templates.map((template) => template.id), [
      "scrapbook-maximal",
      "scrapbook-calm",
      "minimal-editorial",
    ]);
    expect(manifest.defaultTemplate, same(manifest.templates.first));
    expect(
      manifest.templateFor("scrapbook-maximal"),
      same(manifest.defaultTemplate),
    );
    expect(manifest.defaultTemplate.layers, hasLength(17));
    for (final template in manifest.templates) {
      expect(template.photoSlots, hasLength(7));
    }
  });

  test("scopes ordered background choices to the template", () {
    final background = manifest.defaultTemplate.background;

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
    final layers = manifest.defaultTemplate.layers;

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
        expect(
          slot.windowIndex,
          inInclusiveRange(0, asset.photoWindows.length - 1),
        );
      }
    }
  });

  test("parses the exact seven-photo layout", () {
    expect(
      manifest.defaultTemplate.photoSlots.map(_slotContract),
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
      manifest.defaultTemplate.layerFor("strip").assetID,
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

  test("parses layer-anchored title typography and overlay blends", () {
    final template = manifest.defaultTemplate;
    final title = template.titleStyle;

    expect(title.placement, isA<MemoryCollageTitleAnchor>());
    expect((title.placement as MemoryCollageTitleAnchor).layerID, "banner");
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

  test("parses calm and minimal editorial template contracts", () {
    final calm = manifest.templateFor("scrapbook-calm");
    final minimal = manifest.templateFor("minimal-editorial");

    expect(calm.titleStyle.fontStyle, "italic");
    expect(calm.titleStyle.fontWeight, 600);
    expect(calm.titleStyle.minFontSize, 66);
    expect(calm.titleStyle.maxLines, 2);
    expect(calm.titleStyle.lineHeight, 1.08);
    expect(calm.background.defaultAssetID, "paper-notebook-blush");
    expect(
      calm.photoSlots.whereType<MemoryCollageAssetWindowPhotoSlot>(),
      hasLength(7),
    );

    expect(minimal.titleStyle.fontStyle, "italic");
    expect(minimal.titleStyle.fontWeight, 500);
    expect(minimal.titleStyle.minFontSize, 84);
    expect(minimal.titleStyle.maxLines, 2);
    expect(minimal.titleStyle.colorOnDark, "#f2ede2");
    expect(minimal.rules, hasLength(2));
    expect(
      minimal.photoSlots.whereType<MemoryCollageRectPhotoSlot>(),
      hasLength(7),
    );
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
    final rectSlot =
        parsed.defaultTemplate.photoSlots.first as MemoryCollageRectPhotoSlot;
    final titleRect =
        parsed.defaultTemplate.titleStyle.placement as MemoryCollageTitleRect;

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
      final placement =
          (_firstTemplate(invalidAnchor)["titleStyle"]!
                  as Map<String, dynamic>)["placement"]!
              as Map<String, dynamic>;
      placement["layerId"] = "missing";
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
