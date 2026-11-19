import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
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
