import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/ui/home/memories/collage/memory_collage_controller.dart";

void main() {
  late List<EnteFile> files;

  setUp(() {
    files = List.generate(8, _file);
  });

  test("starts with revision zero and the first background", () {
    final calls = <int>[];
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      backgroundIDs: const ["first", "second"],
      selector:
          ({required memoryID, required shuffleRevision, required files}) {
            expect(memoryID, "memory-1");
            calls.add(shuffleRevision);
            return files.take(6).toList();
          },
    );

    expect(calls, [0]);
    expect(controller.shuffleRevision, 0);
    expect(controller.backgroundIndex, 0);
    expect(controller.backgroundAssetID, "first");
    expect(controller.canCreate, isTrue);
    expect(controller.selectedFiles, files.take(6));
  });

  test("shuffle advances the revision and replaces only the photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      backgroundIDs: const ["first", "second"],
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.skip(shuffleRevision).take(6).toList(),
    );
    controller.nextBackground();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.shuffle();

    expect(controller.shuffleRevision, 1);
    expect(controller.selectedFiles, files.skip(1).take(6));
    expect(controller.backgroundAssetID, "second");
    expect(notifications, 1);
  });

  test("background selection wraps without changing the photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      backgroundIDs: const ["first", "second"],
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(6).toList(),
    );
    final initialSelection = controller.selectedFiles;
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.nextBackground();
    controller.nextBackground();

    expect(controller.backgroundAssetID, "first");
    expect(controller.shuffleRevision, 0);
    expect(identical(controller.selectedFiles, initialSelection), isTrue);
    expect(notifications, 2);
  });

  test("exposes immutable photos and background IDs", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      backgroundIDs: const ["first", "second"],
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(6).toList(),
    );

    expect(
      () => controller.selectedFiles.add(_file(99)),
      throwsUnsupportedError,
    );
    expect(() => controller.backgroundIDs.add("third"), throwsUnsupportedError);
  });

  test("rejects an empty background list", () {
    expect(
      () => MemoryCollageController(
        memoryID: "memory-1",
        files: files,
        backgroundIDs: const [],
        selector:
            ({required memoryID, required shuffleRevision, required files}) =>
                files.take(6).toList(),
      ),
      throwsArgumentError,
    );
  });

  test("cannot create when selection has fewer than six photos", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files.take(5),
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.toList(),
    );

    expect(controller.selectedFiles, hasLength(5));
    expect(controller.canCreate, isFalse);
  });

  test("a single background does not emit a no-op notification", () {
    final controller = MemoryCollageController(
      memoryID: "memory-1",
      files: files,
      backgroundIDs: const ["only"],
      selector:
          ({required memoryID, required shuffleRevision, required files}) =>
              files.take(6).toList(),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.nextBackground();

    expect(controller.backgroundAssetID, "only");
    expect(notifications, 0);
  });
}

EnteFile _file(int id) {
  return EnteFile()
    ..uploadedFileID = id
    ..generatedID = id
    ..fileType = FileType.image;
}
