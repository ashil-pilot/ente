import 'package:photos/events/files_updated_event.dart';

class LocalPhotosUpdatedEvent extends FilesUpdatedEvent {
  final bool hasRecentNewLocalDiscovery;
  final bool requiresGalleryForceReload;

  LocalPhotosUpdatedEvent(
    super.updatedFiles, {
    type,
    required source,
    this.hasRecentNewLocalDiscovery = false,
    this.requiresGalleryForceReload = false,
  }) : super(type: type ?? EventType.addedOrUpdated, source: source ?? "");
}

class LocalPhotosAddedEvent extends LocalPhotosUpdatedEvent {
  LocalPhotosAddedEvent(
    super.updatedFiles, {
    required super.source,
    required super.hasRecentNewLocalDiscovery,
  });
}
