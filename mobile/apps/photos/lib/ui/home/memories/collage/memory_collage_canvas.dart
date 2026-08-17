import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";

const memoryCollageLogicalSize = Size(360, 640);
const memoryCollageExportPixelRatio = 3.0;
const memoryCollagePhotoBleedCanvasPixels = 2.0;

const _sunStreakAssetID = "sun-streak";
const _vignetteAssetID = "vignette";
const _grainAssetID = "grain-overlay";
const _editorialBackgroundIDs = {"editorial-sand", "editorial-sage"};

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
  if (!manifest.backgroundAssetIDs.contains(backgroundAssetID)) {
    throw ArgumentError.value(
      backgroundAssetID,
      "backgroundAssetID",
      "is not a memory collage background",
    );
  }
  return {
    backgroundAssetID,
    template.plateAssetID,
    ..._finishAssetIDs(template.finishPreset, backgroundAssetID),
  };
}

/// Renders a frozen memory-collage layout at 360 x 640 logical pixels.
///
/// At the export pixel ratio of 3, this maps exactly to the authored
/// 1080 x 1920 canvas and full-canvas raster assets.
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
    final ids =
        assetIDs ??
        {
          ...manifest.backgroundAssetIDs,
          for (final template in manifest.templates) template.plateAssetID,
          _sunStreakAssetID,
          _vignetteAssetID,
          _grainAssetID,
        };
    await Future.wait([
      for (final assetID in ids) precacheMemoryCollageAsset(context, assetID),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final template = templateID == null
        ? manifest.defaultTemplate
        : manifest.templateFor(templateID!);
    if (!manifest.backgroundAssetIDs.contains(backgroundAssetID)) {
      throw StateError(
        "Background $backgroundAssetID is not supported by memory collages",
      );
    }
    if (files.length != template.photoSlots.length) {
      throw StateError(
        "Memory collage requires ${template.photoSlots.length} photos, "
        "got ${files.length}",
      );
    }

    return SizedBox.fromSize(
      size: memoryCollageLogicalSize,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _assetImage(backgroundAssetID)),
            for (final slot in template.photoSlots)
              _buildPhotoSlot(context, slot),
            Positioned.fill(child: _assetImage(template.plateAssetID)),
            _positionedRect(
              rect: template.title.rect,
              rotation: template.title.rotation,
              child: _MemoryCollageTitle(title: title, style: template.title),
            ),
            ..._buildFinish(template.finishPreset, backgroundAssetID),
          ],
        ),
      ),
    );
  }

  Widget _assetImage(String assetID) {
    return Image(
      image: memoryCollageAssetProvider(assetID),
      width: memoryCollageLogicalSize.width,
      height: memoryCollageLogicalSize.height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
  }

  Widget _buildPhotoSlot(BuildContext context, MemoryCollagePhotoSlot slot) {
    final rect = slot.rect;
    const bleed = memoryCollagePhotoBleedCanvasPixels;
    return Positioned(
      left: (rect.x - bleed) / memoryCollageExportPixelRatio,
      top: (rect.y - bleed) / memoryCollageExportPixelRatio,
      width: (rect.width + bleed * 2) / memoryCollageExportPixelRatio,
      height: (rect.height + bleed * 2) / memoryCollageExportPixelRatio,
      child: Transform.rotate(
        angle: slot.rotation * math.pi / 180,
        alignment: Alignment.center,
        child: ClipRect(
          child: ColoredBox(
            key: ValueKey("memory-collage-photo-backing-${slot.slot}"),
            color: parseMemoryCollageColor(slot.backingColor),
            child: photoBuilder(context, files[slot.slot], slot.slot),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFinish(
    MemoryCollageFinishPreset preset,
    String backgroundAssetID,
  ) {
    return switch (preset) {
      MemoryCollageFinishPreset.scrapbook => [
        _blendAsset(_sunStreakAssetID, BlendMode.softLight, 1),
        _blendAsset(_vignetteAssetID, BlendMode.multiply, 1),
        _blendAsset(_grainAssetID, BlendMode.overlay, 0.55),
      ],
      MemoryCollageFinishPreset.calm => [
        _blendAsset(_sunStreakAssetID, BlendMode.softLight, 1),
        _blendAsset(_vignetteAssetID, BlendMode.multiply, 0.7),
        _blendAsset(_grainAssetID, BlendMode.overlay, 0.41),
      ],
      MemoryCollageFinishPreset.minimal => [
        if (_editorialBackgroundIDs.contains(backgroundAssetID))
          _blendAsset(_grainAssetID, BlendMode.overlay, 0.12),
      ],
    };
  }

  Widget _blendAsset(String assetID, BlendMode blendMode, double opacity) {
    return Positioned.fill(
      child: _BlendAssetImage(
        assetID: assetID,
        width: memoryCollageLogicalSize.width,
        height: memoryCollageLogicalSize.height,
        blendMode: blendMode,
        opacity: opacity,
      ),
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

Set<String> _finishAssetIDs(
  MemoryCollageFinishPreset preset,
  String backgroundAssetID,
) {
  return switch (preset) {
    MemoryCollageFinishPreset.scrapbook || MemoryCollageFinishPreset.calm => {
      _sunStreakAssetID,
      _vignetteAssetID,
      _grainAssetID,
    },
    MemoryCollageFinishPreset.minimal => {
      if (_editorialBackgroundIDs.contains(backgroundAssetID)) _grainAssetID,
    },
  };
}

class _MemoryCollageTitle extends StatelessWidget {
  final String title;
  final MemoryCollageTitleStyle style;

  const _MemoryCollageTitle({required this.title, required this.style});

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.replaceAll(
      RegExp(r"[\r\n\u000B\u000C\u0085\u2028\u2029]+"),
      " ",
    );
    final locale = Localizations.maybeLocaleOf(context);
    final textDirection = Directionality.of(context);
    final textHeightBehavior = DefaultTextHeightBehavior.maybeOf(context);
    return LayoutBuilder(
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
              style: _textStyle(titleLayout.fontSize),
            ),
          ),
        );
      },
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
      text: TextSpan(text: displayTitle, style: _textStyle(fontSize)),
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

  TextStyle _textStyle(double fontSize) {
    final preferredFontSize = style.fontSize / memoryCollageExportPixelRatio;
    final scale = fontSize / preferredFontSize;
    final shadow = style.shadow;
    return TextStyle(
      inherit: false,
      color: parseMemoryCollageColor(style.color),
      fontFamily: style.fontFamily,
      fontSize: fontSize,
      fontWeight: _fontWeightFor(style.fontWeight),
      fontStyle: FontStyle.normal,
      letterSpacing:
          style.letterSpacing / memoryCollageExportPixelRatio * scale,
      height: style.lineHeight,
      shadows: shadow == null
          ? null
          : [
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
    _ => throw FormatException(
      "Unsupported memory collage font weight: $weight",
    ),
  };
}

TextAlign _textAlignFor(String value) {
  return switch (value) {
    "left" => TextAlign.left,
    "center" => TextAlign.center,
    "right" => TextAlign.right,
    "start" => TextAlign.start,
    "end" => TextAlign.end,
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
    "center" => Alignment(0, y),
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
