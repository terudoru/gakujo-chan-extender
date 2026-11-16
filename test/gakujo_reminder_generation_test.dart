import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final outcome in [
    'unreadable assignments',
    'permission refused',
    'assignment read failed',
    'rebooked',
  ]) {
    test('booked in-app reminder after a sync: $outcome', () async {
      var now = DateTime.utc(2099, 7, 1, 8);
      final store = _ControlledAssignmentStore();
      final service = _ReminderNotificationService();
      final coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
        now: () => now,
      );
      await store.mergeAssignments([
        GakujoAssignment(
          kind: 'レポート',
          title: '課題',
          course: '科目',
          status: '未提出',
          dueAt: now.add(const Duration(hours: 2)),
          capturedAt: now,
        ),
      ]);
      Future<void> sync() => coordinator.syncReminders(
        notificationsEnabled: true,
        topics: {GakujoNotificationTopic.coursework},
        preferences: const GakujoNotificationPreferences(
          reminderOffsets: {GakujoReminderOffset.oneHour},
        ),
      );

      await sync();
      final reminder = service.bookings.single.single;
      final previousCallback = service.onInAppReminder!;
      if (outcome == 'unreadable assignments') {
        store.onLoadAssignments = () async => null;
      } else if (outcome == 'permission refused') {
        service.onRequestPermission = () async => false;
      } else if (outcome == 'assignment read failed') {
        store.onLoadAssignments = () async => throw StateError('read failed');
      }
      if (outcome == 'assignment read failed') {
        await expectLater(sync(), throwsStateError);
      } else {
        await sync();
      }

      store.onLoadAssignments = null;
      service.onRequestPermission = null;
      now = reminder.at;
      await previousCallback(reminder);
      if (outcome == 'rebooked') {
        expect(service.bookings, hasLength(2));
        expect(service.notifiedReminders, isEmpty);
        await service.onInAppReminder!(service.bookings.last.single);
      } else {
        expect(service.bookings, hasLength(1));
      }
      expect(service.notifiedReminders.map((entry) => entry.toJson()), [
        reminder.toJson(),
      ]);
      expect(await store.loadNotifiedDeadlineKeys(), hasLength(1));
    });
  }

  test(
    'in-app callbacks wait for all queued syncs that preserve bookings',
    () async {
      var now = DateTime.utc(2099, 7, 1, 8);
      final store = _ControlledAssignmentStore();
      final service = _ReminderNotificationService();
      final coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
        now: () => now,
      );
      await store.mergeAssignments([
        GakujoAssignment(
          kind: 'レポート',
          title: '課題',
          course: '科目',
          status: '未提出',
          dueAt: now.add(const Duration(hours: 2)),
          capturedAt: now,
        ),
      ]);
      Future<void> sync() => coordinator.syncReminders(
        notificationsEnabled: true,
        topics: {GakujoNotificationTopic.coursework},
        preferences: const GakujoNotificationPreferences(
          reminderOffsets: {GakujoReminderOffset.oneHour},
        ),
      );

      await sync();
      final reminder = service.bookings.single.single;
      final callback = service.onInAppReminder!;
      final readStarted = Completer<void>();
      final read = Completer<List<GakujoAssignment>?>();
      store.onLoadAssignments = () {
        readStarted.complete();
        return read.future;
      };
      final firstSync = sync();
      await readStarted.future;
      now = reminder.at;
      final queuedReminder = callback(reminder);
      final secondSync = sync();
      store.onLoadAssignments = () async => null;
      read.complete(null);
      await firstSync;
      await queuedReminder;
      expect(service.notifiedReminders, isEmpty);
      await secondSync;
      expect(service.bookings, hasLength(1));

      store.onLoadAssignments = null;
      await callback(reminder);
      expect(service.notifiedReminders, [reminder]);
    },
  );
}

class _ControlledAssignmentStore extends GakujoActivityStore {
  Future<List<GakujoAssignment>?> Function()? onLoadAssignments;

  @override
  Future<List<GakujoAssignment>?> loadAssignmentsIfAvailable() =>
      onLoadAssignments?.call() ?? super.loadAssignmentsIfAvailable();
}

class _ReminderNotificationService extends GakujoNotificationService {
  final List<GakujoReminder> notifiedReminders = [];
  final List<List<GakujoReminder>> bookings = [];
  Future<bool> Function()? onRequestPermission;
  Future<void> Function(GakujoReminder)? onInAppReminder;

  @override
  Future<bool> requestPermission() async =>
      await onRequestPermission?.call() ?? true;

  @override
  Future<bool> scheduleReminders(
    List<GakujoReminder> reminders, {
    Future<void> Function(GakujoReminder)? onInAppReminder,
  }) async {
    bookings.add(reminders);
    this.onInAppReminder = onInAppReminder;
    return false;
  }

  @override
  Future<bool> notifyReminder(GakujoReminder reminder) async {
    notifiedReminders.add(reminder);
    return true;
  }
}
