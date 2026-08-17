import "dart:async";

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_photo.dart";

enum _MemoryCollageExportCompletion { ready, cancelled }

class MemoryCollageExportCancelledException implements Exception {
  const MemoryCollageExportCancelledException();

  @override
  String toString() => "Memory collage export was cancelled";
}

/// An immutable selection and readiness session for one transient export.
///
/// The list and its file identities are frozen when the snapshot is created.
/// A photo callback only counts when it carries the exact file originally
/// assigned to that slot, so callbacks from another or cancelled surface
/// cannot make this export ready.
class MemoryCollageExportSnapshot {
  static const defaultReadyTimeout = Duration(minutes: 2);
  static int _nextID = 0;

  final List<EnteFile> files;
  final String title;
  final String templateID;
  final String backgroundAssetID;

  final Completer<_MemoryCollageExportCompletion> _completion = Completer();
  final Set<int> _readySlots = {};
  final int _id;

  bool _isReady = false;
  bool _isCancelled = false;

  late final GlobalKey repaintKey = GlobalKey(
    debugLabel: "memory-collage-export-$_id",
  );

  MemoryCollageExportSnapshot({
    required Iterable<EnteFile> files,
    required this.title,
    required this.templateID,
    required this.backgroundAssetID,
  }) : files = List<EnteFile>.unmodifiable(files),
       _id = _nextID++ {
    if (this.files.isEmpty) {
      _isReady = true;
      _completion.complete(_MemoryCollageExportCompletion.ready);
    }
  }

  bool get isReady => _isReady;

  bool get isCancelled => _isCancelled;

  int get readySlotCount => _readySlots.length;

  /// Waits for each frozen slot to report its full-resolution photo once.
  ///
  /// The wait is bounded generously enough for seven originals to download and
  /// decode on a mobile connection. A timeout only ends that waiter; it does
  /// not poison the snapshot, so a caller may keep the surface mounted and
  /// retry.
  Future<void> waitUntilReady({Duration timeout = defaultReadyTimeout}) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, "timeout", "must be positive");
    }
    final result = await _completion.future.timeout(timeout);
    if (result == _MemoryCollageExportCompletion.cancelled) {
      throw const MemoryCollageExportCancelledException();
    }
  }

  /// Records a ready slot if [file] is the original object for [slot].
  ///
  /// Returns true only for the first valid report for a slot.
  bool markPhotoLoaded({required EnteFile file, required int slot}) {
    if (_isReady || _isCancelled || slot < 0 || slot >= files.length) {
      return false;
    }
    if (!identical(file, files[slot]) || !_readySlots.add(slot)) {
      return false;
    }
    if (_readySlots.length == files.length) {
      _isReady = true;
      _completion.complete(_MemoryCollageExportCompletion.ready);
    }
    return true;
  }

  /// Cancels an incomplete snapshot and immediately releases its waiters.
  ///
  /// Returns true only when this call performs the cancellation.
  bool cancel() {
    if (_isReady || _isCancelled) return false;
    _isCancelled = true;
    _completion.complete(_MemoryCollageExportCompletion.cancelled);
    return true;
  }
}

/// A non-interactive, semantics-free 360 x 640 surface for high-resolution
/// collage capture.
class MemoryCollageExportSurface extends StatefulWidget {
  final MemoryCollageManifest manifest;
  final MemoryCollageExportSnapshot snapshot;

  @visibleForTesting
  final MemoryCollageExportPhotoTestBuilder? testPhotoBuilder;

  const MemoryCollageExportSurface({
    required this.manifest,
    required this.snapshot,
    this.testPhotoBuilder,
    super.key,
  });

  @override
  State<MemoryCollageExportSurface> createState() =>
      _MemoryCollageExportSurfaceState();
}

class _MemoryCollageExportSurfaceState
    extends State<MemoryCollageExportSurface> {
  @override
  void didUpdateWidget(covariant MemoryCollageExportSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      oldWidget.snapshot.cancel();
    }
  }

  @override
  void dispose() {
    widget.snapshot.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final template = widget.manifest.templateFor(snapshot.templateID);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: memoryCollageLogicalSize,
          child: RepaintBoundary(
            key: snapshot.repaintKey,
            child: MemoryCollageCanvasView(
              manifest: widget.manifest,
              files: snapshot.files,
              title: snapshot.title,
              templateID: snapshot.templateID,
              backgroundAssetID: snapshot.backgroundAssetID,
              photoBuilder: (context, file, slot) {
                return MemoryCollageExportPhoto(
                  key: ValueKey("memory-collage-export-${snapshot._id}-$slot"),
                  file: file,
                  tagPrefix: "memory-collage-export-${snapshot._id}-$slot-",
                  targetPixelSize: memoryCollageExportTargetPixelSize(
                    template,
                    slot,
                  ),
                  testPhotoBuilder: widget.testPhotoBuilder,
                  onFinalImageLoaded: () =>
                      snapshot.markPhotoLoaded(file: file, slot: slot),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns the authored pixel size occupied by a photo slot on the 1080 x
/// 1920 export canvas.
@visibleForTesting
Size memoryCollageExportTargetPixelSize(
  MemoryCollageTemplate template,
  int slot,
) {
  final photoSlot = template.photoSlot(slot);
  const totalBleed = memoryCollagePhotoBleedCanvasPixels * 2;
  return Size(
    photoSlot.rect.width + totalBleed,
    photoSlot.rect.height + totalBleed,
  );
}
