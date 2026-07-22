import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'allowed_web_origins.dart';
import 'gakujo_activity_store.dart';

typedef DeadlineNotificationTappedCallback = FutureOr<void> Function(
  String url,
);

@visibleForTesting
String? deadlineNotificationTargetUrl(
  String? url, {
  required bool debugAllowed,
}) {
  final normalized = url?.trim();
  if (!AllowedWebOrigins.canLoad(
    normalized,
    debugAllowed: debugAllowed,
  )) {
    return null;
  }
  return normalized;
}

class GakujoNotificationService {
  GakujoNotificationService();

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );

  DeadlineNotificationTappedCallback? _deadlineNotificationTapped;

  String? targetUrl(String? url, {required bool debugAllowed}) {
    return deadlineNotificationTargetUrl(
      url,
      debugAllowed: debugAllowed,
    );
  }

  void setDeadlineNotificationTappedHandler(
    DeadlineNotificationTappedCallback? handler,
  ) {
    _deadlineNotificationTapped = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleMethodCall);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'deadlineNotificationTapped') {
      throw MissingPluginException(
          'Unknown notification method ${call.method}');
    }
    final arguments = call.arguments;
    final url = arguments is Map ? arguments['url'] : arguments;
    final normalized = url is String ? url.trim() : '';
    final handler = _deadlineNotificationTapped;
    if (normalized.isEmpty || handler == null) {
      return false;
    }
    await handler(normalized);
    return true;
  }

  Future<String?> takePendingNotificationUrl() async {
    try {
      final url = await _channel.invokeMethod<String>(
        'takePendingNotificationUrl',
      );
      final normalized = url?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

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
  Future<void> _pendingNotificationOperation = Future<void>.value();

  Future<void> notifyPendingDeadlines({
    required bool notificationsEnabled,
  }) {
    return _enqueueNotificationOperation(
      () => _notifyPendingDeadlines(
        notificationsEnabled: notificationsEnabled,
      ),
    );
  }

  Future<void> _notifyPendingDeadlines({
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

  Future<T> _enqueueNotificationOperation<T>(
    Future<T> Function() operation,
  ) {
    final next = _pendingNotificationOperation.then((_) => operation());
    _pendingNotificationOperation = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }
}
