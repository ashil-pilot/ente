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
    expect(manifest.defaultTemplateID, "calm-film-trio");
    expect(manifest.templates.map((template) => template.id), [
      "scrapbook-maximal",
      "calm-classic",
      "calm-film-trio",
      "calm-accent-print",
      "minimal-classic",
      "minimal-rows",
      "minimal-grid",
    ]);
    expect(
      manifest.templateFor("calm-film-trio"),
      same(manifest.defaultTemplate),
    );
    expect(manifest.defaultTemplate.layers, hasLength(13));
    expect(manifest.templateFor("scrapbook-maximal").layers, hasLength(17));
    expect(manifest.templateFor("calm-classic").layers, hasLength(12));
    expect(manifest.templateFor("calm-accent-print").layers, hasLength(12));
    for (final id in ["minimal-classic", "minimal-rows", "minimal-grid"]) {
      expect(manifest.templateFor(id).layers, hasLength(2));
    }
    for (final template in manifest.templates) {
      expect(template.photoSlots, hasLength(7));
    }
  });

  test("ships only fields consumed by the frozen runtime schema", () {
    _expectOnlyKeys(sourceJson, const {
      "version",
      "canvas",
      "assets",
      "defaultTemplateId",
      "templates",
    });
    _expectOnlyKeys(sourceJson["canvas"]! as Map<String, dynamic>, const {
      "width",
      "height",
    });
    for (final asset
        in (sourceJson["assets"]! as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      _expectOnlyKeys(asset, const {
        "id",
        "width",
        "height",
        "emptyWindowColor",
        "photoWindows",
      });
      for (final window
          in (asset["photoWindows"] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()) {
        _expectOnlyKeys(window, const {"x", "y", "width", "height"});
      }
    }

    for (final template
        in (sourceJson["templates"]! as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      _expectOnlyKeys(template, const {
        "id",
        "minimumPhotoShortSide",
        "background",
        "layers",
        "photoSlots",
        "rules",
        "matStyle",
        "titleStyle",
      });
      _expectOnlyKeys(template["background"]! as Map<String, dynamic>, const {
        "layerId",
        "defaultAssetId",
        "assetIds",
      });
      for (final layer
          in (template["layers"]! as List<dynamic>)
              .cast<Map<String, dynamic>>()) {
        _expectOnlyKeys(layer, const {
          "layerId",
          "asset",
          "x",
          "y",
          "width",
          "height",
          "z",
          "rotation",
          "shadows",
          "backgroundAssetIds",
          "blendMode",
          "opacity",
        });
      }
      for (final slot
          in (template["photoSlots"]! as List<dynamic>)
              .cast<Map<String, dynamic>>()) {
        final kind = slot["kind"];
        _expectOnlyKeys(
          slot,
          kind == "assetWindow"
              ? const {"kind", "slot", "layerId", "windowIndex"}
              : const {"kind", "slot", "mat", "rect", "z", "rotation"},
        );
      }
      for (final rule
          in (template["rules"] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()) {
        _expectOnlyKeys(rule, const {
          "x",
          "y",
          "width",
          "height",
          "z",
          "color",
          "colorsByBackground",
        });
      }
      final matStyle = template["matStyle"] as Map<String, dynamic>?;
      if (matStyle != null) {
        _expectOnlyKeys(matStyle, const {
          "fill",
          "photoFill",
          "border",
          "photoInset",
          "shadows",
        });
      }
      final title = template["titleStyle"]! as Map<String, dynamic>;
      _expectOnlyKeys(title, const {
        "placement",
        "fontFamily",
        "fontWeight",
        "fontStyle",
        "fontSize",
        "minFontSize",
        "lineHeight",
        "maxLines",
        "letterSpacing",
        "color",
        "textAlign",
        "verticalAlign",
        "shadow",
      });
      _expectOnlyKeys(title["placement"]! as Map<String, dynamic>, const {
        "kind",
        "x",
        "y",
        "width",
        "height",
        "z",
        "rotation",
      });
    }
  });

  test("shares every ordered background choice across all templates", () {
    const backgroundIDs = [
      "paper-washi",
      "paper-cream-fiber",
      "paper-blush-stripe",
      "paper-sage-stripe",
      "paper-terracotta-mottle",
      "editorial-sand",
      "editorial-sage",
    ];

    for (final template in manifest.templates) {
      expect(template.background.layerID, "bg", reason: template.id);
      expect(template.background.assetIDs, backgroundIDs, reason: template.id);
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
    expect(polaroidWindows, hasLength(1));
    expect(polaroidWindows.single.width, 414);
    expect(polaroidWindows.single.height, 420);
  });

  test(
    "parses the restored four-frame and retained three-frame film assets",
    () {
      final fourFrame = manifest.assetFor("film-strip-four-horizontal");
      final threeFrame = manifest.assetFor("film-strip-three-horizontal");

      expect((fourFrame.width, fourFrame.height), (972, 252));
      expect(fourFrame.emptyWindowColor, "#33241a");
      expect(
        fourFrame.photoWindows.map(_windowGeometry),
        orderedEquals([
          (30, 39, 210, 174),
          (264, 39, 210, 174),
          (498, 39, 210, 174),
          (732, 39, 210, 174),
        ]),
      );

      expect((threeFrame.width, threeFrame.height), (972, 348));
      expect(threeFrame.emptyWindowColor, "#33241a");
      expect(
        threeFrame.photoWindows.map(_windowGeometry),
        orderedEquals([
          (30, 39, 288, 270),
          (342, 39, 288, 270),
          (654, 39, 288, 270),
        ]),
      );
    },
  );

  test("parses the exact C0, C1, and C2 Calm geometries", () {
    final classic = manifest.templateFor("calm-classic");
    final filmTrio = manifest.templateFor("calm-film-trio");
    final accentPrint = manifest.templateFor("calm-accent-print");

    expect(
      classic.layers.map(_layerGeometry),
      orderedEquals([
        ("bg", "paper-cream-fiber", 0, 0, 1080, 1920, 0, 0),
        ("fern", "fern", 882, -42, 228, 408, 3, 188),
        ("strip", "film-strip-four-horizontal", 54, 1566, 972, 252, 5, -1.2),
        ("hero", "print-frame-hero", 102, 264, 876, 594, 6, -0.8),
        ("p1", "polaroid-frame", 78, 900, 462, 534, 7, 1.2),
        ("p2", "polaroid-frame", 546, 918, 462, 534, 8, -1),
        ("tapeL", "tape-blush", 48, 228, 228, 66, 10, -43),
        ("tapeR", "tape-sage", 816, 222, 210, 63, 11, 44),
        ("stamp", "stamp-postmark", 840, 1398, 192, 216, 12, -6),
        ("sunStreak", "sun-streak", 0, 0, 1080, 1920, 34, 0),
        ("vignette", "vignette", 0, 0, 1080, 1920, 36, 0),
        ("grain", "grain-overlay", 0, 0, 1080, 1920, 38, 0),
      ]),
    );
    expect(
      classic.photoSlots.map(_slotContract),
      orderedEquals([
        (0, "hero", 0),
        (1, "p1", 0),
        (2, "p2", 0),
        (3, "strip", 0),
        (4, "strip", 1),
        (5, "strip", 2),
        (6, "strip", 3),
      ]),
    );

    expect(
      filmTrio.layers.map(_layerGeometry),
      orderedEquals([
        ("bg", "paper-cream-fiber", 0, 0, 1080, 1920, 0, 0),
        ("fern", "fern", 882, -42, 228, 408, 3, 188),
        ("strip", "film-strip-three-horizontal", 54, 1434, 972, 348, 5, -1.2),
        ("hero", "print-frame-hero", 102, 264, 876, 594, 6, -0.8),
        ("p1", "polaroid-frame", 48, 900, 312, 361, 7, 1.2),
        ("p2", "polaroid-frame", 384, 930, 312, 361, 8, -1),
        ("p3", "polaroid-frame", 720, 912, 312, 361, 9, 1.8),
        ("tapeL", "tape-blush", 48, 228, 228, 66, 10, -43),
        ("tapeR", "tape-sage", 816, 222, 210, 63, 11, 44),
        ("stamp", "stamp-postmark", 840, 1254, 192, 216, 12, -6),
        ("sunStreak", "sun-streak", 0, 0, 1080, 1920, 34, 0),
        ("vignette", "vignette", 0, 0, 1080, 1920, 36, 0),
        ("grain", "grain-overlay", 0, 0, 1080, 1920, 38, 0),
      ]),
    );
    expect(
      filmTrio.photoSlots.map(_slotContract),
      orderedEquals([
        (0, "hero", 0),
        (1, "p1", 0),
        (2, "p2", 0),
        (3, "p3", 0),
        (4, "strip", 0),
        (5, "strip", 1),
        (6, "strip", 2),
      ]),
    );

    expect(
      accentPrint.layers.map(_layerGeometry),
      orderedEquals([
        ("bg", "paper-cream-fiber", 0, 0, 1080, 1920, 0, 0),
        ("fern", "fern", 882, -42, 228, 408, 3, 188),
        ("strip", "film-strip-three-horizontal", 54, 1506, 972, 348, 5, -1.2),
        ("hero", "print-frame-hero", 102, 264, 876, 594, 6, -0.8),
        ("p1", "polaroid-frame", 78, 900, 462, 534, 7, 1.2),
        ("p2", "polaroid-frame", 546, 918, 462, 534, 8, -1),
        ("tapeL", "tape-blush", 48, 228, 228, 66, 10, -43),
        ("print", "polaroid-frame", 726, 204, 312, 361, 12, 5),
        ("printTape", "tape-sage", 777, 172, 210, 63, 13, -6),
        ("sunStreak", "sun-streak", 0, 0, 1080, 1920, 34, 0),
        ("vignette", "vignette", 0, 0, 1080, 1920, 36, 0),
        ("grain", "grain-overlay", 0, 0, 1080, 1920, 38, 0),
      ]),
    );
    expect(
      accentPrint.photoSlots.map(_slotContract),
      orderedEquals([
        (0, "hero", 0),
        (1, "p1", 0),
        (2, "p2", 0),
        (3, "strip", 0),
        (4, "strip", 1),
        (5, "strip", 2),
        (6, "print", 0),
      ]),
    );
  });

  test("parses the B2 maximal rebalance and explicit title safe rect", () {
    final template = manifest.templateFor("scrapbook-maximal");
    final title = template.titleStyle;
    final bannerAsset = manifest.assetFor("banner-wide");
    final bannerLayer = template.layerFor("banner");
    final tape = template.layerFor("tapeA");
    final stamp = template.layerFor("stamp");

    expect((bannerAsset.width, bannerAsset.height), (900, 150));
    expect(bannerLayer.assetID, "banner-wide");
    expect(
      (
        bannerLayer.x,
        bannerLayer.y,
        bannerLayer.width,
        bannerLayer.height,
        bannerLayer.rotation,
      ),
      (90, 138, 900, 150, -2.5),
    );
    expect((tape.x, tape.y), (54, 78));
    expect((stamp.x, stamp.y), (786, 72));
    expect(
      [
        "torn",
        "fern",
        "strip",
        "p1",
        "p2",
        "p3",
        "banner",
        "tapeA",
        "tapeB",
        "tapeC",
        "stamp",
      ].map((id) {
        final layer = template.layerFor(id);
        return (id, layer.x, layer.y);
      }),
      orderedEquals([
        ("torn", -12, 120),
        ("fern", 897, 72),
        ("strip", 618, 270),
        ("p1", 42, 312),
        ("p2", 96, 858),
        ("p3", 48, 1362),
        ("banner", 90, 138),
        ("tapeA", 54, 78),
        ("tapeB", 132, 276),
        ("tapeC", 444, 822),
        ("stamp", 786, 72),
      ]),
    );
    for (final id in ["bg", "sunStreak", "vignette", "grain"]) {
      final layer = template.layerFor(id);
      expect((layer.x, layer.y), (0, 0));
    }

    final titlePlacement = title.placement;
    expect(
      (
        titlePlacement.rect.x,
        titlePlacement.rect.y,
        titlePlacement.rect.width,
        titlePlacement.rect.height,
      ),
      (144, 156, 618, 114),
    );
    expect(titlePlacement.z, 20);
    expect(titlePlacement.rotation, -2.5);
    expect(title.fontFamily, "Lora");
    expect(title.fontWeight, 600);
    expect(title.fontSize, 45);
    expect(title.minFontSize, 27);
    expect(title.maxLines, 1);
    expect(title.letterSpacing, 12);
    expect(template.layerFor("sunStreak").blendMode, "soft-light");
    expect(template.layerFor("vignette").blendMode, "multiply");
    expect(template.layerFor("grain").blendMode, "overlay");
    expect(template.layerFor("grain").opacity, 0.55);
  });

  test("shares the Calm typography and background contract across C0-C2", () {
    for (final id in ["calm-classic", "calm-film-trio", "calm-accent-print"]) {
      final calm = manifest.templateFor(id);
      final title = calm.titleStyle;
      final placement = title.placement;

      expect(title.fontFamily, "Lora", reason: id);
      expect(title.fontStyle, "normal", reason: id);
      expect(title.fontWeight, 600, reason: id);
      expect(title.fontSize, 96, reason: id);
      expect(title.minFontSize, 60, reason: id);
      expect(title.maxLines, 2, reason: id);
      expect(title.lineHeight, 1.06, reason: id);
      expect(title.letterSpacing, -0.5, reason: id);
      expect(title.color, "#6f5642", reason: id);
      expect(title.textAlign, "left", reason: id);
      expect(title.verticalAlign, "top", reason: id);
      expect(
        (
          placement.rect.x,
          placement.rect.y,
          placement.rect.width,
          placement.rect.height,
          placement.z,
          placement.rotation,
        ),
        (114, 66, 672, 180, 20, -1.5),
        reason: id,
      );
      expect(calm.background.defaultAssetID, "paper-cream-fiber", reason: id);
      expect(calm.background.assetIDs, [
        "paper-washi",
        "paper-cream-fiber",
        "paper-blush-stripe",
        "paper-sage-stripe",
        "paper-terracotta-mottle",
        "editorial-sand",
        "editorial-sage",
      ], reason: id);
      expect(
        calm.photoSlots.whereType<MemoryCollageAssetWindowPhotoSlot>(),
        hasLength(7),
        reason: id,
      );
      expect(calm.layerFor("sunStreak").blendMode, "soft-light", reason: id);
      expect(calm.layerFor("vignette").blendMode, "multiply", reason: id);
      expect(calm.layerFor("vignette").opacity, 0.7, reason: id);
      expect(calm.layerFor("grain").blendMode, "overlay", reason: id);
      expect(calm.layerFor("grain").opacity, 0.41, reason: id);
    }
  });

  test(
    "shares the Minimal typography, background, and mat contract across D0-D2",
    () {
      for (final id in ["minimal-classic", "minimal-rows", "minimal-grid"]) {
        final minimal = manifest.templateFor(id);
        final title = minimal.titleStyle;
        final titlePlacement = title.placement;

        expect(title.fontFamily, "Inter", reason: id);
        expect(title.fontStyle, "normal", reason: id);
        expect(title.fontWeight, 500, reason: id);
        expect(title.fontSize, 102, reason: id);
        expect(title.minFontSize, 66, reason: id);
        expect(title.maxLines, 2, reason: id);
        expect(title.lineHeight, 1.04, reason: id);
        expect(title.letterSpacing, -1.5, reason: id);
        expect(title.color, "#24201a", reason: id);
        expect(
          (
            titlePlacement.rect.x,
            titlePlacement.rect.y,
            titlePlacement.rect.width,
            titlePlacement.rect.height,
            titlePlacement.z,
            titlePlacement.rotation,
          ),
          (78, 84, 924, 186, 20, 0),
          reason: id,
        );
        expect(
          minimal.background.defaultAssetID,
          "paper-cream-fiber",
          reason: id,
        );
        expect(minimal.background.assetIDs, [
          "paper-washi",
          "paper-cream-fiber",
          "paper-blush-stripe",
          "paper-sage-stripe",
          "paper-terracotta-mottle",
          "editorial-sand",
          "editorial-sage",
        ], reason: id);
        expect(
          minimal.rules.map(
            (rule) => (
              rule.rect.x,
              rule.rect.y,
              rule.rect.width,
              rule.rect.height,
              rule.z,
              rule.color,
            ),
          ),
          orderedEquals([
            (78, 288, 924, 3, 10, "#cfc5ae"),
            (78, 1842, 924, 3, 10, "#cfc5ae"),
          ]),
          reason: id,
        );
        for (final rule in minimal.rules) {
          expect(rule.colorsByBackground, {
            "editorial-sand": "#d8cfbc",
            "editorial-sage": "#d8cfbc",
          }, reason: id);
        }

        final matStyle = minimal.matStyle!;
        expect(matStyle.fill, "#faf6ec", reason: id);
        expect(matStyle.photoFill, "#e7e1d4", reason: id);
        expect(matStyle.photoInset, 15, reason: id);
        expect(matStyle.border.width, 3, reason: id);
        expect(matStyle.border.color, "rgba(90,75,55,0.20)", reason: id);
        expect(matStyle.shadows, hasLength(1), reason: id);
        final matShadow = matStyle.shadows.single;
        expect(
          (
            matShadow.kind,
            matShadow.dx,
            matShadow.dy,
            matShadow.blur,
            matShadow.color,
          ),
          ("dropShadow", 0, 3, 9, "rgba(90,70,45,0.12)"),
          reason: id,
        );

        expect(
          minimal.layers.map(_layerGeometry),
          orderedEquals([
            ("bg", "paper-cream-fiber", 0, 0, 1080, 1920, 0, 0),
            ("grain", "grain-overlay", 0, 0, 1080, 1920, 38, 0),
          ]),
          reason: id,
        );
        final grain = minimal.layerFor("grain");
        expect(grain.blendMode, "overlay", reason: id);
        expect(grain.opacity, 0.12, reason: id);
        expect(grain.backgroundAssetIDs, [
          "editorial-sand",
          "editorial-sage",
        ], reason: id);
        expect(grain.appliesToBackground("paper-cream-fiber"), isFalse);
        expect(grain.appliesToBackground("editorial-sand"), isTrue);

        final minimalJson = _template(sourceJson, id);
        for (final slot in minimalJson["photoSlots"]! as List<dynamic>) {
          final slotJson = slot as Map<String, dynamic>;
          expect(slotJson["kind"], "mattedRect", reason: id);
          expect(slotJson, isNot(contains("shadows")), reason: id);
        }
      }
    },
  );

  test("parses the exact D0, D1, and D2 Minimal geometries", () {
    final classic = manifest.templateFor("minimal-classic");
    final rows = manifest.templateFor("minimal-rows");
    final grid = manifest.templateFor("minimal-grid");

    expect(
      classic.photoSlots.map(_mattedGeometry),
      orderedEquals([
        (0, 78, 390, 924, 798, 93, 405, 894, 768, 4, 0),
        (1, 78, 1212, 450, 318, 93, 1227, 420, 288, 4, 0),
        (2, 552, 1212, 450, 318, 567, 1227, 420, 288, 4, 0),
        (3, 78, 1554, 213, 252, 93, 1569, 183, 222, 4, 0),
        (4, 315, 1554, 213, 252, 330, 1569, 183, 222, 4, 0),
        (5, 552, 1554, 213, 252, 567, 1569, 183, 222, 4, 0),
        (6, 789, 1554, 213, 252, 804, 1569, 183, 222, 4, 0),
      ]),
    );
    expect(
      rows.photoSlots.map(_mattedGeometry),
      orderedEquals([
        (0, 78, 351, 924, 699, 93, 366, 894, 669, 4, 0),
        (1, 78, 1095, 300, 330, 93, 1110, 270, 300, 4, 0),
        (2, 390, 1095, 300, 330, 405, 1110, 270, 300, 4, 0),
        (3, 702, 1095, 300, 330, 717, 1110, 270, 300, 4, 0),
        (4, 78, 1470, 300, 330, 93, 1485, 270, 300, 4, 0),
        (5, 390, 1470, 300, 330, 405, 1485, 270, 300, 4, 0),
        (6, 702, 1470, 300, 330, 717, 1485, 270, 300, 4, 0),
      ]),
    );
    expect(
      grid.photoSlots.map(_mattedGeometry),
      orderedEquals([
        (0, 78, 357, 450, 474, 93, 372, 420, 444, 4, 0),
        (1, 552, 357, 450, 474, 567, 372, 420, 444, 4, 0),
        (2, 78, 900, 300, 330, 93, 915, 270, 300, 4, 0),
        (3, 390, 900, 300, 330, 405, 915, 270, 300, 4, 0),
        (4, 702, 900, 300, 330, 717, 915, 270, 300, 4, 0),
        (5, 78, 1299, 450, 474, 93, 1314, 420, 444, 4, 0),
        (6, 552, 1299, 450, 474, 567, 1314, 420, 444, 4, 0),
      ]),
    );

    for (final template in [classic, rows, grid]) {
      for (final slot
          in template.photoSlots
              .whereType<MemoryCollageMattedRectPhotoSlot>()) {
        expect(slot.photoRect.x, slot.matRect.x + 15, reason: template.id);
        expect(slot.photoRect.y, slot.matRect.y + 15, reason: template.id);
        expect(
          slot.photoRect.width,
          slot.matRect.width - 30,
          reason: template.id,
        );
        expect(
          slot.photoRect.height,
          slot.matRect.height - 30,
          reason: template.id,
        );
      }
    }
  });

  test("uses the production template-specific photo short-side floors", () {
    expect(
      {
        for (final template in manifest.templates)
          template.id: template.minimumPhotoShortSide,
      },
      {
        "scrapbook-maximal": 270,
        "calm-classic": 174,
        "calm-film-trio": 270,
        "calm-accent-print": 270,
        "minimal-classic": 183,
        "minimal-rows": 270,
        "minimal-grid": 270,
      },
    );
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
    final minimal = manifest.templateFor("minimal-rows");
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

      final wrongSizedBackground = _copyJson(sourceJson);
      final wrongSizedBackgroundConfig =
          _firstTemplate(wrongSizedBackground)["background"]!
              as Map<String, dynamic>;
      (wrongSizedBackgroundConfig["assetIds"]! as List<dynamic>).add(
        "paper-torn",
      );
      expect(
        () => MemoryCollageManifest.fromJson(wrongSizedBackground),
        throwsFormatException,
      );

      final invalidConditionalLayer = _copyJson(sourceJson);
      final minimal = _template(invalidConditionalLayer, "minimal-rows");
      final grain = (minimal["layers"]! as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((layer) => layer["layerId"] == "grain");
      grain["backgroundAssetIds"] = ["missing"];
      expect(
        () => MemoryCollageManifest.fromJson(invalidConditionalLayer),
        throwsFormatException,
      );

      final invalidRuleBackground = _copyJson(sourceJson);
      final rule =
          (_template(invalidRuleBackground, "minimal-rows")["rules"]!
                      as List<dynamic>)
                  .first
              as Map<String, dynamic>;
      rule["colorsByBackground"] = {"missing": "#ffffff"};
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

    test("rejects unsupported photo slots and invalid title geometry", () {
      final unsupportedPhotoSlot = _copyJson(sourceJson);
      final slots =
          _firstTemplate(unsupportedPhotoSlot)["photoSlots"]! as List<dynamic>;
      slots[0] = {
        "slot": 0,
        "kind": "rect",
        "x": 0,
        "y": 0,
        "width": 300,
        "height": 300,
        "z": 1,
      };
      expect(
        () => MemoryCollageManifest.fromJson(unsupportedPhotoSlot),
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

    test("rejects photos below each template's shorter-side floor", () {
      final undersizedAssetWindow = _copyJson(sourceJson);
      final film = (undersizedAssetWindow["assets"]! as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((asset) => asset["id"] == "film-strip-four");
      final filmWindow =
          (film["photoWindows"]! as List<dynamic>).first
              as Map<String, dynamic>;
      filmWindow["width"] = 260;
      expect(
        () => MemoryCollageManifest.fromJson(undersizedAssetWindow),
        throwsFormatException,
      );

      final tooStrictCalmFloor = _copyJson(sourceJson);
      _template(tooStrictCalmFloor, "calm-classic")["minimumPhotoShortSide"] =
          175;
      expect(
        () => MemoryCollageManifest.fromJson(tooStrictCalmFloor),
        throwsFormatException,
      );

      final tooStrictMinimalFloor = _copyJson(sourceJson);
      _template(
        tooStrictMinimalFloor,
        "minimal-classic",
      )["minimumPhotoShortSide"] = 184;
      expect(
        () => MemoryCollageManifest.fromJson(tooStrictMinimalFloor),
        throwsFormatException,
      );
    });

    test("rejects invalid template-specific shorter-side floors", () {
      for (final value in <Object>[
        0,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        "270",
      ]) {
        final json = _copyJson(sourceJson);
        _firstTemplate(json)["minimumPhotoShortSide"] = value;

        expect(
          () => MemoryCollageManifest.fromJson(json),
          throwsFormatException,
          reason: "minimumPhotoShortSide=$value",
        );
      }
    });

    test("rejects incomplete or incorrectly inset matted rect contracts", () {
      final missingStyle = _copyJson(sourceJson);
      _template(missingStyle, "minimal-rows").remove("matStyle");
      expect(
        () => MemoryCollageManifest.fromJson(missingStyle),
        throwsFormatException,
      );

      final incorrectInset = _copyJson(sourceJson);
      final minimal = _template(incorrectInset, "minimal-rows");
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
          _template(invalidMatBorder, "minimal-rows")["matStyle"]!
              as Map<String, dynamic>;
      (style["border"]! as Map<String, dynamic>)["width"] = 0;
      expect(
        () => MemoryCollageManifest.fromJson(invalidMatBorder),
        throwsFormatException,
      );

      final invalidMatShadow = _copyJson(sourceJson);
      final shadows =
          (_template(invalidMatShadow, "minimal-rows")["matStyle"]!
                  as Map<String, dynamic>)["shadows"]!
              as List<dynamic>;
      (shadows.first as Map<String, dynamic>)["blur"] = -1;
      expect(
        () => MemoryCollageManifest.fromJson(invalidMatShadow),
        throwsFormatException,
      );
    });

    test("rejects invalid title enumerations and placements", () {
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

(double, double, double, double) _windowGeometry(
  MemoryCollagePhotoWindow window,
) {
  return (window.x, window.y, window.width, window.height);
}

(String, String, double, double, double, double, int, double) _layerGeometry(
  MemoryCollageLayer layer,
) {
  return (
    layer.layerID,
    layer.assetID,
    layer.x,
    layer.y,
    layer.width,
    layer.height,
    layer.z,
    layer.rotation,
  );
}

(
  int,
  double,
  double,
  double,
  double,
  double,
  double,
  double,
  double,
  int,
  double,
)
_mattedGeometry(MemoryCollagePhotoSlot slot) {
  final matted = slot as MemoryCollageMattedRectPhotoSlot;
  return (
    matted.slot,
    matted.matRect.x,
    matted.matRect.y,
    matted.matRect.width,
    matted.matRect.height,
    matted.photoRect.x,
    matted.photoRect.y,
    matted.photoRect.width,
    matted.photoRect.height,
    matted.z,
    matted.rotation,
  );
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

void _expectOnlyKeys(Map<String, dynamic> json, Set<String> allowedKeys) {
  expect(json.keys.toSet().difference(allowedKeys), isEmpty);
}
