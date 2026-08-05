import "dart:convert";

import "package:flutter/services.dart";

const memoryCollageManifestAsset = "assets/memories_collage/manifest.json";

class MemoryCollageManifest {
  final int version;
  final String scale;
  final MemoryCollageCanvas canvas;
  final List<MemoryCollageAsset> assets;
  final MemoryCollageTemplate template;
  final Map<String, MemoryCollageAsset> _assetsByID;

  MemoryCollageManifest._({
    required this.version,
    required this.scale,
    required this.canvas,
    required List<MemoryCollageAsset> assets,
    required this.template,
  }) : assets = List.unmodifiable(assets),
       _assetsByID = Map.unmodifiable({
         for (final asset in assets) asset.id: asset,
       });

  factory MemoryCollageManifest.fromJson(Map<String, dynamic> json) {
    final assets = _jsonList(
      json,
      "assets",
    ).map(MemoryCollageAsset.fromJson).toList(growable: false);

    return MemoryCollageManifest._(
      version: _jsonInt(json, "version"),
      scale: _jsonString(json, "scale"),
      canvas: MemoryCollageCanvas.fromJson(_jsonMap(json, "canvas")),
      assets: assets,
      template: MemoryCollageTemplate.fromJson(_jsonMap(json, "template2a")),
    );
  }

  static Future<MemoryCollageManifest> load({AssetBundle? bundle}) async {
    final encoded = await (bundle ?? rootBundle).loadString(
      memoryCollageManifestAsset,
    );
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Memory collage manifest must be an object");
    }
    return MemoryCollageManifest.fromJson(decoded);
  }

  List<MemoryCollageAsset> get backgroundAssets => List.unmodifiable(
    assets.where((asset) => asset.role == MemoryCollageAssetRole.background),
  );

  MemoryCollageAsset assetFor(String id) {
    final asset = _assetsByID[id];
    if (asset == null) {
      throw FormatException("Unknown memory collage asset: $id");
    }
    return asset;
  }
}

class MemoryCollageCanvas {
  final int width;
  final int height;

  const MemoryCollageCanvas({required this.width, required this.height});

  factory MemoryCollageCanvas.fromJson(Map<String, dynamic> json) {
    return MemoryCollageCanvas(
      width: _jsonInt(json, "width"),
      height: _jsonInt(json, "height"),
    );
  }
}

enum MemoryCollageAssetRole { background }

class MemoryCollageAsset {
  final String id;
  final int width;
  final int height;
  final bool opaque;
  final MemoryCollageAssetRole? role;
  final int? safetyMarginPx;
  final String? note;
  final List<MemoryCollagePhotoWindow> photoWindows;
  final double? bakedOpacity;
  final String? recommendedBlendMode;
  final double? recommendedOpacity;

  MemoryCollageAsset({
    required this.id,
    required this.width,
    required this.height,
    required this.opaque,
    required this.role,
    required this.safetyMarginPx,
    required this.note,
    required List<MemoryCollagePhotoWindow> photoWindows,
    required this.bakedOpacity,
    required this.recommendedBlendMode,
    required this.recommendedOpacity,
  }) : photoWindows = List.unmodifiable(photoWindows);

  factory MemoryCollageAsset.fromJson(Map<String, dynamic> json) {
    final role = _optionalString(json, "role");
    return MemoryCollageAsset(
      id: _jsonString(json, "id"),
      width: _jsonInt(json, "width"),
      height: _jsonInt(json, "height"),
      opaque: json["opaque"] as bool? ?? false,
      role: switch (role) {
        "background" => MemoryCollageAssetRole.background,
        null => null,
        _ => throw FormatException("Unknown memory collage asset role: $role"),
      },
      safetyMarginPx: _optionalInt(json, "safetyMarginPx"),
      note: _optionalString(json, "note"),
      photoWindows: _optionalJsonList(
        json,
        "photoWindows",
      ).map(MemoryCollagePhotoWindow.fromJson).toList(growable: false),
      bakedOpacity: _optionalDouble(json, "bakedOpacity"),
      recommendedBlendMode: _optionalString(json, "recommendedBlendMode"),
      recommendedOpacity: _optionalDouble(json, "recommendedOpacity"),
    );
  }
}

class MemoryCollagePhotoWindow {
  final double x;
  final double y;
  final double width;
  final double height;

  const MemoryCollagePhotoWindow({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory MemoryCollagePhotoWindow.fromJson(Map<String, dynamic> json) {
    return MemoryCollagePhotoWindow(
      x: _jsonDouble(json, "x"),
      y: _jsonDouble(json, "y"),
      width: _jsonDouble(json, "width"),
      height: _jsonDouble(json, "height"),
    );
  }
}

class MemoryCollageTemplate {
  final MemoryCollageCanvas canvas;
  final String rotationOrigin;
  final String overflow;
  final List<MemoryCollageLayer> layers;
  final List<MemoryCollagePhotoSlot> photoSlots;
  final String appRendered;
  final MemoryCollageTitleStyle titleStyle;

  MemoryCollageTemplate._({
    required this.canvas,
    required this.rotationOrigin,
    required this.overflow,
    required List<MemoryCollageLayer> layers,
    required List<MemoryCollagePhotoSlot> photoSlots,
    required this.appRendered,
    required this.titleStyle,
  }) : layers = List.unmodifiable(layers),
       photoSlots = List.unmodifiable(photoSlots);

  factory MemoryCollageTemplate.fromJson(Map<String, dynamic> json) {
    final sourceLayers = _jsonList(json, "layers");
    final layers =
        <MemoryCollageLayer>[
          for (var index = 0; index < sourceLayers.length; index++)
            MemoryCollageLayer.fromJson(
              sourceLayers[index],
              sourceIndex: index,
            ),
        ]..sort((left, right) {
          final zOrder = left.z.compareTo(right.z);
          return zOrder != 0
              ? zOrder
              : left.sourceIndex.compareTo(right.sourceIndex);
        });

    final photoSlots =
        _jsonList(
            json,
            "photoSlots",
          ).map(MemoryCollagePhotoSlot.fromJson).toList(growable: false)
          ..sort((left, right) => left.slot.compareTo(right.slot));

    return MemoryCollageTemplate._(
      canvas: MemoryCollageCanvas.fromJson(_jsonMap(json, "canvas")),
      rotationOrigin: _jsonString(json, "rotationOrigin"),
      overflow: _jsonString(json, "overflow"),
      layers: layers,
      photoSlots: photoSlots,
      appRendered: _jsonString(json, "appRendered"),
      titleStyle: MemoryCollageTitleStyle.fromJson(
        _jsonMap(json, "titleStyle"),
      ),
    );
  }

  MemoryCollageLayer layerFor(String layerID) {
    for (final layer in layers) {
      if (layer.layerID == layerID) return layer;
    }
    throw FormatException("Unknown memory collage layer: $layerID");
  }
}

class MemoryCollageLayer {
  final String layerID;
  final String assetID;
  final double x;
  final double y;
  final double width;
  final double height;
  final int z;
  final double rotation;
  final bool backgroundSwappable;
  final List<MemoryCollageShadow> shadows;
  final String? blendMode;
  final double opacity;

  /// Position in the manifest before z-ordering. It makes equal-z ordering
  /// deterministic and preserves the artist-authored layer order.
  final int sourceIndex;

  MemoryCollageLayer({
    required this.layerID,
    required this.assetID,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.z,
    required this.rotation,
    required this.backgroundSwappable,
    required List<MemoryCollageShadow> shadows,
    required this.blendMode,
    required this.opacity,
    required this.sourceIndex,
  }) : shadows = List.unmodifiable(shadows);

  factory MemoryCollageLayer.fromJson(
    Map<String, dynamic> json, {
    required int sourceIndex,
  }) {
    return MemoryCollageLayer(
      layerID: _jsonString(json, "layerId"),
      assetID: _jsonString(json, "asset"),
      x: _jsonDouble(json, "x"),
      y: _jsonDouble(json, "y"),
      width: _jsonDouble(json, "width"),
      height: _jsonDouble(json, "height"),
      z: _jsonInt(json, "z"),
      rotation: _jsonDouble(json, "rotation"),
      backgroundSwappable: json["backgroundSwappable"] as bool? ?? false,
      shadows: _optionalJsonList(
        json,
        "shadows",
      ).map(MemoryCollageShadow.fromJson).toList(growable: false),
      blendMode: _optionalString(json, "blendMode"),
      opacity: _optionalDouble(json, "opacity") ?? 1,
      sourceIndex: sourceIndex,
    );
  }
}

class MemoryCollageShadow {
  final String kind;
  final double dx;
  final double dy;
  final double blur;
  final String color;

  const MemoryCollageShadow({
    required this.kind,
    required this.dx,
    required this.dy,
    required this.blur,
    required this.color,
  });

  factory MemoryCollageShadow.fromJson(Map<String, dynamic> json) {
    return MemoryCollageShadow(
      kind: _optionalString(json, "kind") ?? "dropShadow",
      dx: _jsonDouble(json, "dx"),
      dy: _jsonDouble(json, "dy"),
      blur: _jsonDouble(json, "blur"),
      color: _jsonString(json, "color"),
    );
  }
}

class MemoryCollagePhotoSlot {
  final int slot;
  final String layerID;
  final int windowIndex;

  const MemoryCollagePhotoSlot({
    required this.slot,
    required this.layerID,
    required this.windowIndex,
  });

  factory MemoryCollagePhotoSlot.fromJson(Map<String, dynamic> json) {
    return MemoryCollagePhotoSlot(
      slot: _jsonInt(json, "slot"),
      layerID: _jsonString(json, "layerId"),
      windowIndex: _jsonInt(json, "windowIndex"),
    );
  }
}

class MemoryCollageTitleStyle {
  final String layerID;
  final String units;
  final String fontFamily;
  final String fontAsset;
  final int fontWeight;
  final String fontStyle;
  final double fontSize;
  final double letterSpacing;
  final String color;
  final String textAlign;
  final String verticalAlign;
  final String memoryTitleCasing;
  final String generatedMonthLabelCasing;
  final String glyphFallback;
  final MemoryCollageShadow shadow;

  const MemoryCollageTitleStyle({
    required this.layerID,
    required this.units,
    required this.fontFamily,
    required this.fontAsset,
    required this.fontWeight,
    required this.fontStyle,
    required this.fontSize,
    required this.letterSpacing,
    required this.color,
    required this.textAlign,
    required this.verticalAlign,
    required this.memoryTitleCasing,
    required this.generatedMonthLabelCasing,
    required this.glyphFallback,
    required this.shadow,
  });

  factory MemoryCollageTitleStyle.fromJson(Map<String, dynamic> json) {
    return MemoryCollageTitleStyle(
      layerID: _jsonString(json, "layerId"),
      units: _jsonString(json, "units"),
      fontFamily: _jsonString(json, "fontFamily"),
      fontAsset: _jsonString(json, "fontAsset"),
      fontWeight: _jsonInt(json, "fontWeight"),
      fontStyle: _jsonString(json, "fontStyle"),
      fontSize: _jsonDouble(json, "fontSize"),
      letterSpacing: _jsonDouble(json, "letterSpacing"),
      color: _jsonString(json, "color"),
      textAlign: _jsonString(json, "textAlign"),
      verticalAlign: _jsonString(json, "verticalAlign"),
      memoryTitleCasing: _jsonString(json, "memoryTitleCasing"),
      generatedMonthLabelCasing: _jsonString(json, "generatedMonthLabelCasing"),
      glyphFallback: _jsonString(json, "glyphFallback"),
      shadow: MemoryCollageShadow.fromJson(_jsonMap(json, "shadow")),
    );
  }
}

Map<String, dynamic> _jsonMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException("$key must be an object");
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _jsonList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException("$key must be a list");
  return value
      .map((item) {
        if (item is! Map) throw FormatException("$key entries must be objects");
        return Map<String, dynamic>.from(item);
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> _optionalJsonList(
  Map<String, dynamic> json,
  String key,
) {
  if (json[key] == null) return const [];
  return _jsonList(json, key);
}

String _jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException("$key must be a string");
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException("$key must be a string");
  return value;
}

int _jsonInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException("$key must be a number");
  return value.toInt();
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _jsonInt(json, key);
}

double _jsonDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException("$key must be a number");
  return value.toDouble();
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _jsonDouble(json, key);
}
