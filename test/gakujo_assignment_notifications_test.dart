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
    expect(open.id, '260G3529|第三回（通信とネットワーク）|小テスト');

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

  for (final (period, expected) in [
    ('2026/10/24 8:45 ～10/30 17:00', _jst(2026, 10, 30, 17)),
    ('2026/10/24 8:45 ~10/30 17:00', _jst(2026, 10, 30, 17)),
    ('２０２６／１０／２４ ８：４５ ～１０／３０ １７：００', _jst(2026, 10, 30, 17)),
    ('2026/10/24 8:45 ～10/30', _jst(2026, 10, 30, 23, 59)),
    ('2026/12/24 8:45 ～1/5 17:00', _jst(2027, 1, 5, 17)),
    ('2026/12/24 8:45 ～1/5', _jst(2027, 1, 5, 23, 59)),
    ('2026/10/24 8:45 ～2026/10/30', _jst(2026, 10, 30, 23, 59)),
  ]) {
    test('a list row takes the closing part in JST: $period', () {
      expect(_assignment(_row('レポート', '第1回', '未提出', period)).dueAt, expected);
    });
  }

  test('an absent or invalid closing date never falls back to opening', () {
    for (final period in [
      '2026/10/24 8:45 ～',
      '2026/10/24 8:45 ～期限未定',
      '2026/10/24 8:45 ～2/30 17:00',
    ]) {
      expect(
        GakujoAssignment.fromReportRow(
          _row('レポート', '第1回', '未提出', period),
          capturedAt: DateTime.utc(2026, 10, 24),
        ),
        isNull,
        reason: period,
      );
    }
  });

  test('same-title reports and quizzes survive a merge with stored rows',
      () async {
    final report = _assignment(
      _row('レポート', '第1回', '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
    );
    final quiz = _assignment(
      _row('小テスト', '第1回', '提出済', '2099/10/21 17:01 ～2099/10/28 16:31'),
    );
    // Stored rows have no ID field; old data must be rekeyed on reading.
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_assignments': jsonEncode([report.toJson()]),
    });
    final store = GakujoActivityStore();
    await store.mergeAssignments([quiz]);
    expect((await store.loadAssignments()).map((a) => a.id).toSet(),
        {report.id, quiz.id});
    await store.mergeAssignments([report, quiz], isWholeList: true);
    final restored = await GakujoActivityStore().loadAssignments();
    expect(restored, hasLength(2));
    for (final assignment in restored) {
      final entry = deadlineEntriesForAssignments(
        [assignment],
        url: 'https://gakujo.example/report',
        detectedAt: DateTime(2026, 10, 21),
      ).single;
      expect(assignmentForDeadline(entry, restored)?.kind, assignment.kind);
    }
    expect(findAssignment(restored, title: report.title), isNull);
  });

  for (final (closing, expected) in [
    ('2026/10/31 24:00', _jst(2026, 11, 1)),
    ('2026/12/31 24:00', _jst(2027, 1, 1)),
    ('2028/02/29 24:00', _jst(2028, 3, 1)),
  ]) {
    test('a list row accepts midnight rollover: $closing', () {
      expect(
        _assignment(_row('レポート', '課題', '未提出', closing)).dueAt,
        expected,
      );
    });
  }

  test('a list row rejects invalid dates and times around midnight', () {
    for (final closing in [
      '2026/02/30 24:00',
      '2026/12/31 24:01',
      '2026/12/31 25:00',
      '2026/12/31 23:60',
    ]) {
      expect(
        GakujoAssignment.fromReportRow(
          _row('レポート', '課題', '未提出', closing),
          capturedAt: DateTime(2026),
        ),
        isNull,
        reason: closing,
      );
    }
  });

  group('isSubmitted', () {
    for (final entry in {
      'Submitted': true,
      'submitted': true,
      'SUBMITTED': true,
      ' Submitted ': true,
      'Not submitted': false,
      'Not Submitted': false,
      'NOT   SUBMITTED': false,
      'Not\tsubmitted': false,
      'Temporarily saved': false,
      '提出済': true,
      '回答済': true,
      '解答済': true,
      '未提出': false,
      '一時保存': false,
    }.entries) {
      test('recognizes ${entry.key}', () {
        final assignment = GakujoAssignment(
          kind: 'レポート',
          title: 'レポート１',
          status: entry.key,
          course: '情報処理概論Ａ II',
          dueAt: _jst(2026, 10, 23, 8, 45),
          capturedAt: DateTime(2026, 10, 21),
        );
        expect(assignment.isSubmitted, entry.value);
      });
    }
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

    test('an existing assignment notification key prevents upgrade replay',
        () async {
      final store = GakujoActivityStore();
      final service = _FakeNotificationService();
      await store.mergeAssignments([open]);
      await store.mergeDeadlines([fromSchedule(open), fromList(open)]);
      await store.addNotifiedDeadlineKeys(['assignment|260G3529|第三回']);

      await GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
      ).notifyPendingDeadlines(notificationsEnabled: true);

      expect(deadlineNotificationKey(fromList(open), open),
          'assignment|260G3529|第三回');
      expect(service.titles, isEmpty);
    });

    for (final hasLegacyKey in [false, true]) {
      test(
          'same-title report and quiz each notify once (legacy: $hasLegacyKey)',
          () async {
        final report = _assignment(
          _row('レポート', open.title, '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
        );
        final store = GakujoActivityStore();
        final service = _FakeNotificationService();
        await store.mergeAssignments([open, report]);
        await store.mergeDeadlines([
          fromSchedule(open),
          fromList(open),
          fromSchedule(report),
          fromList(report),
        ]);
        // An ambiguous old key cannot establish which kind was delivered.
        if (hasLegacyKey) {
          await store.addNotifiedDeadlineKeys([
            'assignment|${open.notificationId}',
          ]);
        }
        Future<void> notify(GakujoActivityStore store) =>
            GakujoDeadlineNotificationCoordinator(
              activityStore: store,
              notificationService: service,
            ).notifyPendingDeadlines(notificationsEnabled: true);

        await notify(store);
        await notify(GakujoActivityStore());

        expect(
            service.titles,
            unorderedEquals([
              fromList(open).title,
              fromList(report).title,
            ]));
        expect(await store.loadNotifiedDeadlineKeys(), {
          if (hasLegacyKey) 'assignment|${open.notificationId}',
          'assignment|${open.id}',
          'assignment|${report.id}',
        });
        // Once the collision disappears, the remaining kind must stay notified.
        await store.mergeAssignments([open], isWholeList: true);
        await notify(GakujoActivityStore());
        expect(service.titles, hasLength(2));
      });
    }

    test('a skipped same-title quiz notifies after the report is withdrawn',
        () async {
      final report = _assignment(
        _row('レポート', open.title, '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
      );
      final submittedQuiz = _assignment(
        _row('小テスト', open.title, '提出済', '2099/10/21 17:01 ～2099/10/28 16:31'),
      );
      final store = GakujoActivityStore();
      final service = _FakeNotificationService();
      Future<void> notify() => GakujoDeadlineNotificationCoordinator(
            activityStore: GakujoActivityStore(),
            notificationService: service,
          ).notifyPendingDeadlines(notificationsEnabled: true);
      await store.mergeAssignments([report, submittedQuiz], isWholeList: true);
      await store.mergeDeadlines([fromList(report), fromList(submittedQuiz)]);
      await notify();
      expect(service.titles, [fromList(report).title]);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'assignment|${report.id}',
      });

      await store.mergeAssignments([open], isWholeList: true);
      await notify();
      await notify();
      expect(service.titles, [fromList(report).title, fromList(open).title]);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'assignment|${report.id}',
        'assignment|${open.notificationId}',
        'assignment|${open.id}',
      });
    });

    test('a later same-title quiz does not repeat the delivered report',
        () async {
      final report = _assignment(
        _row('レポート', open.title, '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
      );
      final store = GakujoActivityStore();
      final service = _FakeNotificationService();
      Future<void> notify() => GakujoDeadlineNotificationCoordinator(
            activityStore: GakujoActivityStore(),
            notificationService: service,
          ).notifyPendingDeadlines(notificationsEnabled: true);
      await store.mergeAssignments([report], isWholeList: true);
      await store.mergeDeadlines([fromList(report)]);
      await notify();
      expect(service.titles, [fromList(report).title]);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'assignment|${report.notificationId}',
        'assignment|${report.id}',
      });

      await store.mergeAssignments([report, open], isWholeList: true);
      await store.mergeDeadlines([fromList(open)]);
      await notify();
      await notify();
      expect(service.titles, [fromList(report).title, fromList(open).title]);
      expect(await store.loadNotifiedDeadlineKeys(), {
        'assignment|${report.notificationId}',
        'assignment|${report.id}',
        'assignment|${open.id}',
      });

      await store.mergeAssignments([open], isWholeList: true);
      await notify();
      expect(service.titles, hasLength(2));
    });

    test('a matched exact closing time overrides a date-only deadline',
        () async {
      final store = GakujoActivityStore();
      final service = _FakeNotificationService();
      final expired = _assignment(
        _row('小テスト', '第三回', '未提出', '2099/10/21 17:01 ～2099/10/28 10:00'),
      );
      await store.mergeAssignments([expired]);
      await store.mergeDeadlines([fromSchedule(expired)]);
      final coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
        now: () => _jst(2099, 10, 28, 12),
      );

      await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
      expect(service.titles, isEmpty);
      // An unmatched schedule deadline still uses its date-only text.
      await store.mergeAssignments(const [], isWholeList: true);
      await store.mergeDeadlines([fromSchedule(submitted)]);
      await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
      expect(service.titles, [fromSchedule(submitted).title]);
    });

    test('a whole list removes only withdrawn coursework deadline entries',
        () async {
      final store = GakujoActivityStore();
      final service = _FakeNotificationService();
      final unrelated = GakujoDeadlineEntry(
        title: '学内イベント',
        url: 'https://gakujo.example/schedule',
        dueText: '2099/10/28まで',
        detectedAt: DateTime(2026, 10, 21),
        source: 'スケジュール',
        assignment: '授業外の予定',
      );
      final message = GakujoDeadlineEntry(
        title: '課題の連絡',
        url: 'https://gakujo.example/message',
        dueText: '2099/10/28まで',
        detectedAt: DateTime(2026, 10, 21),
        source: '連絡通知',
      );
      final orphan = fromList(_assignment(
        _row('レポート', '一覧にない課題', '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
      ));
      await store.mergeAssignments([open]);
      await store.mergeDeadlines([
        fromList(open),
        fromSchedule(open),
        orphan,
        unrelated,
        message,
      ]);
      await store.mergeAssignments([submitted]);
      expect(await store.loadDeadlines(), hasLength(5));

      await store.mergeAssignments(const [], isWholeList: true);
      // Pruning is persisted, so a restarted store also cannot notify them.
      final restarted = GakujoActivityStore();
      expect((await restarted.loadDeadlines()).map((e) => e.key).toSet(),
          {unrelated.key, message.key});
      // Even a stale list entry reintroduced by another scan stays silent.
      await restarted.mergeDeadlines([orphan]);
      final coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: restarted,
        notificationService: service,
      );
      await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
      expect(service.titles, unorderedEquals([unrelated.title, message.title]));
      // A paged refresh no longer proves absence from the whole list.
      await restarted.mergeAssignments([submitted]);
      await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
      expect(service.titles.last, orphan.title);
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
      // These are the pre-upgrade course/title/offset booking IDs.
      expect(first.map((r) => r.id), [812177153, 481562399]);
    });

    test('same-title reports and quizzes receive separate stable reminder ids',
        () {
      final report = _assignment(
        _row('レポート', '第三回', '未提出', '2026/10/21 17:01 ～2026/10/28 16:31'),
      );
      List<GakujoReminder> reminders(Iterable<GakujoAssignment> assignments) =>
          planReminders(
            assignments: assignments,
            topics: GakujoNotificationTopicLabels.defaults,
            preferences: const GakujoNotificationPreferences(),
            now: now,
          );
      final oldIds = reminders([open]).map((r) => r.id).toSet();
      final both = reminders([open, report]);
      expect(both, hasLength(4));
      expect(both.map((r) => r.id).toSet(), hasLength(4));
      expect(both.map((r) => r.id).toSet().intersection(oldIds), isEmpty);
      expect(reminders([report, open]).map((r) => r.id),
          unorderedEquals(both.map((r) => r.id)));
      expect(reminders([open]).map((r) => r.id).toSet(), oldIds);
      final late = <GakujoReminder>[];
      planReminders(
        assignments: [open, report],
        topics: GakujoNotificationTopicLabels.defaults,
        preferences: const GakujoNotificationPreferences(),
        now: _jst(2026, 10, 28, 16, 15),
        lateReminders: late,
      );
      expect(late, hasLength(2));
      expect(late.map((r) => r.id).toSet(), hasLength(2));
    });

    test('Android legacy ids exclude ambiguous pre-upgrade report bookings',
        () {
      final report = _assignment(
        _row('レポート', '第三回', '未提出', '2026/10/21 17:01 ～2026/10/28 16:31'),
      );
      List<GakujoReminder> reminders(Iterable<GakujoAssignment> assignments) =>
          planReminders(
            assignments: assignments,
            topics: GakujoNotificationTopicLabels.defaults,
            preferences: const GakujoNotificationPreferences(
              reminderOffsets: {GakujoReminderOffset.oneHour},
            ),
            now: now,
          );
      final oldReport = reminders([report]).single;
      final both = reminders([report, open]);

      expect(both, hasLength(2));
      expect(both.map((r) => r.toJson()['stableKey']),
          unorderedEquals([report.id, open.id]));
      for (final reminder in both) {
        final booking = reminder.toJson();
        expect(booking['atMillis'], oldReport.at.millisecondsSinceEpoch);
        // Old report history cannot identify either kind at this trigger.
        expect(booking['legacyIds'], isNot(contains(oldReport.id)));
        expect(booking['legacyIds'], [reminder.id]);
      }

      // Without a collision, both historical identities still prevent replay.
      final quiz = both.singleWhere((r) => r.assignmentId == open.id);
      expect(reminders([open]).single.legacyIds,
          containsAll([oldReport.id, quiz.id]));
    });

    test('sync replaces obsolete ids when a colliding assignment appears',
        () async {
      final report = _assignment(
        _row('レポート', '第三回', '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
      );
      final quiz = _assignment(
        _row('小テスト', '第三回', '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
      );
      final store = GakujoActivityStore();
      final service = _BookingNotificationService();
      final coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: store,
        notificationService: service,
        now: () => _jst(2099, 10, 21, 12),
      );
      Future<void> sync() => coordinator.syncReminders(
            notificationsEnabled: true,
            topics: GakujoNotificationTopicLabels.defaults,
            preferences: const GakujoNotificationPreferences(),
          );
      await store.mergeAssignments([quiz], isWholeList: true);
      await sync();
      final oldIds = service.bookings.single.map((r) => r.id).toSet();
      expect(oldIds, hasLength(2));
      await store.mergeAssignments([quiz, report], isWholeList: true);
      await sync();
      final newIds = service.bookings.last.map((r) => r.id).toSet();
      expect(newIds, hasLength(4));
      expect(newIds.intersection(oldIds), isEmpty);
      await store.mergeAssignments([quiz], isWholeList: true);
      await sync();
      expect(service.bookings.last.map((r) => r.id).toSet(), oldIds);
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

  test('a withdrawn assignment leaves when the whole list is read', () async {
    final store = GakujoActivityStore();
    final kept = _assignment(
      _row('小テスト', '残る課題', '未提出', '2099/10/21 17:01 ～2099/10/28 16:31'),
    );
    final withdrawn = _assignment(
      _row('小テスト', '取り下げ', '未提出', '2099/10/21 17:01 ～2099/10/29 16:31'),
    );
    final past = _assignment(
      _row('レポート', '終わった課題', '提出済', '2026/10/01 00:00 ～2026/10/02 00:00'),
    );
    await store.mergeAssignments([kept, withdrawn, past]);

    // One page of a longer list says nothing about the others.
    await store.mergeAssignments([kept]);
    expect((await store.loadAssignments()).map((a) => a.title),
        containsAll(['残る課題', '取り下げ']));

    await store.mergeAssignments([kept], isWholeList: true);
    final titles = (await store.loadAssignments()).map((a) => a.title);
    expect(titles, contains('残る課題'));
    expect(titles, isNot(contains('取り下げ')));

    // The last open assignment leaves too when the list is empty.
    await store.mergeAssignments(const [], isWholeList: true);
    expect((await store.loadAssignments()).map((a) => a.title), ['終わった課題']);
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

class _BookingNotificationService extends GakujoNotificationService {
  final List<List<GakujoReminder>> bookings = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> scheduleReminders(
    List<GakujoReminder> reminders, {
    Future<void> Function(GakujoReminder)? onInAppReminder,
  }) async {
    bookings.add(reminders);
    return true;
  }
}
