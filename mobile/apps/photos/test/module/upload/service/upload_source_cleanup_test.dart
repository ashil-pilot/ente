import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photos/module/upload/service/upload_source_cleanup.dart';

void main() {
  late Directory directory;
  late File source;
  const originalBytes = [1, 2, 3, 4];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('upload-source-');
    source = await File('${directory.path}/source').writeAsBytes(originalBytes);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  for (final isLivePhoto in [false, true]) {
    test(
      'iOS shared source survives hard failure (live: $isLivePhoto)',
      () async {
        await cleanupUploadSource(
          source,
          isIOS: true,
          isSharedMedia: true,
          isLivePhoto: isLivePhoto,
          uploadCompleted: false,
          uploadHardFailure: true,
        );

        expect(await source.readAsBytes(), originalBytes);

        await cleanupUploadSource(
          source,
          isIOS: true,
          isSharedMedia: true,
          isLivePhoto: isLivePhoto,
          uploadCompleted: true,
          uploadHardFailure: false,
        );

        expect(await source.exists(), isFalse);
      },
    );
  }

  test('iOS library export is reclaimed after a hard failure', () async {
    await cleanupUploadSource(
      source,
      isIOS: true,
      isSharedMedia: false,
      isLivePhoto: false,
      uploadCompleted: false,
      uploadHardFailure: true,
    );

    expect(await source.exists(), isFalse);
  });

  test(
    'iOS rejected shared import is reclaimed after its entry is removed',
    () async {
      await cleanupUploadSource(
        source,
        isIOS: true,
        isSharedMedia: true,
        isLivePhoto: false,
        uploadCompleted: false,
        uploadHardFailure: true,
        uploadInvalidFile: true,
      );

      expect(await source.exists(), isFalse);
    },
  );

  test('iOS generated Live Photo archive is reclaimed before retry', () async {
    await cleanupUploadSource(
      source,
      isIOS: true,
      isSharedMedia: false,
      isLivePhoto: true,
      uploadCompleted: false,
      uploadHardFailure: false,
    );

    expect(await source.exists(), isFalse);
  });

  test(
    'Android deletes successful shared imports but keeps library originals',
    () async {
      for (final uploadCompleted in [false, true]) {
        await cleanupUploadSource(
          source,
          isIOS: false,
          isSharedMedia: false,
          isLivePhoto: false,
          uploadCompleted: uploadCompleted,
          uploadHardFailure: !uploadCompleted,
        );
        expect(await source.readAsBytes(), originalBytes);
      }

      await cleanupUploadSource(
        source,
        isIOS: false,
        isSharedMedia: true,
        isLivePhoto: false,
        uploadCompleted: true,
        uploadHardFailure: false,
      );

      expect(await source.exists(), isFalse);
    },
  );
}
