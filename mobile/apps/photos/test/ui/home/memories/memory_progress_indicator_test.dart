import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";

void main() {
  test("adds a final progress step for the collage", () {
    expect(
      memoryProgressTotalSteps(memoryItemCount: 7, includeCollage: true),
      8,
    );
  });

  test("keeps six memories at six steps when collage is unavailable", () {
    expect(
      memoryProgressTotalSteps(memoryItemCount: 6, includeCollage: false),
      6,
    );
  });

  testWidgets("fills the available width with equal chunks", (tester) async {
    const totalSteps = 6;
    const availableWidth = 343.0;
    const currentIndex = 3;

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: availableWidth,
            child: MemoryProgressIndicator(
              totalSteps: totalSteps,
              currentIndex: currentIndex,
            ),
          ),
        ),
      ),
    );

    final widths = [
      for (var index = 0; index < totalSteps; index++)
        tester
            .getSize(find.byKey(ValueKey("memory-progress-segment-$index")))
            .width,
    ];

    for (final width in widths.skip(1)) {
      expect(width, widths.first);
    }
    expect(
      widths.reduce((left, right) => left + right) +
          ((totalSteps - 1) * kMemoryProgressGap),
      availableWidth,
    );
  });

  testWidgets("uses the full track when segmented chunks become too narrow", (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 343,
            child: MemoryProgressIndicator(totalSteps: 20, currentIndex: 7),
          ),
        ),
      ),
    );

    expect(find.byType(Row), findsNothing);
    expect(tester.getSize(find.byType(LinearProgressIndicator)).width, 343);
  });

  testWidgets("renders the collage as the final active segment", (
    tester,
  ) async {
    const memoryItemCount = 7;
    final totalSteps = memoryProgressTotalSteps(
      memoryItemCount: memoryItemCount,
      includeCollage: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 343,
            child: MemoryProgressIndicator(
              totalSteps: totalSteps,
              currentIndex: memoryItemCount,
              currentStepProgress: 1,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey("memory-progress-segment-7")),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey("memory-progress-segment-7")),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    final finalSegment = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const ValueKey("memory-progress-segment-7")),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(finalSegment.value, 1);
  });

  testWidgets("completes a continuous track on the collage step", (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 343,
            child: MemoryProgressIndicator(
              totalSteps: 20,
              currentIndex: 19,
              currentStepProgress: 1,
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });
}
