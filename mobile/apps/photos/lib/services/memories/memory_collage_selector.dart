import "dart:convert";

import "package:crypto/crypto.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/utils/image_util.dart";

class MemoryCollageSelector {
  static const photoCount = 7;

  const MemoryCollageSelector._();

  static bool isSupportedPhotoCount(int candidateCount) =>
      candidateCount == photoCount;

  /// Returns the photo-capable files selected for a memory.
  ///
  /// Selection is deterministic for the same memory and shuffle revision. It
  /// is independent of the source iterable's order and never mutates it. Seven
  /// files are returned whenever at least seven are eligible. An empty list
  /// means there are fewer than seven uniquely identifiable photos.
  static List<EnteFile> select({
    required String memoryID,
    required int shuffleRevision,
    required Iterable<EnteFile> files,
  }) {
    final eligibleByKey = <String, EnteFile>{};
    for (final file in files) {
      if (!_isPhotoCapable(file)) continue;
      final key = stableFileKey(file);
      if (key != null) eligibleByKey.putIfAbsent(key, () => file);
    }
    if (eligibleByKey.length < photoCount) return const [];

    final ranked = <_RankedFile>[
      for (final entry in eligibleByKey.entries)
        _RankedFile(
          file: entry.value,
          key: entry.key,
          digest: sha256
              .convert(utf8.encode("$memoryID:$shuffleRevision:${entry.key}"))
              .bytes,
        ),
    ]..sort(_compareRankedFiles);

    return List.unmodifiable(
      ranked.take(photoCount).map((entry) => entry.file),
    );
  }

  static List<EnteFile> eligibleFiles(Iterable<EnteFile> files) {
    return List.unmodifiable(files.where(_isPhotoCapable));
  }

  /// Returns the strongest stable identity available for [file].
  static String? stableFileKey(EnteFile file) {
    final uploadedFileID = file.uploadedFileID;
    if (uploadedFileID != null) return "uploaded:$uploadedFileID";

    final generatedID = file.generatedID;
    if (generatedID != null) return "generated:$generatedID";

    final localID = file.localID;
    if (localID != null && localID.isNotEmpty) return "local:$localID";

    return null;
  }

  static bool _isPhotoCapable(EnteFile file) {
    final isPhoto =
        file.fileType == FileType.image || file.fileType == FileType.livePhoto;
    if (!isPhoto) return false;
    final filename = file.title ?? "";
    final extension = filename.contains(".") ? filename.split(".").last : "";
    // The viewer can only show a thumbnail fallback for RAW originals, so
    // they cannot satisfy the editor's full-image export readiness contract.
    return !isRawImageExtension(extension);
  }

  static int _compareRankedFiles(_RankedFile left, _RankedFile right) {
    for (var index = 0; index < left.digest.length; index++) {
      final byteOrder = left.digest[index].compareTo(right.digest[index]);
      if (byteOrder != 0) return byteOrder;
    }
    return left.key.compareTo(right.key);
  }
}

class _RankedFile {
  final EnteFile file;
  final String key;
  final List<int> digest;

  const _RankedFile({
    required this.file,
    required this.key,
    required this.digest,
  });
}
