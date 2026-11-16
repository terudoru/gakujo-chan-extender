import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';

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
      expect(service.notifiedReminders, [reminder]);

      store.onLoadAssignments = null;
      await callback(reminder);
      expect(service.notifiedReminders, [reminder]);
    },
  );

  for (final replacesBookings in [false, true]) {
    testWidgets(
      'one-shot reminder after queued syncs replace bookings: $replacesBookings',
      (tester) async {
        const channel = MethodChannel(
          'net.yoshida.morebettergakujo/notifications',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => false);
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        var now = DateTime.utc(2099, 7, 1, 8);
        final store = _ControlledAssignmentStore();
        final service = _ReminderNotificationService(
          now: () => now,
          useRealTimers: true,
        );
        addTearDown(() => service.scheduleReminders(const []));
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
            dueAt: now.add(const Duration(hours: 1, seconds: 1)),
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
        final readStarted = Completer<void>();
        final read = Completer<List<GakujoAssignment>?>();
        store.onLoadAssignments = () {
          readStarted.complete();
          return read.future;
        };
        final firstSync = sync();
        await readStarted.future;
        now = reminder.at;
        // Fire the one-shot timer before the periodic one-minute check can run.
        await tester.pump(const Duration(seconds: 1));
        final secondSync = sync();
        final secondReadStarted = Completer<void>();
        final secondRead = Completer<List<GakujoAssignment>?>();
        store.onLoadAssignments = () {
          secondReadStarted.complete();
          return secondRead.future;
        };
        read.complete(null);
        await firstSync;
        await secondReadStarted.future;
        expect(service.notifiedReminders, isEmpty);

        store.onLoadAssignments = () async => null;
        secondRead.complete(replacesBookings ? const [] : null);
        await secondSync;
        expect(service.bookings, hasLength(replacesBookings ? 2 : 1));
        final expected = replacesBookings ? <GakujoReminder>[] : [reminder];
        expect(service.notifiedReminders, expected);
        await tester.pump(const Duration(minutes: 2));
        await sync();
        expect(service.notifiedReminders, expected);
        expect(
          await store.loadNotifiedDeadlineKeys(),
          hasLength(replacesBookings ? 0 : 1),
        );
      },
    );
  }
}

class _ControlledAssignmentStore extends GakujoActivityStore {
  Future<List<GakujoAssignment>?> Function()? onLoadAssignments;

  @override
  Future<List<GakujoAssignment>?> loadAssignmentsIfAvailable() =>
      onLoadAssignments?.call() ?? super.loadAssignmentsIfAvailable();
}

class _ReminderNotificationService extends GakujoNotificationService {
  _ReminderNotificationService({super.now, this.useRealTimers = false});

  final bool useRealTimers;
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
    if (useRealTimers) {
      return super.scheduleReminders(
        reminders,
        onInAppReminder: onInAppReminder,
      );
    }
    return false;
  }

  @override
  Future<bool> notifyReminder(GakujoReminder reminder) async {
    notifiedReminders.add(reminder);
    return true;
  }
}
