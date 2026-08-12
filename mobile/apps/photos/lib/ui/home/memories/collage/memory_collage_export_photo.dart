import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";

typedef MemoryCollageExportPhotoTestBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback onFirstFrame,
      VoidCallback onFinalImageLoaded,
    );

class MemoryCollageExportPhoto extends StatefulWidget {
  final EnteFile file;
  final String tagPrefix;
  final VoidCallback onFinalImageLoaded;

  @visibleForTesting
  final MemoryCollageExportPhotoTestBuilder? testPhotoBuilder;

  const MemoryCollageExportPhoto({
    required this.file,
    required this.tagPrefix,
    required this.onFinalImageLoaded,
    this.testPhotoBuilder,
    super.key,
  });

  @override
  State<MemoryCollageExportPhoto> createState() =>
      _MemoryCollageExportPhotoState();
}

class _MemoryCollageExportPhotoState extends State<MemoryCollageExportPhoto> {
  static const _fadeDuration = Duration(milliseconds: 300);

  bool _showPhoto = false;
  bool _fadeFinished = false;
  bool _finalImageLoaded = false;
  bool _didNotifyFinalImageLoaded = false;

  @override
  void didUpdateWidget(covariant MemoryCollageExportPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.file, widget.file) &&
        oldWidget.tagPrefix == widget.tagPrefix) {
      return;
    }
    _showPhoto = false;
    _fadeFinished = false;
    _finalImageLoaded = false;
    _didNotifyFinalImageLoaded = false;
  }

  void _onFirstFrame() {
    if (_showPhoto || !mounted) return;
    setState(() => _showPhoto = true);
  }

  void _onFadeEnd() {
    if (!_showPhoto || _fadeFinished) return;
    _fadeFinished = true;
    _notifyFinalImageLoadedIfReady();
  }

  void _onFinalImageLoaded() {
    if (_finalImageLoaded) return;
    _finalImageLoaded = true;
    _notifyFinalImageLoadedIfReady();
  }

  void _notifyFinalImageLoadedIfReady() {
    if (!_fadeFinished || !_finalImageLoaded || _didNotifyFinalImageLoaded) {
      return;
    }
    _didNotifyFinalImageLoaded = true;
    widget.onFinalImageLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        widget.file.hasDimensions && widget.file.width >= widget.file.height;
    final photo =
        widget.testPhotoBuilder?.call(
          context,
          _onFirstFrame,
          _onFinalImageLoaded,
        ) ??
        ZoomableImage(
          widget.file,
          tagPrefix: widget.tagPrefix,
          shouldCover: true,
          isFromMemories: true,
          showCaption: false,
          showLoadingIndicator: false,
          cacheWidth: isLandscape
              ? null
              : (widget.file.hasDimensions ? 720 : 1080),
          cacheHeight: isLandscape ? 720 : null,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          onFinalFileLoad: ({required memoryDuration}) => _onFirstFrame(),
          onFinalImageLoaded: (_) => _onFinalImageLoaded(),
        );
    return AnimatedOpacity(
      opacity: _showPhoto ? 1 : 0,
      duration: _fadeDuration,
      curve: Curves.easeOut,
      onEnd: _onFadeEnd,
      child: ColoredBox(
        color: Colors.black,
        child: IgnorePointer(child: photo),
      ),
    );
  }
}
