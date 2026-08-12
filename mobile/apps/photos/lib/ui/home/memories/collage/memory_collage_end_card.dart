import "dart:ui" show ImageFilter;

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/services/memories/memory_collage_selector.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";
import "package:photos/ui/home/memories/collage/memory_collage_editor_page.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export_photo.dart";
import "package:photos/ui/home/memories/custom_listener.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";
import "package:photos/ui/home/memories/memory_viewer_chrome.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/share_util.dart";

const memoryCollageShareActionKey = ValueKey<String>(
  "memory-collage-share-action",
);
const memoryCollageEditActionKey = ValueKey<String>(
  "memory-collage-edit-action",
);
const memoryCollageSaveActionKey = ValueKey<String>(
  "memory-collage-save-action",
);

// Keeps the authored title clear of the shared viewer header. On taller
// screens the collage remains full-width; compact screens shrink to fit.
const _memoryCollageViewerTopInset = 96.0;

class MemoryCollageEndCard extends StatefulWidget {
  final String title;
  final String memoryID;
  final List<Memory> memories;
  final VoidCallback onPrevious;
  final VoidCallback onContinue;

  const MemoryCollageEndCard({
    required this.title,
    required this.memoryID,
    required this.memories,
    required this.onPrevious,
    required this.onContinue,
    super.key,
  });

  @override
  State<MemoryCollageEndCard> createState() => _MemoryCollageEndCardState();
}

class _MemoryCollageEndCardState extends State<MemoryCollageEndCard> {
  final _logger = Logger("MemoryCollageEndCard");
  final _repaintKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  final _loadedSlots = <int>{};

  late List<EnteFile> _selectedFiles;
  Future<MemoryCollageManifest>? _manifestFuture;
  int _selectionGeneration = 0;
  bool _assetsReady = false;
  MemoryCollageExportAction? _exportAction;
  bool _ineligibleContinueScheduled = false;

  List<EnteFile> get _files => _selectedFiles;

  bool get _photosReady => _loadedSlots.length == _files.length;

  bool get _contentReady => _assetsReady && _photosReady;

  bool get _isExporting => _exportAction != null;

  bool get _isReadyToExport => _contentReady && !_isExporting;

  @override
  void initState() {
    super.initState();
    _selectedFiles = _selectFiles();
  }

  @override
  void didUpdateWidget(covariant MemoryCollageEndCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextFiles = _selectFiles();
    if (_hasSameSelection(_selectedFiles, nextFiles)) return;
    _selectedFiles = nextFiles;
    _selectionGeneration++;
    _loadedSlots.clear();
    _ineligibleContinueScheduled = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manifestFuture ??= _loadManifestAndAssets();
  }

  List<EnteFile> _selectFiles() => MemoryCollageSelector.select(
    memoryID: widget.memoryID,
    shuffleRevision: 0,
    files: widget.memories.map((memory) => memory.file),
  );

  bool _hasSameSelection(List<EnteFile> left, List<EnteFile> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!identical(left[index], right[index])) return false;
    }
    return true;
  }

  Future<MemoryCollageManifest> _loadManifestAndAssets() async {
    final manifest = await MemoryCollageManifest.load();
    if (!mounted) return manifest;
    final files = _files;
    if (!MemoryCollageSelector.isSupportedPhotoCount(files.length)) {
      return manifest;
    }
    final defaultTemplate = manifest.defaultTemplate;
    await MemoryCollageCanvasView.precacheAssets(
      context,
      manifest,
      assetIDs: memoryCollageRequiredAssetIDs(
        manifest,
        defaultTemplate.background.defaultAssetID,
        templateID: defaultTemplate.id,
      ),
    );
    if (mounted) {
      setState(() => _assetsReady = true);
    }
    return manifest;
  }

  void _retryManifest() {
    setState(() {
      _assetsReady = false;
      _manifestFuture = _loadManifestAndAssets();
    });
  }

  void _continueIfStillIneligible() {
    if (_ineligibleContinueScheduled) return;
    _ineligibleContinueScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MemoryCollageSelector.isSupportedPhotoCount(_files.length)) {
        widget.onContinue();
      } else {
        _ineligibleContinueScheduled = false;
      }
    });
  }

  void _navigatePrevious() {
    if (_isExporting) return;
    HapticFeedback.selectionClick();
    widget.onPrevious();
  }

  void _navigateNext() {
    if (_isExporting) return;
    HapticFeedback.selectionClick();
    widget.onContinue();
  }

  void _onFinalPhotoLoaded(EnteFile file, int generation, int slot) {
    final files = _files;
    if (generation != _selectionGeneration ||
        slot < 0 ||
        slot >= files.length ||
        !identical(file, files[slot])) {
      return;
    }
    if (mounted && _loadedSlots.add(slot)) {
      setState(() {});
    }
  }

  void _editCollage() {
    if (_isExporting) return;
    routeToPage(
      context,
      MemoryCollageEditorPage(
        title: widget.title,
        memoryID: widget.memoryID,
        memories: widget.memories,
      ),
    );
  }

  Future<void> _shareCollage() async {
    if (!_isReadyToExport) return;
    Object? failure;
    setState(() => _exportAction = MemoryCollageExportAction.share);
    try {
      final bytes = await MemoryCollageExport.capturePng(_repaintKey);
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
      final bytes = await MemoryCollageExport.capturePng(_repaintKey);
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
    final files = _files;
    if (!MemoryCollageSelector.isSupportedPhotoCount(files.length)) {
      _continueIfStillIneligible();
      return const SizedBox.shrink();
    }
    _ineligibleContinueScheduled = false;

    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<MemoryCollageManifest>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          final manifest = snapshot.data;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (manifest != null) _buildBackdrop(manifest, files),
              Semantics(
                container: true,
                customSemanticsActions: {
                  CustomSemanticsAction(label: context.strings.previous):
                      _navigatePrevious,
                  CustomSemanticsAction(label: context.strings.continueLabel):
                      _navigateNext,
                },
                child: MemorySideTapGestureDetector(
                  key: const ValueKey("memory-collage-side-navigation"),
                  onPrevious: _navigatePrevious,
                  onNext: _navigateNext,
                  child: _buildForeground(snapshot, files),
                ),
              ),
              const MemoryViewerScrims(),
              MemoryCollageEndCardActions(
                canExport: _contentReady,
                isSharing: _exportAction == MemoryCollageExportAction.share,
                isSaving: _exportAction == MemoryCollageExportAction.save,
                shareButtonKey: _shareButtonKey,
                onShare: _shareCollage,
                onEdit: _editCollage,
                onSave: _saveCollage,
              ),
              MemoryViewerTopChrome(
                totalSteps: memoryProgressTotalSteps(
                  memoryItemCount: widget.memories.length,
                  includeCollage: true,
                ),
                currentIndex: widget.memories.length,
                currentStepProgress: 1,
                header: Align(
                  alignment: Alignment.centerLeft,
                  child: MemoryViewerCloseButton(
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackdrop(MemoryCollageManifest manifest, List<EnteFile> files) {
    final defaultTemplate = manifest.defaultTemplate;
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: MemoryCollageCanvasView(
            manifest: manifest,
            files: files,
            title: widget.title,
            backgroundAssetID: defaultTemplate.background.defaultAssetID,
            templateID: defaultTemplate.id,
            photoBuilder: _buildBackdropPhoto,
          ),
        ),
      ),
    );
  }

  Widget _buildForeground(
    AsyncSnapshot<MemoryCollageManifest> snapshot,
    List<EnteFile> files,
  ) {
    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.strings.somethingWentWrong,
              textAlign: TextAlign.center,
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
    final manifest = snapshot.data;
    if (manifest == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final defaultTemplate = manifest.defaultTemplate;
    return Padding(
      padding: const EdgeInsets.only(top: _memoryCollageViewerTopInset),
      child: FittedBox(
        fit: BoxFit.contain,
        child: RepaintBoundary(
          key: _repaintKey,
          child: MemoryCollageCanvasView(
            manifest: manifest,
            files: files,
            title: widget.title,
            backgroundAssetID: defaultTemplate.background.defaultAssetID,
            templateID: defaultTemplate.id,
            photoBuilder: _buildExportPhoto,
          ),
        ),
      ),
    );
  }

  Widget _buildBackdropPhoto(BuildContext context, EnteFile file, int slot) {
    return ThumbnailWidget(
      file,
      key: ValueKey("memory-collage-backdrop-$_selectionGeneration-$slot"),
      fit: BoxFit.cover,
      rawThumbnail: true,
      thumbnailSize: thumbnailLargeSize,
      shouldShowSyncStatus: false,
      shouldShowFavoriteIcon: false,
      shouldShowLivePhotoOverlay: false,
      shouldShowVideoOverlayIcon: false,
    );
  }

  Widget _buildExportPhoto(BuildContext context, EnteFile file, int slot) {
    final generation = _selectionGeneration;
    return MemoryCollageExportPhoto(
      file: file,
      key: ValueKey("memory-collage-end-$generation-$slot"),
      tagPrefix: "memory-collage-end-$generation-$slot-",
      onFinalImageLoaded: () => _onFinalPhotoLoaded(file, generation, slot),
    );
  }
}

class MemoryCollageEndCardActions extends StatelessWidget {
  final bool canExport;
  final bool canEdit;
  final bool isSharing;
  final bool isSaving;
  final Key shareButtonKey;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final VoidCallback onSave;

  const MemoryCollageEndCardActions({
    required this.canExport,
    required this.onShare,
    required this.onEdit,
    required this.onSave,
    this.canEdit = true,
    this.isSharing = false,
    this.isSaving = false,
    this.shareButtonKey = memoryCollageShareActionKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isExporting = isSharing || isSaving;
    return MemoryViewerActionBar(
      actions: [
        MemoryViewerActionButton(
          key: shareButtonKey,
          tooltip: isSharing ? context.strings.sharing : context.strings.share,
          isLoading: isSharing,
          dimWhenDisabled: !isExporting,
          showTapEffect: false,
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedShare08,
            color: Colors.white,
            size: 24,
          ),
          onPressed: canExport && !isExporting ? onShare : null,
        ),
        MemoryViewerActionButton(
          key: memoryCollageEditActionKey,
          tooltip: context.strings.edit,
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedEdit03,
            color: Colors.white,
            size: 24,
          ),
          onPressed: canEdit ? onEdit : null,
        ),
        MemoryViewerActionButton(
          key: memoryCollageSaveActionKey,
          tooltip: isSaving ? context.strings.saving : context.strings.save,
          isLoading: isSaving,
          dimWhenDisabled: !isExporting,
          showTapEffect: false,
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDownload01,
            color: Colors.white,
            size: 24,
          ),
          onPressed: canExport && !isExporting ? onSave : null,
        ),
      ],
    );
  }
}
