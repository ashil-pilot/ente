import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/collage/memory_collage_export.dart";

void main() {
  testWidgets("captures the collage boundary as a 1080 x 1920 PNG", (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: repaintKey,
        child: const ColoredBox(color: Colors.orange),
      ),
    );

    final capture = MemoryCollageExport.capturePng(repaintKey);
    await tester.pump();
    final bytes = (await tester.runAsync(() => capture))!;

    expect(
      bytes.take(8),
      orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
    );
    final codec = (await tester.runAsync(
      () => ui.instantiateImageCodec(bytes),
    ))!;
    addTearDown(codec.dispose);
    final frame = (await tester.runAsync(codec.getNextFrame))!;
    addTearDown(frame.image.dispose);
    expect(frame.image.width, 1080);
    expect(frame.image.height, 1920);
  });
}
