import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_surface.dart";

typedef MemoryCollageCapture = Future<Uint8List> Function(GlobalKey repaintKey);
typedef MemoryCollageFrameWait = Future<void> Function();

/// Owns the one-at-a-time export lifecycle shared by the collage viewer and
/// editor.
///
/// The coordinator mounts a frozen high-resolution snapshot, waits for its
/// original photos, captures it, and restores the action state. Cancellation
/// is an expected lifecycle outcome and is intentionally not surfaced as an
/// export failure.
class MemoryCollageExportCoordinator extends ChangeNotifier {
  final MemoryCollageCapture _capture;
  final MemoryCollageFrameWait _waitForFrame;

  MemoryCollageExportAction? _action;
  MemoryCollageExportSnapshot? _snapshot;
  bool _isDisposed = false;

  MemoryCollageExportCoordinator({
    MemoryCollageCapture? capture,
    MemoryCollageFrameWait? waitForFrame,
  }) : _capture = capture ?? MemoryCollageExport.capturePng,
       _waitForFrame = waitForFrame ?? _waitForNextFrame;

  MemoryCollageExportAction? get action => _action;

  MemoryCollageExportSnapshot? get snapshot => _snapshot;

  bool get isExporting => _action != null;

  Future<void> run({
    required MemoryCollageExportAction action,
    required MemoryCollageExportSnapshot Function() createSnapshot,
    required Future<void> Function(Uint8List bytes) usePng,
  }) async {
    if (_isDisposed || isExporting) return;

    final snapshot = createSnapshot();
    _action = action;
    _snapshot = snapshot;
    notifyListeners();

    try {
      await snapshot.waitUntilReady();
      if (_isDisposed || !identical(_snapshot, snapshot)) {
        throw const MemoryCollageExportCancelledException();
      }
      await _waitForFrame();
      if (_isDisposed || !identical(_snapshot, snapshot)) {
        throw const MemoryCollageExportCancelledException();
      }
      final bytes = await _capture(snapshot.repaintKey);
      if (_isDisposed || !identical(_snapshot, snapshot)) {
        throw const MemoryCollageExportCancelledException();
      }
      await usePng(bytes);
    } on MemoryCollageExportCancelledException {
      // Disposing the page or replacing its selection is an expected outcome.
    } finally {
      snapshot.cancel();
      if (identical(_snapshot, snapshot)) {
        _snapshot = null;
        _action = null;
        if (!_isDisposed) notifyListeners();
      }
    }
  }

  void cancelCurrent() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    _snapshot = null;
    _action = null;
    snapshot.cancel();
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    final snapshot = _snapshot;
    _snapshot = null;
    _action = null;
    snapshot?.cancel();
    super.dispose();
  }
}

Future<void> _waitForNextFrame() => WidgetsBinding.instance.endOfFrame;
