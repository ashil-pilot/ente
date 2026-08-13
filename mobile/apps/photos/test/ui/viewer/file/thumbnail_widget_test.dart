import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:image/image.dart" as img;
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      prefs,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
  });

  setUp(ThumbnailInMemoryLruCache.clearAll);

  testWidgets("notifies once after a cached thumbnail is decoded", (
    tester,
  ) async {
    final file = _remoteFile(1);
    ThumbnailInMemoryLruCache.put(file, _testPng);
    var notifications = 0;

    await tester.pumpWidget(
      _testApp(
        ThumbnailWidget(
          file,
          rawThumbnail: true,
          onThumbnailLoaded: () {
            notifications++;
          },
        ),
      ),
    );
    await _pumpUntil(tester, () => notifications == 1);

    expect(notifications, 1);

    await tester.pump();
    await tester.pump();
    expect(notifications, 1);

    await _disposeThumbnail(tester);
  });

  testWidgets("resets the notification when the displayed file changes", (
    tester,
  ) async {
    final firstFile = _remoteFile(1);
    final secondFile = _remoteFile(2);
    ThumbnailInMemoryLruCache.put(firstFile, _testPng);
    ThumbnailInMemoryLruCache.put(secondFile, _testPng);
    var currentFile = firstFile;
    var notifications = 0;
    late StateSetter update;

    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ThumbnailWidget(
              currentFile,
              key: const ValueKey("stable-thumbnail"),
              rawThumbnail: true,
              onThumbnailLoaded: () {
                notifications++;
              },
            );
          },
        ),
      ),
    );
    await _pumpUntil(tester, () => notifications == 1);
    expect(notifications, 1);

    update(() => currentFile = secondFile);
    await tester.pump();
    await _pumpUntil(tester, () => notifications == 2);

    expect(notifications, 2);
    await tester.pump();
    expect(notifications, 2);

    await _disposeThumbnail(tester);
  });

  testWidgets("notifies a callback added after the thumbnail was decoded", (
    tester,
  ) async {
    final file = _remoteFile(1);
    ThumbnailInMemoryLruCache.put(file, _testPng);
    var listen = false;
    var notifications = 0;
    late StateSetter update;

    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ThumbnailWidget(
              file,
              key: const ValueKey("stable-thumbnail"),
              rawThumbnail: true,
              onThumbnailLoaded: listen ? () => notifications++ : null,
            );
          },
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          find.byType(RawImage).evaluate().isNotEmpty &&
          tester.widget<RawImage>(find.byType(RawImage)).image != null,
    );
    expect(notifications, 0);

    update(() => listen = true);
    await tester.pump();
    await tester.pump();

    expect(notifications, 1);

    await _disposeThumbnail(tester);
  });
}

EnteFile _remoteFile(int id) {
  return EnteFile()
    ..generatedID = id
    ..uploadedFileID = id
    ..fileType = FileType.image;
}

Widget _testApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox.square(dimension: 100, child: child)),
  );
}

Future<void> _disposeThumbnail(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 11));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(condition(), isTrue);
}

final _testPng = Uint8List.fromList(
  img.encodePng(img.Image(width: 2, height: 2)),
);
