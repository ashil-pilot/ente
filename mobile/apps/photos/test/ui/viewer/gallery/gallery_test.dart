import "dart:async";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
  });

  testWidgets("initial hydration remains limited then full and serialized", (
    tester,
  ) async {
    final loader = _ControlledGalleryLoader();
    final key = GlobalKey<GalleryState>();
    await tester.pumpWidget(_galleryHarness(key: key, loader: loader.call));
    await tester.pump(const Duration(microseconds: 1));

    expect(loader.invocationCount, 1);
    expect(loader.attempts.single.limit, GalleryState.kInitialLoadLimit);
    final preview = _file(generatedID: 1, uploadedID: 1);
    loader.completeNext(FileLoadResult([preview], true));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump(const Duration(microseconds: 1));

    expect(key.currentState!.debugGalleryFiles, [preview]);
    expect(loader.invocationCount, 2);
    expect(loader.attempts.last.limit, isNull);
    final full = _file(generatedID: 2, uploadedID: 2);
    loader.completeNext(FileLoadResult([full], false));
    await tester.pump(const Duration(microseconds: 1));

    expect(key.currentState!.debugGalleryFiles, [full]);
    expect(key.currentState!.debugMaximumActivePhysicalLoads, 1);
    expect(loader.maximumActiveCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets("typed force, soft, priority, and force streams use one gate", (
    tester,
  ) async {
    final reloadEvents = StreamController<FilesUpdatedEvent>.broadcast();
    final forceEvents =
        StreamController<ForceReloadHomeGalleryEvent>.broadcast();
    addTearDown(reloadEvents.close);
    addTearDown(forceEvents.close);
    final loader = _ControlledGalleryLoader();
    final key = GlobalKey<GalleryState>();
    var sortAscending = false;
    await tester.pumpWidget(
      _galleryHarness(
        key: key,
        loader: loader.call,
        reloadEvents: reloadEvents.stream,
        forceEvents: [forceEvents.stream],
        sortAsyncFn: () => sortAscending,
      ),
    );
    await tester.pump(const Duration(microseconds: 1));
    loader.completeNext(FileLoadResult(const [], false));
    await tester.pump();

    sortAscending = true;
    reloadEvents.add(
      LocalPhotosUpdatedEvent(
        const [],
        source: "syncUpdateFromRemote",
        requiresGalleryForceReload: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(microseconds: 1));
    expect(loader.invocationCount, 2);
    expect(loader.attempts.last.asc, isTrue);

    final remoteFile = _file(generatedID: 5, uploadedID: 5);
    loader.completeNext(FileLoadResult([remoteFile], false));
    await tester.pump();
    expect(loader.invocationCount, 2);
    expect(key.currentState!.debugGalleryFiles, [remoteFile]);

    reloadEvents.add(LocalPhotosUpdatedEvent(const [], source: "ordinarySoft"));
    reloadEvents.add(
      LocalPhotosUpdatedEvent(
        const [],
        source: "recentLocal",
        hasRecentNewLocalDiscovery: true,
      ),
    );
    forceEvents.add(ForceReloadHomeGalleryEvent("newFilesDisplay"));
    sortAscending = false;
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(loader.invocationCount, 3);
    expect(loader.attempts.last.asc, isFalse);

    loader.completeNext(FileLoadResult(const [], false));
    await tester.pump(const Duration(microseconds: 1));
    expect(loader.invocationCount, 3);

    expect(key.currentState!.debugMaximumActivePhysicalLoads, 1);
    expect(loader.maximumActiveCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets("all idle in-memory fast paths avoid database loading", (
    tester,
  ) async {
    final reloadEvents = StreamController<FilesUpdatedEvent>.broadcast();
    addTearDown(reloadEvents.close);
    final loader = _ControlledGalleryLoader();
    final key = GlobalKey<GalleryState>();
    final uploadedCandidate = _file(generatedID: 10, localID: "local-10");
    final missingCandidate = _file(generatedID: 11, localID: "local-11");
    final added = _file(generatedID: 12, localID: "local-12");
    await tester.pumpWidget(
      _galleryHarness(
        key: key,
        loader: loader.call,
        reloadEvents: reloadEvents.stream,
        newLocalFilesResolver: (_) async => [added],
      ),
    );
    await tester.pump(const Duration(microseconds: 1));
    loader.completeNext(
      FileLoadResult([uploadedCandidate, missingCandidate], false),
    );
    await tester.pump();

    final uploaded = _file(
      generatedID: 10,
      localID: "local-10",
      uploadedID: 100,
    );
    reloadEvents.add(
      LocalPhotosUpdatedEvent([uploaded], source: "uploadCompleted"),
    );
    await tester.pump();
    expect(uploadedCandidate.uploadedFileID, 100);

    reloadEvents.add(
      LocalPhotosUpdatedEvent(
        [missingCandidate],
        type: EventType.deletedFromEverywhere,
        source: "fileMissingLocal",
      ),
    );
    await tester.pump();
    expect(key.currentState!.debugGalleryFiles, [uploadedCandidate]);

    reloadEvents.add(
      LocalPhotosAddedEvent(
        [added],
        source: "loadedPhoto",
        hasRecentNewLocalDiscovery: false,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(key.currentState!.debugGalleryFiles, [added, uploadedCandidate]);
    expect(loader.invocationCount, 1);
    expect(loader.maximumActiveCount, 1);
    expect(key.currentState!.debugMaximumActivePhysicalLoads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets("same single-subscription force stream survives rebuild", (
    tester,
  ) async {
    final forceEvents = StreamController<ForceReloadHomeGalleryEvent>();
    addTearDown(forceEvents.close);
    final loader = _ControlledGalleryLoader();
    final key = GlobalKey<GalleryState>();
    final stream = forceEvents.stream;
    await tester.pumpWidget(
      _galleryHarness(key: key, loader: loader.call, forceEvents: [stream]),
    );
    await tester.pump(const Duration(microseconds: 1));
    expect(loader.invocationCount, 1);

    await tester.pumpWidget(
      _galleryHarness(key: key, loader: loader.call, forceEvents: [stream]),
    );
    expect(tester.takeException(), isNull);

    forceEvents.add(ForceReloadHomeGalleryEvent("sameSingleStream"));
    await tester.pump(const Duration(microseconds: 1));
    expect(key.currentState!.debugRequestedGeneration, 2);
    expect(loader.invocationCount, 1);
    loader.completeNext(FileLoadResult(const [], false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(loader.invocationCount, 2);
    loader.completeNext(FileLoadResult(const [], false));
    await tester.pump();

    expect(loader.maximumActiveCount, 1);
    expect(key.currentState!.debugMaximumActivePhysicalLoads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets("busy in-memory update cannot be overwritten by old snapshot", (
    tester,
  ) async {
    final reloadEvents = StreamController<FilesUpdatedEvent>.broadcast();
    addTearDown(reloadEvents.close);
    final loader = _ControlledGalleryLoader();
    final key = GlobalKey<GalleryState>();
    final local = _file(generatedID: 20, localID: "local-20");
    await tester.pumpWidget(
      _galleryHarness(
        key: key,
        loader: loader.call,
        reloadEvents: reloadEvents.stream,
      ),
    );
    await tester.pump(const Duration(microseconds: 1));
    loader.completeNext(FileLoadResult([local], false));
    await tester.pump(const Duration(microseconds: 1));

    reloadEvents.add(LocalPhotosUpdatedEvent(const [], source: "soft"));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump(const Duration(microseconds: 1));
    expect(loader.invocationCount, 2);
    final uploaded = _file(
      generatedID: 20,
      localID: "local-20",
      uploadedID: 200,
    );
    reloadEvents.add(
      LocalPhotosUpdatedEvent([uploaded], source: "uploadCompleted"),
    );
    await tester.pump(const Duration(microseconds: 1));
    expect(local.uploadedFileID, isNull);

    loader.completeNext(FileLoadResult([local], false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(loader.invocationCount, 3);
    loader.completeNext(FileLoadResult([uploaded], false));
    await tester.pump();

    expect(key.currentState!.debugGalleryFiles.single.uploadedFileID, 200);
    expect(loader.maximumActiveCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets("configuration change rejects old load and rebinds ownership", (
    tester,
  ) async {
    final oldEvents = StreamController<FilesUpdatedEvent>.broadcast();
    final newEvents = StreamController<FilesUpdatedEvent>.broadcast();
    addTearDown(oldEvents.close);
    addTearDown(newEvents.close);
    final oldLoader = _ControlledGalleryLoader();
    final newLoader = _ControlledGalleryLoader();
    final oldSelectedFiles = _TestSelectedFiles();
    final newSelectedFiles = _TestSelectedFiles();
    final key = GlobalKey<GalleryState>();

    await tester.pumpWidget(
      _galleryHarness(
        key: key,
        loader: oldLoader.call,
        reloadEvents: oldEvents.stream,
        loadConfigurationKey: "old",
        selectedFiles: oldSelectedFiles,
      ),
    );
    await tester.pump(const Duration(microseconds: 1));
    expect(oldLoader.invocationCount, 1);
    expect(oldSelectedFiles.debugHasListeners, isTrue);

    await tester.pumpWidget(
      _galleryHarness(
        key: key,
        loader: newLoader.call,
        reloadEvents: newEvents.stream,
        loadConfigurationKey: "new",
        selectedFiles: newSelectedFiles,
      ),
    );
    expect(oldSelectedFiles.debugHasListeners, isFalse);
    expect(newSelectedFiles.debugHasListeners, isTrue);

    final generationAfterRebuild = key.currentState!.debugRequestedGeneration;
    oldEvents.add(LocalPhotosUpdatedEvent(const [], source: "oldStream"));
    await tester.pump();
    expect(key.currentState!.debugRequestedGeneration, generationAfterRebuild);

    oldLoader.completeNext(
      FileLoadResult([_file(generatedID: 30, uploadedID: 30)], false),
    );
    await tester.pump();
    await tester.pump(const Duration(microseconds: 1));
    expect(newLoader.invocationCount, 1);
    expect(key.currentState!.debugGalleryFiles, isEmpty);

    final newFile = _file(generatedID: 31, uploadedID: 31);
    newLoader.completeNext(FileLoadResult([newFile], false));
    await tester.pump();
    expect(key.currentState!.debugGalleryFiles, [newFile]);

    newEvents.add(LocalPhotosUpdatedEvent(const [], source: "newStream"));
    await tester.pump();
    await tester.pump(const Duration(microseconds: 1));
    expect(newLoader.invocationCount, 2);
    newLoader.completeNext(FileLoadResult([newFile], false));
    await tester.pump(const Duration(microseconds: 1));
    expect(newLoader.maximumActiveCount, 1);
    expect(oldLoader.maximumActiveCount, 1);
    expect(key.currentState!.debugMaximumActivePhysicalLoads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(newSelectedFiles.debugHasListeners, isFalse);
  });

  testWidgets("dispose ignores an unresolved physical completion", (
    tester,
  ) async {
    final loader = _ControlledGalleryLoader();
    final key = GlobalKey<GalleryState>();
    await tester.pumpWidget(_galleryHarness(key: key, loader: loader.call));
    await tester.pump(const Duration(microseconds: 1));
    expect(loader.invocationCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    loader.completeNext(
      FileLoadResult([_file(generatedID: 40, uploadedID: 40)], false),
    );
    await tester.pump();
    expect(loader.invocationCount, 1);
    expect(loader.maximumActiveCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets("header is measured when first inserted after an empty load", (
    tester,
  ) async {
    final reloadEvents = StreamController<FilesUpdatedEvent>.broadcast();
    addTearDown(reloadEvents.close);
    final loader = _ControlledGalleryLoader();
    final key = GlobalKey<GalleryState>();
    await tester.pumpWidget(
      _galleryHarness(
        key: key,
        loader: loader.call,
        reloadEvents: reloadEvents.stream,
      ),
    );
    await tester.pump(const Duration(microseconds: 1));
    loader.completeNext(FileLoadResult(const [], false));
    await tester.pump();
    expect(key.currentState!.debugHeaderHeight, isNull);

    reloadEvents.add(LocalPhotosUpdatedEvent(const [], source: "soft"));
    await tester.pump(const Duration(microseconds: 1));
    expect(loader.invocationCount, 2);
    loader.completeNext(
      FileLoadResult([_file(generatedID: 50, uploadedID: 50)], false),
    );
    await tester.pump();
    await tester.pump();

    expect(key.currentState!.debugHeaderHeight, 1);
    expect(loader.maximumActiveCount, 1);
    expect(key.currentState!.debugMaximumActivePhysicalLoads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}

Widget _galleryHarness({
  required GlobalKey<GalleryState> key,
  required GalleryLoader loader,
  Stream<FilesUpdatedEvent>? reloadEvents,
  List<Stream<ForceReloadHomeGalleryEvent>>? forceEvents,
  SortAscFn? sortAsyncFn,
  NewLocalFilesResolver? newLocalFilesResolver,
  Object? loadConfigurationKey,
  SelectedFiles? selectedFiles,
}) {
  return MaterialApp(
    home: GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Scaffold(
          body: Gallery(
            key: key,
            asyncLoader: loader,
            reloadEvent: reloadEvents,
            forceReloadEvents: forceEvents,
            tagPrefix: "test-gallery",
            selectedFiles: selectedFiles,
            enableFileGrouping: false,
            loadingWidget: const SizedBox.shrink(),
            emptyState: const SizedBox.shrink(),
            header: const SizedBox(height: 1),
            footer: const SizedBox.shrink(),
            disableScroll: true,
            sortAsyncFn: sortAsyncFn,
            newLocalFilesResolver: newLocalFilesResolver,
            loadConfigurationKey: loadConfigurationKey,
            suppressFileRendering: true,
          ),
        ),
      ),
    ),
  );
}

EnteFile _file({required int generatedID, int? uploadedID, String? localID}) {
  return EnteFile()
    ..generatedID = generatedID
    ..uploadedFileID = uploadedID
    ..localID = localID
    ..creationTime = generatedID
    ..modificationTime = generatedID
    ..fileType = FileType.image;
}

class _ControlledGalleryLoader {
  final List<Completer<FileLoadResult>> _pending = [];
  final List<({int? limit, bool? asc})> attempts = [];
  int invocationCount = 0;
  int activeCount = 0;
  int maximumActiveCount = 0;

  Future<FileLoadResult> call(
    int creationStartTime,
    int creationEndTime, {
    int? limit,
    bool? asc,
  }) {
    invocationCount++;
    activeCount++;
    maximumActiveCount = maximumActiveCount < activeCount
        ? activeCount
        : maximumActiveCount;
    attempts.add((limit: limit, asc: asc));
    final completer = Completer<FileLoadResult>();
    _pending.add(completer);
    return completer.future.whenComplete(() => activeCount--);
  }

  void completeNext(FileLoadResult result) {
    _pending.removeAt(0).complete(result);
  }
}

class _TestSelectedFiles extends SelectedFiles {
  bool get debugHasListeners => hasListeners;
}
