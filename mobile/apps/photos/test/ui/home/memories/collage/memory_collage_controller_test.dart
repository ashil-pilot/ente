import "dart:convert";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/ui/home/memories/collage/memory_collage_controller.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<EnteFile> files;
  late MemoryCollageManifest manifest;

  setUpAll(() async {
    final source =
        jsonDecode(await rootBundle.loadString(memoryCollageManifestAsset))
            as Map<String, dynamic>;
    manifest = _threeTemplateManifest(source);
  });

  setUp(() {
    files = List.generate(8, _file);
  });

  test("starts with revision zero and the manifest default template", () {
    final calls = <int>[];
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      selector:
          ({required memoryID, required shuffleRevision, required files}) {
            expect(memoryID, "memory-1");
            calls.add(shuffleRevision);
            return files.take(7).toList();
          },
    );

    expect(calls, [0]);
    expect(controller.shuffleRevision, 0);
    expect(controller.templateID, "scrapbook-calm");
    expect(controller.backgroundIndex, 0);
    expect(controller.backgroundAssetID, "paper-blush-stripe");
    expect(controller.canCreate, isTrue);
    expect(controller.selectedFiles, files.take(7));
  });

  test("can start with an explicit template and its default background", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      templateID: "scrapbook-maximal",
    );

    expect(controller.templateID, "scrapbook-maximal");
    expect(controller.backgroundIDs, ["paper-cream-fiber", "paper-washi"]);
    expect(controller.backgroundAssetID, "paper-washi");
  });

  test("shuffle advances the revision and replaces only the photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      templateID: "scrapbook-calm",
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.skip(shuffleRevision).take(7).toList(),
    );
    controller.selectTemplate("scrapbook-calm");
    controller.nextBackground();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.shuffle();

    expect(controller.shuffleRevision, 1);
    expect(controller.selectedFiles, files.skip(1).take(7));
    expect(controller.templateID, "scrapbook-calm");
    expect(controller.backgroundAssetID, "paper-sage-stripe");
    expect(notifications, 1);
  });

  test("remembers a separate background for every template", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      templateID: "scrapbook-maximal",
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(7).toList(),
    );
    final initialSelection = controller.selectedFiles;

    controller.nextBackground();
    expect(controller.backgroundAssetID, "paper-cream-fiber");

    controller.selectTemplate("scrapbook-calm");
    expect(controller.backgroundAssetID, "paper-blush-stripe");
    controller.nextBackground();
    expect(controller.backgroundAssetID, "paper-sage-stripe");

    controller.selectTemplate("minimal-editorial");
    expect(controller.backgroundAssetID, "paper-terracotta-mottle");
    controller.nextBackground();
    expect(controller.backgroundAssetID, "paper-terracotta-mottle");

    controller.selectTemplate("scrapbook-maximal");
    expect(controller.backgroundAssetID, "paper-cream-fiber");
    controller.selectTemplate("scrapbook-calm");
    expect(controller.backgroundAssetID, "paper-sage-stripe");

    expect(controller.shuffleRevision, 0);
    expect(identical(controller.selectedFiles, initialSelection), isTrue);
  });

  test("template switches preserve the exact seven selected files", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      templateID: "scrapbook-maximal",
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(7).toList(),
    );
    final initialSelection = controller.selectedFiles;
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.selectTemplate("scrapbook-calm");
    controller.selectTemplate("minimal-editorial");

    expect(controller.selectedFiles, hasLength(7));
    expect(identical(controller.selectedFiles, initialSelection), isTrue);
    expect(controller.shuffleRevision, 0);
    expect(notifications, 2);
  });

  test("selecting the active template is a no-op", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.selectTemplate(manifest.defaultTemplateID);

    expect(notifications, 0);
  });

  test("rejects an unknown template without changing state", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
    );

    expect(
      () => controller.selectTemplate("missing-template"),
      throwsFormatException,
    );
    expect(controller.templateID, manifest.defaultTemplateID);
  });

  test("exposes immutable photos and template background IDs", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(7).toList(),
    );

    expect(
      () => controller.selectedFiles.add(_file(99)),
      throwsUnsupportedError,
    );
    expect(() => controller.backgroundIDs.add("third"), throwsUnsupportedError);
  });

  test("cannot create when selection has fewer than seven photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files.take(6),
      manifest: manifest,
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.toList(),
    );

    expect(controller.selectedFiles, hasLength(6));
    expect(controller.canCreate, isFalse);
  });

  test("can create with seven selected photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(7).toList(),
    );

    expect(controller.selectedFiles, hasLength(7));
    expect(controller.canCreate, isTrue);
  });

  test("cannot create with more than seven selected photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.toList(),
    );

    expect(controller.selectedFiles, hasLength(8));
    expect(controller.canCreate, isFalse);
  });

  test("a single background does not emit a no-op notification", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      templateID: "minimal-editorial",
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(7).toList(),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.nextBackground();

    expect(controller.backgroundAssetID, "paper-terracotta-mottle");
    expect(notifications, 0);
  });
}

MemoryCollageManifest _threeTemplateManifest(Map<String, dynamic> source) {
  final json = _copyJson(source);
  final sourceTemplate = (json["templates"]! as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((template) => template["id"] == "scrapbook-maximal");
  json["defaultTemplateId"] = "scrapbook-calm";
  json["templates"] = [
    _template(
      sourceTemplate,
      id: "scrapbook-maximal",
      backgroundIDs: const ["paper-cream-fiber", "paper-washi"],
      defaultBackgroundID: "paper-washi",
    ),
    _template(
      sourceTemplate,
      id: "scrapbook-calm",
      backgroundIDs: const ["paper-blush-stripe", "paper-sage-stripe"],
      defaultBackgroundID: "paper-blush-stripe",
    ),
    _template(
      sourceTemplate,
      id: "minimal-editorial",
      backgroundIDs: const ["paper-terracotta-mottle"],
      defaultBackgroundID: "paper-terracotta-mottle",
    ),
  ];
  return MemoryCollageManifest.fromJson(json);
}

Map<String, dynamic> _template(
  Map<String, dynamic> source, {
  required String id,
  required List<String> backgroundIDs,
  required String defaultBackgroundID,
}) {
  final template = _copyJson(source)..["id"] = id;
  final background = template["background"]! as Map<String, dynamic>;
  background
    ..["defaultAssetId"] = defaultBackgroundID
    ..["assetIds"] = backgroundIDs;
  final backgroundLayerID = background["layerId"]! as String;
  final layers = (template["layers"]! as List<dynamic>)
      .cast<Map<String, dynamic>>();
  layers.singleWhere(
    (layer) => layer["layerId"] == backgroundLayerID,
  )["asset"] = defaultBackgroundID;
  return template;
}

Map<String, dynamic> _copyJson(Map<String, dynamic> source) {
  return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
}

EnteFile _file(int id) {
  return EnteFile()
    ..uploadedFileID = id
    ..generatedID = id
    ..fileType = FileType.image;
}
