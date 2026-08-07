import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";

const memoryCollageLogicalSize = Size(360, 640);
const memoryCollageExportPixelRatio = 3.0;

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
  required int photoCount,
}) {
  final layout = manifest.template.layoutForPhotoCount(photoCount);
  return {
    backgroundAssetID,
    for (final layer in manifest.template.layers)
      if (!layer.backgroundSwappable) layout.assetIDFor(layer),
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

  const MemoryCollageCanvasView({
    required this.manifest,
    required this.files,
    required this.title,
    required this.backgroundAssetID,
    required this.photoBuilder,
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
    final template = manifest.template;
    final layout = template.layoutForPhotoCount(files.length);
    final slotByLayerAndWindow = <(String, int), int>{
      for (final slot in layout.photoSlots)
        (slot.layerID, slot.windowIndex): slot.slot,
    };

    return SizedBox.fromSize(
      size: memoryCollageLogicalSize,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final layer in template.layers) ...[
              for (final shadow in layer.shadows.reversed)
                _buildShadow(layer, shadow, layout),
              _buildLayer(context, layer, layout, slotByLayerAndWindow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLayer(
    BuildContext context,
    MemoryCollageLayer layer,
    MemoryCollagePhotoLayout layout,
    Map<(String, int), int> slotByLayerAndWindow,
  ) {
    final assetID = layer.backgroundSwappable
        ? backgroundAssetID
        : layout.assetIDFor(layer);
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
          child: ClipRect(child: photoBuilder(context, files[slot], slot)),
        ),
      );
    }
    layerChildren.add(Positioned.fill(child: assetWidget));

    if (manifest.template.titleStyle.layerID == layer.layerID) {
      layerChildren.add(
        Positioned.fill(
          child: _MemoryCollageTitle(
            title: title,
            style: manifest.template.titleStyle,
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

  Widget _buildShadow(
    MemoryCollageLayer layer,
    MemoryCollageShadow shadow,
    MemoryCollagePhotoLayout layout,
  ) {
    final assetID = layer.backgroundSwappable
        ? backgroundAssetID
        : layout.assetIDFor(layer);
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
}

class _MemoryCollageTitle extends StatelessWidget {
  final String title;
  final MemoryCollageTitleStyle style;

  const _MemoryCollageTitle({required this.title, required this.style});

  @override
  Widget build(BuildContext context) {
    final shadow = style.shadow;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          title,
          maxLines: 1,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: parseMemoryCollageColor(style.color),
            fontFamily: style.fontFamily,
            fontSize: style.fontSize / memoryCollageExportPixelRatio,
            fontWeight: _fontWeightFor(style.fontWeight),
            letterSpacing: style.letterSpacing / memoryCollageExportPixelRatio,
            height: 1,
            shadows: [
              Shadow(
                offset: Offset(
                  shadow.dx / memoryCollageExportPixelRatio,
                  shadow.dy / memoryCollageExportPixelRatio,
                ),
                blurRadius: shadow.blur / memoryCollageExportPixelRatio,
                color: parseMemoryCollageColor(shadow.color),
              ),
            ],
          ),
        ),
      ),
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
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..blendMode = blendMode
        ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1))
        ..filterQuality = FilterQuality.high,
    );
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
