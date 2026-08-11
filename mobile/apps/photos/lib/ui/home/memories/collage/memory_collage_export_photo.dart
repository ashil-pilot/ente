import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";

class MemoryCollageExportPhoto extends StatelessWidget {
  final EnteFile file;
  final String tagPrefix;
  final VoidCallback onFinalImageLoaded;

  const MemoryCollageExportPhoto({
    required this.file,
    required this.tagPrefix,
    required this.onFinalImageLoaded,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape = file.hasDimensions && file.width >= file.height;
    return ColoredBox(
      color: Colors.black,
      child: IgnorePointer(
        child: ZoomableImage(
          file,
          tagPrefix: tagPrefix,
          shouldCover: true,
          isFromMemories: true,
          showCaption: false,
          cacheWidth: isLandscape ? null : (file.hasDimensions ? 720 : 1080),
          cacheHeight: isLandscape ? 720 : null,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          onFinalImageLoaded: (_) => onFinalImageLoaded(),
        ),
      ),
    );
  }
}
