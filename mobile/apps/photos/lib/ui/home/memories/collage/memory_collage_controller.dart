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

  late List<EnteFile> _selectedFiles;
  late String _templateID;
  late String _backgroundAssetID;
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
    _backgroundAssetID = manifest
        .templateFor(_templateID)
        .background
        .defaultAssetID;
    _selectedFiles = _selectFiles();
  }

  List<EnteFile> get selectedFiles => _selectedFiles;

  String get templateID => _templateID;

  String get nextTemplateID {
    final templates = manifest.templates;
    if (templates.length == 1) return _templateID;
    final currentIndex = templates.indexWhere(
      (template) => template.id == _templateID,
    );
    if (currentIndex < 0) {
      throw StateError("Active template is missing from the manifest");
    }
    return templates[(currentIndex + 1) % templates.length].id;
  }

  MemoryCollageTemplate get template => manifest.templateFor(_templateID);

  List<String> get backgroundIDs => template.background.assetIDs;

  bool get canCreate =>
      MemoryCollageSelector.isSupportedPhotoCount(_selectedFiles.length);

  int get shuffleRevision => _shuffleRevision;

  int get backgroundIndex => backgroundIDs.indexOf(_backgroundAssetID);

  String get backgroundAssetID => _backgroundAssetID;

  String backgroundAssetIDForTemplate(String templateID) {
    final background = manifest.templateFor(templateID).background;
    return background.assetIDs.contains(_backgroundAssetID)
        ? _backgroundAssetID
        : background.defaultAssetID;
  }

  void shuffle() {
    _shuffleRevision++;
    _selectedFiles = _selectFiles();
    notifyListeners();
  }

  void nextBackground() {
    final backgrounds = backgroundIDs;
    if (backgrounds.length == 1) return;
    _backgroundAssetID =
        backgrounds[(backgroundIndex + 1) % backgrounds.length];
    notifyListeners();
  }

  void selectTemplate(String templateID) {
    manifest.templateFor(templateID);
    if (_templateID == templateID) return;
    final backgroundAssetID = backgroundAssetIDForTemplate(templateID);
    _templateID = templateID;
    _backgroundAssetID = backgroundAssetID;
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
