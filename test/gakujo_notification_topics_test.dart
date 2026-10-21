import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_dated_activity.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';

GakujoDeadlineEntry _entry(
  String title, {
  String dueText = '2099/07/01まで',
  String source = '',
}) {
  return GakujoDeadlineEntry(
    title: title,
    url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/$title',
    dueText: dueText,
    detectedAt: DateTime.utc(2026, 10, 21),
    source: source,
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('schedule page coursework', () {
    // Shapes from Gakujo's schedule page: a month-view row read as one line
    // and the 提出物情報 list below the calendar.
    const monthRow = '12 [休日]祝日\t13\t14 1限:情報セキュリティ概論@備考欄参照 '
        '2限:知的財産概論@備考欄参照 '
        '[小テスト][263T0005 知的財産概論]第2回小テスト【2026/10/14まで】 '
        '[小テスト][263T0006 情報セキュリティ概論]第1回レポート'
        '【10/14（水）〆切】【2026/10/14まで】\t15';
    const submissions = '提出物情報\n'
        'レポート "レポート１" 2026年10月9日 ～ 2026年10月23日\n'
        '小テスト "第2回小テスト" 2026年10月14日 ～ 2026年10月14日\n';
    const monthItem = '[レポート][263T0506 プログラミング基礎Ⅰ]レポート１【2026/10/23まで】';

    test('each assignment becomes its own deadline', () {
      final items = GakujoDatedActivity.scheduleCourseworkItems(
        '$monthRow\n$monthItem\n$submissions',
      );

      expect(
        [for (final item in items) '${item.title} / ${item.dueText}'],
        [
          '小テスト 知的財産概論 第2回小テスト / 2026/10/14まで',
          '小テスト 情報セキュリティ概論 第1回レポート【10/14（水）〆切】 / '
              '2026/10/14まで',
          'レポート プログラミング基礎Ⅰ レポート１ / 2026/10/23まで',
        ],
      );
    });

    test('a calendar row stored by an older version is not a deadline', () {
      expect(GakujoDatedActivity.isScheduleCalendarRow(monthRow), isTrue);
      expect(
        GakujoDatedActivity.isScheduleCalendarRow('2026/10/14まで'),
        isFalse,
      );
    });
  });

  test('deadlines are sorted into the topics a student can choose', () {
    GakujoNotificationTopic topic(GakujoDeadlineEntry entry) =>
        notificationTopicFor(entry);

    expect(
      topic(_entry('レポート プログラミング基礎Ⅰ レポート１')),
      GakujoNotificationTopic.report,
    );
    expect(
      topic(_entry('小テスト 情報処理概論Ａ II 第２回課題（レポート）')),
      GakujoNotificationTopic.quiz,
    );
    expect(
      topic(_entry('授業評価ｱﾝｹｰﾄ', source: 'レポート・小テスト')),
      GakujoNotificationTopic.survey,
    );
    expect(
      topic(_entry('第3回', source: 'レポート・小テスト')),
      GakujoNotificationTopic.report,
    );
    expect(
      topic(_entry('レポートの提出について', source: '連絡通知')),
      GakujoNotificationTopic.message,
    );
    expect(
      topic(_entry('マイナー・プログラムの履修登録の締切は')),
      GakujoNotificationTopic.other,
    );
  });

  test('only the chosen topics are notified', () async {
    final store = GakujoActivityStore();
    final notifications = _FakeNotificationService();
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notifications,
    );
    final report = _entry('レポート 第1回');
    final procedure = _entry('履修登録の締切');
    await store.mergeDeadlines([report, procedure]);

    await coordinator.notifyPendingDeadlines(
      notificationsEnabled: true,
      topics: {GakujoNotificationTopic.report},
    );
    expect(notifications.notified, [report.key]);

    // Choosing a topic later still tells about its pending deadlines.
    await coordinator.notifyPendingDeadlines(
      notificationsEnabled: true,
      topics: {GakujoNotificationTopic.report, GakujoNotificationTopic.other},
    );
    expect(notifications.notified, [report.key, procedure.key]);
  });

  test('a deadline that has already passed is not notified', () async {
    final store = GakujoActivityStore();
    final notifications = _FakeNotificationService();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    // Kept for a week after the date, so it is still stored.
    final passed = _entry(
      'レポート 第2回',
      dueText: '${yesterday.year}/${yesterday.month}/${yesterday.day}まで',
    );
    final upcoming = _entry('レポート 第3回');
    await store.mergeDeadlines([passed, upcoming]);

    await GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notifications,
    ).notifyPendingDeadlines(notificationsEnabled: true);

    expect(notifications.notified, [upcoming.key]);
  });

  test('turning every topic off sends nothing', () async {
    final store = GakujoActivityStore();
    final notifications = _FakeNotificationService();
    await store.mergeDeadlines([_entry('レポート 第1回')]);

    await GakujoDeadlineNotificationCoordinator(
      activityStore: store,
      notificationService: notifications,
    ).notifyPendingDeadlines(notificationsEnabled: true, topics: {});

    expect(notifications.notified, isEmpty);
    expect(notifications.permissionRequests, 0);
  });

  group('the topic choice', () {
    test('defaults to coursework and keeps an empty choice', () {
      expect(GakujoNotificationTopicLabels.decode(null), {
        GakujoNotificationTopic.report,
        GakujoNotificationTopic.quiz,
        GakujoNotificationTopic.survey,
      });
      expect(GakujoNotificationTopicLabels.decode(''), isEmpty);
      expect(GakujoNotificationTopicLabels.decode('other,unknown'), {
        GakujoNotificationTopic.other,
      });
    });

    test('is saved and loaded', () async {
      final store = GakujoAppSettingsStore();
      expect(
        (await store.load()).notificationTopics,
        GakujoNotificationTopicLabels.defaults,
      );

      await store.saveNotificationTopics({GakujoNotificationTopic.message});
      expect((await store.load()).notificationTopics, {
        GakujoNotificationTopic.message,
      });

      await store.saveNotificationTopics({});
      expect((await store.load()).notificationTopics, isEmpty);
    });

    test('travels through a backup', () {
      final exported = buildGakujoBackupPayload(
        appSettings: const GakujoAppSettings(
          notificationTopics: {GakujoNotificationTopic.quiz},
        ),
        downloadHistory: const [],
        failedDownloads: const [],
        favorites: const [],
        deadlines: const [],
        changes: const [],
        reportLists: const [],
      );

      expect(parseGakujoBackup(jsonEncode(exported)).notificationTopics, {
        GakujoNotificationTopic.quiz,
      });
    });
  });
}

class _FakeNotificationService extends GakujoNotificationService {
  final List<String> notified = [];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    return true;
  }

  @override
  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) async {
    notified.add(entry.key);
    return true;
  }
}
