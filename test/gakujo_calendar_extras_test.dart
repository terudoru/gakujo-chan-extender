import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_service.dart';

final _term = GakujoCalendarTermRange(
  start: DateTime(2026, 10, 2),
  end: DateTime(2026, 12, 1),
);

const _weekly = [
  GakujoCalendarCourse(
    title: 'プログラミング基礎Ⅰ',
    weekday: DateTime.tuesday,
    period: 1,
    location: '計算機演習室',
  ),
  GakujoCalendarCourse(
    title: '知的財産概論',
    weekday: DateTime.wednesday,
    period: 2,
    location: 'B-200',
  ),
];

List<String> _meetings(List<GakujoCalendarCourse> courses) => [
      for (final event in GakujoCalendarEventBuilder.buildEvents(
        courses: courses,
        rangeStart: _term.start,
        rangeEnd: _term.end,
        uidNamespace: 'test',
      ))
        '${event.start.month}/${event.start.day} ${event.start.hour}:'
            '${event.start.minute.toString().padLeft(2, '0')} '
            '${event.title} @ ${event.location}',
    ];

void main() {
  group('休講・補講・教室変更', () {
    GakujoClassChange change(String kind, String date, String period,
            String course, String room) =>
        GakujoClassChange.fromJson({
          'kind': kind,
          'date': date,
          'period': period,
          'course': course,
          'room': room,
        })!;

    test('a cancelled class is left out and a make-up class added', () {
      final courses = GakujoCalendarExport.applyClassChanges(_weekly, [
        change('kyuko-kyuko', '2026-10-20', '1', 'プログラミング基礎Ⅰ', ''),
        change('kyuko-hoko', '2026-10-24', '3', 'プログラミング基礎Ⅰ', 'A-101'),
      ]);
      final meetings = _meetings(courses);

      expect(meetings, isNot(contains(startsWith('10/20 8:45'))));
      expect(meetings, contains('10/27 8:45 プログラミング基礎Ⅰ @ 計算機演習室'));
      expect(meetings, contains('10/24 13:00 プログラミング基礎Ⅰ @ A-101'));
    });

    test('a room change moves only that meeting', () {
      final meetings = _meetings(
        GakujoCalendarExport.applyClassChanges(_weekly, [
          change('kyuko-kyoshitsu', '2026-10-21', '2', '知的財産概論', 'E-260'),
        ]),
      );

      expect(
        meetings.where((m) => m.startsWith('10/21 10:30')),
        ['10/21 10:30 知的財産概論 @ E-260'],
      );
      expect(meetings, contains('10/28 10:30 知的財産概論 @ B-200'));
    });

    test('a one-off cancellation matches only its date, course and period', () {
      GakujoCalendarCourse meeting(int day, String title, int period) =>
          GakujoCalendarCourse(
            title: title,
            weekday: DateTime.friday,
            period: period,
            sourceDate: DateTime(2026, 10, day),
            recursWeekly: false,
          );
      final courses = GakujoCalendarExport.applyClassChanges(
        [
          meeting(23, 'A', 3),
          meeting(30, 'A', 3),
          meeting(23, 'A', 4),
          meeting(23, 'B', 3),
        ],
        [change('kyuko-kyuko', '2026-10-23', '3', 'A', '')],
      );
      final events = GakujoCalendarEventBuilder.buildEvents(
        courses: courses,
        rangeStart: _term.start,
        rangeEnd: _term.end,
      );
      expect(
        events.map(
          (event) => '${event.title}:${event.start.day}:${event.start.hour}',
        ),
        ['B:23:13', 'A:23:14', 'A:30:13'],
      );
      final ics = GakujoCalendarExport.buildIcs(
        courses: courses,
        rangeStart: _term.start,
        rangeEnd: _term.end,
      );
      final blocks = ics.split('BEGIN:VEVENT').skip(1).toList();
      expect(blocks, hasLength(3));
      expect(
        blocks.where((block) => block.contains('SUMMARY:A\r\n')).any(
              (block) =>
                  block.contains('DTSTART;TZID=Asia/Tokyo:20261023T130000'),
            ),
        isFalse,
      );
    });

    test('the page rows are read week by week', () async {
      final result = await Process.run(
        'node',
        [
          '-e',
          _changesHarness,
          GakujoCalendarExport.classChangesFetchScript(
            start: DateTime(2026, 12, 28),
            end: DateTime(2027, 1, 10),
          ),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final payload = jsonDecode(result.stdout as String) as Map;
      expect(payload['requests'], [
        '_flowId=KHW0001100-flow',
        'k1 20261228',
        'k2 20270104',
      ]);
      final changes = [
        for (final raw in payload['changes'] as List)
          GakujoClassChange.fromJson(raw as Map),
      ];
      expect(
        [
          for (final c in changes)
            '${c!.kind.name} ${c.date.year}/${c.date.month}/${c.date.day} '
                '${c.period} ${c.courseCode} ${c.course} ${c.room}',
        ],
        [
          'cancelled 2026/12/29 1 263T0506 プログラミング基礎Ⅰ 計算機演習室',
          'makeUp 2027/1/9 3 263T0506 プログラミング基礎Ⅰ A-101',
        ],
      );
    });

    test('a failed week is rejected while successful empty weeks are accepted',
        () async {
      for (final scenario in ['httpError', 'htmlError', 'timeout', 'empty']) {
        final result = await Process.run(
          'node',
          [
            '-e',
            _changesHarness,
            GakujoCalendarExport.classChangesFetchScript(
              start: DateTime(2026, 12, 28),
              end: DateTime(2027, 1, 10),
            ),
            scenario,
          ],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        expect(result.exitCode, 0, reason: '$scenario: ${result.stderr}');
        final raw = result.stdout as String;
        final payload = jsonDecode(raw) as Map;
        expect(
          payload['requests'],
          [
            '_flowId=KHW0001100-flow',
            'k1 20261228',
            'k2 20270104',
          ],
          reason: scenario,
        );
        if (scenario == 'empty') {
          expect(GakujoCalendarExport.classChangesFromJson(raw), isEmpty);
        } else {
          expect(
            () => GakujoCalendarExport.classChangesFromJson(raw),
            throwsFormatException,
            reason: scenario,
          );
        }
      }
    });
  });

  test('assignment deadlines become events at their closing time', () {
    GakujoAssignment assignment(String title, String status, String period) =>
        GakujoAssignment.fromReportRow(
          {
            'kind': '小テスト',
            'title': title,
            'status': status,
            'code': '260G3529',
            'course': '情報処理概論Ａ II',
            'period': period,
          },
          capturedAt: DateTime(2026, 10, 21),
        )!;
    final events = GakujoCalendarEventBuilder.buildAssignmentEvents(
      assignments: [
        assignment('第三回', '未提出', '2026/10/21 17:01 ～2026/10/28 16:31'),
        assignment('第二回', '提出済', '2026/10/14 16:45 ～2026/10/14 23:59'),
        assignment('期間外', '未提出', '2026/12/20 00:00 ～2026/12/24 12:00'),
      ],
      rangeStart: _term.start,
      rangeEnd: _term.end,
      uidNamespace: 'niigata-2026-第3ターム',
    );

    expect(events.map((e) => e.title), [
      '〆切 小テスト 第二回（提出済）',
      '〆切 小テスト 第三回',
    ]);
    expect(events.last.end, japanMoment(2026, 10, 28, 16, 31));
    // Synced together with the classes, so the same namespace.
    expect(events.last.id, startsWith('niigata-2026-第3ターム|deadline|'));

    final ics = GakujoCalendarExport.buildIcs(
      courses: _weekly,
      rangeStart: _term.start,
      rangeEnd: _term.end,
      extraEvents: events,
    );
    expect(ics, contains('SUMMARY:〆切 小テスト 第三回'));
    expect(ics, contains('DTEND;TZID=Asia/Tokyo:20261028T163100'));
  });

  test('the calendar options are saved with the import settings', () {
    final restored = GakujoCalendarImportSettings.fromJson(
      const GakujoCalendarImportSettings(
        applyClassChanges: false,
        includeAssignmentDeadlines: false,
      ).toJson(),
    );
    expect(restored.applyClassChanges, isFalse);
    expect(restored.includeAssignmentDeadlines, isFalse);
    expect(
      GakujoCalendarImportSettings.fromJson(const {}).applyClassChanges,
      isTrue,
    );
  });
}

DateTime japanMoment(int y, int m, int d, int h, int min) =>
    DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

/// Gakujo's 休講補講 flow: the entry page, then one page per week with rows
/// classed kyuko-kyuko (休講), kyuko-hoko (補講), kyuko-kaiko (no change).
const _changesHarness = r'''
const vm = require('node:vm');
const script = process.argv[1];
const scenario = process.argv[2];
const requests = [];
function cell(text) { return {textContent: text}; }
function row(kind, cells) { return {className: kind, cells: cells.map(cell)}; }
const weeks = {
  '20261228': [
    row('kyuko-kyuko', ['12月29日(火)', '1限', '263T0506', 'プログラミング基礎Ⅰ', '岩城', '計算機演習室']),
  ],
  '20270104': [
    row('kyuko-hoko', ['1月9日(土)', '3限', '263T0506', 'プログラミング基礎Ⅰ', '岩城', 'A-101']),
  ],
};
let lastUrl = '';
class XMLHttpRequest {
  open(method, url) { this.url = url; }
  send() {
    lastUrl = this.url;
    const day = (this.url.match(/day=([0-9]{8})/) || [])[1];
    const key = (this.url.match(/_flowExecutionKey=([^&]+)/) || [])[1];
    requests.push(day ? key + ' ' + day : '_flowId=KHW0001100-flow');
    if (day === '20270104' && scenario === 'timeout') throw new Error('Timeout');
    this.status = day === '20270104' && scenario === 'httpError' ? 503 : 200;
    this.responseText = '';
  }
}
let page = 0;
class DOMParser {
  parseFromString() {
    page += 1;
    const day = (lastUrl.match(/day=([0-9]{8})/) || [])[1];
    const invalidPage = day === '20270104' && scenario === 'htmlError';
    const rows = day && scenario !== 'empty' && !invalidPage ? (weeks[day] || []) : [];
    return {
      querySelector(selector) {
        if (invalidPage) return null;
        return selector.indexOf('_flowExecutionKey') >= 0 ? {value: 'k' + page} : null;
      },
      querySelectorAll() { return rows; }
    };
  }
}
const output = vm.runInNewContext(script, {XMLHttpRequest, DOMParser, Date, JSON, String, Number, Array});
const payload = JSON.parse(String(output));
payload.requests = requests;
process.stdout.write(JSON.stringify(payload));
''';
