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

  for (final change in [
    'empty topics',
    'other only',
    'coursework retained',
    'survey retained',
    'readable clear',
    'offsets off',
    'notifications off',
  ]) {
    test('existing OS booking after topic selection: $change', () async {
      const channel = MethodChannel(
        'net.yoshida.morebettergakujo/notifications',
      );
      final now = DateTime.utc(2099, 7, 1, 8);
      final storage = _BookingSecureStorage();
      final store = GakujoActivityStore(secureStorage: storage);
      final survey = change == 'survey retained';
      final topic = survey
          ? GakujoNotificationTopic.survey
          : GakujoNotificationTopic.coursework;
      await store.mergeAssignments([
        GakujoAssignment(
          kind: survey ? 'アンケート' : 'レポート',
          title: '課題',
          course: '科目',
          status: '未提出',
          dueAt: now.add(const Duration(hours: 2)),
          capturedAt: now,
        ),
      ]);
      storage.assignmentReads = 0;
      var granted = true;
      var pending = <Map<Object?, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestPermission' ||
            call.method == 'checkPermission') {
          return granted;
        }
        if (call.method == 'scheduleReminders') {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          pending = [
            for (final item in args['reminders'] as List)
              Map<Object?, Object?>.from(item as Map),
          ];
          return true;
        }
        throw StateError('Unexpected notification call: ${call.method}');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: GakujoNotificationService(now: () => now),
        now: () => now,
      );
      const preferences = GakujoNotificationPreferences(
        reminderOffsets: {GakujoReminderOffset.oneHour},
      );
      await coordinator.syncReminders(
        notificationsEnabled: true,
        topics: {topic},
        preferences: preferences,
      );
      expect(pending, hasLength(1));
      final original = List<Map<Object?, Object?>>.of(pending);
      // The booking has completed. No earlier request is waiting in the queue.
      storage.failLaterAssignmentReads = change != 'readable clear';
      granted = false;
      final retained = change.endsWith('retained');
      await coordinator.syncReminders(
        notificationsEnabled: change != 'notifications off',
        topics: {
          if (retained) topic,
          if (change == 'other only') GakujoNotificationTopic.other,
        },
        preferences: preferences.copyWith(reminderOffsets: {
          if (change != 'offsets off') GakujoReminderOffset.oneHour,
        }),
        allowPermissionRequest: false,
      );
      expect(pending, retained ? equals(original) : isEmpty);
      expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
    });
  }

  for (final boundary in ['assignment read', 'history read', 'permission']) {
    for (final change in [
      'unchanged',
      'topic off',
      'skip submitted',
      'different offset',
      'notifications off',
      'offsets off',
      if (boundary == 'history read') 'offsets enabled',
      if (boundary == 'history read') 'topics enabled',
    ]) {
      test('OS bookings use current settings after $boundary: $change', () async {
        const channel = MethodChannel(
          'net.yoshida.morebettergakujo/notifications',
        );
        final now = DateTime.utc(2099, 7, 1, 8);
        final storage = _BookingSecureStorage();
        final store = GakujoActivityStore(secureStorage: storage);
        await store.mergeAssignments([
          GakujoAssignment(
            kind: 'レポート',
            title: '課題',
            course: '科目',
            status: '提出済み',
            dueAt: now.add(const Duration(hours: 4)),
            capturedAt: now,
          ),
        ]);
        storage.assignmentReads = 0;
        final permissionEntered = Completer<void>();
        final permission = Completer<bool>();
        final bookings = <List<Map<Object?, Object?>>>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestPermission') {
            if (boundary == 'permission' && !permissionEntered.isCompleted) {
              permissionEntered.complete();
              return permission.future;
            }
            return true;
          }
          if (call.method == 'scheduleReminders') {
            final args = Map<Object?, Object?>.from(call.arguments as Map);
            bookings.add([
              for (final item in args['reminders'] as List)
                Map<Object?, Object?>.from(item as Map),
            ]);
            return true;
          }
          throw StateError('Unexpected notification call: ${call.method}');
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        if (boundary != 'permission') {
          storage.gatedKey = boundary == 'assignment read'
              ? 'more_better_gakujo_assignments'
              : 'more_better_gakujo_notified_deadline_keys';
        }
        final coordinator = GakujoDeadlineNotificationCoordinator(
          activityStore: store,
          notificationService: GakujoNotificationService(now: () => now),
          now: () => now,
        );
        final preferences = GakujoNotificationPreferences(
          reminderOffsets: {
            if (change != 'offsets enabled') GakujoReminderOffset.oneHour,
          },
          skipSubmitted: false,
        );
        final first = coordinator.syncReminders(
          notificationsEnabled: true,
          topics: {
            if (change != 'topics enabled') GakujoNotificationTopic.coursework,
          },
          preferences: preferences,
        );
        await (boundary == 'permission'
            ? permissionEntered.future
            : storage.readEntered.future);
        // A newer sync updates eligibility immediately. Its unreadable list
        // must preserve the first operation's valid, current-policy bookings.
        storage.failLaterAssignmentReads = true;
        final newer = coordinator.syncReminders(
          notificationsEnabled: change != 'notifications off',
          topics: {
            if (change != 'topic off') GakujoNotificationTopic.coursework,
          },
          preferences: preferences.copyWith(
            skipSubmitted: change == 'skip submitted',
            reminderOffsets: {
              if (change != 'offsets off')
                change == 'different offset'
                    ? GakujoReminderOffset.threeHours
                    : GakujoReminderOffset.oneHour,
            },
          ),
        );
        if (boundary == 'permission') {
          permission.complete(true);
        } else {
          storage.releaseRead.complete();
        }
        await first;
        await newer;
        final allowed = change == 'unchanged' ||
            change == 'different offset' || change == 'offsets enabled' ||
            change == 'topics enabled';
        expect(bookings, isNotEmpty);
        for (final booking in bookings) {
          expect(booking, hasLength(allowed ? 1 : 0));
          if (allowed) {
            expect(
              booking.single['atMillis'],
              now.add(Duration(
                hours: change == 'different offset' ? 1 : 3,
              )).millisecondsSinceEpoch,
            );
          }
        }
        expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
      });
    }
  }

  for (final change in [
    'notifications off',
    'topic off',
    'offset off',
    'skip submitted',
    'notifications on',
    'unchanged',
    'no newer sync',
  ]) {
    test('resume permission check preserves newer settings: $change', () async {
      final now = DateTime.now().toUtc();
      final store = GakujoActivityStore();
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
          status: change == 'skip submitted' ? '提出済み' : '未提出',
          dueAt: now.add(const Duration(hours: 2)),
          capturedAt: now,
        ),
      ]);
      final entered = Completer<void>();
      final permission = Completer<bool>();
      service.onCheckPermission = () {
        if (!entered.isCompleted) entered.complete();
        return permission.future;
      };
      const preferences = GakujoNotificationPreferences(
        reminderOffsets: {GakujoReminderOffset.oneHour},
        skipSubmitted: false,
      );
      final resuming = coordinator.onAppResumed(
        notificationsEnabled: change != 'notifications on',
        topics: {GakujoNotificationTopic.coursework},
        preferences: preferences,
      );
      await entered.future;
      if (change != 'no newer sync') {
        // A sync may fail before OS access is granted. Resume must still rebook
        // permitted reminders using that sync's current settings.
        service.onRequestPermission = () async => false;
        await coordinator.syncReminders(
          notificationsEnabled: change != 'notifications off',
          topics: {if (change != 'topic off') GakujoNotificationTopic.coursework},
          preferences: preferences.copyWith(
            reminderOffsets: {
              if (change != 'offset off') GakujoReminderOffset.oneHour,
            },
            skipSubmitted: change == 'skip submitted',
          ),
        );
      }
      permission.complete(true);
      await resuming;
      final expectedCount = const {
        'notifications on',
        'unchanged',
        'no newer sync',
      }.contains(change) ? 1 : 0;
      expect(service.bookings, isNotEmpty);
      expect(service.bookings.last, hasLength(expectedCount));
      expect(service.notifiedReminders, isEmpty);
      expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
    });
  }

  for (final pause in ['assignment read', 'permission prompt']) {
    for (final change in [
      'unchanged',
      'coursework off',
      'survey off',
      'offset off',
      'notifications off',
    ]) {
      test('catch-up uses latest settings after $pause: $change', () async {
        final now = DateTime.utc(2099, 7, 1, 8);
        final store = _ControlledAssignmentStore();
        final service = _ReminderNotificationService();
        final coordinator = GakujoDeadlineNotificationCoordinator(
          activityStore: store,
          notificationService: service,
          now: () => now,
        );
        final assignments = [
          GakujoAssignment(
            kind: change == 'survey off' ? 'アンケート' : 'レポート',
            title: '課題',
            course: '科目',
            status: '未提出',
            dueAt: now.add(const Duration(minutes: 30)),
            capturedAt: now,
          ),
        ];
        await store.mergeAssignments(assignments);
        final paused = Completer<void>();
        final resume = Completer<void>();
        if (pause == 'assignment read') {
          store.onLoadAssignments = () async {
            paused.complete();
            await resume.future;
            return assignments;
          };
        } else {
          service.onRequestPermission = () async {
            paused.complete();
            await resume.future;
            return true;
          };
        }
        final firstSync = coordinator.syncReminders(
          notificationsEnabled: true,
          topics: {...GakujoNotificationTopic.values},
          preferences: const GakujoNotificationPreferences(
            reminderOffsets: {GakujoReminderOffset.oneHour},
          ),
        );
        await paused.future;
        final changedSync = coordinator.syncReminders(
          notificationsEnabled: change != 'notifications off',
          topics: {
            for (final topic in GakujoNotificationTopic.values)
              if (!(change == 'coursework off' &&
                      topic == GakujoNotificationTopic.coursework) &&
                  !(change == 'survey off' &&
                      topic == GakujoNotificationTopic.survey))
                topic,
          },
          preferences: GakujoNotificationPreferences(
            reminderOffsets: {
              if (change != 'offset off') GakujoReminderOffset.oneHour,
            },
          ),
        );
        store.onLoadAssignments = null;
        service.onRequestPermission = null;
        resume.complete();
        await firstSync;
        await changedSync;

        final expectedCount = change == 'unchanged' ? 1 : 0;
        expect(service.notifiedReminders, hasLength(expectedCount));
        expect(
          await store.loadNotifiedDeadlineKeys(),
          hasLength(expectedCount),
        );
      });
    }
  }

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

  for (final deferred in [false, true]) {
    for (final change in [
      'unchanged',
      'coursework off',
      'survey off',
      'offset off',
      'notifications off',
      if (!deferred) 'skip submitted',
    ]) {
      testWidgets(
        'preserved reminder uses latest settings: $change, deferred: $deferred',
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
              kind: change == 'survey off' ? 'アンケート' : 'レポート',
              title: '課題',
              course: '科目',
              status: change == 'skip submitted' ? '提出済' : '未提出',
              dueAt: now.add(const Duration(hours: 1, seconds: 1)),
              capturedAt: now,
            ),
          ]);
          await coordinator.syncReminders(
            notificationsEnabled: true,
            topics: {...GakujoNotificationTopic.values},
            preferences: const GakujoNotificationPreferences(
              skipSubmitted: false,
              reminderOffsets: {GakujoReminderOffset.oneHour},
            ),
          );
          final reminder = service.bookings.single.single;
          final callback = service.onInAppReminder!;
          final readStarted = Completer<void>();
          final read = Completer<List<GakujoAssignment>?>();
          store.onLoadAssignments = () {
            readStarted.complete();
            return read.future;
          };
          // Queue a preserving sync ahead of the changed settings, so delivery
          // must wait for both and use the newest request.
          final preservingSync = coordinator.syncReminders(
            notificationsEnabled: true,
            topics: {...GakujoNotificationTopic.values},
            preferences: const GakujoNotificationPreferences(
              skipSubmitted: false,
              reminderOffsets: {GakujoReminderOffset.oneHour},
            ),
          );
          await readStarted.future;
          now = reminder.at;
          if (deferred) {
            await tester.pump(const Duration(seconds: 1));
          }
          final changedSync = coordinator.syncReminders(
            notificationsEnabled: change != 'notifications off',
            topics: {
              for (final topic in GakujoNotificationTopic.values)
                if (!(change == 'coursework off' &&
                        topic == GakujoNotificationTopic.coursework) &&
                    !(change == 'survey off' &&
                        topic == GakujoNotificationTopic.survey))
                  topic,
            },
            preferences: GakujoNotificationPreferences(
              skipSubmitted: change == 'skip submitted',
              // Keep a different offset enabled so the unreadable sync preserves
              // the original bookings instead of clearing every reminder.
              reminderOffsets: {
                change == 'offset off'
                    ? GakujoReminderOffset.threeHours
                    : GakujoReminderOffset.oneHour,
              },
            ),
          );
          store.onLoadAssignments = () async => null;
          read.complete(null);
          await preservingSync;
          await changedSync;
          if (change == 'skip submitted') {
            // The latest skipSubmitted choice can be checked once data returns.
            store.onLoadAssignments = null;
          }
          if (!deferred) {
            await tester.pump(const Duration(seconds: 1));
          }
          await callback(reminder);
          await callback(reminder);
          final expected = change == 'unchanged'
              ? [reminder]
              : <GakujoReminder>[];
          expect(service.notifiedReminders, expected);
          expect(
            await store.loadNotifiedDeadlineKeys(),
            hasLength(expected.length),
          );
          expect(
            service.bookings,
            hasLength(change == 'notifications off' ? 2 : 1),
          );
        },
      );
    }
  }

  test('a deferred reminder write failure does not discard the next reminder', () async {
    var now = DateTime.utc(2099, 7, 1, 8);
    final store = _ControlledAssignmentStore();
    final service = _ReminderNotificationService();
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: service,
      now: () => now,
    );
    await store.mergeAssignments([
      for (final title in ['first', 'second'])
        GakujoAssignment(
          kind: 'レポート',
          title: title,
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
    final reminders = service.bookings.single;
    final callback = service.onInAppReminder!;
    final readStarted = Completer<void>();
    final read = Completer<List<GakujoAssignment>?>();
    store.onLoadAssignments = () {
      readStarted.complete();
      return read.future;
    };
    final firstSync = sync();
    await readStarted.future;
    now = reminders.first.at;
    final firstCallback = callback(reminders.first);
    final secondCallback = callback(reminders.last);
    final secondSync = sync();
    store.onLoadAssignments = () async => null;
    store.failNextNotifiedWrite = true;
    read.complete(null);
    await firstSync;
    await firstCallback;
    await secondCallback;
    await secondSync;

    expect(service.bookings, hasLength(1));
    expect(service.notifiedReminders, reminders);
    expect(store.failedNotifiedWrites, 1);
    expect(await store.loadNotifiedDeadlineKeys(), {
      'reminder|${reminders.last.assignmentId}|${reminders.last.at.millisecondsSinceEpoch}',
    });
    await callback(reminders.last);
    expect(service.notifiedReminders, reminders);
  });
}

class _BookingSecureStorage extends FlutterSecureStorage {
  String? gatedKey;
  final readEntered = Completer<void>();
  final releaseRead = Completer<void>();
  int assignmentReads = 0;
  bool failLaterAssignmentReads = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == 'more_better_gakujo_assignments') {
      assignmentReads += 1;
      if (failLaterAssignmentReads && assignmentReads > 1) {
        throw PlatformException(code: 'SyntheticAssignmentReadFailure');
      }
    }
    if (key == gatedKey) {
      gatedKey = null;
      readEntered.complete();
      await releaseRead.future;
    }
    return super.read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}

class _ControlledAssignmentStore extends GakujoActivityStore {
  Future<List<GakujoAssignment>?> Function()? onLoadAssignments;
  bool failNextNotifiedWrite = false;
  int failedNotifiedWrites = 0;

  @override
  Future<List<GakujoAssignment>?> loadAssignmentsIfAvailable() =>
      onLoadAssignments?.call() ?? super.loadAssignmentsIfAvailable();

  @override
  Future<void> addNotifiedDeadlineKeys(Iterable<String> deadlineKeys) async {
    if (failNextNotifiedWrite) {
      failNextNotifiedWrite = false;
      failedNotifiedWrites += 1;
      throw StateError('notified key write failed');
    }
    await super.addNotifiedDeadlineKeys(deadlineKeys);
  }
}

class _ReminderNotificationService extends GakujoNotificationService {
  _ReminderNotificationService({super.now, this.useRealTimers = false});

  final bool useRealTimers;
  final List<GakujoReminder> notifiedReminders = [];
  final List<List<GakujoReminder>> bookings = [];
  Future<bool> Function()? onRequestPermission;
  Future<bool?> Function()? onCheckPermission;
  Future<void> Function(GakujoReminder)? onInAppReminder;

  @override
  Future<bool> requestPermission() async =>
      await onRequestPermission?.call() ?? true;

  @override
  Future<bool?> checkPermission() =>
      onCheckPermission?.call() ?? super.checkPermission();

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
