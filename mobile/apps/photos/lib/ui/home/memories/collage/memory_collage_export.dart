import "dart:typed_data";
import "dart:ui" show ImageByteFormat, Rect;

import "package:flutter/rendering.dart";
import "package:flutter/widgets.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";
import "package:share_plus/share_plus.dart";

class MemoryCollageExport {
  static const _expectedWidth = 1080;
  static const _expectedHeight = 1920;

  const MemoryCollageExport._();

  static Future<Uint8List> capturePng(GlobalKey repaintKey) async {
    await WidgetsBinding.instance.endOfFrame;
    RenderRepaintBoundary? boundary;
    for (var attempt = 0; attempt < 8; attempt++) {
      final renderObject = repaintKey.currentContext?.findRenderObject();
      if (renderObject is RenderRepaintBoundary &&
          !renderObject.debugNeedsPaint) {
        boundary = renderObject;
        break;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    if (boundary == null) {
      throw StateError("Memory collage did not finish painting");
    }

    final image = await boundary.toImage(
      pixelRatio: memoryCollageExportPixelRatio,
    );
    try {
      if (image.width != _expectedWidth || image.height != _expectedHeight) {
        throw StateError(
          "Unexpected memory collage size ${image.width}x${image.height}",
        );
      }
      final data = await image.toByteData(format: ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError("Unable to encode memory collage PNG");
      }
      return bytes;
    } finally {
      image.dispose();
    }
  }

  static Future<void> sharePng(
    Uint8List bytes, {
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: _filename(), mimeType: "image/png"),
        ],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static Future<void> savePng(Uint8List bytes) async {
    final filename = _filename();
    try {
      await PhotoManager.editor.saveImage(
        bytes,
        filename: filename,
        relativePath: "ente Memories",
      );
    } catch (_) {
      await PhotoManager.editor.saveImage(bytes, filename: filename);
    }
    SyncService.instance.sync().ignore();
  }

  static String _filename() =>
      "ente_memory_${DateTime.now().millisecondsSinceEpoch}.png";
}
