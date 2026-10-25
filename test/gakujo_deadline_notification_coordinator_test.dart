import 'dart:convert';

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

  test('a deadline pushed out of storage stays notified when found again',
      () async {
    final store = GakujoActivityStore();
    final notificationService = _FakeNotificationService(notifyResult: true);
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notificationService,
    );
    final deadline = _deadline('押し出される課題');
    await store.mergeDeadlines([deadline]);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);

    // Other entries take its place, and storage is compacted.
    await store.replaceDeadlines([_deadline('別の課題')]);
    await store.compact();
    await store.mergeDeadlines([deadline]);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);

    expect(
      notificationService.notifiedEntries.map((entry) => entry.title),
      ['押し出される課題', '別の課題'],
    );
  });

  test('v0.70.0 notified keys survive a change of flow execution key',
      () async {
    const baseUrl = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report';
    final deadline = GakujoDeadlineEntry(
      title: 'Report _flowExecutionKey=title',
      url: '$baseUrl?report=42&_flowExecutionKey=e9s9',
      dueText: '2099/07/01 17:00',
      detectedAt: DateTime.now(),
    );
    // v0.70.0 used '$kind|$url|$title|$dueText', retaining the full URL.
    final legacyKey = 'deadline|$baseUrl?_flowExecutionKey=e1s1&report=42|'
        '${deadline.title}|${deadline.dueText}';
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_notified_deadline_keys': jsonEncode([
        legacyKey,
        legacyKey.replaceFirst('e1s1', 'e2s2'),
        'assignment|42',
        'reminder|42',
      ]),
    });
    final store = GakujoActivityStore();
    final notificationService = _FakeNotificationService(notifyResult: true);
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notificationService,
    );

    expect(await store.loadNotifiedDeadlineKeys(),
        {deadline.key, 'assignment|42', 'reminder|42'});
    await store.mergeDeadlines([deadline]);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);

    expect(notificationService.notifiedEntries, isEmpty);
    expect(notificationService.permissionRequestCount, 0);
  });

  test('連絡通知 do not push coursework deadlines out of storage', () async {
    final store = GakujoActivityStore();
    final coursework = _deadline('レポート');
    await store.mergeDeadlines([coursework]);
    await store.mergeDeadlines([
      for (var i = 0; i < 200; i += 1)
        GakujoDeadlineEntry(
          title: '全学のお知らせ$i',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/m$i',
          dueText: '2099/12/1 23:59まで',
          detectedAt: DateTime.utc(2026, 10, 21, 0, i),
          kind: 'notice',
          source: '連絡通知',
        ),
    ]);

    final stored = await store.loadDeadlines();
    expect(stored.map((entry) => entry.key), contains(coursework.key));
    expect(stored.where((entry) => entry.source == '連絡通知'), hasLength(80));
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
