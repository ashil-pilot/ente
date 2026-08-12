import "dart:async";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/retry_failed_image_load_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";
import "package:photos/ui/home/memories/collage/memory_collage_controller.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_photo.dart";
import "package:photos/ui/home/memories/memory_viewer_chrome.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/share_util.dart";

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
  final _photoReadiness = MemoryCollageRendererReadiness();

  MemoryCollageController? _controller;
  Future<MemoryCollageManifest>? _manifestFuture;
  bool _assetsReady = false;
  bool _backgroundReady = true;
  MemoryCollageExportAction? _exportAction;
  bool _showPhotoRetry = false;
  bool _isControlActionPending = false;
  int _photoLoadTimeoutToken = 0;

  bool get _photosReady {
    final controller = _controller;
    if (controller == null || !controller.canCreate) return false;
    return _photoReadiness.areAllSlotsLoaded(controller.selectedFiles.length);
  }

  bool get _contentReady {
    return _assetsReady && _backgroundReady && _photosReady;
  }

  bool get _isExporting => _exportAction != null;

  bool get _isReadyToExport => _contentReady && !_isExporting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manifestFuture ??= _loadManifestAndAssets();
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  Future<MemoryCollageManifest> _loadManifestAndAssets() async {
    final manifest =
        _controller?.manifest ?? await MemoryCollageManifest.load();
    if (!mounted) return manifest;
    final controller = _controller ??= MemoryCollageController(
      memoryID: widget.memoryID,
      files: widget.memories.map((memory) => memory.file),
      manifest: manifest,
    )..addListener(_onControllerChanged);
    _photoReadiness.initialize(
      shuffleRevision: controller.shuffleRevision,
      templateID: controller.templateID,
    );
    await MemoryCollageCanvasView.precacheAssets(
      context,
      manifest,
      assetIDs: memoryCollageRequiredAssetIDs(
        manifest,
        controller.backgroundAssetID,
        templateID: controller.templateID,
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
    final controller = _controller;
    if (controller == null) return;
    if (_photoReadiness.synchronize(
      shuffleRevision: controller.shuffleRevision,
      templateID: controller.templateID,
    )) {
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
    final controller = _controller;
    if (controller == null) return;
    if (generation != _photoReadiness.generation ||
        slot < 0 ||
        slot >= controller.selectedFiles.length ||
        !identical(file, controller.selectedFiles[slot])) {
      return;
    }
    if (!mounted ||
        !_photoReadiness.markSlotLoaded(generation: generation, slot: slot)) {
      return;
    }
    setState(() {
      if (_photosReady) {
        _photoLoadTimeoutToken++;
        _showPhotoRetry = false;
        _isControlActionPending = false;
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
      _photoReadiness.invalidate();
      _showPhotoRetry = false;
    });
    _schedulePhotoRetryOffer();
  }

  Future<void> _nextBackground() async {
    if (!_isReadyToExport) return;
    final controller = _controller;
    if (controller == null || controller.backgroundIDs.length < 2) return;
    final nextIndex =
        (controller.backgroundIndex + 1) % controller.backgroundIDs.length;
    final nextBackgroundID = controller.backgroundIDs[nextIndex];
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _backgroundReady = false;
      _isControlActionPending = true;
    });
    try {
      await MemoryCollageCanvasView.precacheAssets(
        context,
        controller.manifest,
        assetIDs: memoryCollageRequiredAssetIDs(
          controller.manifest,
          nextBackgroundID,
          templateID: controller.templateID,
        ),
      );
      if (!mounted) return;
      controller.nextBackground();
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
      if (mounted) {
        setState(() {
          _backgroundReady = true;
          _isControlActionPending = false;
        });
      }
    }
  }

  Future<void> _nextTemplate() async {
    if (!_isReadyToExport) return;
    final controller = _controller;
    if (controller == null || controller.manifest.templates.length < 2) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _isControlActionPending = true);
    await _selectTemplate(controller.nextTemplateID);
  }

  Future<void> _selectTemplate(String templateID) async {
    if (_isExporting || !_backgroundReady) return;
    final controller = _controller;
    if (controller == null || controller.templateID == templateID) return;

    var didFail = false;
    setState(() => _backgroundReady = false);
    try {
      final destinationBackground = controller.backgroundAssetIDForTemplate(
        templateID,
      );
      await MemoryCollageCanvasView.precacheAssets(
        context,
        controller.manifest,
        assetIDs: memoryCollageRequiredAssetIDs(
          controller.manifest,
          destinationBackground,
          templateID: templateID,
        ),
      );
      if (!mounted) return;
      if (_photoReadiness.prepareTemplate(templateID)) {
        _showPhotoRetry = false;
        _schedulePhotoRetryOffer();
      }
      controller.selectTemplate(templateID);
      await WidgetsBinding.instance.endOfFrame;
    } catch (error, stackTrace) {
      didFail = true;
      _logger.warning(
        "Failed to load memory collage template",
        error,
        stackTrace,
      );
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    } finally {
      if (mounted) {
        setState(() {
          _backgroundReady = true;
          if (didFail || _photosReady) _isControlActionPending = false;
        });
      }
    }
  }

  void _shuffle() {
    if (!_isReadyToExport) return;
    final controller = _controller;
    if (controller == null) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _isControlActionPending = true);
    controller.shuffle();
  }

  Future<Uint8List> _capturePng() async {
    if (!_contentReady) {
      throw StateError("Memory collage is not ready to export");
    }
    return MemoryCollageExport.capturePng(_repaintKey);
  }

  Future<void> _shareCollage() async {
    if (!_isReadyToExport) return;
    Object? failure;
    setState(() => _exportAction = MemoryCollageExportAction.share);
    try {
      final bytes = await _capturePng();
      if (!mounted) return;
      await MemoryCollageExport.sharePng(
        bytes,
        sharePositionOrigin: shareButtonRect(context, _shareButtonKey),
      );
    } catch (error, stackTrace) {
      _logger.severe("Failed to share memory collage", error, stackTrace);
      failure = error;
    } finally {
      if (mounted) setState(() => _exportAction = null);
    }
    if (failure != null && mounted) {
      await showGenericErrorDialog(context: context, error: failure);
    }
  }

  Future<void> _saveCollage() async {
    if (!_isReadyToExport) return;
    Object? failure;
    setState(() => _exportAction = MemoryCollageExportAction.save);
    try {
      final bytes = await _capturePng();
      await MemoryCollageExport.savePng(bytes);
      if (mounted) {
        showShortToast(context, context.strings.collageSaved);
      }
    } catch (error, stackTrace) {
      _logger.severe("Failed to save memory collage", error, stackTrace);
      failure = error;
    } finally {
      if (mounted) setState(() => _exportAction = null);
    }
    if (failure != null && mounted) {
      await showGenericErrorDialog(context: context, error: failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      namesRoute: true,
      label: context.strings.memoryCollageCustomize,
      child: Scaffold(
        backgroundColor: const Color(0xFF161412),
        appBar: MemoryCollageEditorTopBar(
          canExport: _contentReady,
          isSharing: _exportAction == MemoryCollageExportAction.share,
          isSaving: _exportAction == MemoryCollageExportAction.save,
          shareButtonKey: _shareButtonKey,
          onBack: () => Navigator.maybePop(context),
          onShare: _shareCollage,
          onSave: _saveCollage,
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
              return const SizedBox.expand();
            }
            return _buildEditor(context, manifest);
          },
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, MemoryCollageManifest manifest) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.expand();
    }
    final canCustomize = _contentReady;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(21, 12, 21, 8),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x8C000000),
                                blurRadius: 30,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: RepaintBoundary(
                                key: _repaintKey,
                                child: MemoryCollageCanvasView(
                                  key: ValueKey(controller.shuffleRevision),
                                  manifest: manifest,
                                  files: controller.selectedFiles,
                                  title: widget.title,
                                  backgroundAssetID:
                                      controller.backgroundAssetID,
                                  templateID: controller.templateID,
                                  photoBuilder: _buildExportPhoto,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_showPhotoRetry && !_photosReady && !_isExporting)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xE61D1A17),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: TextButton.icon(
                              onPressed: _retryPhotoLoading,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(context.strings.tryAgain),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            MemoryCollageEditorControlDock(
              styleLabel: context.strings.memoryCollageStyle,
              styleValue: _memoryCollageTemplateLabel(
                context,
                controller.templateID,
              ),
              shuffleLabel: context.strings.shuffle,
              backgroundLabel: context.strings.background,
              backgroundValue: context.strings.memoryCollageBackgroundPosition(
                current: controller.backgroundIndex + 1,
                total: controller.backgroundIDs.length,
              ),
              interactionLocked: _isControlActionPending,
              onStyle: canCustomize && manifest.templates.length > 1
                  ? _nextTemplate
                  : null,
              onShuffle: canCustomize ? _shuffle : null,
              onBackground: canCustomize && controller.backgroundIDs.length > 1
                  ? _nextBackground
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExportPhoto(BuildContext context, EnteFile file, int slot) {
    final generation = _photoReadiness.generation;
    return MemoryCollageExportPhoto(
      file: file,
      key: ValueKey("$generation:$slot"),
      tagPrefix: "memory-collage-$generation-$slot-",
      onFinalImageLoaded: () =>
          _onFinalPhotoLoaded(file: file, generation: generation, slot: slot),
    );
  }
}

class MemoryCollageEditorTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  static const toolbarHeight = 48.0;

  final bool canExport;
  final bool isSharing;
  final bool isSaving;
  final Key? shareButtonKey;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onSave;

  const MemoryCollageEditorTopBar({
    required this.canExport,
    required this.onBack,
    required this.onShare,
    required this.onSave,
    this.isSharing = false,
    this.isSaving = false,
    this.shareButtonKey,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isExporting = isSharing || isSaving;
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: toolbarHeight,
      leadingWidth: 52,
      backgroundColor: const Color(0xFF161412),
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: MemoryViewerActionButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          icon: Transform.flip(
            flipX: Directionality.of(context) == TextDirection.rtl,
            child: const HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
      actions: [
        MemoryViewerActionButton(
          key: shareButtonKey,
          tooltip: isSharing ? context.strings.sharing : context.strings.share,
          isLoading: isSharing,
          dimWhenDisabled: false,
          showTapEffect: false,
          onPressed: isExporting
              ? null
              : () {
                  if (canExport) onShare();
                },
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedShare08,
            color: Colors.white,
            size: 24,
          ),
        ),
        MemoryViewerActionButton(
          tooltip: isSaving ? context.strings.saving : context.strings.save,
          isLoading: isSaving,
          dimWhenDisabled: false,
          showTapEffect: false,
          onPressed: isExporting
              ? null
              : () {
                  if (canExport) onSave();
                },
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDownload01,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class MemoryCollageEditorControlDock extends StatelessWidget {
  final String styleLabel;
  final String styleValue;
  final String shuffleLabel;
  final String backgroundLabel;
  final String backgroundValue;
  final bool interactionLocked;
  final VoidCallback? onStyle;
  final VoidCallback? onShuffle;
  final VoidCallback? onBackground;

  const MemoryCollageEditorControlDock({
    required this.styleLabel,
    required this.styleValue,
    required this.shuffleLabel,
    required this.backgroundLabel,
    required this.backgroundValue,
    required this.onStyle,
    required this.onShuffle,
    required this.onBackground,
    this.interactionLocked = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final dockHeight = MediaQuery.textScalerOf(context).scale(1) >= 1.3
        ? 76.0
        : 68.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: dockHeight,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: [
                Expanded(
                  child: _MemoryCollageEditorControlButton(
                    label: styleLabel,
                    semanticValue: styleValue,
                    icon: HugeIcons.strokeRoundedLayers01,
                    dimWhenDisabled: !interactionLocked,
                    onPressed: interactionLocked ? null : onStyle,
                  ),
                ),
                Expanded(
                  child: _MemoryCollageEditorControlButton(
                    label: shuffleLabel,
                    icon: HugeIcons.strokeRoundedShuffle,
                    dimWhenDisabled: !interactionLocked,
                    onPressed: interactionLocked ? null : onShuffle,
                  ),
                ),
                Expanded(
                  child: _MemoryCollageEditorControlButton(
                    label: backgroundLabel,
                    semanticValue: backgroundValue,
                    icon: HugeIcons.strokeRoundedColors,
                    dimWhenDisabled: !interactionLocked,
                    onPressed: interactionLocked ? null : onBackground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryCollageEditorControlButton extends StatelessWidget {
  final String label;
  final String? semanticValue;
  final List<List<dynamic>> icon;
  final bool dimWhenDisabled;
  final VoidCallback? onPressed;

  const _MemoryCollageEditorControlButton({
    required this.label,
    required this.icon,
    required this.dimWhenDisabled,
    required this.onPressed,
    this.semanticValue,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: semanticValue,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              overlayColor: WidgetStatePropertyAll(
                Colors.white.withValues(alpha: 0.12),
              ),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: enabled || !dimWhenDisabled ? 1 : 0.35,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: icon,
                        color: Colors.white.withValues(alpha: 0.92),
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11,
                          height: 13 / 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MemoryCollageRendererReadiness {
  final Set<int> _loadedSlots = {};

  int? _lastShuffleRevision;
  String? _lastTemplateID;
  int _generation = 0;

  int get generation => _generation;

  void initialize({required int shuffleRevision, required String templateID}) {
    _lastShuffleRevision ??= shuffleRevision;
    _lastTemplateID ??= templateID;
  }

  bool synchronize({required int shuffleRevision, required String templateID}) {
    final didChange =
        _lastShuffleRevision != shuffleRevision ||
        _lastTemplateID != templateID;
    _lastShuffleRevision = shuffleRevision;
    _lastTemplateID = templateID;
    if (didChange) invalidate();
    return didChange;
  }

  bool prepareTemplate(String templateID) {
    if (_lastTemplateID == templateID) return false;
    _lastTemplateID = templateID;
    invalidate();
    return true;
  }

  void invalidate() {
    _generation++;
    _loadedSlots.clear();
  }

  bool markSlotLoaded({required int generation, required int slot}) {
    if (generation != _generation) return false;
    return _loadedSlots.add(slot);
  }

  bool areAllSlotsLoaded(int slotCount) {
    if (_loadedSlots.length != slotCount) return false;
    for (var slot = 0; slot < slotCount; slot++) {
      if (!_loadedSlots.contains(slot)) return false;
    }
    return true;
  }
}

String _memoryCollageTemplateLabel(BuildContext context, String templateID) {
  return switch (templateID) {
    "scrapbook-maximal" => context.strings.memoryCollageTemplateScrapbook,
    "scrapbook-calm" => context.strings.memoryCollageTemplateCalm,
    "minimal-editorial" => context.strings.memoryCollageTemplateMinimal,
    _ => throw ArgumentError.value(templateID, "templateID"),
  };
}
