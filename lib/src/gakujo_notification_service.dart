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

class GakujoDeadlineNotificationCoordinator {
  GakujoDeadlineNotificationCoordinator({
    required GakujoActivityStore activityStore,
    required GakujoNotificationService notificationService,
  })  : _activityStore = activityStore,
        _notificationService = notificationService;

  final GakujoActivityStore _activityStore;
  final GakujoNotificationService _notificationService;

  Future<void> notifyPendingDeadlines({
    required bool notificationsEnabled,
  }) async {
    if (!notificationsEnabled) {
      return;
    }
    final deadlines = await _activityStore.loadDeadlines();
    final notifiedKeys = await _activityStore.loadNotifiedDeadlineKeys();
    final pendingDeadlines = deadlines
        .where((entry) => entry.isDeadline)
        .where((entry) => !notifiedKeys.contains(entry.key))
        .take(5)
        .toList();
    if (pendingDeadlines.isEmpty) {
      return;
    }
    if (!await _notificationService.requestPermission()) {
      return;
    }
    final notifiedNow = <String>[];
    for (final entry in pendingDeadlines) {
      if (await _notificationService.notifyDeadline(entry)) {
        notifiedNow.add(entry.key);
      }
    }
    await _activityStore.addNotifiedDeadlineKeys(notifiedNow);
  }
}
