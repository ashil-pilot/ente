import "dart:async";

typedef SearchFileLoader<T> = Future<T> Function();

class SearchFileCacheReset implements Exception {
  const SearchFileCacheReset();

  @override
  String toString() => "Search file cache was reset for an account boundary";
}

class SearchFileRequest<T> {
  SearchFileRequest._() : _completer = Completer<T>();

  final Completer<T> _completer;

  Future<T> get future => _completer.future;
}

/// Coalesces callers within one account session and resolves them with the
/// first result that remains current through a complete load.
class SearchFileCache<T> {
  SearchFileCache({required SearchFileLoader<T> loader}) : _loader = loader;

  final SearchFileLoader<T> _loader;

  SearchFileRequest<T>? _currentRequest;
  int _revision = 0;

  bool isCurrentRequest(SearchFileRequest<T> request) =>
      identical(_currentRequest, request);

  SearchFileRequest<T> request() {
    final current = _currentRequest;
    if (current != null) {
      return current;
    }

    final request = SearchFileRequest<T>._();
    _currentRequest = request;
    unawaited(_runUntilCurrent(request));
    return request;
  }

  /// Returns true when the active request was retained and will reload before
  /// it completes. A false result means a completed request was detached.
  bool invalidate() {
    _revision++;
    final request = _currentRequest;
    if (request != null && !request._completer.isCompleted) {
      return true;
    }

    _currentRequest = null;
    return false;
  }

  /// Detaches account-scoped state immediately. An uncancellable old load may
  /// settle alongside work for the new session, but its result stays detached.
  void resetForAccountBoundary() {
    final request = _currentRequest;
    _revision++;
    _currentRequest = null;
    if (request != null && !request._completer.isCompleted) {
      request._completer.completeError(const SearchFileCacheReset());
    }
  }

  Future<void> _runUntilCurrent(SearchFileRequest<T> request) async {
    // Defer the first load so an account reset in the same turn can detach it
    // before any account-scoped work starts.
    await Future<void>.value();

    while (identical(_currentRequest, request)) {
      final revision = _revision;

      T value;
      try {
        value = await _loader();
      } catch (error, stackTrace) {
        if (identical(_currentRequest, request)) {
          _currentRequest = null;
          if (!request._completer.isCompleted) {
            request._completer.completeError(error, stackTrace);
          }
        }
        return;
      }

      if (!identical(_currentRequest, request)) {
        return;
      }
      if (revision != _revision) {
        continue;
      }

      if (!request._completer.isCompleted) {
        request._completer.complete(value);
      }
      return;
    }
  }
}
