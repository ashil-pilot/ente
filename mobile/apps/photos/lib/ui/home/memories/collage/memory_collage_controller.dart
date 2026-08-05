import "package:flutter/foundation.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/memories/memory_collage_selector.dart";

typedef MemoryCollageSelection =
    List<EnteFile> Function({
      required String memoryID,
      required int shuffleRevision,
      required Iterable<EnteFile> files,
    });

/// Transient state for a single memory's collage editor.
///
/// A new controller starts at shuffle revision zero and the first background.
/// Neither value is persisted after the editor is closed.
class MemoryCollageController extends ChangeNotifier {
  static const int requiredPhotoCount = 6;

  static const List<String> defaultBackgroundIDs = [
    "paper-washi",
    "paper-cream-fiber",
    "paper-blush-stripe",
    "paper-sage-stripe",
    "paper-terracotta-mottle",
  ];

  final String memoryID;
  final MemoryCollageSelection _selector;
  final List<EnteFile> _sourceFiles;
  final List<String> _backgroundIDs;

  late List<EnteFile> _selectedFiles;
  int _shuffleRevision = 0;
  int _backgroundIndex = 0;

  MemoryCollageController({
    required this.memoryID,
    required Iterable<EnteFile> files,
    List<String> backgroundIDs = defaultBackgroundIDs,
    MemoryCollageSelection? selector,
  }) : _sourceFiles = List<EnteFile>.unmodifiable(files),
       _backgroundIDs = List<String>.unmodifiable(backgroundIDs),
       _selector = selector ?? MemoryCollageSelector.select {
    if (_backgroundIDs.isEmpty) {
      throw ArgumentError.value(
        backgroundIDs,
        "backgroundIDs",
        "must contain at least one background",
      );
    }
    _selectedFiles = _selectFiles();
  }

  List<EnteFile> get selectedFiles => _selectedFiles;

  List<String> get backgroundIDs => _backgroundIDs;

  bool get canCreate => _selectedFiles.length == requiredPhotoCount;

  int get shuffleRevision => _shuffleRevision;

  int get backgroundIndex => _backgroundIndex;

  String get backgroundAssetID => _backgroundIDs[_backgroundIndex];

  void shuffle() {
    _shuffleRevision++;
    _selectedFiles = _selectFiles();
    notifyListeners();
  }

  void nextBackground() {
    if (_backgroundIDs.length == 1) return;
    _backgroundIndex = (_backgroundIndex + 1) % _backgroundIDs.length;
    notifyListeners();
  }

  List<EnteFile> _selectFiles() {
    return List<EnteFile>.unmodifiable(
      _selector(
        memoryID: memoryID,
        shuffleRevision: _shuffleRevision,
        files: _sourceFiles,
      ),
    );
  }
}
