import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/collage/memory_collage_canvas.dart";

import "memory_collage_canvas_test_support.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    "lays out the 6-photo canvas with the exact export contract",
    (tester) => verifyMemoryCollageCanvas(tester, photoCount: 6),
  );

  test("parses the authored CSS color formats", () {
    expect(parseMemoryCollageColor("#f4e7cf"), const Color(0xFFF4E7CF));
    expect(
      parseMemoryCollageColor("rgba(90,40,15,0.5)"),
      const Color.fromRGBO(90, 40, 15, 0.5),
    );
  });
}
