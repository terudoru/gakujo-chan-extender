import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_dated_activity.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';
import 'package:test/test.dart';

void main() {
  test('notified-key read failure skips the pass without duplicate sends',
      () async {
    final storage = _FlakyNotifiedKeysSecureStorage();
    final store = GakujoActivityStore(secureStorage: storage);
    final notificationService = _FakeNotificationService(notifyResult: true);
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notificationService,
    );
    final firstDeadline = _deadline('first deadline');
    final secondDeadline = _deadline('second deadline');

    await store.mergeDeadlines([firstDeadline]);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
    expect(
      notificationService.notifiedEntries.map((entry) => entry.key),
      [firstDeadline.key],
    );

    storage.failNotifiedKeysRead = true;
    await expectLater(
      coordinator.notifyPendingDeadlines(notificationsEnabled: true),
      completes,
    );
    expect(
      notificationService.notifiedEntries.map((entry) => entry.key),
      [firstDeadline.key],
    );

    storage.failNotifiedKeysRead = false;
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
    expect(
      notificationService.notifiedEntries.map((entry) => entry.key),
      [firstDeadline.key],
    );

    await store.mergeDeadlines([secondDeadline]);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);

    expect(
      notificationService.notifiedEntries.map((entry) => entry.key),
      [firstDeadline.key, secondDeadline.key],
    );
    expect(await store.loadNotifiedDeadlineKeys(), {
      firstDeadline.key,
      secondDeadline.key,
    });
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('unreadable reminder history skips delivery and recovers without replay',
      () async {
    final now = DateTime.now().toUtc();
    final storage = _FlakyNotifiedKeysSecureStorage();
    final store = GakujoActivityStore(secureStorage: storage);
    final service = _FakeNotificationService(notifyResult: true);
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
        dueAt: now.add(const Duration(minutes: 30)),
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
    expect(service.notifiedReminders, hasLength(1));
    storage.failNotifiedKeysRead = true;
    await expectLater(sync(), completes);
    expect(service.notifiedReminders, hasLength(1));
    storage.failNotifiedKeysRead = false;
    await sync();
    expect(service.notifiedReminders, hasLength(1));
    expect(await store.loadNotifiedDeadlineKeys(), hasLength(1));
  });

  test('desktop list and dated detail scans notify the same message once',
      () async {
    final list = _message(detail: false);
    final detail = _message(detail: true);
    expect(list.key, isNot(detail.key));
    expect(list.kind, 'notice');
    expect(detail.kind, 'deadline');
    final key = deadlineNotificationKey(list, null);
    expect(deadlineNotificationKey(detail, null), key);
    final store = GakujoActivityStore();
    final service = _FakeNotificationService(notifyResult: true);
    Future<void> notify() => GakujoDeadlineNotificationCoordinator(
          activityStore: GakujoActivityStore(),
          notificationService: service,
        ).notifyPendingDeadlines(
          notificationsEnabled: true,
          messages: const GakujoMessageNotificationSettings(
            mode: GakujoMessageNotificationMode.keywords,
            keywords: ['授業資料'],
          ),
        );

    await store.mergeDeadlines([list]);
    await notify();
    expect(service.notifiedEntries, hasLength(1));
    await store.replaceDeadlines([detail]);
    await notify();
    expect(service.notifiedEntries, hasLength(1));
    expect(await store.loadNotifiedDeadlineKeys(), {key});
    final next = _message(detail: true, seqNo: '508183');
    await store.mergeDeadlines([next]);
    await notify();
    expect(service.notifiedEntries, hasLength(2));
  });

  for (final kind in ['notice', 'deadline', 'schedule']) {
    test('legacy $kind message history suppresses a changed detail scan',
        () async {
      final list = _message(detail: false);
      final legacyKey = '$kind|${list.url}&_flowExecutionKey=old|'
          'Old title|Old preview';
      FlutterSecureStorage.setMockInitialValues({
        'more_better_gakujo_notified_deadline_keys': jsonEncode([legacyKey]),
      });
      final store = GakujoActivityStore();
      final service = _FakeNotificationService(notifyResult: true);
      await store.mergeDeadlines([_message(detail: true)]);
      await GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
      ).notifyPendingDeadlines(
        notificationsEnabled: true,
        messages: const GakujoMessageNotificationSettings(
          mode: GakujoMessageNotificationMode.keywords,
          keywords: ['授業資料'],
        ),
      );

      expect(service.notifiedEntries, isEmpty);
      expect(service.permissionRequestCount, 0);
      expect(await store.loadNotifiedDeadlineKeys(), {
        '$kind|${list.url}|Old title|Old preview',
      });
    });
  }

  test('a message without an identifier keeps its text-based identity', () {
    final entry = GakujoDeadlineEntry(
      title: '授業資料',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      dueText: '2099/11/20',
      detectedAt: DateTime.now(),
      source: '連絡通知',
    );
    expect(deadlineNotificationKey(entry, null), entry.key);
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

GakujoDeadlineEntry _message({required bool detail, String seqNo = '508182'}) {
  // Desktop row from gakujo_message_smartphone_script_test.dart, with future
  // dates so retention does not hide it. The detail adds a dated body.
  const title = '情報セキュリティ概論 第4回 授業資料';
  final text = detail
      ? '$title [授業連絡] 提出期限：2099年11月20日17時00分'
      : '2099/10/22 14:00:54 $title - 授業連絡 工学部 落合 博幸 '
          '2099/10/22 13:57～2099/11/05 13:57';
  final kind = GakujoDatedActivity.kindFor(text: text, category: '連絡通知');
  return GakujoDeadlineEntry(
    title: title,
    url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
        '?_flowId=KJW0001100-flow&keijitype=1&genrecd=40&seqNo=$seqNo',
    dueText: GakujoDatedActivity.datedTextPreview(kind == 'notice'
        ? text
        : GakujoDatedActivity.messageContentForDates(text)),
    detectedAt: DateTime.now(),
    kind: kind,
    source: '連絡通知',
    messageText: text,
  );
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
  final List<GakujoReminder> notifiedReminders = [];
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

  @override
  Future<bool> scheduleReminders(
    List<GakujoReminder> reminders, {
    Future<void> Function(GakujoReminder)? onInAppReminder,
  }) async =>
      false;

  @override
  Future<bool> notifyReminder(GakujoReminder reminder) async {
    notifiedReminders.add(reminder);
    return notifyResult;
  }
}

class _FlakyNotifiedKeysSecureStorage extends FlutterSecureStorage {
  bool failNotifiedKeysRead = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (failNotifiedKeysRead &&
        key == 'more_better_gakujo_notified_deadline_keys') {
      throw StateError('notified deadline keys read failed');
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
