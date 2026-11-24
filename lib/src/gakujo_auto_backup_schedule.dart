import 'dart:async';

import 'gakujo_automation_settings.dart';

/// Keeps launch and settled-settings backups while replacing periodic timers.
class GakujoAutoBackupSchedule {
  GakujoAutoBackupSchedule({required this.onBackup});
  final void Function() onBackup;
  Timer? _periodic;
  Timer? _debounce;
  bool _writtenThisLaunch = false;
  bool _disposed = false;

  void schedule({
    required bool enabled,
    required GakujoAutoBackupSettings settings,
  }) {
    if (_disposed) return;
    _periodic?.cancel();
    _debounce?.cancel();
    if (!enabled) return;
    _periodic = Timer.periodic(settings.interval, (_) => onBackup());
    if (!_writtenThisLaunch) {
      _writtenThisLaunch = true;
      onBackup();
      return;
    }
    _debounce = Timer(const Duration(minutes: 1), onBackup);
  }

  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _debounce?.cancel();
  }
}
