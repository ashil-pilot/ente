import "dart:convert";

import "package:flutter/services.dart";

const memoryCollageManifestAsset = "assets/memories_collage/manifest.json";

class MemoryCollageManifest {
  final int version;
  final String scale;
  final MemoryCollageCanvas canvas;
  final List<MemoryCollageAsset> assets;
  final String defaultTemplateID;
  final List<MemoryCollageTemplate> templates;
  final Map<String, MemoryCollageAsset> _assetsByID;
  final Map<String, MemoryCollageTemplate> _templatesByID;

  MemoryCollageManifest._({
    required this.version,
    required this.scale,
    required this.canvas,
    required List<MemoryCollageAsset> assets,
    required this.defaultTemplateID,
    required List<MemoryCollageTemplate> templates,
  }) : assets = List.unmodifiable(assets),
       templates = List.unmodifiable(templates),
       _assetsByID = Map.unmodifiable({
         for (final asset in assets) asset.id: asset,
       }),
       _templatesByID = Map.unmodifiable({
         for (final template in templates) template.id: template,
       });

  factory MemoryCollageManifest.fromJson(Map<String, dynamic> json) {
    final version = _jsonInt(json, "version");
    if (version != 2) {
      throw FormatException(
        "Unsupported memory collage manifest version: $version",
      );
    }

    final manifest = MemoryCollageManifest._(
      version: version,
      scale: _jsonString(json, "scale"),
      canvas: MemoryCollageCanvas.fromJson(_jsonMap(json, "canvas")),
      assets: _jsonList(
        json,
        "assets",
      ).map(MemoryCollageAsset.fromJson).toList(growable: false),
      defaultTemplateID: _jsonString(json, "defaultTemplateId"),
      templates: _jsonList(
        json,
        "templates",
      ).map(MemoryCollageTemplate.fromJson).toList(growable: false),
    );
    manifest._validate();
    return manifest;
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

  MemoryCollageTemplate get defaultTemplate => templateFor(defaultTemplateID);

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

  MemoryCollageTemplate templateFor(String id) {
    final template = _templatesByID[id];
    if (template == null) {
      throw FormatException("Unknown memory collage template: $id");
    }
    return template;
  }

  void _validate() {
    _validateCanvas(canvas, "canvas");
    _validateUnique(
      assets.map((asset) => asset.id),
      "memory collage asset IDs",
    );
    _validateUnique(
      templates.map((template) => template.id),
      "memory collage template IDs",
    );
    if (templates.isEmpty) {
      throw const FormatException(
        "Memory collage manifest must declare at least one template",
      );
    }
    if (!_templatesByID.containsKey(defaultTemplateID)) {
      throw FormatException(
        "Default memory collage template does not exist: $defaultTemplateID",
      );
    }

    for (final asset in assets) {
      _validateAsset(asset);
    }
    for (final template in templates) {
      _validateTemplate(template);
    }
  }

  void _validateAsset(MemoryCollageAsset asset) {
    if (asset.id.isEmpty) {
      throw const FormatException("Memory collage asset ID cannot be empty");
    }
    if (asset.width <= 0 || asset.height <= 0) {
      throw FormatException(
        "Memory collage asset ${asset.id} must have positive dimensions",
      );
    }
    _validateUnitInterval(asset.bakedOpacity, "${asset.id}.bakedOpacity");
    _validateUnitInterval(
      asset.recommendedOpacity,
      "${asset.id}.recommendedOpacity",
    );

    for (var index = 0; index < asset.photoWindows.length; index++) {
      final window = asset.photoWindows[index];
      final path = "${asset.id}.photoWindows[$index]";
      _validateRectGeometry(window.rect, path);
      if (window.x < 0 ||
          window.y < 0 ||
          window.x + window.width > asset.width ||
          window.y + window.height > asset.height) {
        throw FormatException("$path must be within the asset bounds");
      }
    }
  }

  void _validateTemplate(MemoryCollageTemplate template) {
    if (template.id.isEmpty) {
      throw const FormatException("Memory collage template ID cannot be empty");
    }
    _validateUnique(
      template.layers.map((layer) => layer.layerID),
      "layer IDs in template ${template.id}",
    );
    _validateBackground(template);

    for (final layer in template.layers) {
      if (layer.layerID.isEmpty) {
        throw FormatException(
          "Layer ID cannot be empty in template ${template.id}",
        );
      }
      if (!_assetsByID.containsKey(layer.assetID)) {
        throw FormatException(
          "Layer ${layer.layerID} in template ${template.id} references "
          "unknown asset ${layer.assetID}",
        );
      }
      _validateRectGeometry(layer.rect, "${template.id}.${layer.layerID}");
      _validateFinite(
        layer.rotation,
        "${template.id}.${layer.layerID}.rotation",
      );
      _validateUnitInterval(
        layer.opacity,
        "${template.id}.${layer.layerID}.opacity",
      );
      for (var index = 0; index < layer.shadows.length; index++) {
        _validateShadow(
          layer.shadows[index],
          "${template.id}.${layer.layerID}.shadows[$index]",
        );
      }
      final backgroundAssetIDs = layer.backgroundAssetIDs;
      if (backgroundAssetIDs != null) {
        if (layer.layerID == template.background.layerID) {
          throw FormatException(
            "Template ${template.id} background layer cannot be conditional",
          );
        }
        if (backgroundAssetIDs.isEmpty) {
          throw FormatException(
            "Template ${template.id} layer ${layer.layerID} must declare at "
            "least one conditional background",
          );
        }
        _validateUnique(
          backgroundAssetIDs,
          "conditional background asset IDs on ${template.id}."
          "${layer.layerID}",
        );
        for (final assetID in backgroundAssetIDs) {
          if (!template.background.assetIDs.contains(assetID)) {
            throw FormatException(
              "Template ${template.id} layer ${layer.layerID} references "
              "unsupported conditional background $assetID",
            );
          }
        }
      }
    }

    for (var index = 0; index < template.rules.length; index++) {
      final rule = template.rules[index];
      _validateCanvasRect(rule.rect, "${template.id}.rules[$index]");
      if (rule.color.isEmpty) {
        throw FormatException(
          "Template ${template.id} rule $index must declare a color",
        );
      }
      if (rule.colorOnDark?.isEmpty ?? false) {
        throw FormatException(
          "Template ${template.id} rule $index colorOnDark cannot be empty",
        );
      }
      for (final entry in rule.colorsByBackground.entries) {
        if (!template.background.assetIDs.contains(entry.key)) {
          throw FormatException(
            "Template ${template.id} rule $index references unsupported "
            "background ${entry.key}",
          );
        }
        if (entry.value.isEmpty) {
          throw FormatException(
            "Template ${template.id} rule $index background color cannot be "
            "empty",
          );
        }
      }
    }

    _validateMatStyle(template);
    _validatePhotoSlots(template);
    _validateTitleStyle(template);
  }

  void _validateMatStyle(MemoryCollageTemplate template) {
    final hasMattedSlots = template.photoSlots.any(
      (slot) => slot is MemoryCollageMattedRectPhotoSlot,
    );
    final style = template.matStyle;
    if (hasMattedSlots != (style != null)) {
      throw FormatException(
        "Template ${template.id} must declare matStyle exactly when it uses "
        "mattedRect photo slots",
      );
    }
    if (style == null) return;
    if (style.fill.isEmpty || (style.fillOnDark?.isEmpty ?? false)) {
      throw FormatException(
        "Template ${template.id} matStyle must declare valid fill colors",
      );
    }
    if (style.border.width <= 0 || style.border.color.isEmpty) {
      throw FormatException(
        "Template ${template.id} matStyle must declare a valid border",
      );
    }
    if (!style.photoInset.isFinite || style.photoInset <= 0) {
      throw FormatException(
        "Template ${template.id} matStyle photoInset must be positive",
      );
    }
    for (var index = 0; index < style.shadows.length; index++) {
      _validateShadow(
        style.shadows[index],
        "${template.id}.matStyle.shadows[$index]",
      );
    }
  }

  void _validateBackground(MemoryCollageTemplate template) {
    final background = template.background;
    if (background.assetIDs.isEmpty) {
      throw FormatException(
        "Template ${template.id} must declare at least one background",
      );
    }
    _validateUnique(
      background.assetIDs,
      "background asset IDs in template ${template.id}",
    );
    if (!background.assetIDs.contains(background.defaultAssetID)) {
      throw FormatException(
        "Template ${template.id} default background "
        "${background.defaultAssetID} is not in its background list",
      );
    }

    final backgroundLayer = _layerOrNull(template, background.layerID);
    if (backgroundLayer == null) {
      throw FormatException(
        "Template ${template.id} background references unknown layer "
        "${background.layerID}",
      );
    }
    if (backgroundLayer.assetID != background.defaultAssetID) {
      throw FormatException(
        "Template ${template.id} background layer must use its default asset",
      );
    }
    if (backgroundLayer.x != 0 ||
        backgroundLayer.y != 0 ||
        backgroundLayer.width != canvas.width ||
        backgroundLayer.height != canvas.height) {
      throw FormatException(
        "Template ${template.id} background layer must fill the canvas",
      );
    }

    for (final assetID in background.assetIDs) {
      final asset = _assetsByID[assetID];
      if (asset == null) {
        throw FormatException(
          "Template ${template.id} references unknown background $assetID",
        );
      }
      if (asset.role != MemoryCollageAssetRole.background) {
        throw FormatException(
          "Template ${template.id} background $assetID must have the "
          "background role",
        );
      }
      if (asset.width != canvas.width || asset.height != canvas.height) {
        throw FormatException(
          "Template ${template.id} background $assetID must match the canvas",
        );
      }
    }
  }

  void _validatePhotoSlots(MemoryCollageTemplate template) {
    const requiredSlots = 7;
    if (template.photoSlots.length != requiredSlots ||
        !_sameInts(
          template.photoSlots.map((slot) => slot.slot),
          List.generate(requiredSlots, (index) => index),
        )) {
      throw FormatException(
        "Template ${template.id} must declare each photo slot from 0 to 6 "
        "exactly once",
      );
    }

    final assetWindowTargets = <(String, int)>{};
    for (final slot in template.photoSlots) {
      switch (slot) {
        case MemoryCollageAssetWindowPhotoSlot():
          if (!assetWindowTargets.add((slot.layerID, slot.windowIndex))) {
            throw FormatException(
              "Template ${template.id} assigns more than one photo to "
              "${slot.layerID} window ${slot.windowIndex}",
            );
          }
          final layer = _layerOrNull(template, slot.layerID);
          if (layer == null) {
            throw FormatException(
              "Photo slot ${slot.slot} in template ${template.id} references "
              "unknown layer ${slot.layerID}",
            );
          }
          if (layer.backgroundAssetIDs != null) {
            throw FormatException(
              "Photo slot ${slot.slot} in template ${template.id} cannot "
              "reference a background-conditional layer",
            );
          }
          final asset = _assetsByID[layer.assetID]!;
          if (slot.windowIndex < 0 ||
              slot.windowIndex >= asset.photoWindows.length) {
            throw FormatException(
              "Photo slot ${slot.slot} in template ${template.id} references "
              "an invalid window on ${asset.id}",
            );
          }
        case MemoryCollageRectPhotoSlot():
          _validateCanvasRect(
            slot.rect,
            "Photo slot ${slot.slot} in template ${template.id}",
          );
          _validateFinite(
            slot.rotation,
            "${template.id}.photoSlots[${slot.slot}].rotation",
          );
          if (slot.radius != null && slot.radius! < 0) {
            throw FormatException(
              "Photo slot ${slot.slot} in template ${template.id} must have "
              "a non-negative radius",
            );
          }
          if (slot.border case final border?) {
            if (border.width <= 0 || border.color.isEmpty) {
              throw FormatException(
                "Photo slot ${slot.slot} in template ${template.id} has an "
                "invalid border",
              );
            }
          }
          for (var index = 0; index < slot.shadows.length; index++) {
            _validateShadow(
              slot.shadows[index],
              "${template.id}.photoSlots[${slot.slot}].shadows[$index]",
            );
          }
        case MemoryCollageMattedRectPhotoSlot():
          final path = "${template.id}.photoSlots[${slot.slot}]";
          _validateCanvasRect(slot.matRect, "$path.mat");
          _validateCanvasRect(slot.photoRect, "$path.rect");
          _validateFinite(slot.rotation, "$path.rotation");
          if (slot.radius != null && slot.radius! < 0) {
            throw FormatException(
              "Photo slot ${slot.slot} in template ${template.id} must have "
              "a non-negative radius",
            );
          }
          final inset = template.matStyle!.photoInset;
          if (slot.photoRect.x != slot.matRect.x + inset ||
              slot.photoRect.y != slot.matRect.y + inset ||
              slot.photoRect.width != slot.matRect.width - inset * 2 ||
              slot.photoRect.height != slot.matRect.height - inset * 2) {
            throw FormatException(
              "Photo slot ${slot.slot} in template ${template.id} must inset "
              "its photo rect by $inset on every side",
            );
          }
      }
    }
  }

  void _validateTitleStyle(MemoryCollageTemplate template) {
    final style = template.titleStyle;
    if (style.fontStyle != "normal" && style.fontStyle != "italic") {
      throw FormatException(
        "Template ${template.id} has unsupported title fontStyle "
        "${style.fontStyle}",
      );
    }
    const textAlignments = {"left", "center", "right", "start", "end"};
    if (!textAlignments.contains(style.textAlign)) {
      throw FormatException(
        "Template ${template.id} has unsupported title textAlign "
        "${style.textAlign}",
      );
    }
    const verticalAlignments = {"top", "center", "bottom"};
    if (!verticalAlignments.contains(style.verticalAlign)) {
      throw FormatException(
        "Template ${template.id} has unsupported title verticalAlign "
        "${style.verticalAlign}",
      );
    }
    if (style.fontWeight < 1 || style.fontWeight > 1000) {
      throw FormatException(
        "Template ${template.id} title fontWeight must be from 1 to 1000",
      );
    }
    if (style.fontSize <= 0 || !style.fontSize.isFinite) {
      throw FormatException(
        "Template ${template.id} title fontSize must be positive",
      );
    }
    if (style.minFontSize <= 0 ||
        style.minFontSize > style.fontSize ||
        !style.minFontSize.isFinite) {
      throw FormatException(
        "Template ${template.id} title minFontSize must be positive and no "
        "larger than fontSize",
      );
    }
    if (style.lineHeight <= 0 || !style.lineHeight.isFinite) {
      throw FormatException(
        "Template ${template.id} title lineHeight must be positive",
      );
    }
    if (style.maxLines <= 0) {
      throw FormatException(
        "Template ${template.id} title maxLines must be positive",
      );
    }
    _validateFinite(
      style.letterSpacing,
      "${template.id}.titleStyle.letterSpacing",
    );
    _validateShadow(style.shadow, "${template.id}.titleStyle.shadow");

    final placement = style.placement;
    switch (placement) {
      case MemoryCollageTitleAnchor():
        final layer = _layerOrNull(template, placement.layerID);
        if (layer == null) {
          throw FormatException(
            "Template ${template.id} title references unknown layer "
            "${placement.layerID}",
          );
        }
        if (layer.backgroundAssetIDs != null) {
          throw FormatException(
            "Template ${template.id} title cannot reference a "
            "background-conditional layer",
          );
        }
      case MemoryCollageTitleRect():
        _validateCanvasRect(placement.rect, "Title in template ${template.id}");
        _validateFinite(
          placement.rotation,
          "${template.id}.titleStyle.placement.rotation",
        );
    }
  }

  MemoryCollageLayer? _layerOrNull(
    MemoryCollageTemplate template,
    String layerID,
  ) {
    for (final layer in template.layers) {
      if (layer.layerID == layerID) return layer;
    }
    return null;
  }

  void _validateCanvasRect(MemoryCollageRect rect, String path) {
    _validateRectGeometry(rect, path);
    if (rect.x < 0 ||
        rect.y < 0 ||
        rect.x + rect.width > canvas.width ||
        rect.y + rect.height > canvas.height) {
      throw FormatException("$path must be within the canvas bounds");
    }
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
  final bool dark;
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
    required this.dark,
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
      opaque: _optionalBool(json, "opaque") ?? false,
      dark: _optionalBool(json, "dark") ?? false,
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

class MemoryCollageRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const MemoryCollageRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory MemoryCollageRect.fromJson(Map<String, dynamic> json) {
    return MemoryCollageRect(
      x: _jsonDouble(json, "x"),
      y: _jsonDouble(json, "y"),
      width: _jsonDouble(json, "width"),
      height: _jsonDouble(json, "height"),
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

  MemoryCollageRect get rect =>
      MemoryCollageRect(x: x, y: y, width: width, height: height);

  factory MemoryCollagePhotoWindow.fromJson(Map<String, dynamic> json) {
    return MemoryCollagePhotoWindow(
      x: _jsonDouble(json, "x"),
      y: _jsonDouble(json, "y"),
      width: _jsonDouble(json, "width"),
      height: _jsonDouble(json, "height"),
    );
  }
}

class MemoryCollageBackgroundConfig {
  final String layerID;
  final String defaultAssetID;
  final List<String> assetIDs;

  MemoryCollageBackgroundConfig({
    required this.layerID,
    required this.defaultAssetID,
    required List<String> assetIDs,
  }) : assetIDs = List.unmodifiable(assetIDs);

  factory MemoryCollageBackgroundConfig.fromJson(Map<String, dynamic> json) {
    return MemoryCollageBackgroundConfig(
      layerID: _jsonString(json, "layerId"),
      defaultAssetID: _jsonString(json, "defaultAssetId"),
      assetIDs: _jsonStringList(json, "assetIds"),
    );
  }
}

class MemoryCollageRule {
  final MemoryCollageRect rect;
  final int z;
  final String color;
  final String? colorOnDark;
  final Map<String, String> colorsByBackground;

  MemoryCollageRule({
    required this.rect,
    required this.z,
    required this.color,
    required this.colorOnDark,
    required Map<String, String> colorsByBackground,
  }) : colorsByBackground = Map.unmodifiable(colorsByBackground);

  factory MemoryCollageRule.fromJson(Map<String, dynamic> json) {
    return MemoryCollageRule(
      rect: MemoryCollageRect.fromJson(json),
      z: _jsonInt(json, "z"),
      color: _jsonString(json, "color"),
      colorOnDark: _optionalString(json, "colorOnDark"),
      colorsByBackground: _optionalStringMap(json, "colorsByBackground"),
    );
  }

  String colorFor(String backgroundAssetID, {required bool isDark}) =>
      colorsByBackground[backgroundAssetID] ??
      (isDark ? colorOnDark ?? color : color);
}

class MemoryCollageTemplate {
  final String id;
  final String rotationOrigin;
  final String overflow;
  final MemoryCollageBackgroundConfig background;
  final List<MemoryCollageLayer> layers;
  final List<MemoryCollagePhotoSlot> photoSlots;
  final List<MemoryCollageRule> rules;
  final MemoryCollageMatStyle? matStyle;
  final String? appRendered;
  final MemoryCollageTitleStyle titleStyle;

  MemoryCollageTemplate._({
    required this.id,
    required this.rotationOrigin,
    required this.overflow,
    required this.background,
    required List<MemoryCollageLayer> layers,
    required List<MemoryCollagePhotoSlot> photoSlots,
    required List<MemoryCollageRule> rules,
    required this.matStyle,
    required this.appRendered,
    required this.titleStyle,
  }) : layers = List.unmodifiable(layers),
       photoSlots = List.unmodifiable(photoSlots),
       rules = List.unmodifiable(rules);

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
      id: _jsonString(json, "id"),
      rotationOrigin: _optionalString(json, "rotationOrigin") ?? "layer center",
      overflow: _optionalString(json, "overflow") ?? "crop to canvas",
      background: MemoryCollageBackgroundConfig.fromJson(
        _jsonMap(json, "background"),
      ),
      layers: layers,
      photoSlots: photoSlots,
      rules: _optionalJsonList(
        json,
        "rules",
      ).map(MemoryCollageRule.fromJson).toList(growable: false),
      matStyle: json["matStyle"] == null
          ? null
          : MemoryCollageMatStyle.fromJson(_jsonMap(json, "matStyle")),
      appRendered: _optionalString(json, "appRendered"),
      titleStyle: MemoryCollageTitleStyle.fromJson(
        _jsonMap(json, "titleStyle"),
      ),
    );
  }

  MemoryCollageLayer layerFor(String layerID) {
    for (final layer in layers) {
      if (layer.layerID == layerID) return layer;
    }
    throw FormatException(
      "Unknown memory collage layer in template $id: $layerID",
    );
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
  final List<MemoryCollageShadow> shadows;
  final List<String>? backgroundAssetIDs;
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
    required List<MemoryCollageShadow> shadows,
    required List<String>? backgroundAssetIDs,
    required this.blendMode,
    required this.opacity,
    required this.sourceIndex,
  }) : shadows = List.unmodifiable(shadows),
       backgroundAssetIDs = backgroundAssetIDs == null
           ? null
           : List.unmodifiable(backgroundAssetIDs);

  MemoryCollageRect get rect =>
      MemoryCollageRect(x: x, y: y, width: width, height: height);

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
      shadows: _optionalJsonList(
        json,
        "shadows",
      ).map(MemoryCollageShadow.fromJson).toList(growable: false),
      backgroundAssetIDs: json["backgroundAssetIds"] == null
          ? null
          : _jsonStringList(json, "backgroundAssetIds"),
      blendMode: _optionalString(json, "blendMode"),
      opacity: _optionalDouble(json, "opacity") ?? 1,
      sourceIndex: sourceIndex,
    );
  }

  bool appliesToBackground(String backgroundAssetID) =>
      backgroundAssetIDs?.contains(backgroundAssetID) ?? true;
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

class MemoryCollageMatStyle {
  final String fill;
  final String? fillOnDark;
  final MemoryCollageBorder border;
  final double photoInset;
  final List<MemoryCollageShadow> shadows;

  MemoryCollageMatStyle({
    required this.fill,
    required this.fillOnDark,
    required this.border,
    required this.photoInset,
    required List<MemoryCollageShadow> shadows,
  }) : shadows = List.unmodifiable(shadows);

  factory MemoryCollageMatStyle.fromJson(Map<String, dynamic> json) {
    return MemoryCollageMatStyle(
      fill: _jsonString(json, "fill"),
      fillOnDark: _optionalString(json, "fillOnDark"),
      border: MemoryCollageBorder.fromJson(_jsonMap(json, "border")),
      photoInset: _jsonDouble(json, "photoInset"),
      shadows: _optionalJsonList(
        json,
        "shadows",
      ).map(MemoryCollageShadow.fromJson).toList(growable: false),
    );
  }
}

sealed class MemoryCollagePhotoSlot {
  final int slot;

  const MemoryCollagePhotoSlot({required this.slot});

  factory MemoryCollagePhotoSlot.fromJson(Map<String, dynamic> json) {
    return switch (_jsonString(json, "kind")) {
      "assetWindow" => MemoryCollageAssetWindowPhotoSlot.fromJson(json),
      "rect" => MemoryCollageRectPhotoSlot.fromJson(json),
      "mattedRect" => MemoryCollageMattedRectPhotoSlot.fromJson(json),
      final kind => throw FormatException(
        "Unknown memory collage photo slot kind: $kind",
      ),
    };
  }
}

class MemoryCollageAssetWindowPhotoSlot extends MemoryCollagePhotoSlot {
  final String layerID;
  final int windowIndex;

  const MemoryCollageAssetWindowPhotoSlot({
    required super.slot,
    required this.layerID,
    required this.windowIndex,
  });

  factory MemoryCollageAssetWindowPhotoSlot.fromJson(
    Map<String, dynamic> json,
  ) {
    return MemoryCollageAssetWindowPhotoSlot(
      slot: _jsonInt(json, "slot"),
      layerID: _jsonString(json, "layerId"),
      windowIndex: _jsonInt(json, "windowIndex"),
    );
  }
}

class MemoryCollageRectPhotoSlot extends MemoryCollagePhotoSlot {
  final MemoryCollageRect rect;
  final int z;
  final double rotation;
  final MemoryCollageBorder? border;
  final double? radius;
  final List<MemoryCollageShadow> shadows;

  MemoryCollageRectPhotoSlot({
    required super.slot,
    required this.rect,
    required this.z,
    required this.rotation,
    required this.border,
    required this.radius,
    required List<MemoryCollageShadow> shadows,
  }) : shadows = List.unmodifiable(shadows);

  factory MemoryCollageRectPhotoSlot.fromJson(Map<String, dynamic> json) {
    return MemoryCollageRectPhotoSlot(
      slot: _jsonInt(json, "slot"),
      rect: MemoryCollageRect.fromJson(json),
      z: _jsonInt(json, "z"),
      rotation: _optionalDouble(json, "rotation") ?? 0,
      border: json["border"] == null
          ? null
          : MemoryCollageBorder.fromJson(_jsonMap(json, "border")),
      radius: _optionalDouble(json, "radius"),
      shadows: _optionalJsonList(
        json,
        "shadows",
      ).map(MemoryCollageShadow.fromJson).toList(growable: false),
    );
  }
}

class MemoryCollageMattedRectPhotoSlot extends MemoryCollagePhotoSlot {
  final MemoryCollageRect matRect;
  final MemoryCollageRect photoRect;
  final int z;
  final double rotation;
  final double? radius;

  const MemoryCollageMattedRectPhotoSlot({
    required super.slot,
    required this.matRect,
    required this.photoRect,
    required this.z,
    required this.rotation,
    required this.radius,
  });

  factory MemoryCollageMattedRectPhotoSlot.fromJson(Map<String, dynamic> json) {
    return MemoryCollageMattedRectPhotoSlot(
      slot: _jsonInt(json, "slot"),
      matRect: MemoryCollageRect.fromJson(_jsonMap(json, "mat")),
      photoRect: MemoryCollageRect.fromJson(_jsonMap(json, "rect")),
      z: _jsonInt(json, "z"),
      rotation: _optionalDouble(json, "rotation") ?? 0,
      radius: _optionalDouble(json, "radius"),
    );
  }
}

class MemoryCollageBorder {
  final double width;
  final String color;

  const MemoryCollageBorder({required this.width, required this.color});

  factory MemoryCollageBorder.fromJson(Map<String, dynamic> json) {
    return MemoryCollageBorder(
      width: _jsonDouble(json, "width"),
      color: _jsonString(json, "color"),
    );
  }
}

sealed class MemoryCollageTitlePlacement {
  const MemoryCollageTitlePlacement();

  factory MemoryCollageTitlePlacement.fromJson(Map<String, dynamic> json) {
    return switch (_jsonString(json, "kind")) {
      "layer" => MemoryCollageTitleAnchor.fromJson(json),
      "rect" => MemoryCollageTitleRect.fromJson(json),
      final kind => throw FormatException(
        "Unknown memory collage title placement kind: $kind",
      ),
    };
  }
}

class MemoryCollageTitleAnchor extends MemoryCollageTitlePlacement {
  final String layerID;

  const MemoryCollageTitleAnchor({required this.layerID});

  factory MemoryCollageTitleAnchor.fromJson(Map<String, dynamic> json) {
    return MemoryCollageTitleAnchor(layerID: _jsonString(json, "layerId"));
  }
}

class MemoryCollageTitleRect extends MemoryCollageTitlePlacement {
  final MemoryCollageRect rect;
  final int z;
  final double rotation;

  const MemoryCollageTitleRect({
    required this.rect,
    required this.z,
    required this.rotation,
  });

  factory MemoryCollageTitleRect.fromJson(Map<String, dynamic> json) {
    return MemoryCollageTitleRect(
      rect: MemoryCollageRect.fromJson(json),
      z: _jsonInt(json, "z"),
      rotation: _optionalDouble(json, "rotation") ?? 0,
    );
  }
}

class MemoryCollageTitleStyle {
  final MemoryCollageTitlePlacement placement;
  final String units;
  final String fontFamily;
  final String fontAsset;
  final int fontWeight;
  final String fontStyle;
  final double fontSize;
  final double minFontSize;
  final double lineHeight;
  final int maxLines;
  final double letterSpacing;
  final String color;
  final String? colorOnDark;
  final String textAlign;
  final String verticalAlign;
  final String memoryTitleCasing;
  final String generatedMonthLabelCasing;
  final String glyphFallback;
  final MemoryCollageShadow shadow;

  const MemoryCollageTitleStyle({
    required this.placement,
    required this.units,
    required this.fontFamily,
    required this.fontAsset,
    required this.fontWeight,
    required this.fontStyle,
    required this.fontSize,
    required this.minFontSize,
    required this.lineHeight,
    required this.maxLines,
    required this.letterSpacing,
    required this.color,
    required this.colorOnDark,
    required this.textAlign,
    required this.verticalAlign,
    required this.memoryTitleCasing,
    required this.generatedMonthLabelCasing,
    required this.glyphFallback,
    required this.shadow,
  });

  factory MemoryCollageTitleStyle.fromJson(Map<String, dynamic> json) {
    return MemoryCollageTitleStyle(
      placement: MemoryCollageTitlePlacement.fromJson(
        _jsonMap(json, "placement"),
      ),
      units: _jsonString(json, "units"),
      fontFamily: _jsonString(json, "fontFamily"),
      fontAsset: _jsonString(json, "fontAsset"),
      fontWeight: _jsonInt(json, "fontWeight"),
      fontStyle: _jsonString(json, "fontStyle"),
      fontSize: _jsonDouble(json, "fontSize"),
      minFontSize:
          _optionalDouble(json, "minFontSize") ?? _jsonDouble(json, "fontSize"),
      lineHeight: _optionalDouble(json, "lineHeight") ?? 1,
      maxLines: _optionalInt(json, "maxLines") ?? 1,
      letterSpacing: _jsonDouble(json, "letterSpacing"),
      color: _jsonString(json, "color"),
      colorOnDark: _optionalString(json, "colorOnDark"),
      textAlign: _jsonString(json, "textAlign"),
      verticalAlign: _jsonString(json, "verticalAlign"),
      memoryTitleCasing: _jsonString(json, "memoryTitleCasing"),
      generatedMonthLabelCasing: _jsonString(json, "generatedMonthLabelCasing"),
      glyphFallback: _jsonString(json, "glyphFallback"),
      shadow: MemoryCollageShadow.fromJson(_jsonMap(json, "shadow")),
    );
  }
}

void _validateCanvas(MemoryCollageCanvas canvas, String path) {
  if (canvas.width <= 0 || canvas.height <= 0) {
    throw FormatException("$path must have positive dimensions");
  }
}

void _validateRectGeometry(MemoryCollageRect rect, String path) {
  _validateFinite(rect.x, "$path.x");
  _validateFinite(rect.y, "$path.y");
  if (!rect.width.isFinite || !rect.height.isFinite) {
    throw FormatException("$path dimensions must be finite");
  }
  if (rect.width <= 0 || rect.height <= 0) {
    throw FormatException("$path must have positive dimensions");
  }
}

void _validateShadow(MemoryCollageShadow shadow, String path) {
  if (shadow.kind != "dropShadow") {
    throw FormatException("$path has unsupported kind ${shadow.kind}");
  }
  _validateFinite(shadow.dx, "$path.dx");
  _validateFinite(shadow.dy, "$path.dy");
  if (!shadow.blur.isFinite || shadow.blur < 0) {
    throw FormatException("$path.blur must be a non-negative finite number");
  }
  if (shadow.color.isEmpty) {
    throw FormatException("$path.color cannot be empty");
  }
}

void _validateUnique(Iterable<String> values, String description) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw FormatException("Duplicate $description: $value");
    }
  }
}

void _validateFinite(double value, String path) {
  if (!value.isFinite) throw FormatException("$path must be finite");
}

void _validateUnitInterval(double? value, String path) {
  if (value == null) return;
  if (!value.isFinite || value < 0 || value > 1) {
    throw FormatException("$path must be from 0 to 1");
  }
}

bool _sameInts(Iterable<int> left, Iterable<int> right) {
  final leftIterator = left.iterator;
  final rightIterator = right.iterator;
  while (leftIterator.moveNext()) {
    if (!rightIterator.moveNext() ||
        leftIterator.current != rightIterator.current) {
      return false;
    }
  }
  return !rightIterator.moveNext();
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

List<String> _jsonStringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException("$key must be a list");
  return List.unmodifiable(
    value.map((item) {
      if (item is! String) {
        throw FormatException("$key entries must be strings");
      }
      return item;
    }),
  );
}

Map<String, String> _optionalStringMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const {};
  if (value is! Map) throw FormatException("$key must be an object");
  return Map.unmodifiable(
    value.map<String, String>((entryKey, entryValue) {
      if (entryKey is! String || entryValue is! String) {
        throw FormatException("$key entries must map strings to strings");
      }
      return MapEntry(entryKey, entryValue);
    }),
  );
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

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) throw FormatException("$key must be a boolean");
  return value;
}

int _jsonInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite || value != value.toInt()) {
    throw FormatException("$key must be an integer");
  }
  return value.toInt();
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _jsonInt(json, key);
}

double _jsonDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException("$key must be a finite number");
  }
  return value.toDouble();
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _jsonDouble(json, key);
}
