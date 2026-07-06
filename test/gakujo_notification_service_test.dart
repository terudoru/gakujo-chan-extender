import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('net.yoshida.morebettergakujo/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('requestPermission returns native permission result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestPermission');
      return true;
    });

    expect(await const GakujoNotificationService().requestPermission(), isTrue);
  });

  test('notifyDeadline forwards title body and url', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'notifyDeadline');
      expect(call.arguments, {
        'title': '課題A',
        'body': '提出期限 2026/07/01 17:00',
        'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
      });
      return false;
    });

    final notified = await const GakujoNotificationService().notifyDeadline(
      GakujoDeadlineEntry(
        title: '課題A',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        dueText: '提出期限 2026/07/01 17:00',
        detectedAt: DateTime.utc(2026, 6, 26),
      ),
    );

    expect(notified, isFalse);
  });

  test('notification calls fail closed when the platform channel is missing',
      () async {
    final service = const GakujoNotificationService();

    expect(await service.requestPermission(), isFalse);
    expect(
      await service.notifyDeadline(
        GakujoDeadlineEntry(
          title: '課題A',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
          dueText: '提出期限 2026/07/01 17:00',
          detectedAt: DateTime.utc(2026, 6, 26),
        ),
      ),
      isFalse,
    );
  });
}
