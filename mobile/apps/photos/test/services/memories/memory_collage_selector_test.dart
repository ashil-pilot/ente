import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/services/memories/memory_collage_selector.dart";

EnteFile _file(
  int id, {
  FileType fileType = FileType.image,
  String title = "photo.jpg",
}) {
  return EnteFile()
    ..uploadedFileID = id
    ..title = title
    ..fileType = fileType;
}

List<int?> _ids(Iterable<EnteFile> files) {
  return files.map((file) => file.uploadedFileID).toList(growable: false);
}

void main() {
  group("MemoryCollageSelector", () {
    test("requires exactly seven selected photos", () {
      expect(MemoryCollageSelector.hasRequiredPhotoCount(6), isFalse);
      expect(MemoryCollageSelector.hasRequiredPhotoCount(7), isTrue);
      expect(MemoryCollageSelector.hasRequiredPhotoCount(8), isFalse);
    });

    test("eligibility uses seven unique renderable photo identities", () {
      final files = [
        _file(1),
        _file(2, fileType: FileType.livePhoto),
        _file(3, fileType: FileType.video),
        _file(4, fileType: FileType.other),
        _file(5, title: "capture.dng"),
        _file(1),
        _file(6),
        _file(7),
        _file(8),
        _file(9),
        _file(10),
      ];

      expect(MemoryCollageSelector.hasEnoughEligiblePhotos(files), isTrue);
      expect(
        MemoryCollageSelector.hasEnoughEligiblePhotos(files.take(9)),
        isFalse,
      );
    });

    test("eligibility stops after finding the seventh photo", () {
      Iterable<EnteFile> files() sync* {
        yield* List.generate(7, _file);
        throw StateError("eligibility scanned beyond the required photos");
      }

      expect(MemoryCollageSelector.hasEnoughEligiblePhotos(files()), isTrue);
    });

    test("generated and local identities can complete the seven photos", () {
      final generated = EnteFile()
        ..generatedID = 20
        ..fileType = FileType.image;
      final local = EnteFile()
        ..localID = "local-photo"
        ..fileType = FileType.image;
      final unidentified = EnteFile()..fileType = FileType.image;
      final files = [
        ...List.generate(5, _file),
        generated,
        local,
        unidentified,
      ];

      expect(MemoryCollageSelector.hasEnoughEligiblePhotos(files), isTrue);
      expect(
        MemoryCollageSelector.select(
          memoryID: "memory",
          shuffleRevision: 0,
          files: files,
        ),
        hasLength(7),
      );
    });

    test("returns empty when fewer than seven eligible files exist", () {
      final result = MemoryCollageSelector.select(
        memoryID: "memory",
        shuffleRevision: 0,
        files: List.generate(6, (index) => _file(index)),
      );

      expect(result, isEmpty);
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

    test("shuffle revision deterministically changes the seven slots", () {
      for (final eligibleCount in [7, 20]) {
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
          _file(7),
        ],
      );

      expect(result, hasLength(7));
      expect(_ids(result).toSet(), hasLength(7));
    });
  });
}
