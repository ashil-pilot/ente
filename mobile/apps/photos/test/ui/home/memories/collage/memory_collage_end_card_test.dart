import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/home/memories/collage/memory_collage_end_card.dart";
import "package:photos/ui/home/memories/memory_viewer_chrome.dart";

void main() {
  testWidgets("centers the full-width collage vertically in the viewer", (
    tester,
  ) async {
    const viewportSize = Size(402, 874);
    const collageKey = ValueKey("collage-canvas");
    await _setSurfaceSize(tester, viewportSize);

    await tester.pumpWidget(
      _testApp(
        const MemoryCollageEndCardCanvasLayout(
          child: SizedBox(key: collageKey, width: 360, height: 640),
        ),
      ),
    );

    final collageRect = tester.getRect(find.byKey(collageKey));
    final topSpace = collageRect.top;
    final bottomSpace = viewportSize.height - collageRect.bottom;

    expect(collageRect.width, closeTo(viewportSize.width, 0.001));
    expect(collageRect.height / collageRect.width, closeTo(16 / 9, 0.001));
    expect(topSpace, closeTo(bottomSpace, 0.001));
    expect(topSpace, closeTo(79.67, 0.01));
  });

  testWidgets("shows share, edit, and save as the three collage actions", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(320, 640));
    var shareTaps = 0;
    var editTaps = 0;
    var saveTaps = 0;

    await tester.pumpWidget(
      _testApp(
        MemoryCollageEndCardActions(
          canExport: true,
          onShare: () => shareTaps++,
          onEdit: () => editTaps++,
          onSave: () => saveTaps++,
        ),
      ),
    );

    expect(find.byType(MemoryViewerActionButton), findsNWidgets(3));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(HugeIcon), findsNWidgets(3));

    final icons = tester.widgetList<HugeIcon>(find.byType(HugeIcon)).toList();
    expect(identical(icons[0].icon, HugeIcons.strokeRoundedShare08), isTrue);
    expect(identical(icons[1].icon, HugeIcons.strokeRoundedEdit03), isTrue);
    expect(identical(icons[2].icon, HugeIcons.strokeRoundedDownload01), isTrue);

    for (final key in [
      memoryCollageShareActionKey,
      memoryCollageEditActionKey,
      memoryCollageSaveActionKey,
    ]) {
      expect(tester.getSize(find.byKey(key)), const Size.square(48));
    }

    await tester.tap(find.byKey(memoryCollageShareActionKey));
    await tester.tap(find.byKey(memoryCollageEditActionKey));
    await tester.tap(find.byKey(memoryCollageSaveActionKey));
    expect((shareTaps, editTaps, saveTaps), (1, 1, 1));
    _expectTapEffect(tester, memoryCollageShareActionKey, isVisible: false);
    _expectTapEffect(tester, memoryCollageEditActionKey, isVisible: true);
    _expectTapEffect(tester, memoryCollageSaveActionKey, isVisible: false);
  });

  testWidgets("export actions look active but no-op while getting ready", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(240, 480));
    var shareTaps = 0;
    var editTaps = 0;
    var saveTaps = 0;

    await tester.pumpWidget(
      _testApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(240, 480),
            textScaler: TextScaler.linear(3),
          ),
          child: MemoryCollageEndCardActions(
            canExport: false,
            onShare: () => shareTaps++,
            onEdit: () => editTaps++,
            onSave: () => saveTaps++,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(_actionIconOpacity(tester, memoryCollageShareActionKey), 1);
    expect(_actionIconOpacity(tester, memoryCollageEditActionKey), 1);
    expect(_actionIconOpacity(tester, memoryCollageSaveActionKey), 1);
    expect(_actionOnPressed(tester, memoryCollageShareActionKey), isNotNull);
    expect(_actionOnPressed(tester, memoryCollageSaveActionKey), isNotNull);
    await tester.tap(find.byKey(memoryCollageShareActionKey));
    await tester.tap(find.byKey(memoryCollageEditActionKey));
    await tester.tap(find.byKey(memoryCollageSaveActionKey));
    expect((shareTaps, editTaps, saveTaps), (0, 1, 0));
  });

  testWidgets("replaces only the active export action with a spinner", (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(320, 640));

    Future<void> pumpActions({bool isSharing = false, bool isSaving = false}) {
      return tester.pumpWidget(
        _testApp(
          MemoryCollageEndCardActions(
            canExport: true,
            isSharing: isSharing,
            isSaving: isSaving,
            onShare: () {},
            onEdit: () {},
            onSave: () {},
          ),
        ),
      );
    }

    await pumpActions(isSharing: true);
    _expectOnlyActionLoading(tester, loadingKey: memoryCollageShareActionKey);
    expect(find.byTooltip("Sharing..."), findsOneWidget);
    expect(_actionOnPressed(tester, memoryCollageShareActionKey), isNull);
    expect(_actionOnPressed(tester, memoryCollageSaveActionKey), isNull);
    expect(_actionIconOpacity(tester, memoryCollageShareActionKey), 1);
    expect(_actionIconOpacity(tester, memoryCollageEditActionKey), 1);
    expect(_actionIconOpacity(tester, memoryCollageSaveActionKey), 1);

    await pumpActions(isSaving: true);
    _expectOnlyActionLoading(tester, loadingKey: memoryCollageSaveActionKey);
    expect(find.byTooltip("Saving..."), findsOneWidget);
    expect(_actionOnPressed(tester, memoryCollageShareActionKey), isNull);
    expect(_actionOnPressed(tester, memoryCollageSaveActionKey), isNull);
    expect(_actionIconOpacity(tester, memoryCollageShareActionKey), 1);
    expect(_actionIconOpacity(tester, memoryCollageEditActionKey), 1);
    expect(_actionIconOpacity(tester, memoryCollageSaveActionKey), 1);
  });
}

void _expectOnlyActionLoading(WidgetTester tester, {required Key loadingKey}) {
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  for (final key in [
    memoryCollageShareActionKey,
    memoryCollageEditActionKey,
    memoryCollageSaveActionKey,
  ]) {
    expect(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(CircularProgressIndicator),
      ),
      key == loadingKey ? findsOneWidget : findsNothing,
    );
  }
}

double _actionIconOpacity(WidgetTester tester, Key actionKey) {
  final button = _actionIconButton(tester, actionKey);
  return (button.icon as Opacity).opacity;
}

VoidCallback? _actionOnPressed(WidgetTester tester, Key actionKey) {
  return _actionIconButton(tester, actionKey).onPressed;
}

IconButton _actionIconButton(WidgetTester tester, Key actionKey) {
  return tester.widget<IconButton>(
    find.descendant(
      of: find.byKey(actionKey),
      matching: find.byType(IconButton),
    ),
  );
}

void _expectTapEffect(
  WidgetTester tester,
  Key actionKey, {
  required bool isVisible,
}) {
  final button = _actionIconButton(tester, actionKey);
  expect(
    button.style?.splashFactory,
    isVisible ? isNull : NoSplash.splashFactory,
  );
  expect(
    button.style?.overlayColor?.resolve({WidgetState.pressed}),
    isVisible ? isNot(Colors.transparent) : Colors.transparent,
  );
}

Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [child]),
    ),
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
