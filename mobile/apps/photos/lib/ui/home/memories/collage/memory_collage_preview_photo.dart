import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

typedef MemoryCollagePreviewPhotoTestBuilder =
    Widget Function(BuildContext context, VoidCallback onThumbnailLoaded);

/// A lightweight, noninteractive photo tile for the live collage preview.
///
/// Collage exports use a separate, temporary high-resolution surface. Keeping
/// this widget thumbnail-only avoids fetching and decoding seven originals for
/// every open, shuffle, and style change.
class MemoryCollagePreviewPhoto extends StatefulWidget {
  final EnteFile file;
  final VoidCallback onReady;

  @visibleForTesting
  final MemoryCollagePreviewPhotoTestBuilder? testPhotoBuilder;

  const MemoryCollagePreviewPhoto({
    required this.file,
    required this.onReady,
    this.testPhotoBuilder,
    super.key,
  });

  @override
  State<MemoryCollagePreviewPhoto> createState() =>
      _MemoryCollagePreviewPhotoState();
}

class _MemoryCollagePreviewPhotoState extends State<MemoryCollagePreviewPhoto> {
  static const _fadeDuration = Duration(milliseconds: 300);

  bool _showPhoto = false;
  bool _didNotifyReady = false;

  @override
  void didUpdateWidget(covariant MemoryCollagePreviewPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.tag == widget.file.tag) return;
    _showPhoto = false;
    _didNotifyReady = false;
  }

  void _onThumbnailLoaded() {
    if (_showPhoto || !mounted) return;
    setState(() => _showPhoto = true);
  }

  void _onFadeEnd() {
    if (!_showPhoto || _didNotifyReady) return;
    _didNotifyReady = true;
    widget.onReady();
  }

  @override
  Widget build(BuildContext context) {
    final photo =
        widget.testPhotoBuilder?.call(context, _onThumbnailLoaded) ??
        ThumbnailWidget(
          widget.file,
          fit: BoxFit.cover,
          rawThumbnail: true,
          thumbnailSize: thumbnailLargeSize,
          useRequestedThumbnailSizeForLocalCache: true,
          shouldShowSyncStatus: false,
          shouldShowFavoriteIcon: false,
          shouldShowLivePhotoOverlay: false,
          shouldShowVideoOverlayIcon: false,
          placeholderColor: Colors.transparent,
          onThumbnailLoaded: _onThumbnailLoaded,
        );
    return AnimatedOpacity(
      opacity: _showPhoto ? 1 : 0,
      duration: _fadeDuration,
      curve: Curves.easeOut,
      onEnd: _onFadeEnd,
      child: IgnorePointer(child: photo),
    );
  }
}
