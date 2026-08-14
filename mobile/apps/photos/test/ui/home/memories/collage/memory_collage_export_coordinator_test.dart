import "dart:async";
import "dart:typed_data";

import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_coordinator.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_surface.dart";

void main() {
  test("runs one export and restores its action state", () async {
    var captureCalls = 0;
    Uint8List? usedBytes;
    final coordinator = MemoryCollageExportCoordinator(
      capture: (_) async {
        captureCalls++;
        return Uint8List.fromList([1, 2, 3]);
      },
      waitForFrame: () async {},
    );
    addTearDown(coordinator.dispose);

    final export = coordinator.run(
      action: MemoryCollageExportAction.share,
      createSnapshot: _readySnapshot,
      usePng: (bytes) async {
        usedBytes = bytes;
      },
    );

    expect(coordinator.action, MemoryCollageExportAction.share);
    expect(coordinator.snapshot, isNotNull);
    await export;

    expect(captureCalls, 1);
    expect(usedBytes, orderedEquals([1, 2, 3]));
    expect(coordinator.action, isNull);
    expect(coordinator.snapshot, isNull);
  });

  test("ignores a concurrent action while an export is running", () async {
    final file = EnteFile();
    late MemoryCollageExportSnapshot firstSnapshot;
    var secondSnapshotCreations = 0;
    var captureCalls = 0;
    final coordinator = MemoryCollageExportCoordinator(
      capture: (_) async {
        captureCalls++;
        return Uint8List(1);
      },
      waitForFrame: () async {},
    );
    addTearDown(coordinator.dispose);

    final first = coordinator.run(
      action: MemoryCollageExportAction.share,
      createSnapshot: () => firstSnapshot = _snapshot([file]),
      usePng: (_) async {},
    );
    await coordinator.run(
      action: MemoryCollageExportAction.save,
      createSnapshot: () {
        secondSnapshotCreations++;
        return _readySnapshot();
      },
      usePng: (_) async {},
    );

    expect(secondSnapshotCreations, 0);
    expect(coordinator.action, MemoryCollageExportAction.share);
    firstSnapshot.markPhotoLoaded(file: file, slot: 0);
    await first;
    expect(captureCalls, 1);
  });

  test("clears a failure and permits a successful retry", () async {
    var shouldFail = true;
    var useCalls = 0;
    final coordinator = MemoryCollageExportCoordinator(
      capture: (_) async {
        if (shouldFail) throw StateError("capture failed");
        return Uint8List.fromList([9]);
      },
      waitForFrame: () async {},
    );
    addTearDown(coordinator.dispose);

    final failed = coordinator.run(
      action: MemoryCollageExportAction.save,
      createSnapshot: _readySnapshot,
      usePng: (_) async {
        useCalls++;
      },
    );
    await expectLater(failed, throwsStateError);
    expect(coordinator.action, isNull);
    expect(coordinator.snapshot, isNull);

    shouldFail = false;
    final retried = coordinator.run(
      action: MemoryCollageExportAction.save,
      createSnapshot: _readySnapshot,
      usePng: (_) async {
        useCalls++;
      },
    );
    await retried;

    expect(useCalls, 1);
    expect(coordinator.action, isNull);
  });

  test("treats lifecycle cancellation as a silent outcome", () async {
    final file = EnteFile();
    var captureCalls = 0;
    var useCalls = 0;
    final coordinator = MemoryCollageExportCoordinator(
      capture: (_) async {
        captureCalls++;
        return Uint8List(1);
      },
      waitForFrame: () async {},
    );
    addTearDown(coordinator.dispose);

    final export = coordinator.run(
      action: MemoryCollageExportAction.share,
      createSnapshot: () => _snapshot([file]),
      usePng: (_) async {
        useCalls++;
      },
    );
    coordinator.cancelCurrent();
    await export;

    expect(captureCalls, 0);
    expect(useCalls, 0);
    expect(coordinator.action, isNull);
    expect(coordinator.snapshot, isNull);
  });

  test("does not capture when cancelled during the frame wait", () async {
    final frameWait = Completer<void>();
    var captureCalls = 0;
    var useCalls = 0;
    final coordinator = MemoryCollageExportCoordinator(
      capture: (_) async {
        captureCalls++;
        return Uint8List(1);
      },
      waitForFrame: () => frameWait.future,
    );
    addTearDown(coordinator.dispose);

    final export = coordinator.run(
      action: MemoryCollageExportAction.share,
      createSnapshot: _readySnapshot,
      usePng: (_) async {
        useCalls++;
      },
    );
    await Future<void>.delayed(Duration.zero);
    coordinator.cancelCurrent();
    frameWait.complete();
    await export;

    expect(captureCalls, 0);
    expect(useCalls, 0);
    expect(coordinator.action, isNull);
    expect(coordinator.snapshot, isNull);
  });
}

MemoryCollageExportSnapshot _readySnapshot() => _snapshot(const []);

MemoryCollageExportSnapshot _snapshot(Iterable<EnteFile> files) {
  return MemoryCollageExportSnapshot(
    files: files,
    title: "Title",
    templateID: "template",
    backgroundAssetID: "background",
  );
}
