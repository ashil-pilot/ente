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

  test("loads the frozen v3 collage contract", () {
    expect(manifest.version, 3);
    expect(manifest.canvas.width, 1080);
    expect(manifest.canvas.height, 1920);
    expect(manifest.defaultTemplateID, "calm-film-trio");
    expect(manifest.backgroundAssetIDs, _backgroundIDs);
    expect(manifest.templates.map((template) => template.id), _templateIDs);

    expect(
      {
        for (final template in manifest.templates)
          template.id: template.plateAssetID,
      },
      {for (final id in _templateIDs) id: "layout-$id"},
    );
    expect(
      {
        for (final template in manifest.templates)
          template.id: template.finishPreset,
      },
      {
        "scrapbook-maximal": MemoryCollageFinishPreset.scrapbook,
        for (final id in const [
          "calm-classic",
          "calm-film-trio",
          "calm-accent-print",
        ])
          id: MemoryCollageFinishPreset.calm,
        for (final id in const [
          "minimal-classic",
          "minimal-rows",
          "minimal-grid",
        ])
          id: MemoryCollageFinishPreset.minimal,
      },
    );
    expect(
      manifest.templateFor("scrapbook-maximal").defaultBackgroundAssetID,
      "paper-washi",
    );
    for (final template in manifest.templates.skip(1)) {
      expect(
        template.defaultBackgroundAssetID,
        "paper-cream-fiber",
        reason: template.id,
      );
    }
  });

  test("ships only data consumed by the flattened runtime", () {
    expect(sourceJson.keys.toSet(), {
      "version",
      "canvas",
      "backgrounds",
      "defaultTemplateId",
      "templates",
    });
    expect((sourceJson["canvas"]! as Map).keys.toSet(), {"width", "height"});
    final backgrounds = sourceJson["backgrounds"]! as Map<String, dynamic>;
    expect(backgrounds.keys.toSet(), {"assets"});
    for (final background in backgrounds["assets"]! as List<dynamic>) {
      expect((background as Map<String, dynamic>).keys.toSet(), {
        "id",
        "width",
        "height",
      });
    }

    for (final template in sourceJson["templates"]! as List<dynamic>) {
      final typedTemplate = template as Map<String, dynamic>;
      expect(typedTemplate.keys.toSet(), {
        "id",
        "defaultBackgroundAssetId",
        "plateAssetId",
        "finishPreset",
        "photoSlots",
        "title",
      });
      for (final slot in typedTemplate["photoSlots"]! as List<dynamic>) {
        expect((slot as Map<String, dynamic>).keys.toSet(), {
          "slot",
          "x",
          "y",
          "width",
          "height",
          "z",
          "rotation",
          "backingColor",
        });
      }
      final title = typedTemplate["title"]! as Map<String, dynamic>;
      expect(title.keys.toSet(), anyOf(_titleKeys, _titleKeysWithShadow));
      if (title["shadow"] case final Map<String, dynamic> shadow) {
        expect(shadow.keys.toSet(), {"dx", "dy", "blur", "color"});
      }
    }
  });

  test("declares seven full-canvas shared backgrounds", () {
    expect(manifest.backgrounds, hasLength(7));
    for (final background in manifest.backgrounds) {
      expect(background.width, manifest.canvas.width, reason: background.id);
      expect(background.height, manifest.canvas.height, reason: background.id);
      expect(manifest.backgroundFor(background.id), same(background));
    }
  });

  test("declares seven sorted photo slots within every canvas", () {
    for (final template in manifest.templates) {
      expect(template.photoSlots, hasLength(7), reason: template.id);
      expect(
        template.photoSlots.map((slot) => slot.slot).toSet(),
        Set.of(List.generate(7, (index) => index)),
        reason: template.id,
      );
      for (var index = 1; index < template.photoSlots.length; index++) {
        final previous = template.photoSlots[index - 1];
        final current = template.photoSlots[index];
        expect(
          current.z > previous.z ||
              (current.z == previous.z &&
                  current.sourceIndex > previous.sourceIndex),
          isTrue,
          reason: template.id,
        );
      }
      for (final slot in template.photoSlots) {
        expect(slot.rect.x, greaterThanOrEqualTo(0), reason: template.id);
        expect(slot.rect.y, greaterThanOrEqualTo(0), reason: template.id);
        expect(
          slot.rect.x + slot.rect.width,
          lessThanOrEqualTo(manifest.canvas.width),
          reason: template.id,
        );
        expect(
          slot.rect.y + slot.rect.height,
          lessThanOrEqualTo(manifest.canvas.height),
          reason: template.id,
        );
        expect(slot.backingColor, isNotEmpty, reason: template.id);
        expect(template.photoSlot(slot.slot), same(slot));
      }
    }
  });

  test("preserves every approved natural empty-photo backing color", () {
    const polaroid = "#E7E1D4";
    const verticalFilm = "#7B4A32";
    const horizontalFilm = "#7A5B41";
    expect(_backings(manifest, "scrapbook-maximal"), [
      verticalFilm,
      verticalFilm,
      verticalFilm,
      polaroid,
      polaroid,
      polaroid,
      verticalFilm,
    ]);
    expect(_backings(manifest, "calm-classic"), [
      polaroid,
      polaroid,
      polaroid,
      horizontalFilm,
      horizontalFilm,
      horizontalFilm,
      horizontalFilm,
    ]);
    expect(_backings(manifest, "calm-film-trio"), [
      polaroid,
      polaroid,
      polaroid,
      polaroid,
      horizontalFilm,
      horizontalFilm,
      horizontalFilm,
    ]);
    expect(_backings(manifest, "calm-accent-print"), [
      polaroid,
      polaroid,
      polaroid,
      horizontalFilm,
      horizontalFilm,
      horizontalFilm,
      polaroid,
    ]);
    for (final templateID in const [
      "minimal-classic",
      "minimal-rows",
      "minimal-grid",
    ]) {
      expect(_backings(manifest, templateID), List.filled(7, polaroid));
    }
    expect(
      {
        for (final template in manifest.templates)
          for (final slot in template.photoSlots) slot.backingColor,
      },
      {polaroid, verticalFilm, horizontalFilm},
    );
  });

  test("keeps representative dynamic title contracts", () {
    final scrapbook = manifest.templateFor("scrapbook-maximal").title;
    expect(
      scrapbook.rect,
      isA<MemoryCollageRect>()
          .having((rect) => rect.x, "x", 144)
          .having((rect) => rect.y, "y", 156)
          .having((rect) => rect.width, "width", 618)
          .having((rect) => rect.height, "height", 114),
    );
    expect(scrapbook.fontFamily, "Lora");
    expect(scrapbook.rotation, -2.5);
    expect(scrapbook.shadow, isNotNull);

    final calm = manifest.templateFor("calm-film-trio").title;
    expect(calm.fontFamily, "Lora");
    expect(calm.maxLines, 2);
    expect(calm.shadow, isNull);

    final minimal = manifest.templateFor("minimal-rows").title;
    expect(minimal.fontFamily, "Inter");
    expect(minimal.maxLines, 2);
    expect(minimal.shadow, isNull);
  });

  test("sorts photo z-order and preserves equal-z source order", () {
    final json = _deepCopy(sourceJson);
    final slots = _firstTemplate(json)["photoSlots"]! as List<dynamic>;
    for (final slot in slots) {
      (slot as Map<String, dynamic>)["z"] = 1;
    }
    final sourceOrder = [
      for (final slot in slots) (slot as Map<String, dynamic>)["slot"] as int,
    ];
    var parsed = MemoryCollageManifest.fromJson(json);
    expect(
      parsed.templates.first.photoSlots.map((slot) => slot.slot),
      sourceOrder,
    );

    (slots.first as Map<String, dynamic>)["z"] = 2;
    parsed = MemoryCollageManifest.fromJson(json);
    expect(parsed.templates.first.photoSlots.last.slot, sourceOrder.first);
  });

  test("exposes immutable runtime collections", () {
    expect(
      () => manifest.backgrounds.add(manifest.backgrounds.first),
      throwsUnsupportedError,
    );
    expect(
      () => manifest.backgroundAssetIDs.add("another"),
      throwsUnsupportedError,
    );
    expect(
      () => manifest.templates.add(manifest.templates.first),
      throwsUnsupportedError,
    );
    expect(
      () => manifest.defaultTemplate.photoSlots.add(
        manifest.defaultTemplate.photoSlots.first,
      ),
      throwsUnsupportedError,
    );
  });

  group("validation", () {
    test(
      "rejects unsupported versions, duplicate IDs, and missing defaults",
      () {
        final oldVersion = _deepCopy(sourceJson)..["version"] = 2;
        expect(
          () => MemoryCollageManifest.fromJson(oldVersion),
          throwsFormatException,
        );

        final duplicateBackground = _deepCopy(sourceJson);
        final backgrounds =
            (duplicateBackground["backgrounds"]!
                    as Map<String, dynamic>)["assets"]!
                as List<dynamic>;
        backgrounds.add(Map<String, dynamic>.from(backgrounds.first as Map));
        expect(
          () => MemoryCollageManifest.fromJson(duplicateBackground),
          throwsFormatException,
        );

        final duplicateTemplate = _deepCopy(sourceJson);
        final templates = duplicateTemplate["templates"]! as List<dynamic>;
        templates.add(Map<String, dynamic>.from(templates.first as Map));
        expect(
          () => MemoryCollageManifest.fromJson(duplicateTemplate),
          throwsFormatException,
        );

        final missingDefault = _deepCopy(sourceJson)
          ..["defaultTemplateId"] = "missing";
        expect(
          () => MemoryCollageManifest.fromJson(missingDefault),
          throwsFormatException,
        );
      },
    );

    test("rejects invalid backgrounds and template references", () {
      final wrongSize = _deepCopy(sourceJson);
      final background =
          (((wrongSize["backgrounds"]! as Map<String, dynamic>)["assets"]!
                      as List<dynamic>)
                  .first
              as Map<String, dynamic>);
      background["width"] = 1;
      expect(
        () => MemoryCollageManifest.fromJson(wrongSize),
        throwsFormatException,
      );

      final unknownBackground = _deepCopy(sourceJson);
      _firstTemplate(unknownBackground)["defaultBackgroundAssetId"] = "missing";
      expect(
        () => MemoryCollageManifest.fromJson(unknownBackground),
        throwsFormatException,
      );

      final missingPlate = _deepCopy(sourceJson);
      _firstTemplate(missingPlate)["plateAssetId"] = "";
      expect(
        () => MemoryCollageManifest.fromJson(missingPlate),
        throwsFormatException,
      );

      final badFinish = _deepCopy(sourceJson);
      _firstTemplate(badFinish)["finishPreset"] = "generic-layers";
      expect(
        () => MemoryCollageManifest.fromJson(badFinish),
        throwsFormatException,
      );
    });

    test("requires slots zero through six with valid geometry", () {
      final duplicateSlot = _deepCopy(sourceJson);
      final slots = _firstTemplate(duplicateSlot)["photoSlots"]! as List;
      (slots.last as Map<String, dynamic>)["slot"] =
          (slots.first as Map<String, dynamic>)["slot"];
      expect(
        () => MemoryCollageManifest.fromJson(duplicateSlot),
        throwsFormatException,
      );

      final outsideCanvas = _deepCopy(sourceJson);
      ((_firstTemplate(outsideCanvas)["photoSlots"]! as List).first
              as Map<String, dynamic>)["x"] =
          -1;
      expect(
        () => MemoryCollageManifest.fromJson(outsideCanvas),
        throwsFormatException,
      );

      final emptyBacking = _deepCopy(sourceJson);
      ((_firstTemplate(emptyBacking)["photoSlots"]! as List).first
              as Map<String, dynamic>)["backingColor"] =
          "";
      expect(
        () => MemoryCollageManifest.fromJson(emptyBacking),
        throwsFormatException,
      );
    });

    test("rejects invalid dynamic title data", () {
      final invalidAlign = _deepCopy(sourceJson);
      (_firstTemplate(invalidAlign)["title"]!
              as Map<String, dynamic>)["textAlign"] =
          "diagonal";
      expect(
        () => MemoryCollageManifest.fromJson(invalidAlign),
        throwsFormatException,
      );

      final invalidWeight = _deepCopy(sourceJson);
      (_firstTemplate(invalidWeight)["title"]!
              as Map<String, dynamic>)["fontWeight"] =
          550;
      expect(
        () => MemoryCollageManifest.fromJson(invalidWeight),
        throwsFormatException,
      );

      final invalidShadow = _deepCopy(sourceJson);
      (_firstTemplate(invalidShadow)["title"]!
          as Map<String, dynamic>)["shadow"] = {
        "dx": 0,
        "dy": 0,
        "blur": -1,
        "color": "#000000",
      };
      expect(
        () => MemoryCollageManifest.fromJson(invalidShadow),
        throwsFormatException,
      );
    });
  });

  test("rejects unknown runtime lookups", () {
    expect(() => manifest.backgroundFor("missing"), throwsFormatException);
    expect(() => manifest.templateFor("missing"), throwsFormatException);
    expect(() => manifest.defaultTemplate.photoSlot(99), throwsFormatException);
  });
}

List<String> _backings(MemoryCollageManifest manifest, String templateID) {
  final template = manifest.templateFor(templateID);
  return [
    for (var slot = 0; slot < 7; slot++) template.photoSlot(slot).backingColor,
  ];
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
  return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
}

Map<String, dynamic> _firstTemplate(Map<String, dynamic> json) {
  return (json["templates"]! as List<dynamic>).first as Map<String, dynamic>;
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

const _backgroundIDs = [
  "paper-washi",
  "paper-cream-fiber",
  "paper-blush-stripe",
  "paper-sage-stripe",
  "paper-terracotta-mottle",
  "editorial-sand",
  "editorial-sage",
];

const _titleKeys = {
  "x",
  "y",
  "width",
  "height",
  "rotation",
  "fontFamily",
  "fontWeight",
  "fontSize",
  "minFontSize",
  "lineHeight",
  "maxLines",
  "letterSpacing",
  "color",
  "textAlign",
  "verticalAlign",
};
const _titleKeysWithShadow = {..._titleKeys, "shadow"};
