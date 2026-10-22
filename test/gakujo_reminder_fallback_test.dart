import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';

const _channel = MethodChannel('net.yoshida.morebettergakujo/notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  void answer({required bool booksAhead}) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'scheduleReminders' && !booksAhead) {
        // What Windows answers: the runner does not implement it.
        throw MissingPluginException();
      }
      return true;
    });
  }

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

    await service.scheduleReminders([
      reminder(1, const Duration(milliseconds: 100)),
      reminder(2, const Duration(hours: 1)),
    ]);
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

    await service.scheduleReminders([
      reminder(1, const Duration(milliseconds: 100)),
    ]);
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
}
