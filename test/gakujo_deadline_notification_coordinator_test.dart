import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('failed deadline notification is retried after the next merge',
      () async {
    final store = GakujoActivityStore();
    final notificationService = _FakeNotificationService(notifyResult: false);
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notificationService,
    );
    final deadline = _deadline('再試行する課題');

    expect(await store.mergeDeadlines([deadline]), [deadline]);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);

    expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
    expect(await store.mergeDeadlines([deadline]), isEmpty);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);

    expect(
      notificationService.notifiedEntries.map((entry) => entry.key),
      [deadline.key, deadline.key],
    );
    expect(await store.loadNotifiedDeadlineKeys(), isEmpty);
  });

  test('successful deadline notification is not sent again', () async {
    final store = GakujoActivityStore();
    final notificationService = _FakeNotificationService(notifyResult: true);
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notificationService,
    );
    final deadline = _deadline('一度だけ通知する課題');

    await store.mergeDeadlines([deadline]);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
    expect(await store.loadNotifiedDeadlineKeys(), {deadline.key});

    expect(await store.mergeDeadlines([deadline]), isEmpty);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);

    expect(
      notificationService.notifiedEntries.map((entry) => entry.key),
      [deadline.key],
    );
    expect(notificationService.permissionRequestCount, 1);
  });

  test('compact prunes notified keys for deadlines that no longer exist',
      () async {
    final store = GakujoActivityStore();
    final active = _deadline('残る課題');
    final removed = _deadline('消えた課題');
    await store.replaceDeadlines([active, removed]);
    await store.addNotifiedDeadlineKeys([active.key, removed.key]);
    await store.replaceDeadlines([active]);

    await store.compact();

    expect(await store.loadNotifiedDeadlineKeys(), {active.key});
  });
}

GakujoDeadlineEntry _deadline(String title) {
  return GakujoDeadlineEntry(
    title: title,
    url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/$title',
    dueText: '提出期限 2099/07/01 17:00',
    detectedAt: DateTime.utc(2026, 7, 16),
  );
}

class _FakeNotificationService extends GakujoNotificationService {
  _FakeNotificationService({required this.notifyResult});

  final bool notifyResult;
  final List<GakujoDeadlineEntry> notifiedEntries = [];
  int permissionRequestCount = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequestCount += 1;
    return true;
  }

  @override
  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) async {
    notifiedEntries.add(entry);
    return notifyResult;
  }
}
