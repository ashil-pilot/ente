import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:flutter/services.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/services/memories/memory_collage_selector.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";
import "package:photos/ui/home/memories/collage/memory_collage_controller.dart";
import "package:photos/ui/home/memories/collage/memory_collage_editor_page.dart";
import "package:photos/ui/home/memories/custom_listener.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

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
  Future<MemoryCollageManifest>? _manifestFuture;
  bool _ineligibleContinueScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _manifestFuture ??= _loadManifestAndAssets();
  }

  Future<MemoryCollageManifest> _loadManifestAndAssets() async {
    final manifest = await MemoryCollageManifest.load();
    if (!mounted) return manifest;
    final files = MemoryCollageSelector.select(
      memoryID: widget.memoryID,
      shuffleRevision: 0,
      files: widget.memories.map((memory) => memory.file),
    );
    if (!MemoryCollageSelector.isSupportedPhotoCount(files.length)) {
      return manifest;
    }
    await MemoryCollageCanvasView.precacheAssets(
      context,
      manifest,
      assetIDs: memoryCollageRequiredAssetIDs(
        manifest,
        MemoryCollageController.defaultBackgroundIDs.first,
        photoCount: files.length,
      ),
    );
    return manifest;
  }

  void _retryManifest() {
    setState(() => _manifestFuture = _loadManifestAndAssets());
  }

  void _continueIfStillIneligible() {
    if (_ineligibleContinueScheduled) return;
    _ineligibleContinueScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final files = MemoryCollageSelector.select(
        memoryID: widget.memoryID,
        shuffleRevision: 0,
        files: widget.memories.map((memory) => memory.file),
      );
      if (!MemoryCollageSelector.isSupportedPhotoCount(files.length)) {
        widget.onContinue();
      } else {
        _ineligibleContinueScheduled = false;
      }
    });
  }

  void _navigatePrevious() {
    HapticFeedback.selectionClick();
    widget.onPrevious();
  }

  void _navigateNext() {
    HapticFeedback.selectionClick();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final files = MemoryCollageSelector.select(
      memoryID: widget.memoryID,
      shuffleRevision: 0,
      files: widget.memories.map((memory) => memory.file),
    );
    if (!MemoryCollageSelector.isSupportedPhotoCount(files.length)) {
      _continueIfStillIneligible();
      return const SizedBox.shrink();
    }
    _ineligibleContinueScheduled = false;

    return ColoredBox(
      color: const Color(0xFF161412),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              MemoryProgressIndicator(
                totalSteps: memoryProgressTotalSteps(
                  memoryItemCount: widget.memories.length,
                  includeCollage: true,
                ),
                currentIndex: widget.memories.length,
                currentStepProgress: 1,
                selectedColor: Colors.white,
                unselectedColor: Colors.white.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: context.strings.close,
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    context.strings.createCollage,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox.square(dimension: 48),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Semantics(
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
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: FutureBuilder<MemoryCollageManifest>(
                            future: _manifestFuture,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return SizedBox(
                                  width: 360,
                                  height: 640,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          context.strings.somethingWentWrong,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        FilledButton.icon(
                                          onPressed: _retryManifest,
                                          icon: const Icon(Icons.refresh),
                                          label: Text(context.strings.tryAgain),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              final manifest = snapshot.data;
                              if (manifest == null) {
                                return const SizedBox(
                                  width: 360,
                                  height: 640,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return MemoryCollageCanvasView(
                                manifest: manifest,
                                files: files,
                                title: widget.title,
                                backgroundAssetID: MemoryCollageController
                                    .defaultBackgroundIDs
                                    .first,
                                photoBuilder: (context, file, slot) {
                                  return ThumbnailWidget(
                                    file,
                                    key: ValueKey(
                                      "memory-collage-preview-$slot",
                                    ),
                                    fit: BoxFit.cover,
                                    rawThumbnail: true,
                                    thumbnailSize: thumbnailLargeSize,
                                    shouldShowSyncStatus: false,
                                    shouldShowFavoriteIcon: false,
                                    shouldShowLivePhotoOverlay: false,
                                    shouldShowVideoOverlayIcon: false,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => routeToPage(
                    context,
                    MemoryCollageEditorPage(
                      title: widget.title,
                      memoryID: widget.memoryID,
                      memories: widget.memories,
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(context.strings.createCollage),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
