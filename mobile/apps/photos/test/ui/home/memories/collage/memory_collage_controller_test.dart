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
  late Map<String, dynamic> sourceManifest;
  late MemoryCollageManifest manifest;

  setUpAll(() async {
    sourceManifest =
        jsonDecode(await rootBundle.loadString(memoryCollageManifestAsset))
            as Map<String, dynamic>;
    manifest = MemoryCollageManifest.fromJson(sourceManifest);
  });

  setUp(() {
    files = List.generate(8, _file);
  });

  test("starts at revision zero with the default template and background", () {
    final revisions = <int>[];
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      selector:
          ({required memoryID, required shuffleRevision, required files}) {
            expect(memoryID, "memory-1");
            revisions.add(shuffleRevision);
            return files.take(7).toList();
          },
    );

    expect(revisions, [0]);
    expect(controller.shuffleRevision, 0);
    expect(controller.templateID, "calm-film-trio");
    expect(controller.backgroundAssetID, "paper-cream-fiber");
    expect(controller.backgroundIndex, 1);
    expect(controller.backgroundIDs, manifest.backgroundAssetIDs);
    expect(controller.canCreate, isTrue);
    expect(controller.selectedFiles, files.take(7));
  });

  test("an explicit template starts with its authored default background", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      templateID: "scrapbook-maximal",
    );

    expect(controller.templateID, "scrapbook-maximal");
    expect(controller.backgroundAssetID, "paper-washi");
    expect(controller.backgroundIndex, 0);
  });

  test("shuffle replaces only the photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.skip(shuffleRevision).take(7).toList(),
    );
    controller.nextBackground();
    final templateID = controller.templateID;
    final backgroundID = controller.backgroundAssetID;
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.shuffle();

    expect(controller.shuffleRevision, 1);
    expect(controller.selectedFiles, files.skip(1).take(7));
    expect(controller.templateID, templateID);
    expect(controller.backgroundAssetID, backgroundID);
    expect(notifications, 1);
  });

  test("background selection is global and remains stable across styles", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
      templateID: "scrapbook-maximal",
    );
    final initialSelection = controller.selectedFiles;

    controller.nextBackground();
    expect(controller.backgroundAssetID, "paper-cream-fiber");
    for (final template in manifest.templates) {
      controller.selectTemplate(template.id);
      expect(
        controller.backgroundAssetID,
        "paper-cream-fiber",
        reason: template.id,
      );
    }
    expect(controller.shuffleRevision, 0);
    expect(identical(controller.selectedFiles, initialSelection), isTrue);
  });

  test("next template follows style-family order and preserves state", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
    );
    final initialSelection = controller.selectedFiles;
    final initialBackground = controller.backgroundAssetID;
    var notifications = 0;
    controller.addListener(() => notifications++);

    const expectedCycle = [
      "calm-accent-print",
      "scrapbook-maximal",
      "minimal-classic",
      "minimal-rows",
      "minimal-grid",
      "calm-classic",
      "calm-film-trio",
    ];
    final visited = <String>[];
    for (var count = 0; count < expectedCycle.length; count++) {
      controller.selectTemplate(controller.nextTemplateID);
      visited.add(controller.templateID);
    }

    expect(visited, expectedCycle);
    expect(controller.templateID, manifest.defaultTemplateID);
    expect(controller.backgroundAssetID, initialBackground);
    expect(identical(controller.selectedFiles, initialSelection), isTrue);
    expect(controller.shuffleRevision, 0);
    expect(notifications, expectedCycle.length);
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

  test("exposes immutable photos and background IDs", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
    );

    expect(
      () => controller.selectedFiles.add(_file(99)),
      throwsUnsupportedError,
    );
    expect(
      () => controller.backgroundIDs.add("another"),
      throwsUnsupportedError,
    );
  });

  test("requires exactly seven selected photos", () {
    MemoryCollageController controllerFor(int count) {
      return MemoryCollageController(
        memoryID: "memory-1",
        files: files,
        manifest: manifest,
        selector:
            ({required memoryID, required shuffleRevision, required files}) =>
                files.take(count).toList(),
      );
    }

    expect(controllerFor(6).canCreate, isFalse);
    expect(controllerFor(7).canCreate, isTrue);
    expect(controllerFor(8).canCreate, isFalse);
  });

  test("a single global background does not emit a no-op notification", () {
    final singleBackgroundManifest = _singleBackgroundManifest(sourceManifest);
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: singleBackgroundManifest,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.nextBackground();

    expect(controller.backgroundAssetID, "paper-cream-fiber");
    expect(notifications, 0);
  });

  test("production manifest contains all seven frozen templates", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      manifest: manifest,
    );
    const order = [
      "scrapbook-maximal",
      "calm-classic",
      "calm-film-trio",
      "calm-accent-print",
      "minimal-classic",
      "minimal-rows",
      "minimal-grid",
    ];

    expect(manifest.templates.map((template) => template.id), order);
    expect(controller.templateID, "calm-film-trio");
  });
}

MemoryCollageManifest _singleBackgroundManifest(Map<String, dynamic> source) {
  final json = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  final backgrounds = json["backgrounds"]! as Map<String, dynamic>;
  backgrounds["assets"] = (backgrounds["assets"]! as List<dynamic>)
      .where(
        (entry) => (entry as Map<String, dynamic>)["id"] == "paper-cream-fiber",
      )
      .toList();
  for (final template in json["templates"]! as List<dynamic>) {
    (template as Map<String, dynamic>)["defaultBackgroundAssetId"] =
        "paper-cream-fiber";
  }
  return MemoryCollageManifest.fromJson(json);
}

EnteFile _file(int id) {
  return EnteFile()
    ..uploadedFileID = id
    ..generatedID = id
    ..fileType = FileType.image;
}
