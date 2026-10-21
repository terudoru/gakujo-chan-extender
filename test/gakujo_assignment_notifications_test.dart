import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_dated_activity.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';

/// Rows as the page scan reads Gakujo's レポート・小テスト・アンケート list.
Map<String, String> _row(
  String kind,
  String title,
  String status,
  String period, {
  String code = '260G3529',
  String course = '情報処理概論Ａ II',
}) =>
    {
      'kind': kind,
      'title': title,
      'status': status,
      'code': code,
      'course': course,
      'period': period,
    };

/// A moment given as Japan wall-clock time, as Gakujo writes it.
DateTime _jst(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

GakujoAssignment _assignment(Map<String, String> row) =>
    GakujoAssignment.fromReportRow(row, capturedAt: DateTime(2026, 10, 21))!;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a list row gives the exact closing time and status', () {
    final open = _assignment(
      _row('小テスト', '第三回（通信とネットワーク）', '未提出',
          '2026/10/21 17:01 ～2026/10/28 16:31'),
    );
    expect(open.dueAt, _jst(2026, 10, 28, 16, 31));
    expect(open.isSubmitted, isFalse);
    expect(open.id, '260G3529|第三回（通信とネットワーク）');

    // The smartphone list, also served when the list is fetched on its own.
    expect(
      _assignment(
        _row('小テスト', '第三回', '未提出', '2026/10/21 17:01 - 2026/10/28 16:31'),
      ).dueAt,
      _jst(2026, 10, 28, 16, 31),
    );

    final done = _assignment(
      _row('レポート', 'レポート１', '提出済', '2026/10/09 09:44 ～2026/10/23 08:45'),
    );
    expect(done.isSubmitted, isTrue);
    expect(
      GakujoAssignment.fromReportRow(
        _row('レポート', 'x', '未提出', '期間未定'),
        capturedAt: DateTime(2026),
      ),
      isNull,
    );
  });

  test('the schedule page and the list name the same assignment', () {
    final assignments = [
      _assignment(_row(
          '小テスト', '第2回小テスト', '提出済', '2026/10/14 10:15 ～2026/10/14 23:59',
          code: '263T0005', course: '知的財産概論')),
    ];
    final item = GakujoDatedActivity.scheduleCourseworkItems(
      '[小テスト][263T0005 知的財産概論]第2回小テスト【2026/10/14まで】',
    ).single;

    expect(item.courseCode, '263T0005');
    expect(
      findAssignment(
        assignments,
        title: item.name,
        course: item.course,
        courseCode: item.courseCode,
      ),
      same(assignments.single),
    );
    // The 提出物情報 list names only the title.
    expect(findAssignment(assignments, title: '第2回小テスト'),
        same(assignments.single));
  });

  group('notifications', () {
    final open = _assignment(
      _row('小テスト', '第三回', '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
    );
    final submitted = _assignment(
      _row('レポート', 'レポート１', '提出済', '2099/10/09 09:44 ～2099/10/23 08:45',
          code: '263T0506', course: 'プログラミング基礎Ⅰ'),
    );
    GakujoDeadlineEntry fromSchedule(GakujoAssignment a) => GakujoDeadlineEntry(
          title: '${a.kind} ${a.course} ${a.title}',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/sch',
          dueText: '2099/10/28まで',
          detectedAt: DateTime(2026, 10, 21),
          source: 'スケジュール',
          course: a.course,
          courseCode: a.courseCode,
          assignment: a.title,
        );
    GakujoDeadlineEntry fromList(GakujoAssignment a) => GakujoDeadlineEntry(
          title: '${a.kind} ${a.course} ${a.title}',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
          dueText: '2099/10/28 16:31まで',
          detectedAt: DateTime(2026, 10, 21),
          source: 'レポート・小テスト',
          course: a.course,
          courseCode: a.courseCode,
          assignment: a.title,
        );

    Future<List<String>> notify(
        GakujoNotificationPreferences preferences) async {
      final store = GakujoActivityStore();
      final service = _FakeNotificationService();
      await store.mergeAssignments([open, submitted]);
      await store.mergeDeadlines([
        fromSchedule(open),
        fromList(open),
        fromSchedule(submitted),
      ]);
      await GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
      ).notifyPendingDeadlines(
        notificationsEnabled: true,
        topics: GakujoNotificationTopicLabels.defaults,
        preferences: preferences,
      );
      return service.titles;
    }

    test('one assignment found on two pages is told about once', () async {
      expect(await notify(const GakujoNotificationPreferences()),
          ['小テスト 情報処理概論Ａ II 第三回']);
    });

    test('submitted assignments can still be told about', () async {
      expect(
        await notify(const GakujoNotificationPreferences(skipSubmitted: false)),
        unorderedEquals([
          '小テスト 情報処理概論Ａ II 第三回',
          'レポート プログラミング基礎Ⅰ レポート１',
        ]),
      );
    });

    test('a muted course is left out', () async {
      expect(
        await notify(
          const GakujoNotificationPreferences(
            mutedCourses: {'情報処理概論Ａ II'},
          ),
        ),
        isEmpty,
      );
    });
  });

  group('reminders', () {
    final now = _jst(2026, 10, 21, 12);
    final open = _assignment(
      _row('小テスト', '第三回', '未提出', '2026/10/21 17:01 ～2026/10/28 16:31'),
    );
    final submitted = _assignment(
      _row('レポート', 'レポート１', '提出済', '2026/10/09 09:44 ～2026/10/23 08:45',
          code: '263T0506', course: 'プログラミング基礎Ⅰ'),
    );
    final closingSoon = _assignment(
      _row('アンケート', '授業評価', '未提出', '2026/10/20 00:00 ～2026/10/21 12:30',
          code: '263T0005', course: '知的財産概論'),
    );

    List<GakujoReminder> plan(
      GakujoNotificationPreferences preferences, {
      Set<GakujoNotificationTopic> topics =
          GakujoNotificationTopicLabels.defaults,
    }) =>
        planReminders(
          assignments: [open, submitted, closingSoon],
          topics: topics,
          preferences: preferences,
          now: now,
        );

    test('are booked before the closing time of open assignments', () {
      final reminders = plan(const GakujoNotificationPreferences());
      expect(
        [for (final r in reminders) '${r.title} @ ${r.at}'],
        [
          '【あと1日】小テスト 第三回 @ ${_jst(2026, 10, 27, 16, 31)}',
          '【あと1時間】小テスト 第三回 @ ${_jst(2026, 10, 28, 15, 31)}',
        ],
      );
      expect(reminders.first.body, '情報処理概論Ａ II　10/28 16:31まで');
    });

    test('follow the chosen times, topics and courses', () {
      expect(
        plan(
          const GakujoNotificationPreferences(
            reminderOffsets: {GakujoReminderOffset.threeDays},
          ),
        ).map((r) => r.at),
        [_jst(2026, 10, 25, 16, 31)],
      );
      expect(
        plan(const GakujoNotificationPreferences(reminderOffsets: {})),
        isEmpty,
      );
      expect(
        plan(
          const GakujoNotificationPreferences(),
          topics: {GakujoNotificationTopic.survey},
        ),
        isEmpty,
      );
      expect(
        plan(
          const GakujoNotificationPreferences(
            mutedCourses: {'情報処理概論Ａ II'},
          ),
        ),
        isEmpty,
      );
    });

    test('keep stable ids so a booking is replaced, not doubled', () {
      final first = plan(const GakujoNotificationPreferences());
      final again = plan(const GakujoNotificationPreferences());
      expect(again.map((r) => r.id), first.map((r) => r.id));
      expect(first.map((r) => r.id).toSet(), hasLength(first.length));
    });
  });

  test('the notification choices are saved and loaded', () async {
    final store = GakujoAppSettingsStore();
    expect(
      (await store.load()).notificationPreferences.reminderOffsets,
      GakujoNotificationPreferences.defaultReminderOffsets,
    );
    await store.saveNotificationPreferences(
      const GakujoNotificationPreferences(
        skipSubmitted: false,
        mutedCourses: {'知的財産概論'},
        reminderOffsets: {GakujoReminderOffset.threeHours},
      ),
    );
    final loaded = (await store.load()).notificationPreferences;
    expect(loaded.skipSubmitted, isFalse);
    expect(loaded.mutedCourses, {'知的財産概論'});
    expect(loaded.reminderOffsets, {GakujoReminderOffset.threeHours});
  });

  group('the notification choices travel', () {
    const chosen = GakujoAppSettings(
      notificationPreferences: GakujoNotificationPreferences(
        skipSubmitted: false,
        mutedCourses: {'知的財産概論'},
        reminderOffsets: {GakujoReminderOffset.threeDays},
      ),
    );
    void expectChosen(GakujoNotificationPreferences? restored) {
      expect(restored?.skipSubmitted, isFalse);
      expect(restored?.mutedCourses, {'知的財産概論'});
      expect(restored?.reminderOffsets, {GakujoReminderOffset.threeDays});
    }

    test('through a backup', () {
      final exported = buildGakujoBackupPayload(
        appSettings: chosen,
        downloadHistory: const [],
        failedDownloads: const [],
        favorites: const [],
        deadlines: const [],
        changes: const [],
        reportLists: const [],
      );
      expectChosen(
        parseGakujoBackup(jsonEncode(exported)).notificationPreferences,
      );
    });

    test('through the local mirror macOS starts from', () async {
      final directory = await Directory.systemTemp.createTemp('mbg-prefs');
      addTearDown(() => directory.delete(recursive: true));
      final store = GakujoLocalPrefsStore(directory: directory);
      await store.saveAppSettings(chosen);
      final loaded = await GakujoLocalPrefsStore(directory: directory).load();
      expectChosen(
        macosStartupSettingsFromLocalPrefs(loaded).notificationPreferences,
      );
      expectChosen(
        mergeMacosLocalMessageFiltersWithSecureSettings(
          secureSettings: const GakujoAppSettings(),
          localPrefs: loaded,
        ).notificationPreferences,
      );
    });
  });
}

class _FakeNotificationService extends GakujoNotificationService {
  final List<String> titles = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) async {
    titles.add(entry.title);
    return true;
  }
}
