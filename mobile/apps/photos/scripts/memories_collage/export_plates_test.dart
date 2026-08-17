import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";

const _logicalSize = Size(360, 640);
const _pixelRatio = 3.0;
const _templateIDs = <String>[
  "scrapbook-maximal",
  "calm-classic",
  "calm-film-trio",
  "calm-accent-print",
  "minimal-classic",
  "minimal-rows",
  "minimal-grid",
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    "exports the seven frozen memory-collage plates",
    (tester) async {
      final sourcePath = Platform.environment["COLLAGE_SOURCE"];
      final ingredientDirectory =
          Platform.environment["COLLAGE_INGREDIENT_DIRECTORY"];
      final outputDirectory = Platform.environment["COLLAGE_PLATE_OUTPUT"];
      if (sourcePath == null ||
          ingredientDirectory == null ||
          outputDirectory == null) {
        fail(
          "COLLAGE_SOURCE, COLLAGE_INGREDIENT_DIRECTORY, and "
          "COLLAGE_PLATE_OUTPUT are required.",
        );
      }

      final source = File(sourcePath).readAsStringSync();
      final match = RegExp(
        r'<script id="asset-manifest" type="application/json">([\s\S]*?)</script>',
      ).firstMatch(source);
      if (match == null) fail("The design source has no authoring manifest.");
      final manifest = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      final templates = manifest["templates"] as Map<String, dynamic>;
      expect(templates.keys.toList(growable: false), _templateIDs);

      final assets = <String, Map<String, dynamic>>{
        for (final value in manifest["assets"] as List<dynamic>)
          (value as Map<String, dynamic>)["id"] as String: value,
      };
      final ingredientProviders = <String, ImageProvider>{};
      for (final templateID in _templateIDs) {
        final template = templates[templateID] as Map<String, dynamic>;
        for (final value in template["layers"] as List<dynamic>) {
          final layer = value as Map<String, dynamic>;
          if (_isPlateLayer(layer)) {
            final assetID = layer["asset"] as String;
            ingredientProviders.putIfAbsent(
              assetID,
              () => FileImage(
                File("$ingredientDirectory/$assetID.png"),
                scale: _pixelRatio,
              ),
            );
          }
        }
      }

      late BuildContext precacheContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              precacheContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.runAsync(
        () => Future.wait([
          for (final provider in ingredientProviders.values)
            precacheImage(provider, precacheContext),
        ]),
      );

      final output = Directory(outputDirectory)..createSync(recursive: true);
      for (final templateID in _templateIDs) {
        final template = templates[templateID] as Map<String, dynamic>;
        final bytes = await _capture(
          tester,
          _LayoutPlate(
            template: template,
            assets: assets,
            ingredientProviders: ingredientProviders,
          ),
        );
        await tester.runAsync(
          () => File(
            "${output.path}/layout-$templateID.png",
          ).writeAsBytes(bytes, flush: true),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

bool _isPlateLayer(Map<String, dynamic> layer) {
  return layer["layerId"] != "bg" && layer["blendMode"] == null;
}

Future<Uint8List> _capture(WidgetTester tester, Widget child) async {
  final boundaryKey = GlobalKey();
  await tester.binding.setSurfaceSize(const Size(400, 700));
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox.fromSize(size: _logicalSize, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    try {
      return image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
  });
  return data!.buffer.asUint8List();
}

class _LayoutPlate extends StatelessWidget {
  final Map<String, dynamic> template;
  final Map<String, Map<String, dynamic>> assets;
  final Map<String, ImageProvider> ingredientProviders;

  const _LayoutPlate({
    required this.template,
    required this.assets,
    required this.ingredientProviders,
  });

  @override
  Widget build(BuildContext context) {
    final slots = (template["photoSlots"] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    if (template["matStyle"] != null) {
      return _MinimalPlate(template: template, slots: slots);
    }

    final slotsByLayer = <String, List<Map<String, dynamic>>>{};
    for (final slot in slots) {
      final layerID = slot["layerId"] as String;
      slotsByLayer.putIfAbsent(layerID, () => []).add(slot);
    }
    final layers =
        (template["layers"] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .asMap()
            .entries
            .where((entry) => _isPlateLayer(entry.value))
            .toList(growable: false)
          ..sort((left, right) {
            final z = (left.value["z"] as num).compareTo(
              right.value["z"] as num,
            );
            return z != 0 ? z : left.key.compareTo(right.key);
          });

    Widget plate = const SizedBox.expand();
    for (final entry in layers) {
      final layer = entry.value;
      Widget below = SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: plate),
            for (final value
                in (layer["shadows"] as List<dynamic>? ?? const []).reversed)
              _LayerShadow(
                layer: layer,
                shadow: value as Map<String, dynamic>,
                provider: ingredientProviders[layer["asset"] as String]!,
              ),
          ],
        ),
      );
      final layerSlots = slotsByLayer[layer["layerId"] as String] ?? const [];
      if (layerSlots.isNotEmpty) {
        below = ClipPath(
          clipBehavior: Clip.antiAlias,
          clipper: _WindowKnockoutClipper([
            for (final slot in layerSlots)
              _assetWindowPolygon(
                layer,
                assets[layer["asset"] as String]!,
                slot,
              ),
          ]),
          child: below,
        );
      }
      plate = SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: below),
            _StaticLayer(
              layer: layer,
              provider: ingredientProviders[layer["asset"] as String]!,
            ),
          ],
        ),
      );
    }
    return ClipRect(child: plate);
  }
}

class _StaticLayer extends StatelessWidget {
  final Map<String, dynamic> layer;
  final ImageProvider provider;

  const _StaticLayer({required this.layer, required this.provider});

  @override
  Widget build(BuildContext context) {
    final width = (layer["width"] as num).toDouble() / _pixelRatio;
    final height = (layer["height"] as num).toDouble() / _pixelRatio;
    Widget image = Image(
      image: provider,
      width: width,
      height: height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
    final opacity = (layer["opacity"] as num?)?.toDouble() ?? 1;
    if (opacity < 1) image = Opacity(opacity: opacity, child: image);
    return Positioned(
      left: (layer["x"] as num).toDouble() / _pixelRatio,
      top: (layer["y"] as num).toDouble() / _pixelRatio,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: _radians(layer["rotation"]),
        alignment: Alignment.center,
        child: image,
      ),
    );
  }
}

class _LayerShadow extends StatelessWidget {
  final Map<String, dynamic> layer;
  final Map<String, dynamic> shadow;
  final ImageProvider provider;

  const _LayerShadow({
    required this.layer,
    required this.shadow,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final width = (layer["width"] as num).toDouble() / _pixelRatio;
    final height = (layer["height"] as num).toDouble() / _pixelRatio;
    final color = _color(shadow["color"] as String);
    final blurSigma = BoxShadow(
      color: color,
      blurRadius: (shadow["blur"] as num).toDouble() / _pixelRatio,
    ).blurSigma;
    return Positioned(
      left:
          ((layer["x"] as num).toDouble() + (shadow["dx"] as num).toDouble()) /
          _pixelRatio,
      top:
          ((layer["y"] as num).toDouble() + (shadow["dy"] as num).toDouble()) /
          _pixelRatio,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: _radians(layer["rotation"]),
        alignment: Alignment.center,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: Image(
              image: provider,
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

class _WindowKnockoutClipper extends CustomClipper<Path> {
  final List<List<Offset>> polygons;

  const _WindowKnockoutClipper(this.polygons);

  @override
  Path getClip(Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    for (final polygon in polygons) {
      path.addPolygon(polygon, true);
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _WindowKnockoutClipper oldClipper) => false;
}

class _MinimalPlate extends StatelessWidget {
  final Map<String, dynamic> template;
  final List<Map<String, dynamic>> slots;

  const _MinimalPlate({required this.template, required this.slots});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipBehavior: Clip.antiAlias,
      clipper: _WindowKnockoutClipper([
        for (final slot in slots) _mattedPhotoPolygon(slot),
      ]),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final slot in slots)
            _Mat(slot: slot, style: template["matStyle"]),
        ],
      ),
    );
  }
}

class _Mat extends StatelessWidget {
  final Map<String, dynamic> slot;
  final Map<String, dynamic> style;

  const _Mat({required this.slot, required this.style});

  @override
  Widget build(BuildContext context) {
    final rect = slot["mat"] as Map<String, dynamic>;
    final border = style["border"] as Map<String, dynamic>;
    return Positioned(
      left: (rect["x"] as num).toDouble() / _pixelRatio,
      top: (rect["y"] as num).toDouble() / _pixelRatio,
      width: (rect["width"] as num).toDouble() / _pixelRatio,
      height: (rect["height"] as num).toDouble() / _pixelRatio,
      child: Transform.rotate(
        angle: _radians(slot["rotation"]),
        alignment: Alignment.center,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _color(style["fill"] as String),
            border: Border.all(
              color: _color(border["color"] as String),
              width: (border["width"] as num).toDouble() / _pixelRatio,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            boxShadow: [
              for (final value
                  in style["shadows"] as List<dynamic>? ?? const [])
                BoxShadow(
                  color: _color(
                    (value as Map<String, dynamic>)["color"] as String,
                  ),
                  offset: Offset(
                    (value["dx"] as num).toDouble() / _pixelRatio,
                    (value["dy"] as num).toDouble() / _pixelRatio,
                  ),
                  blurRadius: (value["blur"] as num).toDouble() / _pixelRatio,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

List<Offset> _assetWindowPolygon(
  Map<String, dynamic> layer,
  Map<String, dynamic> asset,
  Map<String, dynamic> slot,
) {
  final window =
      (asset["photoWindows"] as List<dynamic>)[slot["windowIndex"]]
          as Map<String, dynamic>;
  final assetWidth = (asset["width"] as num).toDouble();
  final assetHeight = (asset["height"] as num).toDouble();
  final layerX = (layer["x"] as num).toDouble();
  final layerY = (layer["y"] as num).toDouble();
  final layerWidth = (layer["width"] as num).toDouble();
  final layerHeight = (layer["height"] as num).toDouble();
  final x = layerX + (window["x"] as num).toDouble() / assetWidth * layerWidth;
  final y =
      layerY + (window["y"] as num).toDouble() / assetHeight * layerHeight;
  final width = (window["width"] as num).toDouble() / assetWidth * layerWidth;
  final height =
      (window["height"] as num).toDouble() / assetHeight * layerHeight;
  return _rotatedRectPolygon(
    x: x,
    y: y,
    width: width,
    height: height,
    centerX: layerX + layerWidth / 2,
    centerY: layerY + layerHeight / 2,
    rotation: (layer["rotation"] as num?)?.toDouble() ?? 0,
  );
}

List<Offset> _mattedPhotoPolygon(Map<String, dynamic> slot) {
  final photo = slot["rect"] as Map<String, dynamic>;
  final mat = slot["mat"] as Map<String, dynamic>;
  return _rotatedRectPolygon(
    x: (photo["x"] as num).toDouble(),
    y: (photo["y"] as num).toDouble(),
    width: (photo["width"] as num).toDouble(),
    height: (photo["height"] as num).toDouble(),
    centerX:
        (mat["x"] as num).toDouble() + (mat["width"] as num).toDouble() / 2,
    centerY:
        (mat["y"] as num).toDouble() + (mat["height"] as num).toDouble() / 2,
    rotation: (slot["rotation"] as num?)?.toDouble() ?? 0,
  );
}

List<Offset> _rotatedRectPolygon({
  required double x,
  required double y,
  required double width,
  required double height,
  required double centerX,
  required double centerY,
  required double rotation,
}) {
  final angle = rotation * math.pi / 180;
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  return [
        Offset(x, y),
        Offset(x + width, y),
        Offset(x + width, y + height),
        Offset(x, y + height),
      ]
      .map((point) {
        final dx = point.dx - centerX;
        final dy = point.dy - centerY;
        return Offset(
          (centerX + dx * cosine - dy * sine) / _pixelRatio,
          (centerY + dx * sine + dy * cosine) / _pixelRatio,
        );
      })
      .toList(growable: false);
}

double _radians(Object? degrees) {
  return ((degrees as num?)?.toDouble() ?? 0) * math.pi / 180;
}

Color _color(String value) {
  final hex = RegExp(r"^#([0-9a-fA-F]{6})$").firstMatch(value);
  if (hex != null) {
    return Color(0xff000000 | int.parse(hex.group(1)!, radix: 16));
  }
  final rgba = RegExp(
    r"^rgba\((\d+),(\d+),(\d+),([0-9.]+)\)$",
  ).firstMatch(value.replaceAll(" ", ""));
  if (rgba == null) throw FormatException("Unsupported color: $value");
  return Color.fromRGBO(
    int.parse(rgba.group(1)!),
    int.parse(rgba.group(2)!),
    int.parse(rgba.group(3)!),
    double.parse(rgba.group(4)!),
  );
}
