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
    expect(
      requests.every((request) => identical(request, requests.first)),
      isTrue,
    );

    loader.completeNext("stable");
    final results = await Future.wait(
      requests.map((request) => request.future),
    );

    expect(results.toSet(), {"stable"});
    expect(loader.maximumActiveCount, 1);
  });

  test(
    "invalidation keeps existing and later callers on one stable operation",
    () async {
      final loader = _ControlledLoader<String>();
      final cache = SearchFileCache<String>(loader: loader.call);

      final beforeInvalidation = cache.request();
      await loader.waitForInvocationCount(1);
      cache.invalidate();
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
      expect(results, ["fresh", "fresh"]);
      expect(loader.maximumActiveCount, 1);
    },
  );

  test("an event burst coalesces into one successor", () async {
    final loader = _ControlledLoader<int>();
    final cache = SearchFileCache<int>(loader: loader.call);

    final request = cache.request();
    await loader.waitForInvocationCount(1);
    for (var index = 0; index < 10; index++) {
      cache.invalidate();
    }

    loader.completeNext(0);
    await loader.waitForInvocationCount(2);
    loader.completeNext(10);

    expect(await request.future, 10);
    expect(loader.invocationCount, 2);
    expect(loader.maximumActiveCount, 1);
  });

  test("invalidation before loading is absorbed into the first load", () async {
    final loader = _ControlledLoader<int>();
    final cache = SearchFileCache<int>(loader: loader.call);

    final request = cache.request();
    cache.invalidate();
    expect(identical(cache.request(), request), isTrue);

    await loader.waitForInvocationCount(1);
    loader.completeNext(1);
    expect(await request.future, 1);
    expect(loader.invocationCount, 1);
  });

  test(
    "an invalidation during a successor schedules serial attempt three",
    () async {
      final loader = _ControlledLoader<int>();
      final cache = SearchFileCache<int>(loader: loader.call);

      final request = cache.request();
      await loader.waitForInvocationCount(1);
      cache.invalidate();
      loader.completeNext(0);

      await loader.waitForInvocationCount(2);
      cache.invalidate();
      loader.completeNext(1);

      await loader.waitForInvocationCount(3);
      loader.completeNext(2);

      expect(await request.future, 2);
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
    expect(await first.future, 4);

    final reused = await cache.request().future;
    expect(reused, 4);
    expect(loader.invocationCount, 1);

    cache.invalidate();
    expect(loader.invocationCount, 1);
    final refreshed = cache.request();
    await loader.waitForInvocationCount(2);
    loader.completeNext(5);
    expect(await refreshed.future, 5);
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
    expect(await retry.future, 7);
    expect(loader.maximumActiveCount, 1);
  });

  test("new session does not wait for an old failing load", () async {
    final loader = _ControlledLoader<String>();
    final cache = SearchFileCache<String>(loader: loader.call);

    final oldRequest = cache.request();
    final oldExpectation = expectLater(
      oldRequest.future,
      throwsA(isA<SearchFileCacheReset>()),
    );
    await loader.waitForInvocationCount(1);
    cache.resetForAccountBoundary();
    await oldExpectation;
    final newRequest = cache.request();

    await loader.waitForInvocationCount(2);
    expect(loader.activeCount, 2);
    loader.failNext(StateError("old-account failure"));
    await Future<void>.delayed(Duration.zero);
    expect(identical(cache.request(), newRequest), isTrue);
    expect(loader.activeCount, 1);

    loader.completeNext("new-account");
    expect(await newRequest.future, "new-account");
    expect(await cache.request().future, "new-account");
    expect(loader.activeCount, 0);
    expect(loader.maximumActiveCount, 2);
  });

  test("late old-session success cannot replace a newer result", () async {
    final loader = _ControlledLoader<String>();
    final cache = SearchFileCache<String>(loader: loader.call);

    final oldRequest = cache.request();
    final oldExpectation = expectLater(
      oldRequest.future,
      throwsA(isA<SearchFileCacheReset>()),
    );
    await loader.waitForInvocationCount(1);

    cache.resetForAccountBoundary();
    await oldExpectation;
    final newRequest = cache.request();
    await loader.waitForInvocationCount(2);
    expect(loader.activeCount, 2);

    loader.completeLast("new-account");
    expect(await newRequest.future, "new-account");
    expect(loader.activeCount, 1);

    loader.completeNext("old-account");
    await Future<void>.delayed(Duration.zero);
    expect(await cache.request().future, "new-account");
    expect(loader.activeCount, 0);
    expect(loader.maximumActiveCount, 2);
  });

  test(
    "new-session successors stay serial while an old-session load settles",
    () async {
      final loader = _ControlledLoader<String>();
      final cache = SearchFileCache<String>(loader: loader.call);

      final oldRequest = cache.request();
      final oldExpectation = expectLater(
        oldRequest.future,
        throwsA(isA<SearchFileCacheReset>()),
      );
      await loader.waitForInvocationCount(1);

      cache.resetForAccountBoundary();
      await oldExpectation;
      final newRequest = cache.request();
      await loader.waitForInvocationCount(2);

      cache.invalidate();
      expect(identical(cache.request(), newRequest), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(loader.invocationCount, 2);
      expect(loader.activeCount, 2);

      loader.completeLast("stale-new-account");
      await loader.waitForInvocationCount(3);
      expect(loader.activeCount, 2);

      loader.completeLast("fresh-new-account");
      expect(await newRequest.future, "fresh-new-account");
      loader.completeNext("old-account");
      await Future<void>.delayed(Duration.zero);

      expect(await cache.request().future, "fresh-new-account");
      expect(loader.activeCount, 0);
      expect(loader.maximumActiveCount, 2);
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
    expect(await newRequest.future, "new-account");
    expect(loader.invocationCount, 1);
    expect(loader.maximumActiveCount, 1);
  });
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

  void completeLast(T value) {
    _pending.removeLast().complete(value);
  }

  void failNext(Object error) {
    _pending.removeAt(0).completeError(error);
  }
}
