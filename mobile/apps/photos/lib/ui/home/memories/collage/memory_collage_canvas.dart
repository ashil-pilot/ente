import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";

const memoryCollageLogicalSize = Size(360, 640);
const memoryCollageExportPixelRatio = 3.0;
const _memoryCollageDefaultPhotoFill = Color(0xFFE7E1D4);

typedef MemoryCollagePhotoBuilder =
    Widget Function(BuildContext context, EnteFile file, int slot);

String memoryCollageAssetPath(String assetID) =>
    "assets/memories_collage/3.0x/$assetID.png";

ImageProvider memoryCollageAssetProvider(String assetID) => ExactAssetImage(
  memoryCollageAssetPath(assetID),
  scale: memoryCollageExportPixelRatio,
);

Future<void> precacheMemoryCollageAsset(
  BuildContext context,
  String assetID,
) async {
  Object? loadError;
  StackTrace? loadStackTrace;
  await precacheImage(
    memoryCollageAssetProvider(assetID),
    context,
    onError: (error, stackTrace) {
      loadError = error;
      loadStackTrace = stackTrace;
    },
  );
  if (loadError != null) {
    Error.throwWithStackTrace(loadError!, loadStackTrace ?? StackTrace.current);
  }
}

Set<String> memoryCollageRequiredAssetIDs(
  MemoryCollageManifest manifest,
  String backgroundAssetID, {
  String? templateID,
}) {
  final template = templateID == null
      ? manifest.defaultTemplate
      : manifest.templateFor(templateID);
  if (!template.background.assetIDs.contains(backgroundAssetID)) {
    throw ArgumentError.value(
      backgroundAssetID,
      "backgroundAssetID",
      "is not supported by memory collage template ${template.id}",
    );
  }
  return {
    backgroundAssetID,
    for (final layer in template.layers)
      if (layer.layerID != template.background.layerID &&
          layer.appliesToBackground(backgroundAssetID))
        layer.assetID,
  };
}

/// Renders the approved memory collage at a fixed 360 x 640 logical size.
///
/// At the export pixel ratio of 3, this maps exactly to the authored
/// 1080 x 1920 canvas and its 3x raster assets.
class MemoryCollageCanvasView extends StatelessWidget {
  final MemoryCollageManifest manifest;
  final List<EnteFile> files;
  final String title;
  final String backgroundAssetID;
  final MemoryCollagePhotoBuilder photoBuilder;
  final String? templateID;

  const MemoryCollageCanvasView({
    required this.manifest,
    required this.files,
    required this.title,
    required this.backgroundAssetID,
    required this.photoBuilder,
    this.templateID,
    super.key,
  });

  static Future<void> precacheAssets(
    BuildContext context,
    MemoryCollageManifest manifest, {
    Iterable<String>? assetIDs,
  }) async {
    final ids = assetIDs ?? manifest.assets.map((asset) => asset.id);
    await Future.wait([
      for (final assetID in ids) precacheMemoryCollageAsset(context, assetID),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final template = templateID == null
        ? manifest.defaultTemplate
        : manifest.templateFor(templateID!);
    if (!template.background.assetIDs.contains(backgroundAssetID)) {
      throw StateError(
        "Background $backgroundAssetID is not supported by memory collage "
        "template ${template.id}",
      );
    }
    if (files.length != template.photoSlots.length) {
      throw StateError(
        "Memory collage requires ${template.photoSlots.length} photos, "
        "got ${files.length}",
      );
    }
    final isDarkBackground = manifest.assetFor(backgroundAssetID).dark;
    final slotByLayerAndWindow = <(String, int), int>{
      for (final slot in template.photoSlots)
        if (slot is MemoryCollageAssetWindowPhotoSlot)
          (slot.layerID, slot.windowIndex): slot.slot,
    };
    final entries = <_MemoryCollageStackEntry>[];
    var sourceOrder = 0;
    for (final layer in template.layers) {
      if (!layer.appliesToBackground(backgroundAssetID)) continue;
      entries.add(
        _MemoryCollageStackEntry(
          z: layer.z,
          sourceOrder: sourceOrder++,
          children: [
            for (final shadow in layer.shadows.reversed)
              _buildLayerShadow(template, layer, shadow),
            _buildLayer(
              context,
              template,
              layer,
              slotByLayerAndWindow,
              isDarkBackground,
            ),
          ],
        ),
      );
    }
    for (final slot in template.photoSlots) {
      switch (slot) {
        case MemoryCollageAssetWindowPhotoSlot():
          break;
        case MemoryCollageRectPhotoSlot():
          entries.add(
            _MemoryCollageStackEntry(
              z: slot.z,
              sourceOrder: sourceOrder++,
              children: [
                for (final shadow in slot.shadows.reversed)
                  _buildRectPhotoShadow(slot, shadow),
                _buildRectPhoto(context, slot),
              ],
            ),
          );
        case MemoryCollageMattedRectPhotoSlot():
          entries.add(
            _MemoryCollageStackEntry(
              z: slot.z,
              sourceOrder: sourceOrder++,
              children: [
                _buildMattedRectPhoto(
                  context,
                  slot,
                  template.matStyle!,
                  isDarkBackground,
                ),
              ],
            ),
          );
      }
    }
    for (final rule in template.rules) {
      entries.add(
        _MemoryCollageStackEntry(
          z: rule.z,
          sourceOrder: sourceOrder++,
          children: [_buildRule(rule, isDarkBackground, backgroundAssetID)],
        ),
      );
    }
    final titlePlacement = template.titleStyle.placement;
    if (titlePlacement is MemoryCollageTitleRect) {
      entries.add(
        _MemoryCollageStackEntry(
          z: titlePlacement.z,
          sourceOrder: sourceOrder++,
          children: [
            _buildRectTitle(
              template.titleStyle,
              titlePlacement,
              isDarkBackground,
            ),
          ],
        ),
      );
    }
    entries.sort((left, right) {
      final zOrder = left.z.compareTo(right.z);
      return zOrder != 0
          ? zOrder
          : left.sourceOrder.compareTo(right.sourceOrder);
    });

    return SizedBox.fromSize(
      size: memoryCollageLogicalSize,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [for (final entry in entries) ...entry.children],
        ),
      ),
    );
  }

  Widget _buildLayer(
    BuildContext context,
    MemoryCollageTemplate template,
    MemoryCollageLayer layer,
    Map<(String, int), int> slotByLayerAndWindow,
    bool isDarkBackground,
  ) {
    final assetID = layer.layerID == template.background.layerID
        ? backgroundAssetID
        : layer.assetID;
    final asset = manifest.assetFor(assetID);
    final width = layer.width / memoryCollageExportPixelRatio;
    final height = layer.height / memoryCollageExportPixelRatio;

    final blendMode = _blendModeFor(layer.blendMode);
    final Widget assetWidget;
    if (blendMode != null) {
      assetWidget = _BlendAssetImage(
        assetID: assetID,
        width: width,
        height: height,
        blendMode: blendMode,
        opacity: layer.opacity,
      );
    } else {
      Widget image = Image(
        image: memoryCollageAssetProvider(assetID),
        width: width,
        height: height,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
      );
      if (layer.opacity < 1) {
        image = Opacity(opacity: layer.opacity, child: image);
      }
      assetWidget = image;
    }

    final layerChildren = <Widget>[];
    for (
      var windowIndex = 0;
      windowIndex < asset.photoWindows.length;
      windowIndex++
    ) {
      final slot = slotByLayerAndWindow[(layer.layerID, windowIndex)];
      if (slot == null || slot >= files.length) continue;
      final window = asset.photoWindows[windowIndex];
      layerChildren.add(
        Positioned(
          left: window.x / asset.width * width,
          top: window.y / asset.height * height,
          width: window.width / asset.width * width,
          height: window.height / asset.height * height,
          child: ClipRect(
            child: ColoredBox(
              key: ValueKey("memory-collage-photo-backing-$slot"),
              color: parseMemoryCollageColor(asset.emptyWindowColor!),
              child: photoBuilder(context, files[slot], slot),
            ),
          ),
        ),
      );
    }
    layerChildren.add(Positioned.fill(child: assetWidget));

    final titlePlacement = template.titleStyle.placement;
    if (titlePlacement is MemoryCollageTitleAnchor &&
        titlePlacement.layerID == layer.layerID) {
      final safetyMargin = asset.safetyMarginPx;
      final horizontalTitlePadding = safetyMargin == null
          ? 10.0
          : safetyMargin / asset.width * width;
      layerChildren.add(
        Positioned.fill(
          child: _MemoryCollageTitle(
            title: title,
            style: template.titleStyle,
            useDarkColors: isDarkBackground,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalTitlePadding,
              vertical: 4,
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: layer.x / memoryCollageExportPixelRatio,
      top: layer.y / memoryCollageExportPixelRatio,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: layer.rotation * math.pi / 180,
        alignment: Alignment.center,
        child: Stack(clipBehavior: Clip.none, children: layerChildren),
      ),
    );
  }

  Widget _buildLayerShadow(
    MemoryCollageTemplate template,
    MemoryCollageLayer layer,
    MemoryCollageShadow shadow,
  ) {
    final assetID = layer.layerID == template.background.layerID
        ? backgroundAssetID
        : layer.assetID;
    final width = layer.width / memoryCollageExportPixelRatio;
    final height = layer.height / memoryCollageExportPixelRatio;
    final color = parseMemoryCollageColor(shadow.color);
    final blurSigma = BoxShadow(
      color: color,
      blurRadius: shadow.blur / memoryCollageExportPixelRatio,
    ).blurSigma;

    return Positioned(
      left: (layer.x + shadow.dx) / memoryCollageExportPixelRatio,
      top: (layer.y + shadow.dy) / memoryCollageExportPixelRatio,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: layer.rotation * math.pi / 180,
        alignment: Alignment.center,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: Image(
              image: memoryCollageAssetProvider(assetID),
              width: width,
              height: height,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRectPhoto(
    BuildContext context,
    MemoryCollageRectPhotoSlot slot,
  ) {
    final radius = BorderRadius.circular(
      (slot.radius ?? 0) / memoryCollageExportPixelRatio,
    );
    Widget photo = ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        key: ValueKey("memory-collage-photo-backing-${slot.slot}"),
        color: _memoryCollageDefaultPhotoFill,
        child: photoBuilder(context, files[slot.slot], slot.slot),
      ),
    );
    final border = slot.border;
    if (border != null) {
      photo = Stack(
        fit: StackFit.expand,
        children: [
          photo,
          IgnorePointer(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(
                  color: parseMemoryCollageColor(border.color),
                  width: border.width / memoryCollageExportPixelRatio,
                ),
                borderRadius: radius,
              ),
            ),
          ),
        ],
      );
    }
    return _positionedRect(
      rect: slot.rect,
      rotation: slot.rotation,
      child: photo,
    );
  }

  Widget _buildMattedRectPhoto(
    BuildContext context,
    MemoryCollageMattedRectPhotoSlot slot,
    MemoryCollageMatStyle style,
    bool isDarkBackground,
  ) {
    final matRect = slot.matRect;
    final photoRect = slot.photoRect;
    final radius = BorderRadius.circular(
      (slot.radius ?? 0) / memoryCollageExportPixelRatio,
    );
    final fill = isDarkBackground ? style.fillOnDark ?? style.fill : style.fill;

    return Positioned(
      left: matRect.x / memoryCollageExportPixelRatio,
      top: matRect.y / memoryCollageExportPixelRatio,
      width: matRect.width / memoryCollageExportPixelRatio,
      height: matRect.height / memoryCollageExportPixelRatio,
      child: Transform.rotate(
        angle: slot.rotation * math.pi / 180,
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                key: ValueKey("memory-collage-mat-${slot.slot}"),
                decoration: BoxDecoration(
                  color: parseMemoryCollageColor(fill),
                  boxShadow: style.shadows.isEmpty
                      ? null
                      : [
                          for (final shadow in style.shadows)
                            BoxShadow(
                              color: parseMemoryCollageColor(shadow.color),
                              offset: Offset(
                                shadow.dx / memoryCollageExportPixelRatio,
                                shadow.dy / memoryCollageExportPixelRatio,
                              ),
                              blurRadius:
                                  shadow.blur / memoryCollageExportPixelRatio,
                            ),
                        ],
                  border: Border.all(
                    color: parseMemoryCollageColor(style.border.color),
                    width: style.border.width / memoryCollageExportPixelRatio,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                  borderRadius: radius,
                ),
              ),
            ),
            Positioned(
              left: (photoRect.x - matRect.x) / memoryCollageExportPixelRatio,
              top: (photoRect.y - matRect.y) / memoryCollageExportPixelRatio,
              width: photoRect.width / memoryCollageExportPixelRatio,
              height: photoRect.height / memoryCollageExportPixelRatio,
              child: ClipRRect(
                key: ValueKey("memory-collage-matted-photo-${slot.slot}"),
                borderRadius: radius,
                child: ColoredBox(
                  key: ValueKey("memory-collage-photo-backing-${slot.slot}"),
                  color: parseMemoryCollageColor(style.photoFill),
                  child: photoBuilder(context, files[slot.slot], slot.slot),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRectPhotoShadow(
    MemoryCollageRectPhotoSlot slot,
    MemoryCollageShadow shadow,
  ) {
    final color = parseMemoryCollageColor(shadow.color);
    final blurSigma = BoxShadow(
      color: color,
      blurRadius: shadow.blur / memoryCollageExportPixelRatio,
    ).blurSigma;
    final rect = slot.rect;
    final radius = BorderRadius.circular(
      (slot.radius ?? 0) / memoryCollageExportPixelRatio,
    );

    return Positioned(
      left: (rect.x + shadow.dx) / memoryCollageExportPixelRatio,
      top: (rect.y + shadow.dy) / memoryCollageExportPixelRatio,
      width: rect.width / memoryCollageExportPixelRatio,
      height: rect.height / memoryCollageExportPixelRatio,
      child: Transform.rotate(
        angle: slot.rotation * math.pi / 180,
        alignment: Alignment.center,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: radius),
          ),
        ),
      ),
    );
  }

  Widget _buildRectTitle(
    MemoryCollageTitleStyle style,
    MemoryCollageTitleRect placement,
    bool isDarkBackground,
  ) {
    return _positionedRect(
      rect: placement.rect,
      rotation: placement.rotation,
      child: _MemoryCollageTitle(
        title: title,
        style: style,
        useDarkColors: isDarkBackground,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildRule(
    MemoryCollageRule rule,
    bool isDarkBackground,
    String backgroundAssetID,
  ) {
    final colorValue = rule.colorFor(
      backgroundAssetID,
      isDark: isDarkBackground,
    );
    return _positionedRect(
      rect: rule.rect,
      rotation: 0,
      child: ColoredBox(color: parseMemoryCollageColor(colorValue)),
    );
  }

  Widget _positionedRect({
    required MemoryCollageRect rect,
    required double rotation,
    required Widget child,
  }) {
    return Positioned(
      left: rect.x / memoryCollageExportPixelRatio,
      top: rect.y / memoryCollageExportPixelRatio,
      width: rect.width / memoryCollageExportPixelRatio,
      height: rect.height / memoryCollageExportPixelRatio,
      child: Transform.rotate(
        angle: rotation * math.pi / 180,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _MemoryCollageStackEntry {
  final int z;
  final int sourceOrder;
  final List<Widget> children;

  const _MemoryCollageStackEntry({
    required this.z,
    required this.sourceOrder,
    required this.children,
  });
}

class _MemoryCollageTitle extends StatelessWidget {
  final String title;
  final MemoryCollageTitleStyle style;
  final bool useDarkColors;
  final EdgeInsets padding;

  const _MemoryCollageTitle({
    required this.title,
    required this.style,
    required this.useDarkColors,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.replaceAll(
      RegExp(r"[\r\n\u000B\u000C\u0085\u2028\u2029]+"),
      " ",
    );
    final locale = Localizations.maybeLocaleOf(context);
    final textDirection = Directionality.of(context);
    final textHeightBehavior = DefaultTextHeightBehavior.maybeOf(context);
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        key: const ValueKey("memory-collage-title-bounds"),
        builder: (context, constraints) {
          final titleLayout = _titleLayout(context, constraints, displayTitle);
          return Align(
            alignment: _titleAlignment(style.textAlign, style.verticalAlign),
            child: SizedBox(
              width: constraints.maxWidth,
              child: Text(
                displayTitle,
                maxLines: titleLayout.maxLines,
                overflow: TextOverflow.clip,
                softWrap: true,
                textAlign: _textAlignFor(style.textAlign),
                textDirection: textDirection,
                textScaler: TextScaler.noScaling,
                locale: locale,
                textHeightBehavior: textHeightBehavior,
                textWidthBasis: TextWidthBasis.parent,
                style: _textStyle(context, titleLayout.fontSize),
              ),
            ),
          );
        },
      ),
    );
  }

  ({double fontSize, int maxLines}) _titleLayout(
    BuildContext context,
    BoxConstraints constraints,
    String displayTitle,
  ) {
    final maximum = style.fontSize / memoryCollageExportPixelRatio;
    final minimum = style.minFontSize / memoryCollageExportPixelRatio;
    if (_fits(context, constraints, displayTitle, maximum, maxLines: 1)) {
      return (fontSize: maximum, maxLines: 1);
    }
    if (_fits(context, constraints, displayTitle, minimum, maxLines: 1)) {
      return (
        fontSize: _largestFittingFontSize(
          context,
          constraints,
          displayTitle,
          lower: minimum,
          upper: maximum,
          maxLines: 1,
        ),
        maxLines: 1,
      );
    }
    if (_fits(
      context,
      constraints,
      displayTitle,
      minimum,
      maxLines: style.maxLines,
    )) {
      return (fontSize: minimum, maxLines: style.maxLines);
    }

    var nonFittingSize = minimum;
    for (var iteration = 0; iteration < 64; iteration++) {
      final fittingSize = nonFittingSize / 2;
      if (_fits(
        context,
        constraints,
        displayTitle,
        fittingSize,
        maxLines: style.maxLines,
      )) {
        return (
          fontSize: _largestFittingFontSize(
            context,
            constraints,
            displayTitle,
            lower: fittingSize,
            upper: nonFittingSize,
            maxLines: style.maxLines,
          ),
          maxLines: style.maxLines,
        );
      }
      nonFittingSize = fittingSize;
    }

    // Hard line separators have already been normalized, so reaching this
    // branch would require an unrealistically large title or degenerate
    // constraints. Keep the result deterministic and, critically, bounded.
    return (fontSize: nonFittingSize, maxLines: style.maxLines);
  }

  double _largestFittingFontSize(
    BuildContext context,
    BoxConstraints constraints,
    String displayTitle, {
    required double lower,
    required double upper,
    required int maxLines,
  }) {
    for (var iteration = 0; iteration < 16; iteration++) {
      final candidate = (lower + upper) / 2;
      if (_fits(
        context,
        constraints,
        displayTitle,
        candidate,
        maxLines: maxLines,
      )) {
        lower = candidate;
      } else {
        upper = candidate;
      }
    }
    return lower;
  }

  bool _fits(
    BuildContext context,
    BoxConstraints constraints,
    String displayTitle,
    double fontSize, {
    required int maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: displayTitle, style: _textStyle(context, fontSize)),
      maxLines: maxLines,
      textAlign: _textAlignFor(style.textAlign),
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      textWidthBasis: TextWidthBasis.parent,
    )..layout(maxWidth: constraints.maxWidth);
    final fits =
        !painter.didExceedMaxLines &&
        painter.height <= constraints.maxHeight + 0.001;
    painter.dispose();
    return fits;
  }

  TextStyle _textStyle(BuildContext context, double fontSize) {
    final preferredFontSize = style.fontSize / memoryCollageExportPixelRatio;
    final scale = fontSize / preferredFontSize;
    final shadow = style.shadow;
    var textStyle = TextStyle(
      inherit: false,
      color: parseMemoryCollageColor(
        useDarkColors ? style.colorOnDark ?? style.color : style.color,
      ),
      fontFamily: style.fontFamily,
      fontSize: fontSize,
      fontWeight: _fontWeightFor(style.fontWeight),
      fontStyle: _fontStyleFor(style.fontStyle),
      letterSpacing:
          style.letterSpacing / memoryCollageExportPixelRatio * scale,
      height: style.lineHeight,
      shadows: [
        Shadow(
          offset: Offset(
            shadow.dx / memoryCollageExportPixelRatio * scale,
            shadow.dy / memoryCollageExportPixelRatio * scale,
          ),
          blurRadius: shadow.blur / memoryCollageExportPixelRatio * scale,
          color: parseMemoryCollageColor(shadow.color),
        ),
      ],
    );
    if (MediaQuery.boldTextOf(context)) {
      textStyle = textStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return textStyle;
  }
}

class _BlendAssetImage extends StatefulWidget {
  final String assetID;
  final double width;
  final double height;
  final BlendMode blendMode;
  final double opacity;

  const _BlendAssetImage({
    required this.assetID,
    required this.width,
    required this.height,
    required this.blendMode,
    required this.opacity,
  });

  @override
  State<_BlendAssetImage> createState() => _BlendAssetImageState();
}

class _BlendAssetImageState extends State<_BlendAssetImage> {
  ImageStream? _stream;
  ImageInfo? _imageInfo;
  late final ImageStreamListener _listener = ImageStreamListener(_handleImage);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _BlendAssetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetID != widget.assetID) _resolveImage();
  }

  void _resolveImage() {
    final stream = memoryCollageAssetProvider(
      widget.assetID,
    ).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _handleImage(ImageInfo imageInfo, bool synchronousCall) {
    final oldImageInfo = _imageInfo;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => oldImageInfo?.dispose(),
    );
    _imageInfo = imageInfo;
    if (!synchronousCall && mounted) setState(() {});
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _imageInfo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _BlendAssetPainter(
        image: _imageInfo?.image,
        blendMode: widget.blendMode,
        opacity: widget.opacity,
      ),
    );
  }
}

class _BlendAssetPainter extends CustomPainter {
  final ui.Image? image;
  final BlendMode blendMode;
  final double opacity;

  const _BlendAssetPainter({
    required this.image,
    required this.blendMode,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final source = image;
    if (source == null) return;
    final bounds = Offset.zero & size;
    canvas.saveLayer(
      bounds,
      Paint()
        ..blendMode = blendMode
        ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1)),
    );
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      bounds,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BlendAssetPainter oldDelegate) {
    return image != oldDelegate.image ||
        blendMode != oldDelegate.blendMode ||
        opacity != oldDelegate.opacity;
  }
}

BlendMode? _blendModeFor(String? value) {
  return switch (value) {
    "multiply" => BlendMode.multiply,
    "overlay" => BlendMode.overlay,
    "soft-light" => BlendMode.softLight,
    null => null,
    _ => throw FormatException("Unsupported memory collage blend mode: $value"),
  };
}

FontWeight _fontWeightFor(int weight) {
  return switch (weight) {
    100 => FontWeight.w100,
    200 => FontWeight.w200,
    300 => FontWeight.w300,
    400 => FontWeight.w400,
    500 => FontWeight.w500,
    600 => FontWeight.w600,
    700 => FontWeight.w700,
    800 => FontWeight.w800,
    900 => FontWeight.w900,
    _ => FontWeight.normal,
  };
}

FontStyle _fontStyleFor(String value) {
  return switch (value) {
    "normal" => FontStyle.normal,
    "italic" => FontStyle.italic,
    _ => throw FormatException("Unsupported memory collage font style: $value"),
  };
}

TextAlign _textAlignFor(String value) {
  return switch (value) {
    "left" => TextAlign.left,
    "center" => TextAlign.center,
    "right" => TextAlign.right,
    "start" => TextAlign.start,
    "end" => TextAlign.end,
    "justify" => TextAlign.justify,
    _ => throw FormatException(
      "Unsupported memory collage text alignment: $value",
    ),
  };
}

AlignmentGeometry _titleAlignment(String textAlign, String verticalAlign) {
  final y = switch (verticalAlign) {
    "top" => -1.0,
    "center" => 0.0,
    "bottom" => 1.0,
    _ => throw FormatException(
      "Unsupported memory collage vertical alignment: $verticalAlign",
    ),
  };
  return switch (textAlign) {
    "left" => Alignment(-1, y),
    "center" || "justify" => Alignment(0, y),
    "right" => Alignment(1, y),
    "start" => AlignmentDirectional(-1, y),
    "end" => AlignmentDirectional(1, y),
    _ => throw FormatException(
      "Unsupported memory collage text alignment: $textAlign",
    ),
  };
}

Color parseMemoryCollageColor(String value) {
  if (value.startsWith("#") && value.length == 7) {
    return Color(int.parse("ff${value.substring(1)}", radix: 16));
  }
  final rgba = RegExp(
    r"^rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)$",
  ).firstMatch(value);
  if (rgba != null) {
    return Color.fromRGBO(
      int.parse(rgba.group(1)!),
      int.parse(rgba.group(2)!),
      int.parse(rgba.group(3)!),
      double.parse(rgba.group(4)!),
    );
  }
  throw FormatException("Unsupported memory collage color: $value");
}
