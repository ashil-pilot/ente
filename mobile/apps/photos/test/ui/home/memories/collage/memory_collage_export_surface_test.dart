import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_photo.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_surface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryCollageManifest manifest;

  setUpAll(() async {
    manifest = await MemoryCollageManifest.load();
  });

  test(
    "freezes its selection and accepts each original slot only once",
    () async {
      final first = _photo(0);
      final second = _photo(1);
      final sourceFiles = [first, second];
      final snapshot = MemoryCollageExportSnapshot(
        files: sourceFiles,
        title: "Frozen title",
        templateID: "frozen-template",
        backgroundAssetID: "frozen-background",
      );
      sourceFiles
        ..clear()
        ..add(_photo(2));

      expect(snapshot.files, [same(first), same(second)]);
      expect(() => snapshot.files.add(_photo(3)), throwsUnsupportedError);
      expect(snapshot.title, "Frozen title");
      expect(snapshot.templateID, "frozen-template");
      expect(snapshot.backgroundAssetID, "frozen-background");

      final equalButNotIdentical = _photo(0);
      expect(equalButNotIdentical, first);
      expect(identical(equalButNotIdentical, first), isFalse);
      expect(
        snapshot.markPhotoLoaded(file: equalButNotIdentical, slot: 0),
        isFalse,
      );
      expect(snapshot.markPhotoLoaded(file: first, slot: -1), isFalse);
      expect(snapshot.markPhotoLoaded(file: first, slot: 1), isFalse);
      expect(snapshot.markPhotoLoaded(file: first, slot: 0), isTrue);
      expect(snapshot.markPhotoLoaded(file: first, slot: 0), isFalse);
      expect(snapshot.readySlotCount, 1);
      expect(snapshot.isReady, isFalse);

      final ready = snapshot.waitUntilReady(
        timeout: const Duration(seconds: 1),
      );
      expect(snapshot.markPhotoLoaded(file: second, slot: 1), isTrue);
      await ready;

      expect(snapshot.isReady, isTrue);
      expect(snapshot.readySlotCount, 2);
      expect(snapshot.markPhotoLoaded(file: second, slot: 1), isFalse);
      expect(snapshot.cancel(), isFalse);
    },
  );

  test(
    "bounds waits without poisoning readiness and supports cancellation",
    () async {
      final file = _photo(0);
      final snapshot = MemoryCollageExportSnapshot(
        files: [file],
        title: "Title",
        templateID: "template",
        backgroundAssetID: "background",
      );

      await expectLater(
        snapshot.waitUntilReady(timeout: const Duration(milliseconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      expect(snapshot.isCancelled, isFalse);
      expect(snapshot.markPhotoLoaded(file: file, slot: 0), isTrue);
      await snapshot.waitUntilReady(timeout: const Duration(seconds: 1));

      final cancelled = MemoryCollageExportSnapshot(
        files: [_photo(1)],
        title: "Title",
        templateID: "template",
        backgroundAssetID: "background",
      );
      final cancelledWait = cancelled.waitUntilReady(
        timeout: const Duration(seconds: 1),
      );
      expect(cancelled.cancel(), isTrue);
      await expectLater(
        cancelledWait,
        throwsA(isA<MemoryCollageExportCancelledException>()),
      );
      expect(cancelled.isCancelled, isTrue);
      expect(
        cancelled.markPhotoLoaded(file: cancelled.files.single, slot: 0),
        isFalse,
      );
      expect(cancelled.cancel(), isFalse);
    },
  );

  testWidgets(
    "renders a fixed hidden canvas and marks its original photos ready",
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final template = manifest.defaultTemplate;
      final files = List.generate(template.photoSlots.length, _photo);
      final snapshot = MemoryCollageExportSnapshot(
        files: files,
        title: "Export title",
        templateID: template.id,
        backgroundAssetID: template.background.defaultAssetID,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: MemoryCollageExportSurface(
              manifest: manifest,
              snapshot: snapshot,
              testPhotoBuilder: (_, _) => const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );

      expect(find.byType(IgnorePointer), findsWidgets);
      final surfaceIgnorePointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byKey(snapshot.repaintKey),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(surfaceIgnorePointer.ignoring, isTrue);
      final excluded = tester.widget<ExcludeSemantics>(
        find.ancestor(
          of: find.byKey(snapshot.repaintKey),
          matching: find.byType(ExcludeSemantics),
        ),
      );
      expect(excluded.excluding, isTrue);
      expect(
        tester.getSize(find.byKey(snapshot.repaintKey)),
        const Size(360, 640),
      );

      final canvas = tester.widget<MemoryCollageCanvasView>(
        find.byType(MemoryCollageCanvasView),
      );
      expect(canvas.files, same(snapshot.files));
      expect(canvas.title, "Export title");
      expect(canvas.templateID, template.id);
      expect(canvas.backgroundAssetID, template.background.defaultAssetID);

      final renderedPhotos = tester
          .widgetList<MemoryCollageExportPhoto>(
            find.byType(MemoryCollageExportPhoto),
          )
          .toList(growable: false);
      expect(renderedPhotos, hasLength(files.length));
      final renderedFileIndices = <int>{};
      for (final photo in renderedPhotos) {
        final originalIndex = files.indexWhere(
          (original) => identical(original, photo.file),
        );
        expect(originalIndex, isNonNegative);
        expect(renderedFileIndices.add(originalIndex), isTrue);
        expect(
          photo.targetPixelSize,
          memoryCollageExportTargetPixelSize(manifest, template, originalIndex),
        );
        photo.onFinalImageLoaded();
      }
      expect(snapshot.readySlotCount, files.length);
      expect(snapshot.isReady, isTrue);
      await snapshot.waitUntilReady(timeout: const Duration(seconds: 1));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(snapshot.isCancelled, isFalse);
    },
  );

  testWidgets("disposing an incomplete surface cancels its snapshot", (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = manifest.defaultTemplate;
    final snapshot = MemoryCollageExportSnapshot(
      files: List.generate(template.photoSlots.length, _photo),
      title: "Export title",
      templateID: template.id,
      backgroundAssetID: template.background.defaultAssetID,
    );
    final wait = snapshot.waitUntilReady(timeout: const Duration(seconds: 1));
    final waitExpectation = expectLater(
      wait,
      throwsA(isA<MemoryCollageExportCancelledException>()),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MemoryCollageExportSurface(
          manifest: manifest,
          snapshot: snapshot,
          testPhotoBuilder: (_, _) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    expect(snapshot.isCancelled, isTrue);
    await waitExpectation;
  });
}

EnteFile _photo(int index) {
  return EnteFile()
    ..uploadedFileID = index + 1
    ..generatedID = index + 100
    ..fileType = FileType.image;
}
