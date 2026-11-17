import 'package:flutter/services.dart';

class LinuxSessionSettings {
  static const message = '設定は今回の起動中だけ使えます。保存するにはキーリングのロックを解除してください。';

  bool _noticeShown = false;

  Future<bool> save(
    Future<void> Function() save, {
    required bool storageAvailable,
    required ValueChanged<String> showSnackBar,
  }) async {
    if (storageAvailable) {
      try {
        await save();
        return true;
      } on PlatformException catch (error) {
        if (error.code != 'KeyringLocked') rethrow;
      }
    }
    showNotice(showSnackBar);
    return false;
  }

  void showNotice(ValueChanged<String> showSnackBar) {
    if (_noticeShown) return;
    _noticeShown = true;
    showSnackBar(message);
  }
}
