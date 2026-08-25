import "dart:async";
import "dart:collection";
import "dart:io";

enum GalleryLoadExtent { limited, full }

enum GalleryLoadUrgency { normal, priority, immediate }

abstract interface class GalleryLoadTimer {
  bool get isActive;

  void cancel();
}

typedef GalleryLoadNow = DateTime Function();
typedef GalleryLoadTimerFactory =
    GalleryLoadTimer Function(Duration delay, void Function() callback);
typedef GalleryPhysicalLoader<T> =
    Future<T> Function(GalleryLoadAttempt attempt);
typedef GalleryStableResultApplier<T> =
    void Function(T result, GalleryLoadAttempt attempt);
typedef GalleryResultCount<T> = int Function(T result);
typedef GalleryLoadLog = void Function(String message);

class GalleryLoadAttempt {
  const GalleryLoadAttempt({
    required this.operationID,
    required this.generation,
    required this.extent,
    required this.force,
    required this.urgency,
    required this.reasons,
    required this.sources,
    required this.logicalRequestCount,
    required this.configurationGeneration,
    required this.hasNormalRequest,
    required this.hasPriorityRequest,
  });

  final int operationID;
  final int generation;
  final GalleryLoadExtent extent;
  final bool force;
  final GalleryLoadUrgency urgency;
  final List<String> reasons;
  final List<String> sources;
  final int logicalRequestCount;
  final int configurationGeneration;
  final bool hasNormalRequest;
  final bool hasPriorityRequest;
}

/// Serializes every physical load owned by one live Gallery State.
///
/// Logical requests merge while scheduled or active. Every request advances
/// the generation immediately, so a result known to be stale is never applied.
class GalleryLoadCoordinator<T> {
  GalleryLoadCoordinator({
    required GalleryPhysicalLoader<T> loader,
    required GalleryStableResultApplier<T> applyStableResult,
    required GalleryResultCount<T> resultCount,
    required Duration normalDebounce,
    required Duration priorityDebounce,
    required Duration maximumSchedulingInterval,
    GalleryLoadNow? now,
    GalleryLoadTimerFactory? timerFactory,
    GalleryLoadLog? log,
  }) : _loader = loader,
       _applyStableResult = applyStableResult,
       _resultCount = resultCount,
       _normalDebounce = normalDebounce,
       _priorityDebounce = priorityDebounce,
       _maximumSchedulingInterval = maximumSchedulingInterval,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? _systemTimerFactory,
       _log = log ?? _ignoreLog;

  final GalleryPhysicalLoader<T> _loader;
  final GalleryStableResultApplier<T> _applyStableResult;
  final GalleryResultCount<T> _resultCount;
  Duration _normalDebounce;
  Duration _priorityDebounce;
  Duration _maximumSchedulingInterval;
  final GalleryLoadNow _now;
  final GalleryLoadTimerFactory _timerFactory;
  final GalleryLoadLog _log;

  int _requestedGeneration = 0;
  int _nextOperationID = 0;
  int _activePhysicalLoads = 0;
  int _maximumActivePhysicalLoads = 0;
  bool _disposed = false;

  _MergedGalleryLoadRequest? _pending;
  _ActiveGalleryLoad<T>? _active;
  GalleryLoadTimer? _scheduledTimer;
  bool _scheduledLeading = false;
  DateTime? _pendingDeadline;
  DateTime? _idleSchedulingWindowStart;
  DateTime? _normalCooldownUntil;
  DateTime? _priorityCooldownUntil;

  bool get isBusy =>
      _active != null ||
      _pending != null ||
      (_scheduledTimer?.isActive ?? false);

  bool get hasActivePhysicalLoad => _active != null;

  int get requestedGeneration => _requestedGeneration;

  int get maximumActivePhysicalLoads => _maximumActivePhysicalLoads;

  int get activePhysicalLoads => _activePhysicalLoads;

  bool isGenerationCurrent(int generation) =>
      !_disposed && generation == _requestedGeneration;

  void updateScheduling({
    required Duration normalDebounce,
    required Duration priorityDebounce,
    required Duration maximumSchedulingInterval,
  }) {
    if (_disposed) return;
    _normalDebounce = normalDebounce;
    _priorityDebounce = priorityDebounce;
    _maximumSchedulingInterval = maximumSchedulingInterval;
  }

  void request({
    required GalleryLoadExtent extent,
    required bool force,
    required GalleryLoadUrgency urgency,
    required String reason,
    required String source,
    required int configurationGeneration,
  }) {
    if (_disposed) return;

    final now = _now();
    final generation = ++_requestedGeneration;
    final active = _active;
    final wasPending = _pending != null;
    final pending = _pending ??= active == null
        ? _MergedGalleryLoadRequest.empty()
        : _MergedGalleryLoadRequest.carry(active.attempt);
    pending.merge(
      generation: generation,
      extent: extent,
      force: force,
      urgency: urgency,
      reason: reason,
      source: source,
      configurationGeneration: configurationGeneration,
    );

    if (active != null) {
      _updatePendingDeadline(now, urgency, resetNormalDelay: wasPending);
      _log(
        "GalleryLoad request generation=$generation extent=${extent.name} "
        "force=$force urgency=${urgency.name} reason=$reason source=$source "
        "operationId=${active.attempt.operationID} action="
        "${wasPending ? 'coalescedWhileActive' : 'requestedSuccessor'} "
        "representedRequests=${pending.logicalRequestCount}",
      );
      return;
    }

    if (_scheduledTimer != null) {
      if (_scheduledLeading) {
        _log(
          "GalleryLoad request generation=$generation extent=${extent.name} "
          "force=$force urgency=${urgency.name} reason=$reason source=$source "
          "operationId=none action=batchedBeforeLeadingStart "
          "representedRequests=${pending.logicalRequestCount}",
        );
        return;
      }
      _updatePendingDeadline(now, urgency, resetNormalDelay: wasPending);
      _capDeadlineToMaximumInterval();
      _log(
        "GalleryLoad request generation=$generation extent=${extent.name} "
        "force=$force urgency=${urgency.name} reason=$reason source=$source "
        "operationId=none action=batchedBeforeStart "
        "representedRequests=${pending.logicalRequestCount}",
      );
      _schedulePending();
      return;
    }

    final cooldownUntil = switch (urgency) {
      GalleryLoadUrgency.normal => _normalCooldownUntil,
      GalleryLoadUrgency.priority => _priorityCooldownUntil,
      GalleryLoadUrgency.immediate => null,
    };
    if (cooldownUntil != null && cooldownUntil.isAfter(now)) {
      _pendingDeadline = now.add(
        urgency == GalleryLoadUrgency.priority
            ? _priorityDebounce
            : _normalDebounce,
      );
      _idleSchedulingWindowStart = now;
      _scheduledLeading = false;
      _log(
        "GalleryLoad request generation=$generation extent=${extent.name} "
        "force=$force urgency=${urgency.name} reason=$reason source=$source "
        "operationId=none action=scheduledTrailingCooldown "
        "representedRequests=${pending.logicalRequestCount}",
      );
      _schedulePending();
      return;
    }

    // Keep leading behavior while giving same-turn requests one zero-delay
    // scheduling boundary in which to merge before physical work begins.
    _pendingDeadline = now;
    _idleSchedulingWindowStart = now;
    _scheduledLeading = true;
    _log(
      "GalleryLoad request generation=$generation extent=${extent.name} "
      "force=$force urgency=${urgency.name} reason=$reason source=$source "
      "operationId=none action=scheduledLeading representedRequests="
      "${pending.logicalRequestCount}",
    );
    _schedulePending();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestedGeneration++;
    _scheduledTimer?.cancel();
    _scheduledTimer = null;
    _scheduledLeading = false;
    _pending = null;
    _pendingDeadline = null;
    _idleSchedulingWindowStart = null;
    _normalCooldownUntil = null;
    _priorityCooldownUntil = null;
    _log(
      "GalleryLoad dispose activeOperationId="
      "${_active?.attempt.operationID ?? 'none'} "
      "activePhysicalLoads=$_activePhysicalLoads "
      "maxActivePhysicalLoads=$_maximumActivePhysicalLoads",
    );
  }

  void _updatePendingDeadline(
    DateTime now,
    GalleryLoadUrgency newUrgency, {
    required bool resetNormalDelay,
  }) {
    if (newUrgency == GalleryLoadUrgency.immediate) {
      _pendingDeadline = now;
      return;
    }

    final effectiveUrgency = _pending!.urgency;
    if (effectiveUrgency == GalleryLoadUrgency.immediate) {
      _pendingDeadline = now;
      return;
    }

    if (effectiveUrgency == GalleryLoadUrgency.priority) {
      final priorityDeadline = now.add(_priorityDebounce);
      final current = _pendingDeadline;
      if (current == null || priorityDeadline.isBefore(current)) {
        _pendingDeadline = priorityDeadline;
      }
      return;
    }

    if (_pendingDeadline == null || resetNormalDelay) {
      _pendingDeadline = now.add(_normalDebounce);
    }
  }

  void _capDeadlineToMaximumInterval() {
    final windowStart = _idleSchedulingWindowStart;
    final deadline = _pendingDeadline;
    if (windowStart == null || deadline == null) return;
    final maximumDeadline = windowStart.add(_maximumSchedulingInterval);
    if (deadline.isAfter(maximumDeadline)) {
      _pendingDeadline = maximumDeadline;
    }
  }

  void _schedulePending() {
    if (_disposed || _active != null || _pending == null) return;
    _scheduledTimer?.cancel();
    final deadline = _pendingDeadline ?? _now();
    final delay = deadline.difference(_now());
    _scheduledTimer = _timerFactory(
      delay.isNegative ? Duration.zero : delay,
      () {
        _scheduledTimer = null;
        _scheduledLeading = false;
        _idleSchedulingWindowStart = null;
        _startPending();
      },
    );
  }

  void _startPending() {
    if (_disposed || _active != null) return;
    final request = _pending;
    if (request == null) return;
    _pending = null;
    _pendingDeadline = null;

    final attempt = request.toAttempt(++_nextOperationID);
    final startedAt = _now();
    if (attempt.hasNormalRequest) {
      _normalCooldownUntil = startedAt.add(_normalDebounce);
    }
    if (attempt.hasPriorityRequest) {
      _priorityCooldownUntil = startedAt.add(_priorityDebounce);
    }
    final active = _ActiveGalleryLoad<T>(attempt, startedAt);
    _active = active;
    _activePhysicalLoads++;
    if (_activePhysicalLoads > _maximumActivePhysicalLoads) {
      _maximumActivePhysicalLoads = _activePhysicalLoads;
    }
    assert(
      _activePhysicalLoads <= 1,
      "Gallery physical loader concurrency exceeded one",
    );
    _log(
      "GalleryLoad start operationId=${attempt.operationID} "
      "generation=${attempt.generation} extent=${attempt.extent.name} "
      "force=${attempt.force} urgency=${attempt.urgency.name} "
      "configurationGeneration=${attempt.configurationGeneration} "
      "representedRequests=${attempt.logicalRequestCount} "
      "reasons=${attempt.reasons.join('|')} sources=${attempt.sources.join('|')} "
      "activePhysicalLoads=$_activePhysicalLoads "
      "maxActivePhysicalLoads=$_maximumActivePhysicalLoads ${_memorySummary()}",
    );
    unawaited(_run(active));
  }

  Future<void> _run(_ActiveGalleryLoad<T> active) async {
    final attempt = active.attempt;
    T result;
    try {
      result = await _loader(attempt);
    } catch (error) {
      _finishPhysical(active);
      final disposed = _disposed;
      _log(
        "GalleryLoad end operationId=${attempt.operationID} "
        "generation=${attempt.generation} status="
        "${disposed ? 'discardedDisposedError' : 'error'} "
        "durationMs=${_now().difference(active.startedAt).inMilliseconds} "
        "successorPending=${_pending != null} "
        "activePhysicalLoads=$_activePhysicalLoads "
        "maxActivePhysicalLoads=$_maximumActivePhysicalLoads "
        "${_memorySummary()} error=$error",
      );
      if (!disposed) {
        _scheduleSuccessorAfterActive();
      }
      return;
    }

    _finishPhysical(active);
    final disposed = _disposed;
    final stale = !disposed && attempt.generation != _requestedGeneration;
    var status = disposed
        ? "discardedDisposed"
        : stale
        ? "discardedStale"
        : "applied";
    Object? applyError;
    if (!disposed && !stale) {
      try {
        _applyStableResult(result, attempt);
      } catch (error) {
        status = "applyError";
        applyError = error;
      }
    }

    _log(
      "GalleryLoad end operationId=${attempt.operationID} "
      "generation=${attempt.generation} status=$status "
      "resultCount=${_safeResultCount(result)} "
      "durationMs=${_now().difference(active.startedAt).inMilliseconds} "
      "successorPending=${_pending != null} "
      "activePhysicalLoads=$_activePhysicalLoads "
      "maxActivePhysicalLoads=$_maximumActivePhysicalLoads ${_memorySummary()}"
      "${applyError == null ? '' : ' error=$applyError'}",
    );
    _scheduleSuccessorAfterActive();
  }

  void _finishPhysical(_ActiveGalleryLoad<T> active) {
    if (identical(_active, active)) {
      _active = null;
    }
    _activePhysicalLoads--;
  }

  void _scheduleSuccessorAfterActive() {
    if (_disposed || _active != null || _pending == null) return;
    _idleSchedulingWindowStart = _now();
    _scheduledLeading = false;
    _capDeadlineToMaximumInterval();
    _schedulePending();
  }

  int _safeResultCount(T result) {
    try {
      return _resultCount(result);
    } catch (_) {
      return -1;
    }
  }

  static GalleryLoadTimer _systemTimerFactory(
    Duration delay,
    void Function() callback,
  ) => _DartGalleryLoadTimer(delay, callback);

  static String _memorySummary() {
    try {
      const bytesPerMiB = 1024 * 1024;
      return "rssMiB="
          "${(ProcessInfo.currentRss / bytesPerMiB).toStringAsFixed(1)} "
          "maxRssMiB="
          "${(ProcessInfo.maxRss / bytesPerMiB).toStringAsFixed(1)}";
    } catch (_) {
      return "rssMiB=unavailable maxRssMiB=unavailable";
    }
  }

  static void _ignoreLog(String _) {}
}

class _MergedGalleryLoadRequest {
  _MergedGalleryLoadRequest.empty()
    : generation = 0,
      extent = GalleryLoadExtent.limited,
      force = false,
      urgency = GalleryLoadUrgency.normal,
      logicalRequestCount = 0,
      configurationGeneration = 0,
      hasNormalRequest = false,
      hasPriorityRequest = false;

  _MergedGalleryLoadRequest.carry(GalleryLoadAttempt attempt)
    : generation = attempt.generation,
      extent = attempt.extent,
      force = attempt.force,
      urgency = GalleryLoadUrgency.normal,
      logicalRequestCount = attempt.logicalRequestCount,
      configurationGeneration = attempt.configurationGeneration,
      hasNormalRequest = false,
      hasPriorityRequest = false {
    reasons.addAll(attempt.reasons);
    sources.addAll(attempt.sources);
  }

  int generation;
  GalleryLoadExtent extent;
  bool force;
  GalleryLoadUrgency urgency;
  int logicalRequestCount;
  int configurationGeneration;
  bool hasNormalRequest;
  bool hasPriorityRequest;
  final LinkedHashSet<String> reasons = LinkedHashSet<String>();
  final LinkedHashSet<String> sources = LinkedHashSet<String>();

  void merge({
    required int generation,
    required GalleryLoadExtent extent,
    required bool force,
    required GalleryLoadUrgency urgency,
    required String reason,
    required String source,
    required int configurationGeneration,
  }) {
    this.generation = generation;
    if (extent == GalleryLoadExtent.full) {
      this.extent = GalleryLoadExtent.full;
    }
    this.force = this.force || force;
    if (urgency.index > this.urgency.index) {
      this.urgency = urgency;
    }
    if (urgency == GalleryLoadUrgency.normal) {
      hasNormalRequest = true;
    } else if (urgency == GalleryLoadUrgency.priority) {
      hasPriorityRequest = true;
    }
    if (configurationGeneration > this.configurationGeneration) {
      this.configurationGeneration = configurationGeneration;
    }
    logicalRequestCount++;
    _addBounded(reasons, reason);
    _addBounded(sources, source);
  }

  GalleryLoadAttempt toAttempt(int operationID) => GalleryLoadAttempt(
    operationID: operationID,
    generation: generation,
    extent: extent,
    force: force,
    urgency: urgency,
    reasons: List.unmodifiable(reasons),
    sources: List.unmodifiable(sources),
    logicalRequestCount: logicalRequestCount,
    configurationGeneration: configurationGeneration,
    hasNormalRequest: hasNormalRequest,
    hasPriorityRequest: hasPriorityRequest,
  );

  static void _addBounded(LinkedHashSet<String> values, String value) {
    const maximumDistinctValues = 5;
    if (values.contains(value)) return;
    if (values.length < maximumDistinctValues) {
      values.add(value);
    } else {
      values.add("multiple");
    }
  }
}

class _ActiveGalleryLoad<T> {
  const _ActiveGalleryLoad(this.attempt, this.startedAt);

  final GalleryLoadAttempt attempt;
  final DateTime startedAt;
}

class _DartGalleryLoadTimer implements GalleryLoadTimer {
  _DartGalleryLoadTimer(Duration delay, void Function() callback)
    : _timer = Timer(delay, callback);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
