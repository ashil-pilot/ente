import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/gallery/gallery_load_coordinator.dart";

void main() {
  test("force and soft requests batch before one leading load", () async {
    final harness = _Harness();

    harness.request(force: true, reason: "remoteSyncForce");
    harness.request(reason: "syncUpdateFromRemote");
    expect(harness.loader.invocationCount, 0);

    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    final attempt = harness.loader.attempts.single;
    expect(attempt.force, isTrue);
    expect(attempt.logicalRequestCount, 2);
    expect(attempt.generation, 2);

    harness.loader.completeNext("stable");
    await harness.waitForAppliedCount(1);
    expect(harness.applied.single.value, "stable");
    harness.expectSerialized();
  });

  test(
    "initial limited plus priority and force becomes one successor",
    () async {
      final harness = _Harness();
      harness.request(
        extent: GalleryLoadExtent.limited,
        urgency: GalleryLoadUrgency.immediate,
        reason: "initialLimited",
      );
      harness.scheduler.flush();
      await harness.loader.waitForInvocationCount(1);

      harness.request(
        urgency: GalleryLoadUrgency.priority,
        reason: "recentLocal",
      );
      harness.request(force: true, reason: "newFilesDisplay");
      harness.loader.completeNext("stale-preview");
      await harness.settle();
      expect(harness.applied, isEmpty);

      harness.scheduler.advance(const Duration(milliseconds: 200));
      await harness.loader.waitForInvocationCount(2);
      final successor = harness.loader.attempts.last;
      expect(successor.extent, GalleryLoadExtent.full);
      expect(successor.force, isTrue);
      expect(successor.logicalRequestCount, 3);

      harness.loader.completeNext("fresh-full");
      await harness.waitForAppliedCount(1);
      expect(harness.applied.single.value, "fresh-full");
      harness.expectSerialized();
    },
  );

  test("ten updates during one attempt produce one successor", () async {
    final harness = _Harness();
    harness.request(reason: "initial");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);

    for (var index = 0; index < 10; index++) {
      harness.request(reason: "update-$index");
    }
    harness.scheduler.advance(const Duration(seconds: 3));
    expect(harness.loader.invocationCount, 1);
    harness.loader.completeNext("stale");
    await harness.settle();
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(2);

    harness.loader.completeNext("fresh");
    await harness.waitForAppliedCount(1);
    expect(harness.loader.invocationCount, 2);
    expect(harness.applied.single.value, "fresh");
    harness.expectSerialized();
  });

  test("an update during the successor schedules attempt three", () async {
    final harness = _Harness();
    harness.request(reason: "initial");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.request(reason: "first-update");
    harness.scheduler.advance(const Duration(seconds: 2));
    harness.loader.completeNext("stale-1");
    await harness.settle();
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(2);

    harness.request(reason: "second-update");
    harness.scheduler.advance(const Duration(seconds: 2));
    harness.loader.completeNext("stale-2");
    await harness.settle();
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(3);
    harness.loader.completeNext("stable-3");
    await harness.waitForAppliedCount(1);

    expect(harness.applied.single.value, "stable-3");
    harness.expectSerialized();
  });

  test("normal and priority requests share the physical limit", () async {
    final harness = _Harness();
    harness.request(reason: "normal");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.request(urgency: GalleryLoadUrgency.priority, reason: "priority");

    harness.scheduler.advance(const Duration(seconds: 1));
    expect(harness.loader.invocationCount, 1);
    harness.loader.completeNext("stale");
    await harness.settle();
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(2);
    harness.loader.completeNext("fresh");
    await harness.waitForAppliedCount(1);
    harness.expectSerialized();
  });

  test(
    "force semantics and latest configuration survive stale attempts",
    () async {
      final harness = _Harness();
      harness.request(
        force: true,
        reason: "sortChanged",
        configurationGeneration: 1,
      );
      harness.scheduler.flush();
      await harness.loader.waitForInvocationCount(1);
      harness.request(reason: "softAfterForce", configurationGeneration: 2);
      harness.scheduler.advance(const Duration(seconds: 2));
      harness.loader.completeNext("old-sort");
      await harness.settle();
      harness.scheduler.flush();
      await harness.loader.waitForInvocationCount(2);

      final successor = harness.loader.attempts.last;
      expect(successor.force, isTrue);
      expect(successor.configurationGeneration, 2);
      harness.loader.completeNext("latest-sort");
      await harness.waitForAppliedCount(1);
      expect(harness.applied.single.value, "latest-sort");
      harness.expectSerialized();
    },
  );

  test("failure clears active state and a later request retries", () async {
    final harness = _Harness();
    harness.request(reason: "first");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.loader.failNext(StateError("load failed"));
    await harness.settle();
    expect(harness.applied, isEmpty);

    harness.request(reason: "retry");
    harness.scheduler.advance(const Duration(seconds: 2));
    await harness.loader.waitForInvocationCount(2);
    harness.loader.completeNext("recovered");
    await harness.waitForAppliedCount(1);
    expect(harness.applied.single.value, "recovered");
    harness.expectSerialized();
  });

  test("failure with newer work runs exactly one successor", () async {
    final harness = _Harness();
    harness.request(reason: "first");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.request(reason: "newer");
    harness.scheduler.advance(const Duration(seconds: 2));
    harness.loader.failNext(StateError("old attempt failed"));
    await harness.settle();
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(2);
    harness.loader.completeNext("successor");
    await harness.waitForAppliedCount(1);

    expect(harness.loader.invocationCount, 2);
    expect(harness.applied.single.value, "successor");
    harness.expectSerialized();
  });

  test("dispose cancels scheduling and ignores an active completion", () async {
    final harness = _Harness();
    harness.request(reason: "active");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.request(reason: "pending");

    harness.coordinator.dispose();
    harness.loader.completeNext("disposed-result");
    await harness.settle();
    harness.scheduler.advance(const Duration(days: 1));

    expect(harness.applied, isEmpty);
    expect(harness.loader.invocationCount, 1);
    harness.expectSerialized();
  });

  test(
    "expired successor deadline waits for active load then starts",
    () async {
      final harness = _Harness();
      harness.request(reason: "active");
      harness.scheduler.flush();
      await harness.loader.waitForInvocationCount(1);
      harness.request(reason: "successor");

      harness.scheduler.advance(const Duration(seconds: 3));
      expect(harness.loader.invocationCount, 1);
      harness.loader.completeNext("stale");
      await harness.settle();
      harness.scheduler.flush();
      await harness.loader.waitForInvocationCount(2);
      harness.loader.completeNext("fresh");
      await harness.waitForAppliedCount(1);
      harness.expectSerialized();
    },
  );

  test("continuous idle scheduling is capped by maximum interval", () async {
    final harness = _Harness();
    harness.request(reason: "active");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.request(reason: "pending-0");
    harness.loader.completeNext("stale");
    await harness.settle();

    for (var second = 1; second < 5; second++) {
      harness.scheduler.advance(const Duration(seconds: 1));
      harness.request(reason: "pending-$second");
      expect(harness.loader.invocationCount, 1);
    }
    harness.scheduler.advance(const Duration(seconds: 1));
    await harness.loader.waitForInvocationCount(2);
    harness.loader.completeNext("stable");
    await harness.waitForAppliedCount(1);

    expect(harness.scheduler.elapsed, const Duration(seconds: 5));
    harness.expectSerialized();
  });

  test("request after a fast stable load honors trailing cooldown", () async {
    final harness = _Harness();
    harness.request(reason: "leading");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.scheduler.advance(const Duration(milliseconds: 1500));
    harness.loader.completeNext("stable-leading");
    await harness.waitForAppliedCount(1);

    harness.request(reason: "just-after-completion");
    harness.scheduler.advance(const Duration(milliseconds: 1999));
    expect(harness.loader.invocationCount, 1);
    harness.scheduler.advance(const Duration(milliseconds: 1));
    await harness.loader.waitForInvocationCount(2);
    harness.loader.completeNext("stable-trailing");
    await harness.waitForAppliedCount(2);

    expect(harness.applied.last.value, "stable-trailing");
    harness.expectSerialized();
  });

  test("updated scheduling durations apply to later requests", () async {
    final harness = _Harness();
    harness.request(reason: "initial");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.request(reason: "pending");
    harness.loader.completeNext("stale");
    await harness.settle();

    harness.coordinator.updateScheduling(
      normalDebounce: const Duration(milliseconds: 50),
      priorityDebounce: const Duration(milliseconds: 10),
      maximumSchedulingInterval: const Duration(seconds: 1),
    );
    harness.scheduler.advance(const Duration(seconds: 2));
    await harness.loader.waitForInvocationCount(2);
    harness.loader.completeNext("stable");
    await harness.waitForAppliedCount(1);

    harness.request(reason: "later");
    harness.scheduler.advance(const Duration(milliseconds: 49));
    expect(harness.loader.invocationCount, 2);
    harness.scheduler.advance(const Duration(milliseconds: 1));
    await harness.loader.waitForInvocationCount(3);
    harness.request(reason: "later-pending");
    harness.loader.completeNext("later-stale");
    await harness.settle();
    harness.scheduler.advance(const Duration(milliseconds: 49));
    expect(harness.loader.invocationCount, 3);
    harness.scheduler.advance(const Duration(milliseconds: 1));
    await harness.loader.waitForInvocationCount(4);
    harness.loader.completeNext("later-stable");
    await harness.waitForAppliedCount(2);
    harness.expectSerialized();
  });

  test("logs expose operation, coalescing, counts, status, and RSS", () async {
    final logs = <String>[];
    final harness = _Harness(log: logs.add);
    harness.request(reason: "first");
    harness.request(reason: "batched");
    harness.scheduler.flush();
    await harness.loader.waitForInvocationCount(1);
    harness.loader.completeNext("value");
    await harness.waitForAppliedCount(1);

    expect(
      logs.any((line) => line.contains("batchedBeforeLeadingStart")),
      isTrue,
    );
    expect(
      logs.any((line) => line.contains("GalleryLoad start operationId=1")),
      isTrue,
    );
    expect(logs.any((line) => line.contains("representedRequests=2")), isTrue);
    expect(logs.any((line) => line.contains("status=applied")), isTrue);
    expect(
      logs.any((line) => line.contains("maxActivePhysicalLoads=1")),
      isTrue,
    );
    expect(logs.any((line) => line.contains("rssMiB=")), isTrue);
    harness.expectSerialized();
  });
}

class _Harness {
  _Harness({GalleryLoadLog? log}) {
    coordinator = GalleryLoadCoordinator<String>(
      loader: loader.call,
      applyStableResult: (value, attempt) {
        applied.add((value: value, attempt: attempt));
        for (final waiter in _applicationWaiters.toList()) {
          if (applied.length >= waiter.target) {
            waiter.completer.complete();
            _applicationWaiters.remove(waiter);
          }
        }
      },
      resultCount: (value) => value.length,
      normalDebounce: const Duration(seconds: 2),
      priorityDebounce: const Duration(milliseconds: 200),
      maximumSchedulingInterval: const Duration(seconds: 5),
      now: scheduler.now,
      timerFactory: scheduler.createTimer,
      log: log,
    );
  }

  final _FakeScheduler scheduler = _FakeScheduler();
  final _ControlledLoader<String> loader = _ControlledLoader<String>();
  final List<({String value, GalleryLoadAttempt attempt})> applied = [];
  final List<({int target, Completer<void> completer})> _applicationWaiters =
      [];
  late final GalleryLoadCoordinator<String> coordinator;

  void request({
    GalleryLoadExtent extent = GalleryLoadExtent.full,
    bool force = false,
    GalleryLoadUrgency urgency = GalleryLoadUrgency.normal,
    String reason = "update",
    int configurationGeneration = 0,
  }) {
    coordinator.request(
      extent: extent,
      force: force,
      urgency: urgency,
      reason: reason,
      source: "test",
      configurationGeneration: configurationGeneration,
    );
  }

  Future<void> waitForAppliedCount(int count) {
    if (applied.length >= count) return Future.value();
    final completer = Completer<void>();
    _applicationWaiters.add((target: count, completer: completer));
    return completer.future;
  }

  Future<void> settle() async {
    await Future<void>.value();
    await Future<void>.delayed(Duration.zero);
  }

  void expectSerialized() {
    expect(loader.maximumActiveCount, 1);
    expect(coordinator.maximumActivePhysicalLoads, 1);
  }
}

class _ControlledLoader<T> {
  final List<Completer<T>> _pending = [];
  final List<({int target, Completer<void> completer})> _waiters = [];
  final List<GalleryLoadAttempt> attempts = [];
  int invocationCount = 0;
  int activeCount = 0;
  int maximumActiveCount = 0;

  Future<T> call(GalleryLoadAttempt attempt) {
    invocationCount++;
    activeCount++;
    maximumActiveCount = maximumActiveCount < activeCount
        ? activeCount
        : maximumActiveCount;
    attempts.add(attempt);
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

  Future<void> waitForInvocationCount(int count) {
    if (invocationCount >= count) return Future.value();
    final completer = Completer<void>();
    _waiters.add((target: count, completer: completer));
    return completer.future;
  }

  void completeNext(T value) => _pending.removeAt(0).complete(value);

  void failNext(Object error) => _pending.removeAt(0).completeError(error);
}

class _FakeScheduler {
  final DateTime _epoch = DateTime.utc(2026);
  final List<_FakeTimer> _timers = [];
  Duration elapsed = Duration.zero;

  DateTime now() => _epoch.add(elapsed);

  GalleryLoadTimer createTimer(Duration delay, void Function() callback) {
    final timer = _FakeTimer(now().add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  void flush() => advance(Duration.zero);

  void advance(Duration duration) {
    final target = now().add(duration);
    while (true) {
      final due =
          _timers
              .where(
                (timer) => timer.isActive && !timer.deadline.isAfter(target),
              )
              .toList()
            ..sort(
              (first, second) => first.deadline.compareTo(second.deadline),
            );
      if (due.isEmpty) break;
      final timer = due.first;
      elapsed = timer.deadline.difference(_epoch);
      timer.fire();
    }
    elapsed = target.difference(_epoch);
  }
}

class _FakeTimer implements GalleryLoadTimer {
  _FakeTimer(this.deadline, this._callback);

  final DateTime deadline;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }
}
