import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/home/memories/collage/memory_collage_editor_page.dart";

void main() {
  test("template changes invalidate all seven renderer slots", () {
    final readiness = MemoryCollageRendererReadiness()
      ..initialize(shuffleRevision: 0, templateID: "scrapbook-maximal");
    final firstGeneration = readiness.generation;
    for (var slot = 0; slot < 7; slot++) {
      expect(
        readiness.markSlotLoaded(generation: firstGeneration, slot: slot),
        isTrue,
      );
    }
    expect(readiness.areAllSlotsLoaded(7), isTrue);

    expect(readiness.prepareTemplate("scrapbook-calm"), isTrue);

    final secondGeneration = readiness.generation;
    expect(secondGeneration, firstGeneration + 1);
    expect(readiness.areAllSlotsLoaded(7), isFalse);
    expect(
      readiness.markSlotLoaded(generation: firstGeneration, slot: 0),
      isFalse,
    );
    for (var slot = 0; slot < 7; slot++) {
      readiness.markSlotLoaded(generation: secondGeneration, slot: slot);
    }
    expect(readiness.areAllSlotsLoaded(7), isTrue);
    expect(
      readiness.synchronize(shuffleRevision: 0, templateID: "scrapbook-calm"),
      isFalse,
    );
    expect(readiness.generation, secondGeneration);
  });

  testWidgets("shows three accessible direct template choices", (tester) async {
    final semantics = tester.ensureSemantics();
    String? selectedTemplateID;

    await tester.pumpWidget(
      _TestApp(
        child: MemoryCollageTemplateSelector(
          availableTemplateIDs: MemoryCollageTemplateSelector.templateIDs,
          selectedTemplateID: "scrapbook-maximal",
          enabled: true,
          onSelected: (templateID) => selectedTemplateID = templateID,
        ),
      ),
    );

    expect(find.text("Scrapbook"), findsOneWidget);
    expect(find.text("Calm"), findsOneWidget);
    expect(find.text("Minimal"), findsOneWidget);
    expect(find.bySemanticsLabel("Scrapbook"), findsOneWidget);
    expect(find.bySemanticsLabel("Calm"), findsOneWidget);
    expect(find.bySemanticsLabel("Minimal"), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey("memory-collage-template-scrapbook-calm")),
    );
    await tester.pump();

    expect(selectedTemplateID, "scrapbook-calm");
    semantics.dispose();
  });

  testWidgets("scrolls safely at narrow width and large text", (tester) async {
    String? selectedTemplateID;

    await tester.pumpWidget(
      _TestApp(
        width: 220,
        textScaler: const TextScaler.linear(2),
        child: MemoryCollageTemplateSelector(
          availableTemplateIDs: MemoryCollageTemplateSelector.templateIDs,
          selectedTemplateID: "scrapbook-maximal",
          enabled: true,
          onSelected: (templateID) => selectedTemplateID = templateID,
        ),
      ),
    );

    final minimalChip = find.byKey(
      const ValueKey("memory-collage-template-minimal-editorial"),
    );
    expect(minimalChip, findsOneWidget);
    await tester.ensureVisible(minimalChip);
    await tester.tap(minimalChip);
    await tester.pump();

    expect(selectedTemplateID, "minimal-editorial");
    expect(tester.takeException(), isNull);
  });

  testWidgets("disables template choices while assets are loading", (
    tester,
  ) async {
    var selections = 0;

    await tester.pumpWidget(
      _TestApp(
        child: MemoryCollageTemplateSelector(
          availableTemplateIDs: MemoryCollageTemplateSelector.templateIDs,
          selectedTemplateID: "scrapbook-maximal",
          enabled: false,
          onSelected: (_) => selections++,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey("memory-collage-template-scrapbook-calm")),
    );
    await tester.pump();

    expect(selections, 0);
  });
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final double width;
  final TextScaler textScaler;

  const _TestApp({
    required this.child,
    this.width = 400,
    this.textScaler = TextScaler.noScaling,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: textScaler),
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }
}
