import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/semantics.dart" show SemanticsAction;
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/home/memories/collage/memory_collage_editor_page.dart";
import "package:photos/ui/home/memories/memory_viewer_chrome.dart";

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

    expect(readiness.prepareTemplate("calm-film-trio"), isTrue);

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
      readiness.synchronize(shuffleRevision: 0, templateID: "calm-film-trio"),
      isFalse,
    );
    expect(readiness.generation, secondGeneration);
  });

  testWidgets("top bar is titleless and uses viewer export actions", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(320, 640));
    var backTaps = 0;
    var shareTaps = 0;
    var saveTaps = 0;

    await tester.pumpWidget(
      _TestApp(
        width: 320,
        child: Scaffold(
          appBar: MemoryCollageEditorTopBar(
            canExport: true,
            onBack: () => backTaps++,
            onShare: () => shareTaps++,
            onSave: () => saveTaps++,
          ),
        ),
      ),
    );

    expect(find.text("Create collage"), findsNothing);
    expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
    expect(find.byType(MemoryViewerActionButton), findsNWidgets(3));
    final icons = tester.widgetList<HugeIcon>(find.byType(HugeIcon)).toList();
    expect(
      identical(icons[0].icon, HugeIcons.strokeRoundedArrowLeft01),
      isTrue,
    );
    expect(identical(icons[1].icon, HugeIcons.strokeRoundedShare08), isTrue);
    expect(identical(icons[2].icon, HugeIcons.strokeRoundedDownload01), isTrue);

    await tester.tap(find.byTooltip("Back"));
    await tester.tap(find.byTooltip("Share"));
    await tester.tap(find.byTooltip("Save"));
    expect((backTaps, shareTaps, saveTaps), (1, 1, 1));
    _expectTapEffect(tester, "Back", isVisible: true);
    _expectTapEffect(tester, "Share", isVisible: false);
    _expectTapEffect(tester, "Save", isVisible: false);
  });

  testWidgets("top bar shows a spinner only for the active export action", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(320, 640));

    Future<void> pumpTopBar({bool isSharing = false, bool isSaving = false}) {
      return tester.pumpWidget(
        _TestApp(
          width: 320,
          child: Scaffold(
            appBar: MemoryCollageEditorTopBar(
              canExport: true,
              isSharing: isSharing,
              isSaving: isSaving,
              onBack: () {},
              onShare: () {},
              onSave: () {},
            ),
          ),
        ),
      );
    }

    await pumpTopBar(isSharing: true);
    _expectOnlyTooltipLoading(tester, loadingTooltip: "Sharing...");
    expect(_actionOnPressed(tester, "Sharing..."), isNull);
    expect(_actionOnPressed(tester, "Save"), isNull);
    expect(_actionIconOpacity(tester, "Sharing..."), 1);
    expect(_actionIconOpacity(tester, "Save"), 1);

    await pumpTopBar(isSaving: true);
    _expectOnlyTooltipLoading(tester, loadingTooltip: "Saving...");
    expect(_actionOnPressed(tester, "Share"), isNull);
    expect(_actionOnPressed(tester, "Saving..."), isNull);
    expect(_actionIconOpacity(tester, "Share"), 1);
    expect(_actionIconOpacity(tester, "Saving..."), 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets("export actions look active but no-op while getting ready", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(320, 640));
    var shareTaps = 0;
    var saveTaps = 0;

    await tester.pumpWidget(
      _TestApp(
        width: 320,
        child: Scaffold(
          appBar: MemoryCollageEditorTopBar(
            canExport: false,
            onBack: () {},
            onShare: () => shareTaps++,
            onSave: () => saveTaps++,
          ),
        ),
      ),
    );

    expect(_actionIconOpacity(tester, "Share"), 1);
    expect(_actionIconOpacity(tester, "Save"), 1);
    expect(_actionOnPressed(tester, "Share"), isNotNull);
    expect(_actionOnPressed(tester, "Save"), isNotNull);
    await tester.tap(find.byTooltip("Share"));
    await tester.tap(find.byTooltip("Save"));
    expect((shareTaps, saveTaps), (0, 0));
  });

  testWidgets("compact controls dispatch one tap each", (tester) async {
    final semantics = tester.ensureSemantics();
    var styleTaps = 0;
    var shuffleTaps = 0;
    var backgroundTaps = 0;

    await tester.pumpWidget(
      _TestApp(
        child: MemoryCollageEditorControlDock(
          styleLabel: "Style",
          styleValue: "Calm",
          shuffleLabel: "Shuffle",
          backgroundLabel: "Background",
          backgroundValue: "2 of 4",
          onStyle: () => styleTaps++,
          onShuffle: () => shuffleTaps++,
          onBackground: () => backgroundTaps++,
        ),
      ),
    );

    for (final label in ["Style", "Shuffle", "Background"]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        tester.getSize(find.byTooltip(label)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byTooltip(label));
    }
    expect((styleTaps, shuffleTaps, backgroundTaps), (1, 1, 1));
    expect(tester.getSemantics(find.bySemanticsLabel("Style")).value, "Calm");
    expect(
      tester.getSemantics(find.bySemanticsLabel("Background")).value,
      "2 of 4",
    );
    semantics.dispose();
  });

  testWidgets("controls stay overflow-free at narrow width and large text", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(220, 400));

    await tester.pumpWidget(
      _TestApp(
        width: 220,
        textScaler: const TextScaler.linear(3),
        child: MemoryCollageEditorControlDock(
          styleLabel: "Style",
          styleValue: "Calm",
          shuffleLabel: "Shuffle",
          backgroundLabel: "A deliberately long background label",
          backgroundValue: "2 of 4",
          onStyle: () {},
          onShuffle: () {},
          onBackground: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets("locked controls ignore taps without changing their appearance", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      _TestApp(
        child: MemoryCollageEditorControlDock(
          styleLabel: "Style",
          styleValue: "Calm",
          shuffleLabel: "Shuffle",
          backgroundLabel: "Background",
          backgroundValue: "2 of 4",
          interactionLocked: true,
          onStyle: () => taps++,
          onShuffle: () => taps++,
          onBackground: () => taps++,
        ),
      ),
    );

    for (final label in ["Style", "Shuffle", "Background"]) {
      await tester.tap(find.byTooltip(label));
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
    }
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(HugeIcon), findsNWidgets(3));
    expect(
      tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((opacity) => opacity.opacity),
      everyElement(1),
    );
    semantics.dispose();
  });
}

void _expectOnlyTooltipLoading(
  WidgetTester tester, {
  required String loadingTooltip,
}) {
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  for (final tooltip in ["Back", "Share", "Sharing...", "Save", "Saving..."]) {
    final action = _actionButton(tooltip);
    if (action.evaluate().isEmpty) continue;
    expect(
      find.descendant(
        of: action,
        matching: find.byType(CircularProgressIndicator),
      ),
      tooltip == loadingTooltip ? findsOneWidget : findsNothing,
    );
  }
}

double _actionIconOpacity(WidgetTester tester, String tooltip) {
  final button = _actionIconButton(tester, tooltip);
  return (button.icon as Opacity).opacity;
}

VoidCallback? _actionOnPressed(WidgetTester tester, String tooltip) {
  return _actionIconButton(tester, tooltip).onPressed;
}

IconButton _actionIconButton(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.descendant(
      of: _actionButton(tooltip),
      matching: find.byType(IconButton),
    ),
  );
}

void _expectTapEffect(
  WidgetTester tester,
  String tooltip, {
  required bool isVisible,
}) {
  final button = _actionIconButton(tester, tooltip);
  expect(
    button.style?.splashFactory,
    isVisible ? isNull : NoSplash.splashFactory,
  );
  expect(
    button.style?.overlayColor?.resolve({WidgetState.pressed}),
    isVisible ? isNot(Colors.transparent) : Colors.transparent,
  );
}

Finder _actionButton(String tooltip) {
  return find.byWidgetPredicate(
    (widget) => widget is MemoryViewerActionButton && widget.tooltip == tooltip,
  );
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
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
