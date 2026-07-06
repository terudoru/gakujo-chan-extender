import 'package:flutter/services.dart';

import 'gakujo_activity_store.dart';

class GakujoNotificationService {
  const GakujoNotificationService();

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );

  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'notifyDeadline',
        {
          'title': entry.title,
          'body': entry.dueText,
          'url': entry.url,
        },
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
