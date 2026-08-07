import "package:flutter/foundation.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory_collage_manifest.dart";
import "package:photos/services/memories/memory_collage_selector.dart";

typedef MemoryCollageSelection =
    List<EnteFile> Function({
      required String memoryID,
      required int shuffleRevision,
      required Iterable<EnteFile> files,
    });

/// Transient state for a single memory's collage editor.
///
/// A new controller starts at shuffle revision zero and the manifest's default
/// template. Template and background choices are not persisted after the
/// editor is closed.
class MemoryCollageController extends ChangeNotifier {
  final String memoryID;
  final MemoryCollageManifest manifest;
  final MemoryCollageSelection _selector;
  final List<EnteFile> _sourceFiles;
  final Map<String, int> _backgroundIndexByTemplate = {};

  late List<EnteFile> _selectedFiles;
  late String _templateID;
  int _shuffleRevision = 0;

  MemoryCollageController({
    required this.memoryID,
    required Iterable<EnteFile> files,
    required this.manifest,
    String? templateID,
    MemoryCollageSelection? selector,
  }) : _sourceFiles = List<EnteFile>.unmodifiable(files),
       _selector = selector ?? MemoryCollageSelector.select {
    _templateID = templateID ?? manifest.defaultTemplateID;
    _ensureBackgroundIndex(_templateID);
    _selectedFiles = _selectFiles();
  }

  List<EnteFile> get selectedFiles => _selectedFiles;

  String get templateID => _templateID;

  MemoryCollageTemplate get template => manifest.templateFor(_templateID);

  List<String> get backgroundIDs => template.background.assetIDs;

  bool get canCreate =>
      MemoryCollageSelector.isSupportedPhotoCount(_selectedFiles.length);

  int get shuffleRevision => _shuffleRevision;

  int get backgroundIndex => _ensureBackgroundIndex(_templateID);

  String get backgroundAssetID => backgroundAssetIDForTemplate(_templateID);

  String backgroundAssetIDForTemplate(String templateID) {
    final template = manifest.templateFor(templateID);
    return template.background.assetIDs[_ensureBackgroundIndex(templateID)];
  }

  void shuffle() {
    _shuffleRevision++;
    _selectedFiles = _selectFiles();
    notifyListeners();
  }

  void nextBackground() {
    final backgrounds = backgroundIDs;
    if (backgrounds.length == 1) return;
    _backgroundIndexByTemplate[_templateID] =
        (backgroundIndex + 1) % backgrounds.length;
    notifyListeners();
  }

  void selectTemplate(String templateID) {
    manifest.templateFor(templateID);
    if (_templateID == templateID) return;
    _ensureBackgroundIndex(templateID);
    _templateID = templateID;
    notifyListeners();
  }

  int _ensureBackgroundIndex(String templateID) {
    return _backgroundIndexByTemplate.putIfAbsent(templateID, () {
      final background = manifest.templateFor(templateID).background;
      final defaultIndex = background.assetIDs.indexOf(
        background.defaultAssetID,
      );
      if (defaultIndex < 0) {
        throw StateError(
          "Template $templateID does not contain its default background",
        );
      }
      return defaultIndex;
    });
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
