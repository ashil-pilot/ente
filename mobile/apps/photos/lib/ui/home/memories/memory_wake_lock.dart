import "package:flutter/widgets.dart";
import "package:photos/services/wake_lock_service.dart";

class MemoryWakeLock extends StatefulWidget {
  final EnteWakeLockService service;
  final Widget child;

  const MemoryWakeLock({required this.service, required this.child, super.key});

  @override
  State<MemoryWakeLock> createState() => _MemoryWakeLockState();
}

class _MemoryWakeLockState extends State<MemoryWakeLock>
    with WidgetsBindingObserver {
  bool _isRouteCurrent = false;
  late bool _isForeground;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isRouteCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _updateWakeLock();
  }

  @override
  void didUpdateWidget(covariant MemoryWakeLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.updateWakeLock(
        enable: false,
        wakeLockFor: WakeLockFor.memoryViewer,
        owner: this,
      );
      _updateWakeLock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    _updateWakeLock();
  }

  void _updateWakeLock() {
    widget.service.updateWakeLock(
      enable: _isForeground && _isRouteCurrent,
      wakeLockFor: WakeLockFor.memoryViewer,
      owner: this,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.service.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.memoryViewer,
      owner: this,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
