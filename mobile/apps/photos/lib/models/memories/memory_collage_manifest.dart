import "dart:convert";

import "package:flutter/services.dart";

const memoryCollageManifestAsset = "assets/memories_collage/manifest.json";

class MemoryCollageManifest {
  final int version;
  final MemoryCollageCanvas canvas;
  final List<MemoryCollageBackground> backgrounds;
  final String defaultTemplateID;
  final List<MemoryCollageTemplate> templates;
  final Map<String, MemoryCollageBackground> _backgroundsByID;
  final Map<String, MemoryCollageTemplate> _templatesByID;

  MemoryCollageManifest._({
    required this.version,
    required this.canvas,
    required List<MemoryCollageBackground> backgrounds,
    required this.defaultTemplateID,
    required List<MemoryCollageTemplate> templates,
  }) : backgrounds = List.unmodifiable(backgrounds),
       templates = List.unmodifiable(templates),
       _backgroundsByID = Map.unmodifiable({
         for (final background in backgrounds) background.id: background,
       }),
       _templatesByID = Map.unmodifiable({
         for (final template in templates) template.id: template,
       });

  factory MemoryCollageManifest.fromJson(Map<String, dynamic> json) {
    final version = _jsonInt(json, "version");
    if (version != 3) {
      throw FormatException(
        "Unsupported memory collage manifest version: $version",
      );
    }

    final manifest = MemoryCollageManifest._(
      version: version,
      canvas: MemoryCollageCanvas.fromJson(_jsonMap(json, "canvas")),
      backgrounds: _jsonList(
        _jsonMap(json, "backgrounds"),
        "assets",
      ).map(MemoryCollageBackground.fromJson).toList(growable: false),
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

  List<String> get backgroundAssetIDs =>
      List.unmodifiable(backgrounds.map((background) => background.id));

  MemoryCollageBackground backgroundFor(String id) {
    final background = _backgroundsByID[id];
    if (background == null) {
      throw FormatException("Unknown memory collage background: $id");
    }
    return background;
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
      backgrounds.map((background) => background.id),
      "memory collage background IDs",
    );
    _validateUnique(
      templates.map((template) => template.id),
      "memory collage template IDs",
    );
    if (backgrounds.isEmpty) {
      throw const FormatException(
        "Memory collage manifest must declare at least one background",
      );
    }
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

    for (final background in backgrounds) {
      if (background.id.isEmpty) {
        throw const FormatException(
          "Memory collage background ID cannot be empty",
        );
      }
      if (background.width != canvas.width ||
          background.height != canvas.height) {
        throw FormatException(
          "Memory collage background ${background.id} must match the canvas",
        );
      }
    }
    for (final template in templates) {
      _validateTemplate(template);
    }
  }

  void _validateTemplate(MemoryCollageTemplate template) {
    if (template.id.isEmpty) {
      throw const FormatException("Memory collage template ID cannot be empty");
    }
    if (template.plateAssetID.isEmpty) {
      throw FormatException(
        "Template ${template.id} must declare a layout plate",
      );
    }
    if (!_backgroundsByID.containsKey(template.defaultBackgroundAssetID)) {
      throw FormatException(
        "Template ${template.id} references unknown default background "
        "${template.defaultBackgroundAssetID}",
      );
    }
    const requiredSlots = 7;
    final slotIDs = template.photoSlots.map((slot) => slot.slot).toList();
    if (slotIDs.length != requiredSlots ||
        slotIDs.toSet().length != requiredSlots ||
        !slotIDs.every((slot) => slot >= 0 && slot < requiredSlots)) {
      throw FormatException(
        "Template ${template.id} must declare each photo slot from 0 to 6 "
        "exactly once",
      );
    }
    for (final slot in template.photoSlots) {
      final path = "${template.id}.photoSlots[${slot.slot}]";
      _validateCanvasRect(slot.rect, path);
      _validateFinite(slot.rotation, "$path.rotation");
      if (slot.backingColor.isEmpty) {
        throw FormatException("$path.backingColor cannot be empty");
      }
    }

    _validateTitle(template.id, template.title);
  }

  void _validateTitle(String templateID, MemoryCollageTitleStyle title) {
    final path = "$templateID.title";
    _validateCanvasRect(title.rect, path);
    _validateFinite(title.rotation, "$path.rotation");
    if (title.fontFamily.isEmpty) {
      throw FormatException("$path.fontFamily cannot be empty");
    }
    if (title.fontWeight < 100 ||
        title.fontWeight > 900 ||
        title.fontWeight % 100 != 0) {
      throw FormatException(
        "$path.fontWeight must be a multiple of 100 from 100 to 900",
      );
    }
    if (!title.fontSize.isFinite || title.fontSize <= 0) {
      throw FormatException("$path.fontSize must be positive");
    }
    if (!title.minFontSize.isFinite ||
        title.minFontSize <= 0 ||
        title.minFontSize > title.fontSize) {
      throw FormatException(
        "$path.minFontSize must be positive and no larger than fontSize",
      );
    }
    if (!title.lineHeight.isFinite || title.lineHeight <= 0) {
      throw FormatException("$path.lineHeight must be positive");
    }
    if (title.maxLines <= 0) {
      throw FormatException("$path.maxLines must be positive");
    }
    _validateFinite(title.letterSpacing, "$path.letterSpacing");
    if (title.color.isEmpty) {
      throw FormatException("$path.color cannot be empty");
    }
    const textAlignments = {"left", "center", "right", "start", "end"};
    if (!textAlignments.contains(title.textAlign)) {
      throw FormatException(
        "$path has unsupported textAlign ${title.textAlign}",
      );
    }
    const verticalAlignments = {"top", "center", "bottom"};
    if (!verticalAlignments.contains(title.verticalAlign)) {
      throw FormatException(
        "$path has unsupported verticalAlign ${title.verticalAlign}",
      );
    }
    final shadow = title.shadow;
    if (shadow != null) _validateShadow(shadow, "$path.shadow");
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

class MemoryCollageBackground {
  final String id;
  final int width;
  final int height;

  const MemoryCollageBackground({
    required this.id,
    required this.width,
    required this.height,
  });

  factory MemoryCollageBackground.fromJson(Map<String, dynamic> json) {
    return MemoryCollageBackground(
      id: _jsonString(json, "id"),
      width: _jsonInt(json, "width"),
      height: _jsonInt(json, "height"),
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

enum MemoryCollageFinishPreset {
  scrapbook,
  calm,
  minimal;

  factory MemoryCollageFinishPreset.fromJson(String value) {
    return switch (value) {
      "scrapbook" => scrapbook,
      "calm" => calm,
      "minimal" => minimal,
      _ => throw FormatException(
        "Unsupported memory collage finish preset: $value",
      ),
    };
  }
}

class MemoryCollageTemplate {
  final String id;
  final String defaultBackgroundAssetID;
  final String plateAssetID;
  final MemoryCollageFinishPreset finishPreset;
  final List<MemoryCollagePhotoSlot> photoSlots;
  final MemoryCollageTitleStyle title;

  MemoryCollageTemplate._({
    required this.id,
    required this.defaultBackgroundAssetID,
    required this.plateAssetID,
    required this.finishPreset,
    required List<MemoryCollagePhotoSlot> photoSlots,
    required this.title,
  }) : photoSlots = List.unmodifiable(photoSlots);

  factory MemoryCollageTemplate.fromJson(Map<String, dynamic> json) {
    final sourceSlots = _jsonList(json, "photoSlots");
    final photoSlots =
        <MemoryCollagePhotoSlot>[
          for (var index = 0; index < sourceSlots.length; index++)
            MemoryCollagePhotoSlot.fromJson(
              sourceSlots[index],
              sourceIndex: index,
            ),
        ]..sort((left, right) {
          final zOrder = left.z.compareTo(right.z);
          return zOrder != 0
              ? zOrder
              : left.sourceIndex.compareTo(right.sourceIndex);
        });

    return MemoryCollageTemplate._(
      id: _jsonString(json, "id"),
      defaultBackgroundAssetID: _jsonString(json, "defaultBackgroundAssetId"),
      plateAssetID: _jsonString(json, "plateAssetId"),
      finishPreset: MemoryCollageFinishPreset.fromJson(
        _jsonString(json, "finishPreset"),
      ),
      photoSlots: photoSlots,
      title: MemoryCollageTitleStyle.fromJson(_jsonMap(json, "title")),
    );
  }

  MemoryCollagePhotoSlot photoSlot(int slot) {
    for (final photoSlot in photoSlots) {
      if (photoSlot.slot == slot) return photoSlot;
    }
    throw FormatException("Unknown photo slot in template $id: $slot");
  }
}

class MemoryCollagePhotoSlot {
  final int slot;
  final MemoryCollageRect rect;
  final int z;
  final double rotation;
  final String backingColor;

  /// Position in the manifest before z-ordering. It preserves deterministic
  /// artist-authored order when two photos share the same z value.
  final int sourceIndex;

  const MemoryCollagePhotoSlot({
    required this.slot,
    required this.rect,
    required this.z,
    required this.rotation,
    required this.backingColor,
    required this.sourceIndex,
  });

  factory MemoryCollagePhotoSlot.fromJson(
    Map<String, dynamic> json, {
    required int sourceIndex,
  }) {
    return MemoryCollagePhotoSlot(
      slot: _jsonInt(json, "slot"),
      rect: MemoryCollageRect.fromJson(json),
      z: _jsonInt(json, "z"),
      rotation: _jsonDouble(json, "rotation"),
      backingColor: _jsonString(json, "backingColor"),
      sourceIndex: sourceIndex,
    );
  }
}

class MemoryCollageTitleStyle {
  final MemoryCollageRect rect;
  final double rotation;
  final String fontFamily;
  final int fontWeight;
  final double fontSize;
  final double minFontSize;
  final double lineHeight;
  final int maxLines;
  final double letterSpacing;
  final String color;
  final String textAlign;
  final String verticalAlign;
  final MemoryCollageShadow? shadow;

  const MemoryCollageTitleStyle({
    required this.rect,
    required this.rotation,
    required this.fontFamily,
    required this.fontWeight,
    required this.fontSize,
    required this.minFontSize,
    required this.lineHeight,
    required this.maxLines,
    required this.letterSpacing,
    required this.color,
    required this.textAlign,
    required this.verticalAlign,
    required this.shadow,
  });

  factory MemoryCollageTitleStyle.fromJson(Map<String, dynamic> json) {
    return MemoryCollageTitleStyle(
      rect: MemoryCollageRect.fromJson(json),
      rotation: _jsonDouble(json, "rotation"),
      fontFamily: _jsonString(json, "fontFamily"),
      fontWeight: _jsonInt(json, "fontWeight"),
      fontSize: _jsonDouble(json, "fontSize"),
      minFontSize: _jsonDouble(json, "minFontSize"),
      lineHeight: _jsonDouble(json, "lineHeight"),
      maxLines: _jsonInt(json, "maxLines"),
      letterSpacing: _jsonDouble(json, "letterSpacing"),
      color: _jsonString(json, "color"),
      textAlign: _jsonString(json, "textAlign"),
      verticalAlign: _jsonString(json, "verticalAlign"),
      shadow: json["shadow"] == null
          ? null
          : MemoryCollageShadow.fromJson(_jsonMap(json, "shadow")),
    );
  }
}

class MemoryCollageShadow {
  final double dx;
  final double dy;
  final double blur;
  final String color;

  const MemoryCollageShadow({
    required this.dx,
    required this.dy,
    required this.blur,
    required this.color,
  });

  factory MemoryCollageShadow.fromJson(Map<String, dynamic> json) {
    return MemoryCollageShadow(
      dx: _jsonDouble(json, "dx"),
      dy: _jsonDouble(json, "dy"),
      blur: _jsonDouble(json, "blur"),
      color: _jsonString(json, "color"),
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

String _jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException("$key must be a string");
  return value;
}

int _jsonInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite || value != value.toInt()) {
    throw FormatException("$key must be an integer");
  }
  return value.toInt();
}

double _jsonDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException("$key must be a finite number");
  }
  return value.toDouble();
}
