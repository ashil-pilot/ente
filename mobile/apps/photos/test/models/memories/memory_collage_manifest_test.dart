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
    expect(manifest.assets, hasLength(20));
    expect(manifest.backgroundAssets, hasLength(5));
    expect(manifest.template.layers, hasLength(17));
    expect(
      manifest.template.photoLayouts.map((layout) => layout.photoCount),
      orderedEquals([6, 7]),
    );
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

  test("every adaptive layout resolves to declared asset windows", () {
    for (final layout in manifest.template.photoLayouts) {
      expect(layout.photoSlots, hasLength(layout.photoCount));
      expect(
        layout.photoSlots.map((slot) => slot.slot),
        orderedEquals(List.generate(layout.photoCount, (index) => index)),
      );

      for (final layer in manifest.template.layers) {
        expect(
          () => manifest.assetFor(layout.assetIDFor(layer)),
          returnsNormally,
        );
      }

      for (final slot in layout.photoSlots) {
        final layer = manifest.template.layerFor(slot.layerID);
        final asset = manifest.assetFor(layout.assetIDFor(layer));
        expect(
          slot.windowIndex,
          inInclusiveRange(0, asset.photoWindows.length - 1),
        );
      }
    }
  });

  test("parses the exact six- and seven-photo layouts", () {
    final sixPhotoLayout = manifest.template.layoutForPhotoCount(6);
    final sevenPhotoLayout = manifest.template.layoutForPhotoCount(7);

    expect(sixPhotoLayout.assetOverrides, {"strip": "film-strip"});
    expect(
      sixPhotoLayout.photoSlots.map(_slotContract),
      orderedEquals([
        (0, "strip", 0),
        (1, "strip", 1),
        (2, "strip", 2),
        (3, "p1", 0),
        (4, "p2", 0),
        (5, "p3", 0),
      ]),
    );
    expect(sevenPhotoLayout.assetOverrides, {"strip": "film-strip-four"});
    expect(
      sevenPhotoLayout.photoSlots.map(_slotContract),
      orderedEquals([
        (0, "strip", 0),
        (1, "strip", 1),
        (2, "strip", 2),
        (3, "p1", 0),
        (4, "p2", 0),
        (5, "p3", 0),
        (6, "strip", 3),
      ]),
    );
  });

  test("parses the centered three- and four-frame film windows", () {
    final threeFrameWindows = manifest.assetFor("film-strip").photoWindows;
    final fourFrameWindows = manifest.assetFor("film-strip-four").photoWindows;
    final polaroidWindows = manifest.assetFor("polaroid-frame").photoWindows;

    expect(threeFrameWindows, hasLength(3));
    expect(threeFrameWindows.map((window) => window.y), [261, 645, 1029]);
    expect(fourFrameWindows, hasLength(4));
    expect(fourFrameWindows.map((window) => window.y), [69, 453, 837, 1221]);
    for (final window in [...threeFrameWindows, ...fourFrameWindows]) {
      expect(window.x, 57);
      expect(window.width, 276);
      expect(window.height, 318);
    }
    expect(polaroidWindows, hasLength(1));
    expect(polaroidWindows.single.width, 414);
    expect(polaroidWindows.single.height, 420);
  });

  test("rejects unsupported photo counts", () {
    expect(
      () => manifest.template.layoutForPhotoCount(5),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => manifest.template.layoutForPhotoCount(8),
      throwsA(isA<FormatException>()),
    );
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
      () => manifest.template.photoLayouts.add(
        manifest.template.photoLayouts.first,
      ),
      throwsUnsupportedError,
    );
    final layout = manifest.template.layoutForPhotoCount(6);
    expect(
      () => layout.photoSlots.add(layout.photoSlots.first),
      throwsUnsupportedError,
    );
    expect(
      () => layout.assetOverrides["strip"] = "film-strip-four",
      throwsUnsupportedError,
    );
  });
}

(int, String, int) _slotContract(MemoryCollagePhotoSlot slot) =>
    (slot.slot, slot.layerID, slot.windowIndex);
