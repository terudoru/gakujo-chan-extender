import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_history.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';
import 'package:morebettergakujo_flutter/src/widgets/notification_history_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.yoshida.morebettergakujo/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const target =
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
      'campussquare.do?_flowId=KJW0001100-flow&keijitype=1&genrecd=2&seqNo=3';
  final now = DateTime(2026, 11, 20, 12);

  GakujoDeadlineEntry notice(
    String title,
    String url, {
    String account = 'a',
  }) => GakujoDeadlineEntry(
    title: title,
    dueText: '通知本文',
    url: url,
    detectedAt: now.subtract(const Duration(days: 1)),
    source: '連絡通知',
    kind: 'notice',
    notificationAccount: account,
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'only successful posts survive in desktop history, newest first',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var account = 'a';
      var postedAt = now;
      var calls = 0;
      GakujoNotificationService service() => GakujoNotificationService(
        activeAccount: () => account,
        now: () => postedAt,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'notifyDeadline');
        calls++;
        switch ((call.arguments as Map)['title']) {
          case '権限なし':
            return false;
          case '送信失敗':
            throw PlatformException(code: 'notification_failed');
        }
        return true;
      });
      expect(await service().notifyDeadline(notice('実験連絡', target)), isTrue);
      expect(await service().notifyDeadline(notice('権限なし', target)), isFalse);
      expect(await service().notifyDeadline(notice('送信失敗', target)), isFalse);
      expect(
        await service().notifyDeadline(notice('別アカウント', target, account: 'b')),
        isFalse,
      );
      expect(calls, 3);
      postedAt = now.add(const Duration(minutes: 1));
      expect(
        await service().notifyDeadline(
          notice('リンクなし', '$target&_eventId=delete'),
        ),
        isTrue,
      );
      final reloaded = await service().loadHistory('a');
      expect(reloaded.map((e) => e.title), ['リンクなし', '実験連絡']);
      expect(reloaded.first.url, isNull);
      expect(reloaded.first.body, '通知本文');
      expect(reloaded.last.postedAt, now);
      expect(reloaded.last.url, target);
      account = 'b';
      expect(await service().loadHistory('b'), isEmpty);
      expect(await service().loadHistory('a'), isEmpty);
      account = 'a';
      await service().clearHistory();
      expect(await service().loadHistory('a'), isEmpty);
    },
  );

  test('booking, replacing and canceling native reminders only change pending requests', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bookings = <List<dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadNotificationHistory') {
        expect(call.arguments, {'account': 'a'});
        return [];
      }
      expect(call.method, 'scheduleReminders');
      bookings.add((call.arguments as Map)['reminders'] as List);
      return true;
    });
    final service = GakujoNotificationService(activeAccount: () => 'a');
    GakujoReminder reminder(int minutes, String account) => GakujoReminder(
      id: 1,
      title: '実験課題',
      body: 'あと1時間',
      url: target,
      at: now.add(Duration(minutes: minutes)),
      notificationAccount: account,
    );
    await service.scheduleReminders([reminder(1, 'a'), reminder(2, 'b')]);
    await service.scheduleReminders([reminder(3, 'a')]);
    await service.scheduleReminders([]);
    expect(bookings.map((items) => items.length), [1, 1, 0]);
    expect(bookings[0].single['historyAccount'], 'a');
    expect(bookings[0].single['historyUrl'], target);
    expect(
      bookings[0].single['atMillis'],
      isNot(bookings[1].single['atMillis']),
    );
    expect(await service.loadHistory('a'), isEmpty);
  });

  group('native booking account transitions', () {
    late String? account;
    late List<List<dynamic>> bookings;
    late List<dynamic> nativeBookings;
    late _AssignmentStore store;
    late GakujoDeadlineNotificationCoordinator coordinator;
    late bool granted;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      account = null;
      granted = true;
      bookings = [];
      nativeBookings = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestPermission' ||
            call.method == 'checkPermission') {
          return granted;
        }
        if (call.method == 'cancelOtherAccountsReminders') {
          final owner = (call.arguments as Map)['account'];
          nativeBookings.removeWhere(
            (row) =>
                row['historyAccount'] != null && row['historyAccount'] != owner,
          );
          return null;
        }
        expect(call.method, 'scheduleReminders');
        nativeBookings = List.of((call.arguments as Map)['reminders'] as List);
        bookings.add(List.of(nativeBookings));
        return true;
      });
      store = _AssignmentStore();
      await store.mergeAssignments([
        for (final owner in ['a', 'b'])
          GakujoAssignment(
            kind: 'レポート',
            title: '架空の課題 $owner',
            course: 'テスト科目',
            status: '未提出',
            dueAt: now.add(const Duration(days: 1)),
            capturedAt: now,
            notificationAccount: owner,
          ),
      ]);
      coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: GakujoNotificationService(
          activeAccount: () => account,
          now: () => now,
        ),
        now: () => now,
      );
    });

    Future<void> sync({bool enabled = true}) => coordinator.syncReminders(
      notificationsEnabled: enabled,
      topics: {GakujoNotificationTopic.coursework},
      preferences: const GakujoNotificationPreferences(
        reminderOffsets: {GakujoReminderOffset.oneHour},
      ),
      allowPermissionRequest: false,
    );

    test(
      'enabled startup and authentication challenges retain native bookings',
      () async {
        await sync();
        expect(bookings, isEmpty);
        account = 'a';
        await sync();
        account = null;
        await sync();
        expect(bookings, hasLength(1));
        expect(bookings.single.single['historyAccount'], 'a');
      },
    );

    test(
      'explicit disable cancels native bookings without an established account',
      () async {
        await sync(enabled: false);
        expect(bookings, [isEmpty]);
      },
    );

    test('switching to a confirmed account replaces the previous account’s bookings', () async {
      account = 'a';
      await sync();
      account = null;
      await sync();
      account = 'b';
      await sync();
      expect(bookings.map((items) => items.single['historyAccount']), [
        'a',
        'b',
      ]);
    });

    test('permission denial on a confirmed switch clears the old account’s bookings', () async {
      account = 'a';
      await sync();
      account = 'b';
      granted = false;
      await sync();
      expect(bookings, hasLength(1));
      expect(nativeBookings, isEmpty);
    });

    test('a cold confirmation retains matching alarms when the cache cannot be read', () async {
      nativeBookings = [
        {'historyAccount': 'a', 'id': 1},
        {'historyAccount': 'b', 'id': 2},
        {'id': 3},
      ];
      store.unavailable = true;
      account = 'a';
      await sync();
      expect(bookings, isEmpty);
      expect(nativeBookings.map((row) => row['id']), [1, 3]);
    });
  });

  test(
    'desktop acceptance after clear cannot restore the erased history',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final reachedBridge = Completer<void>();
      final accepted = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'notifyDeadline');
        reachedBridge.complete();
        return accepted.future;
      });
      final service = GakujoNotificationService(activeAccount: () => 'a');
      final posting = service.notifyDeadline(notice('消去前の通知', target));
      await reachedBridge.future;
      await GakujoNotificationService().clearHistory();
      accepted.complete(true);
      expect(await posting, isTrue);
      expect(await service.loadHistory('a'), isEmpty);
    },
  );

  testWidgets('history shows full text and hides it on account change', (
    tester,
  ) async {
    final active = ValueNotifier<String?>('a');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => NotificationHistoryDialog(
                  account: 'a',
                  activeAccount: active,
                  entries: Future.value([
                    GakujoNotificationHistoryEntry(
                      title: '本文のみ',
                      body: '以前届いた通知の本文',
                      postedAt: now,
                    ),
                  ]),
                  targetUrl: (url) => url,
                ),
              ),
              child: const Text('履歴を開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('履歴を開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本文のみ'));
    await tester.pumpAndSettle();
    expect(find.text('以前届いた通知の本文'), findsOneWidget);
    expect(find.text('元のページを開く'), findsNothing);
    active.value = 'b';
    await tester.pumpAndSettle();
    expect(find.text('以前届いた通知の本文'), findsNothing);
    expect(find.text('学務にログインすると、通知履歴を確認できます。'), findsOneWidget);
  });
}

class _AssignmentStore extends GakujoActivityStore {
  bool unavailable = false;

  @override
  Future<List<GakujoAssignment>?> loadAssignmentsIfAvailable() async =>
      unavailable ? null : super.loadAssignmentsIfAvailable();
}
