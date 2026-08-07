import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/services/memories/memory_collage_selector.dart";

EnteFile _file(
  int id, {
  FileType fileType = FileType.image,
  int? generatedID,
  String? localID,
  String title = "photo.jpg",
}) {
  return EnteFile()
    ..uploadedFileID = id
    ..generatedID = generatedID
    ..localID = localID
    ..title = title
    ..fileType = fileType;
}

List<int?> _ids(Iterable<EnteFile> files) {
  return files.map((file) => file.uploadedFileID).toList(growable: false);
}

void main() {
  group("MemoryCollageSelector", () {
    test("supports exactly the six- and seven-photo layouts", () {
      expect(MemoryCollageSelector.isSupportedPhotoCount(5), isFalse);
      expect(MemoryCollageSelector.isSupportedPhotoCount(6), isTrue);
      expect(MemoryCollageSelector.isSupportedPhotoCount(7), isTrue);
      expect(MemoryCollageSelector.isSupportedPhotoCount(8), isFalse);
    });

    test(
      "stable key prefers uploaded, then generated, then local identity",
      () {
        final uploaded = _file(1, generatedID: 2, localID: "local");
        final generated = EnteFile()
          ..generatedID = 2
          ..localID = "local"
          ..fileType = FileType.image;
        final local = EnteFile()
          ..localID = "local"
          ..fileType = FileType.image;
        final unidentified = EnteFile()..fileType = FileType.image;

        expect(MemoryCollageSelector.stableFileKey(uploaded), "uploaded:1");
        expect(MemoryCollageSelector.stableFileKey(generated), "generated:2");
        expect(MemoryCollageSelector.stableFileKey(local), "local:local");
        expect(MemoryCollageSelector.stableFileKey(unidentified), isNull);
      },
    );

    test("eligibleFiles includes renderable images and live photos only", () {
      final files = [
        _file(1),
        _file(2, fileType: FileType.livePhoto),
        _file(3, fileType: FileType.video),
        _file(4, fileType: FileType.other),
        _file(5, title: "capture.dng"),
      ];

      expect(_ids(MemoryCollageSelector.eligibleFiles(files)), [1, 2]);
    });

    test("returns empty when fewer than six eligible files exist", () {
      final result = MemoryCollageSelector.select(
        memoryID: "memory",
        shuffleRevision: 0,
        files: [
          ...List.generate(5, (index) => _file(index)),
          _file(10, fileType: FileType.video),
        ],
      );

      expect(result, isEmpty);
      expect(() => result.add(_file(99)), throwsUnsupportedError);
    });

    test("returns exactly six when six are eligible without mutating", () {
      final files = List.generate(6, (index) => _file(index));
      final before = _ids(files);

      final result = MemoryCollageSelector.select(
        memoryID: "memory",
        shuffleRevision: 0,
        files: files,
      );

      expect(result, hasLength(6));
      expect(_ids(files), before);
      expect(() => result.add(_file(99)), throwsUnsupportedError);
    });

    test("returns exactly seven when at least seven are eligible", () {
      for (final eligibleCount in [7, 12]) {
        final files = List.generate(eligibleCount, (index) => _file(index));
        final before = _ids(files);

        final result = MemoryCollageSelector.select(
          memoryID: "memory",
          shuffleRevision: 0,
          files: files,
        );

        expect(result, hasLength(7));
        expect(_ids(files), before);
        expect(() => result.add(_file(99)), throwsUnsupportedError);
      }
    });

    test("selection is deterministic and independent of input order", () {
      final files = List.generate(20, (index) => _file(index));
      final reversed = files.reversed.toList(growable: false);

      final first = MemoryCollageSelector.select(
        memoryID: "summer-2025",
        shuffleRevision: 3,
        files: files,
      );
      final second = MemoryCollageSelector.select(
        memoryID: "summer-2025",
        shuffleRevision: 3,
        files: reversed,
      );

      expect(_ids(first), _ids(second));
    });

    test("shuffle revision deterministically changes six and seven slots", () {
      for (final eligibleCount in [6, 7, 20]) {
        final files = List.generate(eligibleCount, (index) => _file(index));

        final initial = MemoryCollageSelector.select(
          memoryID: "summer-2025",
          shuffleRevision: 0,
          files: files,
        );
        final shuffled = MemoryCollageSelector.select(
          memoryID: "summer-2025",
          shuffleRevision: 1,
          files: files,
        );

        expect(_ids(shuffled), isNot(_ids(initial)));
        expect(
          _ids(
            MemoryCollageSelector.select(
              memoryID: "summer-2025",
              shuffleRevision: 1,
              files: files,
            ),
          ),
          _ids(shuffled),
        );
      }
    });

    test("deduplicates repeated stable identities", () {
      final result = MemoryCollageSelector.select(
        memoryID: "memory",
        shuffleRevision: 0,
        files: [
          _file(1),
          _file(1),
          _file(2),
          _file(3),
          _file(4),
          _file(5),
          _file(6),
        ],
      );

      expect(result, hasLength(6));
      expect(_ids(result).toSet(), hasLength(6));
    });
  });
}
