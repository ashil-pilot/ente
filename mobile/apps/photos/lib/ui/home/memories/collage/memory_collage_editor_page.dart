import "dart:typed_data";
import "dart:ui" as ui;

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/retry_failed_image_load_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";
import "package:photos/ui/home/memories/collage/memory_collage_controller.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";
import "package:photos/utils/share_util.dart";
import "package:share_plus/share_plus.dart";

class MemoryCollageEditorPage extends StatefulWidget {
  final String title;
  final String memoryID;
  final List<Memory> memories;

  const MemoryCollageEditorPage({
    required this.title,
    required this.memoryID,
    required this.memories,
    super.key,
  });

  @override
  State<MemoryCollageEditorPage> createState() =>
      _MemoryCollageEditorPageState();
}

class _MemoryCollageEditorPageState extends State<MemoryCollageEditorPage> {
  final _logger = Logger("MemoryCollageEditorPage");
  final _repaintKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  final _loadedPhotoSlots = <(int, int)>{};

  late final MemoryCollageController _controller;
  Future<MemoryCollageManifest>? _manifestFuture;
  bool _assetsReady = false;
  bool _backgroundReady = true;
  bool _isExporting = false;
  bool _showPhotoRetry = false;
  int _lastShuffleRevision = 0;
  int _photoLoadGeneration = 0;
  int _photoLoadTimeoutToken = 0;

  bool get _photosReady {
    if (!_controller.canCreate) return false;
    for (var slot = 0; slot < _controller.selectedFiles.length; slot++) {
      if (!_loadedPhotoSlots.contains((_photoLoadGeneration, slot))) {
        return false;
      }
    }
    return true;
  }

  bool get _contentReady {
    return _assetsReady && _backgroundReady && _photosReady;
  }

  bool get _isReadyToExport => _contentReady && !_isExporting;

  @override
  void initState() {
    super.initState();
    _controller = MemoryCollageController(
      memoryID: widget.memoryID,
      files: widget.memories.map((memory) => memory.file),
    )..addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manifestFuture ??= _loadManifestAndAssets();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  Future<MemoryCollageManifest> _loadManifestAndAssets() async {
    final manifest = await MemoryCollageManifest.load();
    if (!mounted) return manifest;
    await MemoryCollageCanvasView.precacheAssets(
      context,
      manifest,
      assetIDs: memoryCollageRequiredAssetIDs(
        manifest,
        _controller.backgroundAssetID,
      ),
    );
    if (mounted) {
      setState(() => _assetsReady = true);
      _schedulePhotoRetryOffer();
    }
    return manifest;
  }

  void _retryManifest() {
    setState(() {
      _assetsReady = false;
      _manifestFuture = _loadManifestAndAssets();
    });
  }

  void _onControllerChanged() {
    if (_lastShuffleRevision != _controller.shuffleRevision) {
      _lastShuffleRevision = _controller.shuffleRevision;
      _photoLoadGeneration++;
      _loadedPhotoSlots.clear();
      _showPhotoRetry = false;
      _schedulePhotoRetryOffer();
    }
    if (mounted) setState(() {});
  }

  void _onFinalPhotoLoaded({
    required EnteFile file,
    required int generation,
    required int slot,
  }) {
    if (generation != _photoLoadGeneration ||
        slot < 0 ||
        slot >= _controller.selectedFiles.length ||
        !identical(file, _controller.selectedFiles[slot])) {
      return;
    }
    final readySlot = (generation, slot);
    if (_loadedPhotoSlots.contains(readySlot) || !mounted) {
      return;
    }
    setState(() {
      _loadedPhotoSlots.add(readySlot);
      if (_photosReady) {
        _photoLoadTimeoutToken++;
        _showPhotoRetry = false;
      }
    });
  }

  void _schedulePhotoRetryOffer() {
    final token = ++_photoLoadTimeoutToken;
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (!mounted || token != _photoLoadTimeoutToken || _photosReady) return;
      setState(() => _showPhotoRetry = true);
    });
  }

  void _retryPhotoLoading() {
    if (_isExporting) return;
    Bus.instance.fire(RetryFailedImageLoadEvent());
    setState(() {
      _photoLoadGeneration++;
      _loadedPhotoSlots.clear();
      _showPhotoRetry = false;
    });
    _schedulePhotoRetryOffer();
  }

  Future<void> _nextBackground() async {
    if (_isExporting || !_backgroundReady) return;
    final nextIndex =
        (_controller.backgroundIndex + 1) % _controller.backgroundIDs.length;
    final nextBackgroundID = _controller.backgroundIDs[nextIndex];
    setState(() => _backgroundReady = false);
    try {
      await precacheMemoryCollageAsset(context, nextBackgroundID);
      if (!mounted) return;
      _controller.nextBackground();
      await WidgetsBinding.instance.endOfFrame;
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to load memory collage background",
        error,
        stackTrace,
      );
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    } finally {
      if (mounted) setState(() => _backgroundReady = true);
    }
  }

  Future<Uint8List> _capturePng() async {
    if (!_contentReady) {
      throw StateError("Memory collage is not ready to export");
    }
    await WidgetsBinding.instance.endOfFrame;
    RenderRepaintBoundary? boundary;
    for (var attempt = 0; attempt < 8; attempt++) {
      final renderObject = _repaintKey.currentContext?.findRenderObject();
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
      if (image.width != 1080 || image.height != 1920) {
        throw StateError(
          "Unexpected memory collage size ${image.width}x${image.height}",
        );
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        throw StateError("Unable to encode memory collage PNG");
      }
      return bytes;
    } finally {
      image.dispose();
    }
  }

  Future<void> _shareCollage() async {
    if (!_isReadyToExport) return;
    setState(() => _isExporting = true);
    try {
      final bytes = await _capturePng();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              name: "ente_memory_${DateTime.now().millisecondsSinceEpoch}.png",
              mimeType: "image/png",
            ),
          ],
          sharePositionOrigin: shareButtonRect(context, _shareButtonKey),
        ),
      );
    } catch (error, stackTrace) {
      _logger.severe("Failed to share memory collage", error, stackTrace);
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveCollage() async {
    if (!_isReadyToExport) return;
    setState(() => _isExporting = true);
    try {
      final bytes = await _capturePng();
      final filename =
          "ente_memory_${DateTime.now().millisecondsSinceEpoch}.png";
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
      if (mounted) {
        showShortToast(context, context.strings.collageSaved);
      }
    } catch (error, stackTrace) {
      _logger.severe("Failed to save memory collage", error, stackTrace);
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161412),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161412),
        foregroundColor: Colors.white,
        title: Text(context.strings.createCollage),
        actions: [
          IconButton(
            key: _shareButtonKey,
            tooltip: context.strings.share,
            onPressed: _isReadyToExport ? _shareCollage : null,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: context.strings.save,
            onPressed: _isReadyToExport ? _saveCollage : null,
            icon: const Icon(Icons.download_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<MemoryCollageManifest>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          final manifest = snapshot.data;
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.strings.somethingWentWrong,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _retryManifest,
                    icon: const Icon(Icons.refresh),
                    label: Text(context.strings.tryAgain),
                  ),
                ],
              ),
            );
          }
          if (manifest == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildEditor(context, manifest);
        },
      ),
    );
  }

  Widget _buildEditor(BuildContext context, MemoryCollageManifest manifest) {
    final stackCustomizationActions =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final shuffleButton = FilledButton.tonalIcon(
      onPressed: _isExporting ? null : _controller.shuffle,
      icon: const Icon(Icons.shuffle),
      label: Text(context.strings.shuffle),
    );
    final backgroundButton = FilledButton.tonalIcon(
      onPressed: _isExporting || !_backgroundReady ? null : _nextBackground,
      icon: const Icon(Icons.palette_outlined),
      label: Text(context.strings.background),
    );
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: MemoryCollageCanvasView(
                        key: ValueKey(_controller.shuffleRevision),
                        manifest: manifest,
                        files: _controller.selectedFiles,
                        title: widget.title,
                        backgroundAssetID: _controller.backgroundAssetID,
                        photoBuilder: _buildExportPhoto,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_isReadyToExport && !_isExporting)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.strings.gettingReady,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                  if (_showPhotoRetry && !_photosReady)
                    TextButton.icon(
                      onPressed: _retryPhotoLoading,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.strings.tryAgain),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: stackCustomizationActions
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      shuffleButton,
                      const SizedBox(height: 8),
                      backgroundButton,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: shuffleButton),
                      const SizedBox(width: 12),
                      Expanded(child: backgroundButton),
                    ],
                  ),
          ),
          if (_isExporting) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _buildExportPhoto(BuildContext context, EnteFile file, int slot) {
    final generation = _photoLoadGeneration;
    final isLandscape = file.hasDimensions && file.width >= file.height;
    return ColoredBox(
      color: Colors.black,
      child: IgnorePointer(
        child: ZoomableImage(
          file,
          key: ValueKey("$generation:$slot"),
          tagPrefix: "memory-collage-$generation-$slot-",
          shouldCover: true,
          isFromMemories: true,
          showCaption: false,
          cacheWidth: isLandscape ? null : (file.hasDimensions ? 720 : 1080),
          cacheHeight: isLandscape ? 720 : null,
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          onFinalImageLoaded: (_) => _onFinalPhotoLoaded(
            file: file,
            generation: generation,
            slot: slot,
          ),
        ),
      ),
    );
  }
}
