import "dart:async";
import "dart:io";

import "package:photos/db/file_load_trace.dart";

typedef SearchFileLoader<T> = Future<T> Function();
typedef SearchFileCacheLog = void Function(String message);

class SearchFileCacheReset implements Exception {
  const SearchFileCacheReset();

  @override
  String toString() => "Search file cache was reset for an account boundary";
}

class SearchFileSnapshot<T> {
  const SearchFileSnapshot({
    required this.value,
    required this.generation,
    required this.operationID,
  });

  final T value;
  final int generation;
  final int operationID;
}

class SearchFileRequest<T> {
  const SearchFileRequest({required this.operationID, required this.future});

  final int operationID;
  final Future<SearchFileSnapshot<T>> future;
}

/// Keeps one expensive physical load active while resolving callers with the
/// first result that is stable for the latest requested generation.
class SearchFileCache<T> {
  SearchFileCache({
    required SearchFileLoader<T> loader,
    SearchFileCacheLog? log,
  }) : _loader = loader,
       _log = log ?? _ignoreLog;

  final SearchFileLoader<T> _loader;
  final SearchFileCacheLog _log;

  int _requestedGeneration = 0;
  int _sessionGeneration = 0;
  int _nextOperationID = 0;
  int _activePhysicalLoads = 0;
  int _maximumActivePhysicalLoads = 0;
  String _nextOperationReason = "coldMiss";

  SearchFileRequest<T>? _currentRequest;
  _SearchFileOperation<T>? _activeOperation;
  Future<void>? _physicalLoadBarrier;

  bool get hasStableValue =>
      _currentRequest != null && _activeOperation == null;

  int get maximumActivePhysicalLoads => _maximumActivePhysicalLoads;

  int get requestedGeneration => _requestedGeneration;

  bool isCurrentRequest(SearchFileRequest<T> request) =>
      identical(_currentRequest, request);

  SearchFileRequest<T> request() {
    final current = _currentRequest;
    if (current != null) {
      final active = _activeOperation;
      if (active != null && identical(active.request, current)) {
        active.joinCount++;
      }
      return current;
    }

    final completer = Completer<SearchFileSnapshot<T>>();
    final operationID = ++_nextOperationID;
    final request = SearchFileRequest<T>(
      operationID: operationID,
      future: completer.future,
    );
    final operation = _SearchFileOperation<T>(
      operationID: operationID,
      sessionGeneration: _sessionGeneration,
      initialReason: _nextOperationReason,
      request: request,
      completer: completer,
    );
    _nextOperationReason = "coldMiss";
    _currentRequest = request;
    _activeOperation = operation;
    unawaited(_runUntilStable(operation));
    return request;
  }

  /// Returns true when an active logical request was retained and will resolve
  /// with a stable successor generation. A false result means the completed
  /// request was detached and consumers may release derived state immediately.
  bool invalidate({required String eventType, required String source}) {
    _requestedGeneration++;
    final operation = _activeOperation;
    if (operation == null) {
      _currentRequest = null;
      _nextOperationReason = "staleSuccessor";
      _log(
        "SearchBaseLoad invalidation eventType=$eventType source=$source "
        "operationId=none requestedGeneration=$_requestedGeneration "
        "action=markedStaleLazy",
      );
      return false;
    }

    final alreadyRequested = operation.successorRequested;
    operation.successorRequested = true;
    final action = operation.physicalActive
        ? (alreadyRequested ? "coalescedSuccessor" : "requestedSuccessor")
        : (alreadyRequested ? "coalescedBeforeStart" : "batchedBeforeStart");
    _log(
      "SearchBaseLoad invalidation eventType=$eventType source=$source "
      "operationId=${operation.operationID} "
      "activeAttemptGeneration=${operation.activeAttemptGeneration ?? 'none'} "
      "requestedGeneration=$_requestedGeneration action=$action",
    );
    return true;
  }

  /// Detaches account-scoped state immediately. The uncancellable old load is
  /// allowed to settle, but the physical gate remains held until it does.
  void resetForAccountBoundary() {
    final operation = _activeOperation;
    _sessionGeneration++;
    _requestedGeneration = 0;
    _currentRequest = null;
    _activeOperation = null;
    _nextOperationReason = "coldMiss";
    if (operation != null && !operation.completer.isCompleted) {
      operation.completer.completeError(const SearchFileCacheReset());
      _log(
        "SearchBaseLoad complete operationId=${operation.operationID} "
        "status=reset physicalAttempts=${operation.attemptCount} "
        "joinCount=${operation.joinCount} "
        "maxActivePhysicalLoads=$_maximumActivePhysicalLoads",
      );
    }
    _log(
      "SearchBaseLoad hardReset detachedOperationId="
      "${operation?.operationID ?? 'none'} sessionGeneration=$_sessionGeneration "
      "physicalLoadStillActive=${_activePhysicalLoads > 0}",
    );
  }

  Future<void> _runUntilStable(_SearchFileOperation<T> operation) async {
    while (operation.sessionGeneration == _sessionGeneration) {
      final lease = await _acquirePhysicalLease(operation);
      if (lease == null) {
        return;
      }
      if (operation.sessionGeneration != _sessionGeneration) {
        _releasePhysicalLease(
          lease,
          "SearchBaseLoad end operationId=${operation.operationID} "
          "attempt=none generation=none status=discardedResetBeforeStart "
          "maxActivePhysicalLoads=$_maximumActivePhysicalLoads "
          "${_memorySummary()}",
        );
        return;
      }

      final attempt = ++operation.attemptCount;
      final attemptGeneration = _requestedGeneration;
      operation
        ..activeAttemptGeneration = attemptGeneration
        ..physicalActive = true
        ..successorRequested = false;
      final reason = attempt == 1 ? operation.initialReason : "staleSuccessor";
      final trace = FileLoadTrace(
        family: "searchBase",
        operationID: operation.operationID,
        attempt: attempt,
        generation: attemptGeneration,
      );
      final stopwatch = Stopwatch()..start();
      final startMemory = _memorySummary();
      _log(
        "SearchBaseLoad start operationId=${operation.operationID} "
        "attempt=$attempt generation=$attemptGeneration traceId=${trace.traceID} "
        "requestedGeneration=$_requestedGeneration reason=$reason "
        "activePhysicalLoads=$_activePhysicalLoads "
        "maxActivePhysicalLoads=$_maximumActivePhysicalLoads $startMemory",
      );

      T value;
      try {
        value = await FileLoadTrace.run(trace, _loader);
      } catch (error, stackTrace) {
        stopwatch.stop();
        operation
          ..physicalActive = false
          ..activeAttemptGeneration = null;
        final reset = operation.sessionGeneration != _sessionGeneration;
        _releasePhysicalLease(
          lease,
          "SearchBaseLoad end operationId=${operation.operationID} "
          "attempt=$attempt generation=$attemptGeneration "
          "traceId=${trace.traceID} "
          "status=${reset ? 'discardedResetError' : 'error'} "
          "durationMs=${stopwatch.elapsedMilliseconds} "
          "maxActivePhysicalLoads=$_maximumActivePhysicalLoads "
          "${_memorySummary()}",
        );
        if (!reset) {
          _finishWithError(operation, error, stackTrace);
        }
        return;
      }

      stopwatch.stop();
      operation
        ..physicalActive = false
        ..activeAttemptGeneration = null;
      final reset = operation.sessionGeneration != _sessionGeneration;
      final stale = !reset && attemptGeneration != _requestedGeneration;
      final status = reset
          ? "discardedReset"
          : stale
          ? "discardedStale"
          : "published";
      _releasePhysicalLease(
        lease,
        "SearchBaseLoad end operationId=${operation.operationID} "
        "attempt=$attempt generation=$attemptGeneration "
        "traceId=${trace.traceID} status=$status "
        "durationMs=${stopwatch.elapsedMilliseconds} "
        "maxActivePhysicalLoads=$_maximumActivePhysicalLoads "
        "${_memorySummary()}",
      );

      if (reset) {
        return;
      }
      if (stale) {
        continue;
      }

      final snapshot = SearchFileSnapshot<T>(
        value: value,
        generation: attemptGeneration,
        operationID: operation.operationID,
      );
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
      if (!operation.completer.isCompleted) {
        operation.completer.complete(snapshot);
      }
      _log(
        "SearchBaseLoad complete operationId=${operation.operationID} "
        "generation=$attemptGeneration physicalAttempts=$attempt "
        "joinCount=${operation.joinCount} "
        "maxActivePhysicalLoads=$_maximumActivePhysicalLoads",
      );
      return;
    }
  }

  Future<_PhysicalLease?> _acquirePhysicalLease(
    _SearchFileOperation<T> operation,
  ) async {
    while (_physicalLoadBarrier != null) {
      await _physicalLoadBarrier;
    }
    if (operation.sessionGeneration != _sessionGeneration) {
      return null;
    }

    final completer = Completer<void>();
    final future = completer.future;
    _physicalLoadBarrier = future;
    _activePhysicalLoads++;
    if (_activePhysicalLoads > _maximumActivePhysicalLoads) {
      _maximumActivePhysicalLoads = _activePhysicalLoads;
    }
    assert(
      _activePhysicalLoads <= 1,
      "Search base-file loader concurrency exceeded one",
    );
    return _PhysicalLease(completer: completer, future: future);
  }

  void _releasePhysicalLease(_PhysicalLease lease, String endLog) {
    _activePhysicalLoads--;
    if (identical(_physicalLoadBarrier, lease.future)) {
      _physicalLoadBarrier = null;
    }
    _log("$endLog activePhysicalLoads=$_activePhysicalLoads");
    lease.completer.complete();
  }

  void _finishWithError(
    _SearchFileOperation<T> operation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (identical(_activeOperation, operation)) {
      _activeOperation = null;
    }
    if (identical(_currentRequest, operation.request)) {
      _currentRequest = null;
    }
    _nextOperationReason = "retry";
    if (!operation.completer.isCompleted) {
      operation.completer.completeError(error, stackTrace);
    }
    _log(
      "SearchBaseLoad complete operationId=${operation.operationID} "
      "status=error physicalAttempts=${operation.attemptCount} "
      "joinCount=${operation.joinCount} "
      "maxActivePhysicalLoads=$_maximumActivePhysicalLoads",
    );
  }

  static String _memorySummary() {
    try {
      const bytesPerMiB = 1024 * 1024;
      final current = ProcessInfo.currentRss / bytesPerMiB;
      final maximum = ProcessInfo.maxRss / bytesPerMiB;
      return "rssMiB=${current.toStringAsFixed(1)} "
          "maxRssMiB=${maximum.toStringAsFixed(1)}";
    } catch (_) {
      return "rssMiB=unavailable maxRssMiB=unavailable";
    }
  }

  static void _ignoreLog(String _) {}
}

class _SearchFileOperation<T> {
  _SearchFileOperation({
    required this.operationID,
    required this.sessionGeneration,
    required this.initialReason,
    required this.request,
    required this.completer,
  });

  final int operationID;
  final int sessionGeneration;
  final String initialReason;
  final SearchFileRequest<T> request;
  final Completer<SearchFileSnapshot<T>> completer;
  int attemptCount = 0;
  int joinCount = 0;
  int? activeAttemptGeneration;
  bool physicalActive = false;
  bool successorRequested = false;
}

class _PhysicalLease {
  const _PhysicalLease({required this.completer, required this.future});

  final Completer<void> completer;
  final Future<void> future;
}
