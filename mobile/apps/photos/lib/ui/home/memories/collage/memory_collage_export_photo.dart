import "dart:math" as math;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";

typedef MemoryCollageExportPhotoTestBuilder =
    Widget Function(BuildContext context, VoidCallback onFinalImageLoaded);

/// A noninteractive original-photo renderer used only by the transient export
/// surface.
class MemoryCollageExportPhoto extends StatelessWidget {
  final EnteFile file;
  final String tagPrefix;
  final Size targetPixelSize;
  final VoidCallback onFinalImageLoaded;

  @visibleForTesting
  final MemoryCollageExportPhotoTestBuilder? testPhotoBuilder;

  const MemoryCollageExportPhoto({
    required this.file,
    required this.tagPrefix,
    required this.targetPixelSize,
    required this.onFinalImageLoaded,
    this.testPhotoBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final decodeTarget = memoryCollageExportDecodeTarget(file, targetPixelSize);
    final photo =
        testPhotoBuilder?.call(context, onFinalImageLoaded) ??
        ZoomableImage(
          file,
          tagPrefix: tagPrefix,
          shouldCover: true,
          isFromMemories: true,
          showCaption: false,
          showLoadingIndicator: false,
          cacheWidth: decodeTarget.cacheWidth,
          cacheHeight: decodeTarget.cacheHeight,
          // The canvas owns the natural paper/film empty-window color. Keeping
          // this transparent makes preview and export agree at rounded or
          // transparent image edges.
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
          onFinalImageLoaded: (_) => onFinalImageLoaded(),
        );
    return IgnorePointer(child: photo);
  }
}

/// Chooses the smallest one-axis decode request that can cover the authored
/// output slot when source dimensions are known.
({int? cacheWidth, int? cacheHeight}) memoryCollageExportDecodeTarget(
  EnteFile file,
  Size targetPixelSize,
) {
  if (file.width > 0 && file.height > 0) {
    final aspectRatio = file.width / file.height;
    if (file.width >= file.height) {
      return (
        cacheWidth: null,
        cacheHeight: math
            .max(targetPixelSize.height, targetPixelSize.width / aspectRatio)
            .ceil(),
      );
    }
    return (
      cacheWidth: math
          .max(targetPixelSize.width, targetPixelSize.height * aspectRatio)
          .ceil(),
      cacheHeight: null,
    );
  }

  // Most imported files have dimensions. For legacy metadata, retain a
  // canvas-width fallback rather than decoding the unrestricted original.
  return (
    cacheWidth: math.max(1080, targetPixelSize.width).ceil(),
    cacheHeight: null,
  );
}
