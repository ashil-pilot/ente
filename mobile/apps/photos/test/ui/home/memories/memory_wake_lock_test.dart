import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/home/memories/memory_wake_lock.dart";
import "package:wakelock_plus/wakelock_plus.dart";
// ignore: depend_on_referenced_packages
import "package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart";

void main() {
  late EnteWakeLockService service;
  late _WakeLockPlatform platform;

  setUp(() {
    final previousPlatform = wakelockPlusPlatformInstance;
    platform = _WakeLockPlatform();
    wakelockPlusPlatformInstance = platform;
    service = EnteWakeLockService();
    addTearDown(() => wakelockPlusPlatformInstance = previousPlatform);
  });

  test("overlapping video owners release only their own requests", () {
    final firstVideo = Object();
    final secondVideo = Object();
    for (final owner in [firstVideo, firstVideo, secondVideo]) {
      service.updateWakeLock(
        enable: true,
        wakeLockFor: WakeLockFor.videoPlayback,
        owner: owner,
      );
    }
    for (final owner in [firstVideo, firstVideo]) {
      service.updateWakeLock(
        enable: false,
        wakeLockFor: WakeLockFor.videoPlayback,
        owner: owner,
      );
      expect(platform.isEnabled, isTrue);
    }
    service.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.videoPlayback,
      owner: secondVideo,
    );
    expect(platform.isEnabled, isFalse);
  });

  testWidgets("memory wake lock follows navigation and survives video exit", (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final memoryRoute = MaterialPageRoute<void>(
      builder: (_) => MemoryWakeLock(service: service, child: const SizedBox()),
    );
    navigator.currentState!.push(memoryRoute);
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isTrue);

    service.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.videoPlayback,
    );
    for (var release = 0; release < 2; release++) {
      service.updateWakeLock(
        enable: false,
        wakeLockFor: WakeLockFor.videoPlayback,
      );
      expect(platform.isEnabled, isTrue);
    }

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isTrue);

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MemoryWakeLock(service: service, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isTrue);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isFalse);
  });

  testWidgets("backgrounding releases the lock and returning restores it", (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryWakeLock(service: service, child: const SizedBox()),
      ),
    );
    expect(platform.isEnabled, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isTrue);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      expect(platform.isEnabled, isFalse);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.isEnabled, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(platform.isEnabled, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(platform.isEnabled, isFalse);
  });
}

class _WakeLockPlatform extends WakelockPlusPlatformInterface {
  bool isEnabled = false;

  @override
  Future<void> toggle({required bool enable}) async {
    isEnabled = enable;
  }

  @override
  Future<bool> get enabled async => isEnabled;
}
