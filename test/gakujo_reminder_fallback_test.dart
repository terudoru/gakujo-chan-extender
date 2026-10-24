import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_restore.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';

const _channel = MethodChannel('net.yoshida.morebettergakujo/notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void answer({
    required bool booksAhead,
    bool permissionGranted = true,
    bool notifyResult = true,
  }) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'scheduleReminders' && !booksAhead) {
        // What Windows answers: the runner does not implement it.
        throw MissingPluginException();
      }
      if (call.method == 'requestPermission') {
        return permissionGranted;
      }
      if (call.method == 'notifyDeadline') {
        return notifyResult;
      }
      return true;
    });
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  GakujoReminder reminder(int id, Duration fromNow) => GakujoReminder(
        id: id,
        title: '【あと1時間】レポート $id',
        body: '科目　10/28 16:31まで',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/x',
        at: DateTime.now().add(fromNow),
      );

  testWidgets('where the OS cannot book ahead, the open app reminds',
      (tester) async {
    answer(booksAhead: false);
    final service = GakujoNotificationService();

    expect(
      await service.scheduleReminders([
        reminder(1, const Duration(milliseconds: 100)),
        reminder(2, const Duration(hours: 1)),
      ]),
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 200));

    final shown = calls.where((call) => call.method == 'notifyDeadline');
    expect(shown.map((call) => (call.arguments as Map)['title']), [
      '【あと1時間】レポート 1',
    ]);

    // Booking again replaces the waiting reminder instead of adding to it.
    await service.scheduleReminders(const []);
    await tester.pump(const Duration(hours: 2));
    expect(
        calls.where((call) => call.method == 'notifyDeadline'), hasLength(1));
  });

  testWidgets('a reminder whose timer runs late still comes on the clock',
      (tester) async {
    answer(booksAhead: false);
    var now = DateTime(2099, 10, 28, 12);
    final service = GakujoNotificationService(now: () => now);

    GakujoReminder at(int id, DateTime time) => GakujoReminder(
          id: id,
          title: 'レポート $id',
          body: '',
          url: '',
          at: time,
        );
    await service.scheduleReminders([
      at(1, DateTime(2099, 10, 28, 14)),
      at(2, DateTime(2099, 10, 28, 20)),
    ]);
    // The computer sleeps three hours; its timers do not count them.
    now = now.add(const Duration(hours: 3));
    await tester.pump(const Duration(minutes: 1));

    final shown = calls.where((call) => call.method == 'notifyDeadline');
    expect(shown.map((call) => (call.arguments as Map)['title']), [
      'レポート 1',
    ]);
    // The late timer does not remind again.
    await tester.pump(const Duration(hours: 2));
    expect(
        calls.where((call) => call.method == 'notifyDeadline'), hasLength(1));
    await service.scheduleReminders(const []);
  });

  testWidgets('where the OS books ahead, the app does not remind as well',
      (tester) async {
    answer(booksAhead: true);
    final service = GakujoNotificationService();

    expect(
      await service.scheduleReminders([
        reminder(1, const Duration(milliseconds: 100)),
      ]),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(calls.map((call) => call.method), ['scheduleReminders']);
    expect(
      ((calls.single.arguments as Map)['reminders'] as List).single,
      containsPair('title', '【あと1時間】レポート 1'),
    );
  });

  testWidgets('a refused permission is not asked again in the session',
      (tester) async {
    var asked = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'requestPermission') {
        asked += 1;
        return false;
      }
      return true;
    });
    final service = GakujoNotificationService();

    expect(await service.requestPermission(), isFalse);
    expect(await service.requestPermission(), isFalse);
    expect(asked, 1);
  });

  group('catch-up reminders', () {
    late DateTime now;
    final services = <GakujoNotificationService>[];

    setUp(() {
      now = DateTime.utc(2099, 10, 28, 14, 30);
      answer(booksAhead: false);
    });

    tearDown(() async {
      for (final service in services) {
        await service.scheduleReminders(const []);
      }
      services.clear();
    });

    GakujoAssignment assignment({
      String title = '課題',
      String kind = 'レポート',
      String status = '未提出',
      Duration dueIn = const Duration(minutes: 30),
    }) =>
        GakujoAssignment(
          kind: kind,
          title: title,
          status: status,
          course: '科目',
          dueAt: now.add(dueIn),
          capturedAt: now,
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        );

    GakujoDeadlineNotificationCoordinator coordinator(
      GakujoActivityStore store,
    ) {
      final service = GakujoNotificationService(now: () => now);
      services.add(service);
      return GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
        now: () => now,
      );
    }

    Future<void> sync(
      GakujoDeadlineNotificationCoordinator coordinator, {
      bool enabled = true,
      Set<GakujoNotificationTopic> topics = const {
        GakujoNotificationTopic.coursework,
        GakujoNotificationTopic.survey,
      },
      GakujoNotificationPreferences preferences =
          const GakujoNotificationPreferences(),
    }) =>
        coordinator.syncReminders(
          notificationsEnabled: enabled,
          topics: topics,
          preferences: preferences,
        );

    Iterable<MethodCall> shown() =>
        calls.where((call) => call.method == 'notifyDeadline');

    GakujoReminder onTimeReminder(GakujoAssignment assignment) => planReminders(
          assignments: [assignment],
          topics: {GakujoNotificationTopic.coursework},
          preferences: const GakujoNotificationPreferences(
            reminderOffsets: {GakujoReminderOffset.oneHour},
          ),
          now: assignment.dueAt.subtract(const Duration(hours: 2)),
        ).single;

    test('a late reminder is shown once across syncs and a restart', () async {
      final store = GakujoActivityStore();
      final open = assignment();
      final expected = onTimeReminder(open);
      await store.mergeAssignments([open]);
      final first = coordinator(store);

      await Future.wait([sync(first), sync(first)]);

      expect(shown().single.arguments, {
        'title': '【あと1時間】レポート 課題',
        'body': '科目　10/29 00:00まで',
        'url': open.url,
      });
      expect((shown().single.arguments as Map)['title'], expected.title);
      expect((shown().single.arguments as Map)['body'], expected.body);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'reminder|${expected.assignmentId}|${expected.at.millisecondsSinceEpoch}',
      });

      // A new coordinator, service and store read the persisted key.
      final restartedStore = GakujoActivityStore();
      await sync(coordinator(restartedStore));

      expect(shown(), hasLength(1));
      expect(await restartedStore.loadNotifiedDeadlineKeys(), {
        'reminder|${expected.assignmentId}|${expected.at.millisecondsSinceEpoch}',
      });
    });

    test(
        'delivery history survives a same-title kind appearing or disappearing',
        () async {
      for (final history in [
        'new',
        'legacy',
        'collision',
        'bareLegacy',
        'bareCollision',
      ]) {
        FlutterSecureStorage.setMockInitialValues({});
        calls.clear();
        final store = GakujoActivityStore();
        final open = assignment();
        // A submitted quiz still changes the report's OS booking id.
        final quiz = assignment(kind: '小テスト', status: '提出済');
        final original = onTimeReminder(open);
        final colliding = <GakujoReminder>[];
        planReminders(
          assignments: [open, quiz],
          topics: {GakujoNotificationTopic.coursework},
          preferences: const GakujoNotificationPreferences(
            reminderOffsets: {GakujoReminderOffset.oneHour},
          ),
          now: now,
          lateReminders: colliding,
        );
        expect(colliding.single.id, isNot(original.id));
        if (history != 'new') {
          final id = history.toLowerCase().contains('collision')
              ? colliding.single.id
              : original.id;
          await store.addNotifiedDeadlineKeys([
            history.startsWith('bare')
                ? 'reminder|$id'
                : 'reminder|$id|${original.at.millisecondsSinceEpoch}',
          ]);
        }
        for (final assignments in [
          [open],
          [open, quiz],
          [open],
        ]) {
          await store.mergeAssignments(assignments, isWholeList: true);
          await sync(coordinator(GakujoActivityStore()));
          expect(shown(), hasLength(history == 'new' ? 1 : 0), reason: history);
        }
        if (history == 'new') {
          expect(await store.loadNotifiedDeadlineKeys(), {
            'reminder|${open.id}|${original.at.millisecondsSinceEpoch}',
          });
        }
      }
    });

    test('a pre-upgrade reminder key prevents catch-up replay', () async {
      final store = GakujoActivityStore();
      final open = assignment();
      // The pre-upgrade hash of 科目|課題|one_hour.
      const oldId = 127832593;
      await store.mergeAssignments([open]);
      await store.addNotifiedDeadlineKeys(['reminder|$oldId']);

      await sync(coordinator(store));

      expect(onTimeReminder(open).id, oldId);
      expect(shown(), isEmpty);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'reminder|$oldId',
        'reminder|$oldId|legacySeen|${now.millisecondsSinceEpoch}',
      });
    });

    test('an extended deadline can deliver the same reminder id at a new time',
        () async {
      final store = GakujoActivityStore();
      final original = assignment();
      final firstReminder = onTimeReminder(original);
      await store.mergeAssignments([original]);
      await sync(coordinator(store));
      expect(shown(), hasLength(1));

      now = now.add(const Duration(days: 1));
      final extended = assignment();
      final secondReminder = onTimeReminder(extended);
      expect(secondReminder.id, firstReminder.id);
      expect(secondReminder.at, isNot(firstReminder.at));
      final restartedStore = GakujoActivityStore();
      await restartedStore.mergeAssignments([extended]);
      final restarted = coordinator(restartedStore);
      await sync(restarted);
      await sync(restarted);

      expect(shown(), hasLength(2));
      expect(await restartedStore.loadNotifiedDeadlineKeys(), {
        'reminder|${firstReminder.assignmentId}|${firstReminder.at.millisecondsSinceEpoch}',
        'reminder|${secondReminder.assignmentId}|${secondReminder.at.millisecondsSinceEpoch}',
      });
    });

    test('legacy suppression ends at the original first-seen trigger window',
        () async {
      // Only the one-hour reminder: a three-hour deadline already passed the
      // one-day reminder, which would show as an unrelated catch-up.
      const oneHourOnly = GakujoNotificationPreferences(
        reminderOffsets: {GakujoReminderOffset.oneHour},
      );
      final store = GakujoActivityStore();
      final firstSeen = now;
      final original = assignment(dueIn: const Duration(hours: 3));
      final id = onTimeReminder(original).id;
      await store.mergeAssignments([original]);
      await store.addNotifiedDeadlineKeys(['reminder|$id']);
      await sync(coordinator(store), preferences: oneHourOnly);
      expect(shown(), isEmpty);

      // A restart two hours later must not renew the migration window.
      now = firstSeen.add(const Duration(hours: 2));
      final atBoundary = assignment(dueIn: const Duration(hours: 1));
      final restartedStore = GakujoActivityStore();
      await restartedStore.mergeAssignments([atBoundary]);
      await sync(coordinator(restartedStore), preferences: oneHourOnly);
      expect(shown(), isEmpty);

      now = now.add(const Duration(milliseconds: 1));
      final beyondBoundary = assignment(dueIn: const Duration(hours: 1));
      await restartedStore.mergeAssignments([beyondBoundary]);
      final restarted = coordinator(restartedStore);
      await sync(restarted, preferences: oneHourOnly);
      await sync(restarted, preferences: oneHourOnly);
      expect(shown(), hasLength(1));
      expect(await restartedStore.loadNotifiedDeadlineKeys(), {
        'reminder|$id',
        'reminder|$id|legacySeen|${firstSeen.millisecondsSinceEpoch}',
        'reminder|${beyondBoundary.id}|${onTimeReminder(beyondBoundary).at.millisecondsSinceEpoch}',
      });
    });

    testWidgets('a reminder delayed past closing is skipped and marked done',
        (tester) async {
      final store = GakujoActivityStore();
      final open = assignment(dueIn: const Duration(hours: 1, seconds: 1));
      final expected = onTimeReminder(open);
      await store.mergeAssignments([open]);
      final first = coordinator(store);
      await sync(
        first,
        preferences: const GakujoNotificationPreferences(
          reminderOffsets: {GakujoReminderOffset.oneHour},
        ),
      );

      // Sleep takes the wall clock past closing before either timer runs.
      now = open.dueAt;
      await tester.pump(const Duration(minutes: 1));

      expect(shown(), isEmpty);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'reminder|${expected.assignmentId}|${expected.at.millisecondsSinceEpoch}',
      });
      // Moving the clock back into the catch-up window must not replay it.
      now = open.dueAt.subtract(const Duration(minutes: 30));
      await sync(first);
      expect(shown(), isEmpty);
    });

    test('backup round trip does not repeat a Windows catch-up reminder',
        () async {
      final source = GakujoActivityStore();
      final open = assignment();
      final expected = onTimeReminder(open);
      final key =
          'reminder|${expected.assignmentId}|${expected.at.millisecondsSinceEpoch}';
      await source.mergeAssignments([open]);
      await sync(coordinator(source));
      expect(shown(), hasLength(1));
      expect(await source.loadNotifiedDeadlineKeys(), {key});

      final payload = await readGakujoBackupPayload(
        currentSettings: () => const GakujoAppSettings(),
        settingsStore: GakujoAppSettingsStore(),
        historyStore: GakujoDownloadHistoryStore(),
        activityStore: source,
      );
      FlutterSecureStorage.setMockInitialValues({});
      final target = GakujoActivityStore();
      await restoreGakujoBackup(
        backup: parseGakujoBackup(jsonEncode(payload)),
        settingsStore: GakujoAppSettingsStore(),
        historyStore: GakujoDownloadHistoryStore(),
        activityStore: target,
        isAllowedUrl: (_) => true,
        isAllowedNavigationUrl: (_) => true,
      );
      expect(await target.loadNotifiedDeadlineKeys(), {key});
      // Assignments are rediscovered by the next scan, rather than backed up.
      await target.mergeAssignments([open]);
      final restoredCoordinator = coordinator(target);
      await sync(restoredCoordinator);
      await sync(restoredCoordinator);
      expect(shown(), hasLength(1));
    });

    test('deadlines at or before now do not get catch-up reminders', () async {
      final store = GakujoActivityStore();
      await store.mergeAssignments([
        assignment(title: '終了済み', dueIn: const Duration(minutes: -1)),
        assignment(title: '今締切', dueIn: Duration.zero),
      ]);

      await sync(coordinator(store));

      expect(shown(), isEmpty);
      expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
    });

    test('only the latest elapsed chosen offset per assignment is shown',
        () async {
      final store = GakujoActivityStore();
      await store.mergeAssignments([
        assignment(title: 'まもなく'),
        assignment(title: '2時間後', dueIn: const Duration(hours: 2)),
      ]);
      final first = coordinator(store);
      const preferences = GakujoNotificationPreferences(
        reminderOffsets: {...GakujoReminderOffset.values},
      );

      await sync(first, preferences: preferences);
      await sync(first, preferences: preferences);

      expect(
        shown().map((call) => (call.arguments as Map)['title']),
        unorderedEquals([
          '【あと1時間】レポート まもなく',
          '【あと3時間】レポート 2時間後',
        ]),
      );
      expect(await store.loadNotifiedDeadlineKeys(), hasLength(2));
    });

    test('an elapsed offset exactly at now is eligible', () async {
      final store = GakujoActivityStore();
      await store.mergeAssignments([
        assignment(dueIn: const Duration(hours: 1)),
      ]);

      await sync(coordinator(store));

      expect(
        (shown().single.arguments as Map)['title'],
        '【あと1時間】レポート 課題',
      );
    });

    test('unchosen offsets are excluded from catch-up reminders', () async {
      final store = GakujoActivityStore();
      await store.mergeAssignments([assignment()]);

      await sync(
        coordinator(store),
        preferences: const GakujoNotificationPreferences(
          reminderOffsets: {GakujoReminderOffset.oneDay},
        ),
      );

      expect(
        (shown().single.arguments as Map)['title'],
        '【あと1日】レポート 課題',
      );
    });

    for (final dueIn in [
      const Duration(minutes: 30),
      const Duration(hours: 2),
    ]) {
      test('OS bookings skip catch-up reminders with deadline in $dueIn',
          () async {
        answer(booksAhead: true);
        final store = GakujoActivityStore();
        await store.mergeAssignments([assignment(dueIn: dueIn)]);

        await sync(coordinator(store));

        expect(shown(), isEmpty);
        expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
        if (dueIn < const Duration(hours: 1)) {
          expect(calls.map((call) => call.method), ['scheduleReminders']);
        }
      });
    }

    test('late reminders respect topics, muted courses and submitted status',
        () async {
      final store = GakujoActivityStore();
      await store.mergeAssignments([
        assignment(title: '未提出'),
        assignment(title: '提出済み', status: '提出済'),
        assignment(title: '授業評価', kind: 'アンケート'),
      ]);
      final first = coordinator(store);

      await sync(first, topics: {});
      await sync(
        first,
        preferences: const GakujoNotificationPreferences(mutedCourses: {'科目'}),
      );
      expect(shown(), isEmpty);

      await sync(first, topics: {GakujoNotificationTopic.survey});
      expect(
        shown().map((call) => (call.arguments as Map)['title']),
        ['【あと1時間】アンケート 授業評価'],
      );
      await sync(first, topics: {GakujoNotificationTopic.coursework});
      expect(shown(), hasLength(2));
      expect(
        (shown().last.arguments as Map)['title'],
        '【あと1時間】レポート 未提出',
      );
      await sync(
        first,
        preferences: const GakujoNotificationPreferences(skipSubmitted: false),
      );
      expect(shown(), hasLength(3));
      expect(
        (shown().last.arguments as Map)['title'],
        '【あと1時間】レポート 提出済み',
      );
    });

    test('disabled notifications or offsets do not show late reminders',
        () async {
      final store = GakujoActivityStore();
      await store.mergeAssignments([assignment()]);
      final first = coordinator(store);

      await sync(first, enabled: false);
      await sync(
        first,
        preferences: const GakujoNotificationPreferences(reminderOffsets: {}),
      );

      expect(shown(), isEmpty);
      expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
      expect(
        calls.where((call) => call.method == 'requestPermission'),
        isEmpty,
      );
    });

    test('late reminders require permission and stay eligible after refusal',
        () async {
      answer(booksAhead: false, permissionGranted: false);
      final store = GakujoActivityStore();
      await store.mergeAssignments([assignment()]);
      final first = coordinator(store);

      await sync(first);
      expect(shown(), isEmpty);
      expect(await store.loadNotifiedDeadlineKeys(), isEmpty);

      answer(booksAhead: false);
      services.single.forgetRefusal();
      await sync(first);
      expect(shown(), hasLength(1));
    });

    test('an unsuccessful late notification can be retried', () async {
      answer(booksAhead: false, notifyResult: false);
      final store = GakujoActivityStore();
      await store.mergeAssignments([assignment()]);
      final first = coordinator(store);

      await sync(first);
      expect(shown(), hasLength(1));
      expect(await store.loadNotifiedDeadlineKeys(), isEmpty);

      answer(booksAhead: false);
      await sync(first);
      expect(shown(), hasLength(1));
      expect(await store.loadNotifiedDeadlineKeys(), hasLength(1));
    });

    testWidgets(
        'armed timers recheck submitted, withdrawn and changed deadlines',
        (tester) async {
      final store = GakujoActivityStore();
      const dueIn = Duration(hours: 1, seconds: 1);
      final submitted = assignment(title: 'submitted', dueIn: dueIn);
      final withdrawn = assignment(title: 'withdrawn', dueIn: dueIn);
      final extended = assignment(title: 'extended', dueIn: dueIn);
      final unchanged = assignment(title: 'unchanged', dueIn: dueIn);
      await store.mergeAssignments([submitted, withdrawn, extended, unchanged],
          isWholeList: true);
      await sync(
        coordinator(store),
        preferences: const GakujoNotificationPreferences(
          reminderOffsets: {GakujoReminderOffset.oneHour},
        ),
      );
      expect(shown(), isEmpty);

      // Update the store without rebooking: the already armed timers must check.
      await store.mergeAssignments([
        assignment(title: submitted.title, status: '提出済', dueIn: dueIn),
        assignment(title: extended.title, dueIn: const Duration(hours: 2)),
        unchanged,
      ], isWholeList: true);
      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      expect(shown().map((call) => (call.arguments as Map)['title']),
          ['【あと1時間】レポート unchanged']);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'reminder|${unchanged.id}|${onTimeReminder(unchanged).at.millisecondsSinceEpoch}',
      });
    });

    testWidgets('armed reminders fail open only when the assignment read fails',
        (tester) async {
      for (final failRead in [true, false]) {
        final storage = _AssignmentReadFailureStorage();
        final store = GakujoActivityStore(secureStorage: storage);
        final open = assignment(
          title: failRead ? 'read failed' : 'empty list',
          dueIn: const Duration(hours: 1, seconds: 1),
        );
        await store.mergeAssignments([open], isWholeList: true);
        await sync(
          coordinator(store),
          preferences: const GakujoNotificationPreferences(
            reminderOffsets: {GakujoReminderOffset.oneHour},
          ),
        );
        if (failRead) {
          storage.failAssignmentReads = true;
        } else {
          await store.mergeAssignments([], isWholeList: true);
        }

        now = now.add(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));

        expect(shown().map((call) => (call.arguments as Map)['title']),
            ['【あと1時間】レポート read failed']);
        expect(storage.failedReads, failRead ? 1 : 0);
      }
    });

    testWidgets('an on-time in-app reminder is not shown again as late',
        (tester) async {
      final store = GakujoActivityStore();
      final open = assignment(dueIn: const Duration(hours: 1, seconds: 1));
      final expected = onTimeReminder(open);
      await store.mergeAssignments([open]);
      final first = coordinator(store);

      await sync(
        first,
        preferences: const GakujoNotificationPreferences(
          reminderOffsets: {GakujoReminderOffset.oneHour},
        ),
      );
      expect(shown(), isEmpty);

      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      // The timer must show and persist it before any catch-up sync runs.
      expect(shown(), hasLength(1));
      expect(await store.loadNotifiedDeadlineKeys(), {
        'reminder|${expected.assignmentId}|${expected.at.millisecondsSinceEpoch}',
      });

      await sync(first);
      await sync(coordinator(GakujoActivityStore()));
      expect(shown(), hasLength(1));
    });
  });
}

class _AssignmentReadFailureStorage extends FlutterSecureStorage {
  bool failAssignmentReads = false;
  int failedReads = 0;

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
    if (failAssignmentReads && key == 'more_better_gakujo_assignments') {
      failedReads += 1;
      throw StateError('assignment read failed');
    }
    return super.read(key: key);
  }
}
