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
      // Whole rows of the レポート・小テスト list and of 提出物情報.
      expect(
        GakujoDatedActivity.isScheduleCalendarRow(
          '小テスト 第三回 未提出 260G3529 情報処理概論Ａ II 第3,4ターム 水5 '
          '2026/10/21 17:01 ～2026/10/28 16:31',
        ),
        isTrue,
      );
      expect(
        GakujoDatedActivity.isScheduleCalendarRow(
          'レポート "レポート１" 2026年10月9日 ～ 2026年10月23日 '
          '小テスト "第２回課題" 2026年10月14日 ～ 2026年10月28日',
        ),
        isTrue,
      );
      expect(
        GakujoDatedActivity.isScheduleCalendarRow(
          '小テスト 情報処理概論Ａ II 第三回 2026/10/28 16:31まで',
        ),
        isFalse,
      );
    });
  });

  test('deadlines are sorted into the topics a student can choose', () {
    GakujoNotificationTopic topic(GakujoDeadlineEntry entry) =>
        notificationTopicFor(entry);

    expect(
      topic(_entry('レポート プログラミング基礎Ⅰ レポート１')),
      GakujoNotificationTopic.coursework,
    );
    expect(
      topic(_entry('小テスト 情報処理概論Ａ II 第２回課題')),
      GakujoNotificationTopic.coursework,
    );
    expect(
      topic(_entry('授業評価ｱﾝｹｰﾄ', source: 'レポート・小テスト')),
      GakujoNotificationTopic.survey,
    );
    expect(
      topic(_entry('第3回', source: 'レポート・小テスト')),
      GakujoNotificationTopic.coursework,
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
      topics: {GakujoNotificationTopic.coursework},
    );
    expect(notifications.notified, [report.key]);

    // Choosing a topic later still tells about its pending deadlines.
    await coordinator.notifyPendingDeadlines(
      notificationsEnabled: true,
      topics: {
        GakujoNotificationTopic.coursework,
        GakujoNotificationTopic.other,
      },
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
    ).notifyPendingDeadlines(
      notificationsEnabled: true,
      topics: {},
      messages: const GakujoMessageNotificationSettings(),
    );

    expect(notifications.notified, isEmpty);
    expect(notifications.permissionRequests, 0);
  });

  group('連絡通知', () {
    // A row of Gakujo's 連絡通知 list: 掲載日時, 表題, ジャンル, 差出人, 期間.
    GakujoDeadlineEntry message(String title, String genre, [String? posted]) {
      final row = '${posted ?? '2026/10/20 12:39:16'} $title - $genre (工) 教員 '
          '2026/10/20 16:20から 2099/12/1 23:59まで';
      return GakujoDeadlineEntry(
        title: title,
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/$title',
        dueText: row,
        detectedAt: DateTime.utc(2026, 10, 21),
        kind: GakujoDatedActivity.kindFor(text: row, category: '連絡通知'),
        source: '連絡通知',
      );
    }

    final course = message('第3回目授業の資料です', '授業連絡');
    final campus = message('奨学生募集の締切について', '全学連絡通知', '2026/10/19 15:15:58');

    Future<List<String>> notify(GakujoMessageNotificationSettings rule) async {
      final store = GakujoActivityStore();
      final notifications = _FakeNotificationService();
      await store.mergeDeadlines([course, campus]);
      await GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: notifications,
      ).notifyPendingDeadlines(
        notificationsEnabled: true,
        topics: GakujoNotificationTopicLabels.defaults,
        messages: rule,
      );
      return notifications.notified;
    }

    test('are off unless chosen', () async {
      expect(await notify(const GakujoMessageNotificationSettings()), isEmpty);
    });

    test('can be limited to those with a deadline', () async {
      expect(
        await notify(
          const GakujoMessageNotificationSettings(
            mode: GakujoMessageNotificationMode.deadlines,
          ),
        ),
        [campus.key],
      );
    });

    test('can be limited to keywords, deadline or not', () async {
      expect(
        await notify(
          const GakujoMessageNotificationSettings(
            mode: GakujoMessageNotificationMode.keywords,
            keywords: ['授業連絡'],
          ),
        ),
        [course.key],
      );
      expect(
        await notify(
          const GakujoMessageNotificationSettings(
            mode: GakujoMessageNotificationMode.keywords,
          ),
        ),
        isEmpty,
      );
    });

    test('a new rule leaves out messages posted before it', () async {
      expect(
        await notify(
          GakujoMessageNotificationSettings(
            mode: GakujoMessageNotificationMode.keywords,
            keywords: const ['連絡'],
            // Between the two messages' 掲載日時 below.
            // 2026/10/20 12:00 in Japan, in UTC.
            since: DateTime.utc(2026, 10, 20, 3),
          ),
        ),
        [course.key],
      );
    });

    test('tapped later, links still open a page', () {
      const expiring = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
          'campussquare.do?_flowExecutionKey=_cAAA_kBBB';
      expect(
        durableGakujoLink(expiring, 'レポート・小テスト'),
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
        'campusportal.do?page=main&tabId=en',
      );
      const portal = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
          'campusportal.do?page=main&tabId=sch';
      expect(durableGakujoLink(portal, 'スケジュール'), portal);
      expect(durableGakujoLink(expiring, 'Gakujo'), expiring);
    });

    test('keep one identity across visits', () {
      const first = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
          'campussquare.do?_flowExecutionKey=_cAAA_kBBB'
          '&_eventId=displayMidoku&keijitype=1&genrecd=40&seqNo=507795';
      const second = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
          'campussquare.do?_flowExecutionKey=_cCCC_kDDD'
          '&_eventId=displayMidoku&keijitype=1&genrecd=40&seqNo=507795';

      expect(gakujoMessageLinkFor(first), gakujoMessageLinkFor(second));
      expect(
        gakujoMessageLinkFor(first),
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
        '?_flowId=KJW0001100-flow&keijitype=1&genrecd=40&seqNo=507795',
      );
      expect(
        _entry('x', dueText: '2099/1/1').copyWithUrl(first).key,
        _entry('x', dueText: '2099/1/1').copyWithUrl(second).key,
      );
    });
  });

  group('the topic choice', () {
    test('defaults to coursework and keeps an empty choice', () {
      expect(GakujoNotificationTopicLabels.decode(null), {
        GakujoNotificationTopic.coursework,
        GakujoNotificationTopic.survey,
      });
      expect(GakujoNotificationTopicLabels.decode(''), isEmpty);
      expect(GakujoNotificationTopicLabels.decode('other,unknown'), {
        GakujoNotificationTopic.other,
      });
    });

    test('reads the earlier separate report and quiz choices', () {
      expect(GakujoNotificationTopicLabels.decode('quiz,message'), {
        GakujoNotificationTopic.coursework,
      });
      expect(
        GakujoMessageNotificationSettings.fromJson(
          null,
          legacyTopics: 'report,message',
        ).mode,
        GakujoMessageNotificationMode.deadlines,
      );
      expect(
        GakujoMessageNotificationSettings.fromJson(null, legacyTopics: 'report')
            .mode,
        GakujoMessageNotificationMode.off,
      );
    });

    test('is saved and loaded', () async {
      final store = GakujoAppSettingsStore();
      expect(
        (await store.load()).notificationTopics,
        GakujoNotificationTopicLabels.defaults,
      );
      expect(
        (await store.load()).messageNotification.mode,
        GakujoMessageNotificationMode.off,
      );

      await store.saveNotificationTopics({GakujoNotificationTopic.other});
      await store.saveMessageNotification(
        const GakujoMessageNotificationSettings(
          mode: GakujoMessageNotificationMode.keywords,
          keywords: ['休講'],
        ),
      );
      final loaded = await store.load();
      expect(loaded.notificationTopics, {GakujoNotificationTopic.other});
      expect(loaded.messageNotification.mode,
          GakujoMessageNotificationMode.keywords);
      expect(loaded.messageNotification.keywords, ['休講']);

      await store.saveNotificationTopics({});
      expect((await store.load()).notificationTopics, isEmpty);
    });

    test('travels through a backup', () {
      final exported = buildGakujoBackupPayload(
        appSettings: const GakujoAppSettings(
          notificationTopics: {GakujoNotificationTopic.survey},
          messageNotification: GakujoMessageNotificationSettings(
            mode: GakujoMessageNotificationMode.keywords,
            keywords: ['授業連絡'],
          ),
        ),
        downloadHistory: const [],
        failedDownloads: const [],
        favorites: const [],
        deadlines: const [],
        changes: const [],
        reportLists: const [],
      );

      final restored = parseGakujoBackup(jsonEncode(exported));
      expect(restored.notificationTopics, {GakujoNotificationTopic.survey});
      expect(restored.messageNotification?.keywords, ['授業連絡']);
    });
  });

  test('a 連絡通知 hidden by an exclude keyword is never notified', () {
    const messages = GakujoMessageNotificationSettings(
      mode: GakujoMessageNotificationMode.keywords,
      keywords: ['説明会'],
    );
    final hidden = _entry('2026/10/22 14:00:54 留学説明会 - アンケート', source: '連絡通知');
    final shown = _entry('2026/10/22 14:00:54 留学説明会 - 全学連絡', source: '連絡通知');

    expect(
      isNotifiableDeadline(
        hidden,
        topics: const {},
        messages: messages,
        excludeKeywords: const ['アンケート'],
      ),
      isFalse,
    );
    expect(
      isNotifiableDeadline(
        shown,
        topics: const {},
        messages: messages,
        excludeKeywords: const ['アンケート'],
      ),
      isTrue,
    );
    expect(
      isNotifiableDeadline(hidden, topics: const {}, messages: messages),
      isTrue,
    );
  });
}

extension on GakujoDeadlineEntry {
  GakujoDeadlineEntry copyWithUrl(String url) => GakujoDeadlineEntry(
        title: title,
        url: url,
        dueText: dueText,
        detectedAt: detectedAt,
        kind: kind,
        source: source,
      );
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
