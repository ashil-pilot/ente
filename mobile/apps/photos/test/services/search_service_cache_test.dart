import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/services/search_file_cache.dart";
import "package:photos/services/search_service.dart";

void main() {
  late StreamController<LocalPhotosUpdatedEvent> events;
  late _ControlledFileLoader baseLoader;
  late _ControlledFileLoader hiddenLoader;
  late SearchService service;
  Future<void> Function()? beforeUploadedIDDerivation;

  setUp(() {
    events = StreamController<LocalPhotosUpdatedEvent>.broadcast();
    baseLoader = _ControlledFileLoader();
    hiddenLoader = _ControlledFileLoader();
    beforeUploadedIDDerivation = null;
    service = SearchService.forTesting(
      allFilesLoader: baseLoader.call,
      hiddenFilesLoader: hiddenLoader.call,
      localPhotosUpdatedEvents: events.stream,
      beforeUploadedIDDerivation: () async {
        await beforeUploadedIDDerivation?.call();
      },
    )..init();
  });

  tearDown(() async {
    await service.debugDispose();
    await events.close();
  });

  test("all derived views share one stable base generation", () async {
    final search = service.getAllFilesForSearch();
    final hierarchy = service.getAllFilesForHierarchicalSearch();
    final uploadedGallery = service.getAllFilesForGenericGallery();
    final offlineGallery = service.getAllFilesForGenericGallery(
      onlyUploadedFiles: false,
    );
    final uploadedMap = service.debugGetFilesByUploadedID();

    await baseLoader.waitForInvocationCount(1);
    final firstUploaded = _file(generatedID: 1, uploadedID: 10);
    final duplicateUploaded = _file(generatedID: 2, uploadedID: 10);
    final local = _file(generatedID: 3, localID: "local-3");
    baseLoader.completeNext([firstUploaded, duplicateUploaded, local]);

    expect(await search, [firstUploaded, local]);
    expect(await hierarchy, [firstUploaded, duplicateUploaded]);
    expect(await uploadedGallery, [firstUploaded]);
    expect(await offlineGallery, [firstUploaded, local]);
    expect((await uploadedMap)[10], same(firstUploaded));
    expect(baseLoader.invocationCount, 1);
  });

  test("hasAny joins an already-requested Search view", () async {
    final search = service.getAllFilesForSearch();
    final hasAny = service.hasAnyFilesForSearch();
    await baseLoader.waitForInvocationCount(1);
    final file = _file(generatedID: 4, uploadedID: 4);
    baseLoader.completeNext([file]);

    expect(await search, [file]);
    expect(await hasAny, isTrue);
    expect(baseLoader.invocationCount, 1);
  });

  test(
    "idle invalidation releases every derived view without loading",
    () async {
      final views = <Future<Object>>[
        service.getAllFilesForSearch(),
        service.getAllFilesForHierarchicalSearch(),
        service.getAllFilesForGenericGallery(),
        service.getAllFilesForGenericGallery(onlyUploadedFiles: false),
        service.debugGetFilesByUploadedID(),
      ];
      await baseLoader.waitForInvocationCount(1);
      baseLoader.completeNext([_file(generatedID: 5, uploadedID: 5)]);
      await Future.wait(views);

      events.add(LocalPhotosUpdatedEvent(const [], source: "idleUpdate"));
      await Future<void>.delayed(Duration.zero);

      expect(baseLoader.invocationCount, 1);
      final refreshedSearch = service.getAllFilesForSearch();
      final refreshedHierarchy = service.getAllFilesForHierarchicalSearch();
      final refreshedGallery = service.getAllFilesForGenericGallery();
      final refreshedOfflineGallery = service.getAllFilesForGenericGallery(
        onlyUploadedFiles: false,
      );
      final refreshedUploadedMap = service.debugGetFilesByUploadedID();
      await baseLoader.waitForInvocationCount(2);
      final fresh = _file(generatedID: 6, uploadedID: 6);
      baseLoader.completeNext([fresh]);

      expect(await refreshedSearch, [fresh]);
      expect(await refreshedHierarchy, [fresh]);
      expect(await refreshedGallery, [fresh]);
      expect(await refreshedOfflineGallery, [fresh]);
      expect((await refreshedUploadedMap)[6], same(fresh));
    },
  );

  test("pre and post-event derived callers receive only fresh data", () async {
    final existingSearch = service.getAllFilesForSearch();
    await baseLoader.waitForInvocationCount(1);

    events.add(
      LocalPhotosUpdatedEvent(const [], source: "syncUpdateFromRemote"),
    );
    await Future<void>.delayed(Duration.zero);
    final laterGallery = service.getAllFilesForGenericGallery();
    final laterOfflineGallery = service.getAllFilesForGenericGallery(
      onlyUploadedFiles: false,
    );
    final laterHierarchy = service.getAllFilesForHierarchicalSearch();
    final laterUploadedMap = service.debugGetFilesByUploadedID();

    baseLoader.completeNext([_file(generatedID: 1, uploadedID: 1)]);
    await baseLoader.waitForInvocationCount(2);
    final fresh = _file(generatedID: 2, uploadedID: 2);
    baseLoader.completeNext([fresh]);

    expect(await existingSearch, [fresh]);
    expect(await laterGallery, [fresh]);
    expect(await laterOfflineGallery, [fresh]);
    expect(await laterHierarchy, [fresh]);
    expect((await laterUploadedMap)[2], same(fresh));
    expect(baseLoader.invocationCount, 2);
  });

  test("hidden files retain an independent invalidating cache", () async {
    final first = service.getHiddenFiles();
    final joined = service.getHiddenFiles();
    await hiddenLoader.waitForInvocationCount(1);
    final hiddenOne = _file(generatedID: 10, uploadedID: 10);
    hiddenLoader.completeNext([hiddenOne]);
    expect(await first, [hiddenOne]);
    expect(await joined, [hiddenOne]);
    expect(hiddenLoader.invocationCount, 1);
    expect(baseLoader.invocationCount, 0);

    events.add(LocalPhotosUpdatedEvent(const [], source: "hiddenUpdate"));
    await Future<void>.delayed(Duration.zero);
    final second = service.getHiddenFiles();
    await hiddenLoader.waitForInvocationCount(2);
    final hiddenTwo = _file(generatedID: 11, uploadedID: 11);
    hiddenLoader.completeNext([hiddenTwo]);
    expect(await second, [hiddenTwo]);
    expect(baseLoader.invocationCount, 0);
  });

  test("production account reset isolates every derived view", () async {
    final oldSearch = service.getAllFilesForSearch();
    final oldHierarchy = service.getAllFilesForHierarchicalSearch();
    final oldUploadedGallery = service.getAllFilesForGenericGallery();
    final oldOfflineGallery = service.getAllFilesForGenericGallery(
      onlyUploadedFiles: false,
    );
    final oldUploadedMap = service.debugGetFilesByUploadedID();
    final oldExpectations =
        [
              oldSearch,
              oldHierarchy,
              oldUploadedGallery,
              oldOfflineGallery,
              oldUploadedMap,
            ]
            .map(
              (future) =>
                  expectLater(future, throwsA(isA<SearchFileCacheReset>())),
            )
            .toList();
    await baseLoader.waitForInvocationCount(1);

    final previous = SearchService.debugReplaceInstanceForTesting(service);
    addTearDown(() => SearchService.debugReplaceInstanceForTesting(previous));
    SearchService.resetForAccountBoundaryIfInitialized();
    await Future.wait(oldExpectations);
    final newSearch = service.getAllFilesForSearch();
    final newHierarchy = service.getAllFilesForHierarchicalSearch();
    final newUploadedGallery = service.getAllFilesForGenericGallery();
    final newOfflineGallery = service.getAllFilesForGenericGallery(
      onlyUploadedFiles: false,
    );
    final newUploadedMap = service.debugGetFilesByUploadedID();
    await baseLoader.waitForInvocationCount(2);
    expect(baseLoader.activeCount, 2);

    final newAccountFile = _file(generatedID: 2, uploadedID: 2);
    baseLoader.completeLast([newAccountFile]);

    expect(await newSearch, [newAccountFile]);
    expect(await newHierarchy, [newAccountFile]);
    expect(await newUploadedGallery, [newAccountFile]);
    expect(await newOfflineGallery, [newAccountFile]);
    expect((await newUploadedMap)[2], same(newAccountFile));
    expect(await service.getAllFilesForSearch(), [newAccountFile]);

    baseLoader.completeNext([_file(generatedID: 1, uploadedID: 1)]);
    await Future<void>.delayed(Duration.zero);
    expect(await service.getAllFilesForSearch(), [newAccountFile]);
    expect(baseLoader.activeCount, 0);
  });

  test(
    "late old uploaded-map work cannot replace a newer Search view",
    () async {
      final oldDerivationStarted = Completer<void>();
      final releaseOldDerivation = Completer<void>();
      beforeUploadedIDDerivation = () {
        oldDerivationStarted.complete();
        return releaseOldDerivation.future;
      };

      final oldUploadedMap = service.debugGetFilesByUploadedID();
      await baseLoader.waitForInvocationCount(1);
      final oldFile = _file(generatedID: 30, uploadedID: 30);
      baseLoader.completeNext([oldFile]);
      await oldDerivationStarted.future;

      events.add(LocalPhotosUpdatedEvent(const [], source: "newGeneration"));
      await Future<void>.delayed(Duration.zero);
      beforeUploadedIDDerivation = null;
      final newSearch = service.getAllFilesForSearch();
      await baseLoader.waitForInvocationCount(2);

      releaseOldDerivation.complete();
      expect((await oldUploadedMap)[30], same(oldFile));
      expect(identical(service.getAllFilesForSearch(), newSearch), isTrue);

      final freshFile = _file(generatedID: 31, uploadedID: 31);
      baseLoader.completeNext([freshFile]);
      expect(await newSearch, [freshFile]);
    },
  );

  test("a hidden-file failure is not permanently cached", () async {
    final first = service.getHiddenFiles();
    final expectation = expectLater(first, throwsA(isA<StateError>()));
    await hiddenLoader.waitForInvocationCount(1);
    hiddenLoader.failNext(StateError("hidden query failed"));
    await expectation;

    final retry = service.getHiddenFiles();
    await hiddenLoader.waitForInvocationCount(2);
    final hidden = _file(generatedID: 12, uploadedID: 12);
    hiddenLoader.completeNext([hidden]);
    expect(await retry, [hidden]);
  });

  test("a synchronous hidden-file failure is retryable", () async {
    final hidden = _file(generatedID: 13, uploadedID: 13);
    var shouldFail = true;
    final synchronousService = SearchService.forTesting(
      allFilesLoader: baseLoader.call,
      hiddenFilesLoader: () {
        if (shouldFail) {
          shouldFail = false;
          throw StateError("synchronous hidden query failure");
        }
        return Future.value([hidden]);
      },
      localPhotosUpdatedEvents: events.stream,
    );

    await expectLater(
      synchronousService.getHiddenFiles(),
      throwsA(isA<StateError>()),
    );
    expect(await synchronousService.getHiddenFiles(), [hidden]);
  });

  test("a base failure does not poison a derived view", () async {
    final first = service.getAllFilesForSearch();
    final expectation = expectLater(first, throwsA(isA<StateError>()));
    await baseLoader.waitForInvocationCount(1);
    baseLoader.failNext(StateError("base query failed"));
    await expectation;

    final retry = service.getAllFilesForSearch();
    await baseLoader.waitForInvocationCount(2);
    final file = _file(generatedID: 20, uploadedID: 20);
    baseLoader.completeNext([file]);
    expect(await retry, [file]);
  });
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

class _ControlledFileLoader {
  final List<Completer<List<EnteFile>>> _pending = [];
  final List<({int target, Completer<void> completer})> _waiters = [];
  int invocationCount = 0;

  int get activeCount => _pending.length;

  Future<List<EnteFile>> call() {
    invocationCount++;
    final completer = Completer<List<EnteFile>>();
    _pending.add(completer);
    for (final waiter in _waiters.toList()) {
      if (invocationCount >= waiter.target) {
        waiter.completer.complete();
        _waiters.remove(waiter);
      }
    }
    return completer.future;
  }

  Future<void> waitForInvocationCount(int expected) {
    if (invocationCount >= expected) return Future.value();
    final completer = Completer<void>();
    _waiters.add((target: expected, completer: completer));
    return completer.future;
  }

  void completeNext(List<EnteFile> files) {
    _pending.removeAt(0).complete(files);
  }

  void completeLast(List<EnteFile> files) {
    _pending.removeLast().complete(files);
  }

  void failNext(Object error) {
    _pending.removeAt(0).completeError(error);
  }
}
