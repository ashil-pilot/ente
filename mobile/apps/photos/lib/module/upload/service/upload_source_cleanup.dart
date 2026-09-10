import 'dart:io';

import 'package:ente_pure_utils/ente_pure_utils.dart';

Future<void> cleanupUploadSource(
  File sourceFile, {
  required bool isIOS,
  required bool isSharedMedia,
  required bool isLivePhoto,
  required bool uploadCompleted,
  required bool uploadHardFailure,
  bool uploadInvalidFile = false,
}) async {
  // Shared imports may be the only remaining original. Library exports can be
  // recreated, and generated Live Photo archives are rebuilt on every retry.
  // Invalid-file handling removes rejected imports from the database.
  final shouldDelete = isSharedMedia && !uploadInvalidFile
      ? uploadCompleted
      : isIOS && (isLivePhoto || uploadCompleted || uploadHardFailure);
  if (shouldDelete) {
    await deleteFileSystemEntityIfPresent(sourceFile);
  }
}
