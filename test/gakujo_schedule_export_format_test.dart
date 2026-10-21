import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';

/// Shapes observed on Gakujo's live schedule pages (2026-10).
void main() {
  test('the schedule export lists classes as all-day "N限：" events', () {
    String event(String date, String summary) => [
          'BEGIN:VEVENT',
          'DTSTAMP:20261021T074911Z',
          r'UID:UID:20261021T075059Z-uidGen@csweb3\n',
          'SUMMARY:$summary',
          'DTSTART;VALUE=DATE:$date',
          'END:VEVENT',
        ].join('\r\n');
    final ics = [
      'BEGIN:VCALENDAR',
      'PRODID:campusCalendar',
      event('20261002', '1限：プログラミング基礎'),
      event('20261007', '2限：知的財産概論'),
      event('20261009', '1限：プログラミング基礎'),
      event('20261010', '学内イベント'),
      'END:VCALENDAR',
    ].join('\r\n');

    final courses =
        GakujoCalendarExport.coursesFromOfficialScheduleExportText(ics);

    expect(
      [
        for (final course in courses)
          '${GakujoCalendarExport.displayTitleForCourse(course)}:'
              '${course.weekday}:${course.period}:${course.sourceDate!.day}',
      ],
      unorderedEquals([
        'プログラミング基礎:5:1:2',
        '知的財産概論:3:2:7',
        'プログラミング基礎:5:1:9',
      ]),
    );
  });

  test('a month-view calendar is read day by day', () async {
    final result = await Process.run(
      'node',
      ['-e', _monthViewHarness, GakujoCalendarExport.extractionScript()],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final courses = ((jsonDecode(result.stdout as String)
            as Map<String, dynamic>)['courses'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      [
        for (final course in courses)
          '${course['sourceDate']} ${course['weekday']} ${course['period']} '
              '${course['title']} @ ${course['location']}',
      ],
      unorderedEquals([
        '2026-10-02 5 1 プログラミング基礎 @ A-101',
        '2026-10-06 2 4 基礎数理 @ B-353',
        '2026-10-07 3 2 知的財産概論 @ 備考欄参照',
      ]),
    );
  });

  test('the export fetch follows the progress page to the file', () async {
    final result = await Process.run(
      'node',
      [
        '-e',
        _exportFetchHarness,
        GakujoCalendarExport.officialScheduleExportFetchScript(
          startDate: '2026/10/02',
          endDate: '2026/12/01',
        ),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final payload = jsonDecode(result.stdout as String) as Map<String, dynamic>;

    expect(payload['status'], 'fetched');
    expect(payload['text'], startsWith('BEGIN:VCALENDAR'));
    expect(
      payload['requests'],
      [
        'POST /campusweb/campussquare.do',
        'GET /campusweb/campussquare.do?_flowExecutionKey=k2&_eventId=output',
      ],
    );
    expect(payload['body'], contains('startYmd=2026%2F10%2F02'));
    expect(payload['body'], contains('check2=true'));
    expect(payload['body'], isNot(contains('check1=true')));
  });

  test('the registration page lists each class with its classroom', () {
    String cell(String code, String weekday, String period, String text) =>
        '<div class="tblDivNml"><a href="" onclick="return '
        "InputCallA('$weekday','$period')\">追加</a><br> "
        '<a href="#" onclick="return '
        "CallDetail('2026','09','$code','$weekday','$period')\"> "
        '$code (T4) </a><br> $text<br> &nbsp;&nbsp; '
        '<input type="button" name="del" value="削除" disabled="disabled">'
        '</div>';
    final html = [
      '<table><tr><td>',
      cell('264T0507', '3', '1',
          'プログラミング基礎Ⅱ&nbsp;工学部 計算機演習室&nbsp;2.0単位'),
      cell('264T0004', '3', '3', '技術者の心がまえ◆&nbsp;備考欄参照&nbsp;2.0単位'),
      cell('264G3531', '1', '6', '生成AI活用基礎&nbsp;　&nbsp;1.0単位'),
      '</td></tr></table>',
      // Rejected classes are listed without a CallDetail link.
      '<table><tr><td>260G2509 (T3,4)</td><td>健康スポーツ科学実習 I</td>'
          '<td>第1体育館</td><td>金2</td></tr></table>',
    ].join();

    final courses = GakujoCalendarExport.coursesFromRegistrationPage(html);

    expect(
      [
        for (final course in courses)
          '${course.courseCode} ${course.title} ${course.weekday} '
              '${course.period} [${course.location}]',
      ],
      [
        '264T0507 プログラミング基礎Ⅱ 3 1 [工学部 計算機演習室]',
        '264T0004 技術者の心がまえ 3 3 [備考欄参照]',
        '264G3531 生成AI活用基礎 1 6 []',
      ],
    );
  });

  test('classrooms from the schedule page fill the export gaps', () {
    const exported = [
      GakujoCalendarCourse(
        title: 'プログラミング基礎',
        officialTitle: 'プログラミング基礎',
        weekday: DateTime.friday,
        period: 1,
      ),
      GakujoCalendarCourse(
        title: 'プログラミング基礎',
        weekday: DateTime.tuesday,
        period: 1,
      ),
      GakujoCalendarCourse(
        title: '知的財産概論',
        weekday: DateTime.wednesday,
        period: 2,
        location: 'Zoom',
      ),
    ];
    const page = [
      GakujoCalendarCourse(
        title: 'プログラミング基礎',
        weekday: DateTime.friday,
        period: 1,
        location: 'A-101',
      ),
      GakujoCalendarCourse(
        title: '知的財産概論',
        weekday: DateTime.wednesday,
        period: 2,
        location: 'B-200',
      ),
    ];

    final courses = GakujoCalendarExport.withPageLocations(exported, page);

    expect(courses.map((course) => course.location), ['A-101', 'A-101', 'Zoom']);
  });
}

const _monthViewHarness = r'''
const vm = require('node:vm');
const script = process.argv[1];

function node(text, extra) {
  return Object.assign({
    innerText: text,
    textContent: text,
    children: [],
    querySelector() { return null; },
    querySelectorAll() { return []; },
    getAttribute() { return null; }
  }, extra || {});
}
function day(date, text) {
  const add = node('', {
    getAttribute(name) {
      return name === 'onclick' ? 'addSchedule(' + date + ');' : null;
    }
  });
  return node(text, {
    querySelector(selector) {
      return selector.indexOf('addSchedule') >= 0 ? add : null;
    },
    querySelectorAll() { return [add]; }
  });
}
function row(cells) {
  return node(cells.map((cell) => cell.innerText).join('\t'), {children: cells});
}
const rows = [
  row(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => node(d))),
  row([
    day(20260928, '28\n[休日]夏期休業'),
    day(20260929, '29\n[休日]夏期休業'),
    day(20260930, '30\n[休日]夏期休業'),
    day(20261001, '1\n[休日]補講日'),
    day(20261002, '2\n1限:プログラミング基礎@A-101'),
    day(20261003, '3'),
    day(20261004, '4'),
  ]),
  row([
    day(20261005, '5'),
    day(20261006, '6\n4限:基礎数理@B-353'),
    // A quiz deadline names a course code and another day's date.
    day(20261007, '7\n2限:知的財産概論@備考欄参照\n' +
      '[小テスト][263T0005 知的財産概論]第2回【2026/10/14まで】'),
    day(20261008, '8'),
    day(20261009, '9'),
    day(20261010, '10'),
    day(20261011, '11'),
  ]),
];
const table = node('', {
  querySelectorAll(selector) { return selector === 'tr' ? rows : []; }
});
const doc = node('', {
  body: node(''),
  location: {href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'},
  querySelectorAll(selector) { return selector === 'table' ? [table] : []; }
});
process.stdout.write(String(vm.runInNewContext(script, {
  window: {document: doc, frames: []},
  URL
})));
''';

const _exportFetchHarness = r'''
const vm = require('node:vm');
const script = process.argv[1];
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_flowExecutionKey=k1';

function input(name, type, value, checked) {
  return {
    name, value, checked: !!checked, id: '', className: '',
    innerText: '', textContent: '',
    getAttribute(attr) { return attr === 'type' ? type : null; },
    dispatchEvent() {}
  };
}
const fields = [
  input('_flowExecutionKey', 'hidden', 'k1'),
  input('_eventId', 'hidden', ''),
  input('check1', 'checkbox', 'true', true),
  input('check2', 'checkbox', 'true', true),
  input('startYmd', 'text', '2026/10/07'),
  input('endYmd', 'text', '2026/11/04'),
];
const form = {
  name: 'scheduleExportForm', id: 'scheduleExportForm', className: '',
  method: 'post', action: '/campusweb/campussquare.do', value: '',
  innerText: 'カテゴリ 時間割コマ情報 対象期間 エクスポート実行',
  textContent: '',
  fields,
  getAttribute() { return null; },
  querySelector(selector) {
    return selector.indexOf('_eventId') >= 0 ? fields[1] : null;
  },
  querySelectorAll(selector) {
    if (selector.indexOf('checkbox') >= 0) {
      return fields.filter((f) => f.getAttribute('type') === 'checkbox');
    }
    return selector === 'input' ? fields : fields;
  }
};
class FormData {
  constructor(owner) {
    this.entries = owner.fields
      .filter((f) => f.getAttribute('type') !== 'checkbox' || f.checked)
      .map((f) => [f.name, f.value]);
  }
  [Symbol.iterator]() { return this.entries[Symbol.iterator](); }
}
const requests = [];
let postedBody = '';
const progressPage = '<html><body><meta http-equiv="REFRESH" content="0; ' +
  'URL=/campusweb/campussquare.do?_flowExecutionKey=k2&amp;_eventId=output">' +
  '<span>データ出力処理が完了しました。</span></body></html>';
class XMLHttpRequest {
  open(method, url) { this.method = method; this.url = new URL(url); }
  setRequestHeader() {}
  send(body) {
    requests.push(this.method + ' ' + this.url.pathname + this.url.search);
    if (this.method === 'POST') {
      postedBody = body;
      this.responseText = progressPage;
      this.contentType = 'text/html;charset=UTF-8';
    } else {
      this.responseText = 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n';
      this.contentType = 'text/plain;charset=UTF-8';
    }
    this.status = 200;
    this.responseURL = this.url.href;
  }
  getResponseHeader(name) {
    return name === 'Content-Type' ? this.contentType : null;
  }
}
class DOMParser {
  parseFromString(html) {
    const metas = [];
    const pattern = /<meta\s+http-equiv="([^"]*)"\s+content="([^"]*)"/gi;
    let match;
    while ((match = pattern.exec(html)) !== null) {
      const attrs = {
        'http-equiv': match[1],
        content: match[2].replace(/&amp;/g, '&')
      };
      metas.push({getAttribute(name) { return attrs[name] || null; }});
    }
    return {querySelectorAll(selector) { return selector === 'meta' ? metas : []; }};
  }
}
const doc = {
  location: {href: base},
  title: 'スケジュール',
  querySelectorAll(selector) { return selector === 'form' ? [form] : []; }
};
const output = vm.runInNewContext(script, {
  window: {document: doc, frames: []},
  URL, URLSearchParams, FormData, XMLHttpRequest, DOMParser, Event: class {}
});
const payload = JSON.parse(String(output));
payload.requests = requests;
payload.body = postedBody;
process.stdout.write(JSON.stringify(payload));
''';
