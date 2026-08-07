import "package:flutter_test/flutter_test.dart";

import "memory_collage_canvas_test_support.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    "lays out the 7-photo canvas with the exact export contract",
    (tester) => verifyMemoryCollageCanvas(tester, photoCount: 7),
  );
}
