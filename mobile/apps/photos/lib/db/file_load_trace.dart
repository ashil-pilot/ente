import "dart:async";

class FileLoadTrace {
  const FileLoadTrace({
    required this.family,
    required this.operationID,
    required this.attempt,
    required this.generation,
  });

  final String family;
  final int operationID;
  final int attempt;
  final int generation;

  String get traceID => "$family-$operationID-$attempt-$generation";

  static final Object _zoneKey = Object();

  static FileLoadTrace? get current => Zone.current[_zoneKey] as FileLoadTrace?;

  static Future<T> run<T>(FileLoadTrace trace, Future<T> Function() action) {
    return runZoned(action, zoneValues: {_zoneKey: trace});
  }
}
