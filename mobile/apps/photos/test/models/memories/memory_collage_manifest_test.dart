import "package:flutter_test/flutter_test.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryCollageManifest manifest;

  setUpAll(() async {
    manifest = await MemoryCollageManifest.load();
  });

  test("loads the approved template contract", () {
    expect(manifest.version, 1);
    expect(manifest.canvas.width, 1080);
    expect(manifest.canvas.height, 1920);
    expect(manifest.assets, hasLength(19));
    expect(manifest.backgroundAssets, hasLength(5));
    expect(manifest.template.layers, hasLength(17));
    expect(manifest.template.photoSlots, hasLength(6));
  });

  test("sorts layers by z and preserves source order for ties", () {
    final layers = manifest.template.layers;

    for (var index = 1; index < layers.length; index++) {
      expect(layers[index - 1].z, lessThanOrEqualTo(layers[index].z));
    }
    expect(
      layers.where((layer) => layer.z == 15).map((layer) => layer.layerID),
      orderedEquals(["tapeB", "tapeC"]),
    );
    expect(
      layers.where((layer) => layer.z == 17).map((layer) => layer.layerID),
      orderedEquals(["tapeA", "stamp"]),
    );
  });

  test("every layer and photo slot resolves to a declared asset window", () {
    for (final layer in manifest.template.layers) {
      expect(() => manifest.assetFor(layer.assetID), returnsNormally);
    }

    for (final slot in manifest.template.photoSlots) {
      final layer = manifest.template.layerFor(slot.layerID);
      final asset = manifest.assetFor(layer.assetID);
      expect(
        slot.windowIndex,
        inInclusiveRange(0, asset.photoWindows.length - 1),
      );
    }
  });

  test("parses the six fixed photo windows", () {
    final filmWindows = manifest.assetFor("film-strip").photoWindows;
    final polaroidWindows = manifest.assetFor("polaroid-frame").photoWindows;

    expect(filmWindows, hasLength(3));
    expect(filmWindows.first.width, 276);
    expect(filmWindows.first.height, 318);
    expect(polaroidWindows, hasLength(1));
    expect(polaroidWindows.single.width, 414);
    expect(polaroidWindows.single.height, 420);
  });

  test("parses approved title typography and overlay blends", () {
    final title = manifest.template.titleStyle;

    expect(title.layerID, "banner");
    expect(title.fontFamily, "Lora");
    expect(title.fontWeight, 600);
    expect(title.fontSize, 45);
    expect(title.letterSpacing, 12);
    expect(title.memoryTitleCasing, "preserve");
    expect(manifest.template.layerFor("sunStreak").blendMode, "soft-light");
    expect(manifest.template.layerFor("vignette").blendMode, "multiply");
    expect(manifest.template.layerFor("grain").blendMode, "overlay");
    expect(manifest.template.layerFor("grain").opacity, 0.55);
  });

  test("exposes immutable manifest collections", () {
    expect(
      () => manifest.assets.add(manifest.assets.first),
      throwsUnsupportedError,
    );
    expect(
      () => manifest.template.layers.add(manifest.template.layers.first),
      throwsUnsupportedError,
    );
    expect(
      () =>
          manifest.template.photoSlots.add(manifest.template.photoSlots.first),
      throwsUnsupportedError,
    );
  });
}
