import "package:wakelock_plus/wakelock_plus.dart";

enum WakeLockFor {
  videoPlayback,
  externalVideoPlayback,
  machineLearningSettingsScreen,
  rewindViewer,
  largeBackupStandbyScreen,
  albumSlideshow,
  mlProgressBanner,
  memoryViewer,
}

class EnteWakeLockService {
  final Set<(WakeLockFor, Object?)> _activeWakeLocks = {};

  void updateWakeLock({
    required bool enable,
    required WakeLockFor wakeLockFor,
    Object? owner,
  }) {
    final request = (wakeLockFor, owner);
    if (enable) {
      _activeWakeLocks.add(request);
    } else {
      _activeWakeLocks.remove(request);
    }
    WakelockPlus.toggle(enable: _activeWakeLocks.isNotEmpty);
  }
}
