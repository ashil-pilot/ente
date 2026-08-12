import "dart:math";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart" show ValueListenable;
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";
import "package:photos/ui/home/memories/memory_viewer_constants.dart";

const memoryViewerProgressIndicatorKey = ValueKey<String>(
  "memory-viewer-progress-indicator",
);
const memoryViewerHeaderKey = ValueKey<String>("memory-viewer-header");
const memoryViewerCloseButtonKey = ValueKey<String>(
  "memory-viewer-close-button",
);
const memoryViewerActionBarKey = ValueKey<String>("memory-viewer-action-bar");
const memoryViewerTopScrimKey = ValueKey<String>("memory-viewer-top-scrim");
const memoryViewerBottomScrimKey = ValueKey<String>(
  "memory-viewer-bottom-scrim",
);
const memoryViewerDisabledActionOpacity = 0.38;

class MemoryViewerTopChrome extends StatelessWidget {
  final int totalSteps;
  final int currentIndex;
  final double? currentStepProgress;
  final Widget header;
  final void Function(AnimationController)? animationController;
  final void Function(AnimationController)? onAnimationControllerDisposed;
  final VoidCallback? onComplete;

  const MemoryViewerTopChrome({
    required this.totalSteps,
    required this.currentIndex,
    required this.header,
    this.currentStepProgress = 0,
    this.animationController,
    this.onAnimationControllerDisposed,
    this.onComplete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: max(safePadding.top, 40)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                safePadding.left + 16,
                0,
                safePadding.right + 16,
                0,
              ),
              child: MemoryProgressIndicator(
                key: memoryViewerProgressIndicatorKey,
                totalSteps: totalSteps,
                currentIndex: currentIndex,
                currentStepProgress: currentStepProgress,
                selectedColor: Colors.white,
                unselectedColor: Colors.white.withValues(alpha: 0.4),
                animationController: animationController,
                onAnimationControllerDisposed: onAnimationControllerDisposed,
                onComplete: onComplete,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.fromLTRB(
                safePadding.left + 16,
                0,
                safePadding.right + 16,
                0,
              ),
              child: SizedBox(
                key: memoryViewerHeaderKey,
                height: 52,
                child: header,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MemoryViewerCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const MemoryViewerCloseButton({required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: memoryViewerCloseButtonKey,
      dimension: 48,
      child: IconButton(
        tooltip: context.strings.close,
        padding: const EdgeInsets.all(8),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          maximumSize: const Size.square(48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: Colors.white.withValues(alpha: 0.08),
        ),
        onPressed: onPressed,
        icon: const HugeIcon(
          icon: HugeIcons.strokeRoundedCancel01,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}

class MemoryViewerActionBar extends StatelessWidget {
  final List<Widget> actions;

  const MemoryViewerActionBar({required this.actions, super.key});

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return Positioned(
      key: memoryViewerActionBarKey,
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          safePadding.left + 24,
          20,
          safePadding.right + 24,
          safePadding.bottom + 12,
        ),
        child: Row(
          children: actions
              .map((action) => Expanded(child: Center(child: action)))
              .toList(growable: false),
        ),
      ),
    );
  }
}

class MemoryViewerActionButton extends StatelessWidget {
  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool dimWhenDisabled;
  final bool showTapEffect;

  const MemoryViewerActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.dimWhenDisabled = true,
    this.showTapEffect = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        padding: const EdgeInsets.all(12),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          maximumSize: const Size.square(48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: showTapEffect
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          splashFactory: showTapEffect ? null : NoSplash.splashFactory,
        ),
        onPressed: onPressed,
        icon: Opacity(
          opacity: onPressed == null && dimWhenDisabled
              ? memoryViewerDisabledActionOpacity
              : 1,
          child: isLoading
              ? const SizedBox.square(
                  dimension: 24,
                  child: Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : icon,
        ),
      ),
    );
  }
}

class MemoryViewerScrims extends StatelessWidget {
  final ValueListenable<bool>? socialControlsVisible;

  const MemoryViewerScrims({this.socialControlsVisible, super.key});

  @override
  Widget build(BuildContext context) {
    final topHeight = MediaQuery.paddingOf(context).top + 104;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: memoryViewerTopScrimKey,
              width: double.infinity,
              height: topHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB8000000),
                      Color(0x70000000),
                      Colors.transparent,
                    ],
                    stops: [0, 0.6, 1],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _MemoryViewerBottomScrim(
              socialControlsVisible: socialControlsVisible,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryViewerBottomScrim extends StatelessWidget {
  final ValueListenable<bool>? socialControlsVisible;

  const _MemoryViewerBottomScrim({required this.socialControlsVisible});

  @override
  Widget build(BuildContext context) {
    final notifier = socialControlsVisible;
    if (notifier == null) {
      return _buildScrim(context, false);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, isVisible, _) => _buildScrim(context, isVisible),
    );
  }

  Widget _buildScrim(BuildContext context, bool socialControlsAreVisible) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return AnimatedContainer(
      key: memoryViewerBottomScrimKey,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: double.infinity,
      height: socialControlsAreVisible
          ? kMemorySocialScrimHeight
          : bottomInset + kMemoryBottomActionBarHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color.fromARGB(97, 0, 0, 0),
            Color.fromARGB(42, 0, 0, 0),
            Colors.transparent,
          ],
          stops: [0, 0.5, 1],
        ),
      ),
    );
  }
}
