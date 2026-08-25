import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photos/services/search_file_cache.dart";

void main() {
  test("concurrent callers reuse one physical load", () async {
    final loader = _ControlledLoader<String>();
    final cache = SearchFileCache<String>(loader: loader.call);

    final requests = List.generate(6, (_) => cache.request());
    await loader.waitForInvocationCount(1);
    expect(loader.invocationCount, 1);
    expect(requests.map((request) => request.operationID).toSet(), {1});

    loader.completeNext("stable");
    final snapshots = await Future.wait(
      requests.map((request) => request.future),
    );

    expect(snapshots.map((snapshot) => snapshot.value).toSet(), {"stable"});
    expect(loader.maximumActiveCount, 1);
    expect(cache.maximumActivePhysicalLoads, 1);
  });

  test(
    "invalidation keeps existing and later callers on one stable operation",
    () async {
      final loader = _ControlledLoader<String>();
      final cache = SearchFileCache<String>(loader: loader.call);

      final beforeInvalidation = cache.request();
      await loader.waitForInvocationCount(1);
      cache.invalidate(eventType: "addedOrUpdated", source: "remoteSync");
      final afterInvalidation = cache.request();

      loader.completeNext("stale");
      await loader.waitForInvocationCount(2);
      expect(loader.activeCount, 1);
      expect(loader.invocationCount, 2);

      loader.completeNext("fresh");
      final results = await Future.wait([
        beforeInvalidation.future,
        afterInvalidation.future,
      ]);
      expect(results.map((snapshot) => snapshot.value), ["fresh", "fresh"]);
      expect(results.map((snapshot) => snapshot.generation), [1, 1]);
      expect(loader.maximumActiveCount, 1);
    },
  );

  test("an event burst coalesces into one successor", () async {
    final loader = _ControlledLoader<int>();
    final cache = SearchFileCache<int>(loader: loader.call);

    final request = cache.request();
    await loader.waitForInvocationCount(1);
    for (var index = 0; index < 10; index++) {
      cache.invalidate(eventType: "addedOrUpdated", source: "burst");
    }

    loader.completeNext(0);
    await loader.waitForInvocationCount(2);
    loader.completeNext(10);

    final snapshot = await request.future;
    expect(snapshot.value, 10);
    expect(snapshot.generation, 10);
    expect(loader.invocationCount, 2);
    expect(loader.maximumActiveCount, 1);
  });

  test(
    "an invalidation during a successor schedules serial attempt three",
    () async {
      final loader = _ControlledLoader<int>();
      final cache = SearchFileCache<int>(loader: loader.call);

      final request = cache.request();
      await loader.waitForInvocationCount(1);
      cache.invalidate(eventType: "addedOrUpdated", source: "first");
      loader.completeNext(0);

      await loader.waitForInvocationCount(2);
      cache.invalidate(eventType: "addedOrUpdated", source: "second");
      loader.completeNext(1);

      await loader.waitForInvocationCount(3);
      loader.completeNext(2);

      final snapshot = await request.future;
      expect(snapshot.value, 2);
      expect(snapshot.generation, 2);
      expect(loader.invocationCount, 3);
      expect(loader.maximumActiveCount, 1);
    },
  );

  test("a completed stable generation is reused until invalidated", () async {
    final loader = _ControlledLoader<int>();
    final cache = SearchFileCache<int>(loader: loader.call);

    final first = cache.request();
    await loader.waitForInvocationCount(1);
    loader.completeNext(4);
    expect((await first.future).value, 4);

    final reused = await cache.request().future;
    expect(reused.value, 4);
    expect(loader.invocationCount, 1);

    cache.invalidate(eventType: "deletedFromRemote", source: "sync");
    expect(loader.invocationCount, 1);
    final refreshed = cache.request();
    await loader.waitForInvocationCount(2);
    loader.completeNext(5);
    expect((await refreshed.future).value, 5);
    expect(loader.maximumActiveCount, 1);
  });

  test("a failed operation is shared and a later demand retries", () async {
    final loader = _ControlledLoader<int>();
    final cache = SearchFileCache<int>(loader: loader.call);

    final first = cache.request();
    final joined = cache.request();
    final firstExpectation = expectLater(
      first.future,
      throwsA(isA<StateError>()),
    );
    final joinedExpectation = expectLater(
      joined.future,
      throwsA(isA<StateError>()),
    );
    await loader.waitForInvocationCount(1);
    loader.failNext(StateError("query failed"));
    await Future.wait([firstExpectation, joinedExpectation]);

    final retry = cache.request();
    await loader.waitForInvocationCount(2);
    loader.completeNext(7);
    expect((await retry.future).value, 7);
    expect(loader.maximumActiveCount, 1);
  });

  test(
    "hard reset isolates sessions while retaining the physical gate",
    () async {
      final loader = _ControlledLoader<String>();
      final logs = <String>[];
      final cache = SearchFileCache<String>(loader: loader.call, log: logs.add);

      final oldRequest = cache.request();
      final oldExpectation = expectLater(
        oldRequest.future,
        throwsA(isA<SearchFileCacheReset>()),
      );
      await loader.waitForInvocationCount(1);
      cache.resetForAccountBoundary();
      final newRequest = cache.request();

      await Future<void>.delayed(Duration.zero);
      expect(loader.invocationCount, 1);
      loader.completeNext("old-account");
      await oldExpectation;

      await loader.waitForInvocationCount(2);
      loader.completeNext("new-account");
      expect((await newRequest.future).value, "new-account");
      expect((await cache.request().future).value, "new-account");
      expect(loader.maximumActiveCount, 1);
      expect(cache.maximumActivePhysicalLoads, 1);
      expect(
        logs.any((line) => line.contains("status=discardedReset")),
        isTrue,
      );
    },
  );

  test("hard reset before invocation cancels old physical work", () async {
    final loader = _ControlledLoader<String>();
    final cache = SearchFileCache<String>(loader: loader.call);

    final oldRequest = cache.request();
    final oldExpectation = expectLater(
      oldRequest.future,
      throwsA(isA<SearchFileCacheReset>()),
    );
    cache.resetForAccountBoundary();
    final newRequest = cache.request();

    await oldExpectation;
    await loader.waitForInvocationCount(1);
    loader.completeNext("new-account");
    expect((await newRequest.future).value, "new-account");
    expect(loader.invocationCount, 1);
    expect(loader.maximumActiveCount, 1);
  });

  test(
    "logs expose generations, coalescing, counts, timings, and RSS",
    () async {
      final loader = _ControlledLoader<int>();
      final logs = <String>[];
      final cache = SearchFileCache<int>(loader: loader.call, log: logs.add);

      final request = cache.request();
      await loader.waitForInvocationCount(1);
      cache.invalidate(eventType: "addedOrUpdated", source: "remoteSync");
      cache.invalidate(eventType: "addedOrUpdated", source: "remoteSync");
      loader.completeNext(1);
      await loader.waitForInvocationCount(2);
      loader.completeNext(2);
      await request.future;

      expect(logs.any((line) => line.contains("SearchBaseLoad start")), isTrue);
      expect(logs.any((line) => line.contains("coalescedSuccessor")), isTrue);
      expect(logs.any((line) => line.contains("durationMs=")), isTrue);
      expect(logs.any((line) => line.contains("activePhysicalLoads=")), isTrue);
      expect(
        logs.any((line) => line.contains("maxActivePhysicalLoads=1")),
        isTrue,
      );
      expect(logs.any((line) => line.contains("rssMiB=")), isTrue);
      expect(logs.any((line) => line.contains("physicalAttempts=2")), isTrue);
    },
  );
}

class _ControlledLoader<T> {
  final List<Completer<T>> _pending = [];
  final List<({int target, Completer<void> completer})> _waiters = [];
  int invocationCount = 0;
  int activeCount = 0;
  int maximumActiveCount = 0;

  Future<T> call() {
    invocationCount++;
    activeCount++;
    if (activeCount > maximumActiveCount) {
      maximumActiveCount = activeCount;
    }
    final completer = Completer<T>();
    _pending.add(completer);
    for (final waiter in _waiters.toList()) {
      if (invocationCount >= waiter.target) {
        waiter.completer.complete();
        _waiters.remove(waiter);
      }
    }
    return completer.future.whenComplete(() => activeCount--);
  }

  Future<void> waitForInvocationCount(int expected) {
    if (invocationCount >= expected) {
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add((target: expected, completer: completer));
    return completer.future;
  }

  void completeNext(T value) {
    _pending.removeAt(0).complete(value);
  }

  void failNext(Object error) {
    _pending.removeAt(0).completeError(error);
  }
}
