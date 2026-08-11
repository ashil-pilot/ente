import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/home/memories/collage/memory_collage_end_card.dart";
import "package:photos/ui/home/memories/memory_viewer_chrome.dart";

void main() {
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
  });

  testWidgets("keeps edit available while collage export is getting ready", (
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
    expect(
      _actionIconOpacity(tester, memoryCollageShareActionKey),
      memoryViewerDisabledActionOpacity,
    );
    expect(_actionIconOpacity(tester, memoryCollageEditActionKey), 1);
    expect(
      _actionIconOpacity(tester, memoryCollageSaveActionKey),
      memoryViewerDisabledActionOpacity,
    );
    await tester.tap(find.byKey(memoryCollageShareActionKey));
    await tester.tap(find.byKey(memoryCollageEditActionKey));
    await tester.tap(find.byKey(memoryCollageSaveActionKey));
    expect((shareTaps, editTaps, saveTaps), (0, 1, 0));
  });
}

double _actionIconOpacity(WidgetTester tester, Key actionKey) {
  final button = tester.widget<IconButton>(
    find.descendant(
      of: find.byKey(actionKey),
      matching: find.byType(IconButton),
    ),
  );
  return (button.icon as Opacity).opacity;
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
