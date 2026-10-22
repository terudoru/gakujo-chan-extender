import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_message_filter_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds keyword-based message row filter', () {
    final script = GakujoMessageFilterScript.build(
      keywords: ['アンケート', ' 集中  講義 ', 'アンケート'],
    );

    expect(script, contains('__MBG_MESSAGE_FILTER_VERSION'));
    expect(script, contains('__MBG_MESSAGE_FILTER_SIGNATURE'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script, contains("doc.querySelector('table.normal:nth-child(9)')"));
    expect(script, contains('"アンケート"'));
    expect(script, contains('"集中 講義"'));
    expect(script, contains('data-mbg-message-filtered'));
    expect(script, contains('除外中: '));
  });

  test('filters rows and restores them when the keywords change', () async {
    final result = await _evaluateMessageFilterScripts([
      GakujoMessageFilterScript.build(keywords: const ['アンケート']),
      GakujoMessageFilterScript.build(keywords: const ['重要']),
      GakujoMessageFilterScript.build(keywords: const []),
    ]);

    final first = result[0] as Map<String, dynamic>;
    expect(first['rowDisplays'], ['none', '']);
    expect(first['statusText'], '除外中: 1件');
    expect(first['activeIntervalCount'], 1);

    final changed = result[1] as Map<String, dynamic>;
    expect(changed['rowDisplays'], ['', 'none']);
    expect(changed['statusText'], '除外中: 1件');
    expect(changed['activeIntervalCount'], 1);

    final cleared = result[2] as Map<String, dynamic>;
    expect(cleared['rowDisplays'], ['', '']);
    expect(cleared['statusText'], isNull);
    expect(cleared['activeIntervalCount'], 1);
  });

  for (final directTable in [true, false]) {
    test(
        'desktop frame status stays in the top document '
        '(direct table: $directTable)', () async {
      final survey = GakujoMessageFilterScript.build(
        keywords: const ['アンケート'],
      );
      final empty = GakujoMessageFilterScript.build(keywords: const []);
      final result = await _evaluateMessageFilterScripts(
        [
          survey,
          survey,
          GakujoMessageFilterScript.build(keywords: const ['アンケート', '重要']),
          GakujoMessageFilterScript.build(keywords: const ['該当なし']),
          survey,
          empty,
          empty,
        ],
        frame: 'list',
        directTable: directTable,
        initialStatusCount: 2,
        intervalPasses: 3,
      );

      final labels = [
        '除外中: 1件',
        '除外中: 1件',
        '除外中: 2件',
        null,
        '除外中: 1件',
        null,
        null,
      ];
      for (var index = 0; index < result.length; index += 1) {
        final snapshot = result[index] as Map;
        final documents = (snapshot['documents'] as List).cast<Map>();
        final top = documents[0];
        final frame = documents[1];
        expect(top['hasTabMenu'], isTrue);
        expect(top['rowDisplays'], isEmpty);
        expect(top['statusText'], labels[index]);
        expect(top['statusCount'], labels[index] == null ? 0 : 1);
        expect(top['statusInTabMenu'], labels[index] != null);
        expect(frame['hasTabMenu'], isFalse);
        expect(frame['statusCount'], 0);
        expect(snapshot['activeIntervalCount'], 1);
      }
      expect((result[0] as Map)['rowDisplays'], ['none', '']);
      expect((result[2] as Map)['rowDisplays'], ['none', 'none']);
      for (final index in [3, 5, 6]) {
        expect((result[index] as Map)['rowDisplays'], ['', '']);
      }
      for (final index in [1, 6]) {
        final documents =
            ((result[index] as Map)['documents'] as List).cast<Map>();
        for (final doc in documents) {
          expect(doc['statusWrites'], 0);
        }
      }
    });
  }

  test('empty keywords remove stale statuses from the top and frame documents',
      () async {
    final empty = GakujoMessageFilterScript.build(keywords: const []);
    final result = await _evaluateMessageFilterScripts(
      [empty, empty],
      frame: 'list',
      initialStatusCount: 2,
    );

    for (final snapshot in result.cast<Map>()) {
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['statusCount'], 0);
        expect(doc['rowTextReads'], 0);
        expect(doc['tableTextReads'], 0);
        expect(doc['attributeWrites'], 0);
        expect(doc['displayWrites'], 0);
      }
    }
  });

  test('desktop teardown restores frame rows and removes the top status',
      () async {
    final survey = GakujoMessageFilterScript.build(
      keywords: const ['アンケート'],
    );
    final teardown = GakujoMessageFilterScript.buildTeardown();
    final result = await _evaluateMessageFilterScripts(
      [survey, teardown, teardown, survey],
      frame: 'list',
      initialDisplays: ['table-row', 'none'],
      initialStatusCount: 2,
      intervalPasses: 3,
    );

    for (final index in [1, 2]) {
      final snapshot = result[index] as Map;
      expect(snapshot['rowDisplays'], ['table-row', 'none']);
      expect(snapshot['activeIntervalCount'], 0);
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['statusCount'], 0);
        expect(doc['rowTextReads'], 0);
        expect(doc['tableTextReads'], 0);
      }
    }
    for (final index in [0, 3]) {
      final snapshot = result[index] as Map;
      final documents = (snapshot['documents'] as List).cast<Map>();
      expect(snapshot['rowDisplays'], ['none', 'none']);
      expect(documents[0]['statusText'], '除外中: 1件');
      expect(documents[0]['statusInTabMenu'], isTrue);
      expect(documents[0]['statusCount'], 1);
      expect(documents[1]['statusCount'], 0);
      expect(snapshot['activeIntervalCount'], 1);
    }
  });

  test('preserves page-owned hidden rows and explicit display styles',
      () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['アンケート']),
        GakujoMessageFilterScript.build(keywords: const []),
      ],
      initialDisplays: ['table-row', 'none'],
    );
    expect((result[0] as Map)['rowDisplays'], ['none', 'none']);
    expect((result[1] as Map)['rowDisplays'], ['table-row', 'none']);
  });

  test('does not count rows that were already hidden by the page', () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['重要'])
      ],
      initialDisplays: ['', 'none'],
    );
    expect((result.single as Map)['statusText'], isNull);
    expect((result.single as Map)['rowDisplays'], ['', 'none']);
    expect((result.single as Map)['displayWrites'], 0);
  });

  for (final directTable in [true, false]) {
    test('empty keywords leave rows untouched (direct table: $directTable)',
        () async {
      final script = GakujoMessageFilterScript.build(keywords: const []);
      final result = await _evaluateMessageFilterScripts(
        [script, script],
        initialDisplays: ['table-row', 'none'],
        directTable: directTable,
        intervalPasses: 3,
      );

      for (final snapshot in result.cast<Map<String, dynamic>>()) {
        expect(snapshot['rowTextReads'], 0);
        expect(snapshot['tableTextReads'], 0);
        expect(snapshot['attributeWrites'], 0);
        expect(snapshot['displayWrites'], 0);
        expect(snapshot['rowAttributes'], [{}, {}]);
        expect(snapshot['rowDisplays'], ['table-row', 'none']);
        expect(snapshot['statusText'], isNull);
        expect(snapshot['activeIntervalCount'], 1);
      }
    });
  }

  test('clearing keywords restores only owned rows without reading text',
      () async {
    final empty = GakujoMessageFilterScript.build(keywords: const []);
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['アンケート']),
        empty,
        empty,
      ],
      initialDisplays: ['table-row', 'none'],
      directTable: false,
      intervalPasses: 3,
    );

    final filtered = result[0] as Map<String, dynamic>;
    expect(filtered['rowDisplays'], ['none', 'none']);
    expect(filtered['statusText'], '除外中: 1件');

    final cleared = result[1] as Map<String, dynamic>;
    expect(cleared['rowDisplays'], ['table-row', 'none']);
    expect(cleared['rowAttributes'], [
      {'data-mbg-message-filtered': 'false'},
      {'data-mbg-message-filtered': 'false'},
    ]);
    expect(cleared['rowTextReads'], 0);
    expect(cleared['tableTextReads'], 0);
    expect(cleared['attributeWrites'], 2);
    expect(cleared['displayWrites'], 1);
    expect(cleared['statusText'], isNull);

    final repeated = result[2] as Map<String, dynamic>;
    expect(repeated['rowTextReads'], 0);
    expect(repeated['tableTextReads'], 0);
    expect(repeated['attributeWrites'], 0);
    expect(repeated['displayWrites'], 0);
  });

  test('keyword passes write only changed row attributes and display styles',
      () async {
    final survey = GakujoMessageFilterScript.build(keywords: const ['アンケート']);
    final important = GakujoMessageFilterScript.build(keywords: const ['重要']);
    final result = await _evaluateMessageFilterScripts(
      [survey, survey, important, important],
      intervalPasses: 3,
    );

    final first = result[0] as Map<String, dynamic>;
    expect(first['rowDisplays'], ['none', '']);
    expect(first['attributeWrites'], 3);
    expect(first['displayWrites'], 1);
    expect(first['statusText'], '除外中: 1件');

    final changed = result[2] as Map<String, dynamic>;
    expect(changed['rowDisplays'], ['', 'none']);
    expect(changed['attributeWrites'], 4);
    expect(changed['displayWrites'], 2);
    expect(changed['statusText'], '除外中: 1件');

    for (final index in [1, 3]) {
      final repeated = result[index] as Map<String, dynamic>;
      expect(repeated['attributeWrites'], 0);
      expect(repeated['displayWrites'], 0);
      expect(repeated['statusText'], '除外中: 1件');
      expect(repeated['activeIntervalCount'], 1);
    }
  });

  for (final frame in [
    'none',
    'empty',
    'list',
    'sameDocument',
    'inaccessible',
    'both',
  ]) {
    test('filters smartphone message units in every document (frame: $frame)',
        () async {
      final result = await _evaluateMessageFilterScripts(
        [
          GakujoMessageFilterScript.build(keywords: const ['セキュリティ'])
        ],
        smartphone: true,
        smartphoneMessageCount: 159,
        frame: frame,
        intervalPasses: 3,
      );

      final snapshot = result.single as Map<String, dynamic>;
      final documents = (snapshot['documents'] as List)
          .cast<Map<String, dynamic>>()
          .where((doc) => (doc['rowDisplays'] as List).isNotEmpty)
          .toList();
      expect(documents.length, frame == 'both' ? 2 : 1);
      for (final doc in documents) {
        expect(doc['rowDisplays'], ['none', 'none', ...List.filled(157, '')]);
        expect(doc['statusText'], '除外中: 2件');
        expect(doc['statusBeforeList'], isTrue);
        expect(doc['onlyMessageUnitsTouched'], isTrue);
      }
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['navigationRowDisplays'], ['', '', '']);
        expect(doc['navigationUntouched'], isTrue);
      }
      expect(snapshot['activeIntervalCount'], 1);
    });
  }

  test('ignores smartphone navigation tables without message links', () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['授業'])
      ],
      smartphone: true,
      smartphoneMessageCount: 0,
      intervalPasses: 3,
    );

    final snapshot = result.single as Map;
    expect(snapshot['rowDisplays'], isEmpty);
    expect(snapshot['navigationRowDisplays'], ['', '', '']);
    expect(snapshot['navigationUntouched'], isTrue);
    expect(snapshot['statusText'], isNull);
  });

  test('prefers smartphone message units over a matching fallback table',
      () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['セキュリティ'])
      ],
      smartphone: true,
      fallbackTable: true,
      intervalPasses: 3,
    );

    final snapshot = result.single as Map;
    expect(snapshot['rowDisplays'], ['none', 'none', '']);
    expect(snapshot['statusText'], '除外中: 2件');
    expect(snapshot['statusBeforeList'], isTrue);
    expect(snapshot['onlyMessageUnitsTouched'], isTrue);
    expect(snapshot['navigationRowDisplays'], ['', '', '']);
    expect(snapshot['navigationUntouched'], isTrue);
  });

  for (final frame in ['empty', 'list', 'both']) {
    test('empty keywords leave smartphone lists untouched (frame: $frame)',
        () async {
      final empty = GakujoMessageFilterScript.build(keywords: const []);
      final result = await _evaluateMessageFilterScripts(
        [empty, empty],
        smartphone: true,
        frame: frame,
        initialDisplays: ['table-row', 'none', ''],
        intervalPasses: 3,
      );

      for (final snapshot in result.cast<Map<String, dynamic>>()) {
        for (final doc in (snapshot['documents'] as List).cast<Map>()) {
          expect(doc['rowTextReads'], 0);
          expect(doc['tableTextReads'], 0);
          expect(doc['attributeWrites'], 0);
          expect(doc['displayWrites'], 0);
          expect(doc['statusText'], isNull);
          if ((doc['rowDisplays'] as List).isNotEmpty) {
            expect(doc['rowAttributes'], [{}, {}, {}]);
            expect(doc['rowDisplays'], ['table-row', 'none', '']);
          }
        }
        expect(snapshot['activeIntervalCount'], 1);
      }
    });
  }

  test('smartphone keyword changes restore styles and avoid repeated writes',
      () async {
    final security = GakujoMessageFilterScript.build(
      keywords: const ['セキュリティ'],
    );
    final survey = GakujoMessageFilterScript.build(keywords: const ['アンケート']);
    final empty = GakujoMessageFilterScript.build(keywords: const []);
    final result = await _evaluateMessageFilterScripts(
      [security, security, survey, survey, empty, empty],
      smartphone: true,
      initialDisplays: ['table-row', 'none', ''],
      intervalPasses: 3,
    );

    expect((result[0] as Map)['rowDisplays'], ['none', 'none', '']);
    expect((result[0] as Map)['statusText'], '除外中: 1件');
    expect((result[2] as Map)['rowDisplays'], ['table-row', 'none', 'none']);
    expect((result[2] as Map)['statusText'], '除外中: 1件');
    expect((result[4] as Map)['rowDisplays'], ['table-row', 'none', '']);
    expect((result[4] as Map)['rowAttributes'], [
      {'data-mbg-message-filtered': 'false'},
      {'data-mbg-message-filtered': 'false'},
      {'data-mbg-message-filtered': 'false'},
    ]);
    expect((result[4] as Map)['rowTextReads'], 0);
    expect((result[4] as Map)['tableTextReads'], 0);
    expect((result[4] as Map)['statusText'], isNull);
    for (final index in [1, 3, 5]) {
      final repeated = result[index] as Map;
      expect(repeated['attributeWrites'], 0);
      expect(repeated['displayWrites'], 0);
      expect(repeated['statusWrites'], 0);
      expect(repeated['activeIntervalCount'], 1);
    }
  });

  test('smartphone page-owned hidden matches are excluded from the count',
      () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['セキュリティ'])
      ],
      smartphone: true,
      initialDisplays: ['none', 'none', ''],
    );
    expect((result.single as Map)['rowDisplays'], ['none', 'none', '']);
    expect((result.single as Map)['statusText'], isNull);
    expect((result.single as Map)['displayWrites'], 0);
  });

  test('smartphone teardown restores rows and removes both statuses', () async {
    final security = GakujoMessageFilterScript.build(
      keywords: const ['セキュリティ'],
    );
    final teardown = GakujoMessageFilterScript.buildTeardown();
    final result = await _evaluateMessageFilterScripts(
      [security, teardown, teardown, security],
      smartphone: true,
      frame: 'both',
      initialDisplays: ['table-row', 'none', ''],
      intervalPasses: 3,
    );

    for (final index in [1, 2]) {
      final snapshot = result[index] as Map;
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['rowDisplays'], ['table-row', 'none', '']);
        expect(doc['statusText'], isNull);
        expect(doc['rowTextReads'], 0);
        expect(doc['tableTextReads'], 0);
      }
      expect(snapshot['activeIntervalCount'], 0);
    }
    for (final doc in ((result[3] as Map)['documents'] as List).cast<Map>()) {
      expect(doc['rowDisplays'], ['none', 'none', '']);
      expect(doc['statusText'], '除外中: 1件');
      expect(doc['statusBeforeList'], isTrue);
    }
    expect((result[3] as Map)['activeIntervalCount'], 1);
  });
}

Future<List<dynamic>> _evaluateMessageFilterScripts(
  List<String> scripts, {
  List<String> initialDisplays = const ['', ''],
  bool directTable = true,
  int intervalPasses = 0,
  bool smartphone = false,
  int smartphoneMessageCount = 3,
  String frame = 'none',
  bool fallbackTable = false,
  int initialStatusCount = 0,
}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_message_filter_');
  try {
    final harness = File.fromUri(directory.uri.resolve('harness.cjs'))
      ..writeAsStringSync(_messageFilterDomHarness, encoding: utf8);
    final input = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
        jsonEncode({
          'scripts': scripts,
          'initialDisplays': initialDisplays,
          'directTable': directTable,
          'intervalPasses': intervalPasses,
          'smartphone': smartphone,
          'smartphoneMessageCount': smartphoneMessageCount,
          'frame': frame,
          'fallbackTable': fallbackTable,
          'initialStatusCount': initialStatusCount,
        }),
        encoding: utf8,
      );
    final result = await Process.run('node', [harness.path, input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);

    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    return jsonDecode(result.stdout as String) as List<dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}

const _messageFilterDomHarness = r'''
const vm = require('node:vm');
const options = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const {scripts, initialDisplays} = options;

class FakeElement {
  constructor(tag, text = '') {
    this.tagName = tag.toUpperCase();
    this.id = '';
    this.text = text;
    this.textReads = 0;
    this.textWrites = 0;
    this.attributeWrites = 0;
    this.displayWrites = 0;
    this.value = '';
    this.style = new Proxy({}, {
      set: (target, name, value) => {
        if (name === 'display') this.displayWrites += 1;
        target[name] = value;
        return true;
      }
    });
    this.attributes = {};
    this.children = [];
    this.parentNode = null;
  }

  get innerText() {
    this.textReads += 1;
    return this.text + this.children.map(child => child.innerText).join(' ');
  }

  get textContent() {
    return this.innerText;
  }

  set textContent(value) {
    this.textWrites += 1;
    this.text = value;
  }

  setAttribute(name, value) {
    this.attributeWrites += 1;
    this.attributes[name] = String(value);
  }

  getAttribute(name) {
    if (name === 'id') return this.id || null;
    return this.attributes[name] ?? null;
  }

  removeAttribute(name) {
    this.attributeWrites += 1;
    delete this.attributes[name];
  }

  appendChild(child) {
    return this.insertBefore(child, null);
  }

  insertBefore(child, before) {
    if (child.parentNode) child.remove();
    child.parentNode = this;
    const index = before ? this.children.indexOf(before) : this.children.length;
    if (index < 0) throw new Error('Reference node is not a child');
    this.children.splice(index, 0, child);
    return child;
  }

  matches(selector) {
    if (selector === '*') return true;
    const attributes = [...selector.matchAll(/\[([\w-]+)(?:(\*?=)"([^"]*)")?\]/g)];
    const simple = selector.replace(/\[[^\]]*\]/g, '');
    if (!/^(?:\w+)?(?:\.[\w-]+)*$/.test(simple)) return false;
    const tag = simple.match(/^\w+/)?.[0];
    if (tag && this.tagName !== tag.toUpperCase()) return false;
    for (const match of simple.matchAll(/\.([\w-]+)/g)) {
      if (!(this.attributes.class || '').split(/\s+/).includes(match[1])) return false;
    }
    return attributes.every(([, key, operator, value]) => {
      const actual = this.getAttribute(key);
      return actual !== null &&
        (!operator || (operator === '*=' ? actual.includes(value) : actual === value));
    });
  }

  closest(selector) {
    for (let node = this; node; node = node.parentNode) {
      if (node.matches(selector)) return node;
    }
    return null;
  }

  querySelectorAll(selector) {
    const result = [];
    for (const child of this.children) {
      if (child.matches(selector)) result.push(child);
      result.push(...child.querySelectorAll(selector));
    }
    return result;
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] || null;
  }

  remove() {
    if (!this.parentNode) return;
    const index = this.parentNode.children.indexOf(this);
    if (index >= 0) this.parentNode.children.splice(index, 1);
    this.parentNode = null;
  }
}

function findById(root, id) {
  if (root.id === id) return root;
  for (const child of root.children || []) {
    const match = findById(child, id);
    if (match) return match;
  }
  return null;
}

function add(parent, tag, text = '', attributes = {}) {
  const child = new FakeElement(tag, text);
  Object.entries(attributes).forEach(([name, value]) => child.setAttribute(name, value));
  return parent.appendChild(child);
}

function makeDocument(withList) {
  const root = new FakeElement('body');
  const doc = {
    root,
    rows: [],
    getElementById(id) {
      if (id === 'main-frame-if') return this.frame || null;
      return findById(root, id);
    },
    querySelector(selector) {
      if (selector === 'table.normal:nth-child(9)') {
        return options.directTable && !options.smartphone ? this.listTable : null;
      }
      return root.querySelector(selector);
    },
    querySelectorAll(selector) { return root.querySelectorAll(selector); },
    createElement(tag) { return new FakeElement(tag); }
  };
  if (options.smartphone) {
    doc.navigationTable = add(root, 'table');
    add(add(doc.navigationTable, 'tr'), 'td', '連絡通知');
    add(add(add(doc.navigationTable, 'tr'), 'td'), 'a', '授業掲示板',
      {href: 'campussquare.do?_flowId=掲示'});
    add(add(add(doc.navigationTable, 'tr'), 'td'), 'a', '授業連絡',
      {href: 'campussquare.do?_flowId=連絡'});
    if (options.fallbackTable) {
      const fallback = add(root, 'table', '連絡通知');
      add(fallback, 'tr', '件名');
      add(add(fallback, 'tr'), 'a', '重要なお知らせ',
        {href: 'campussquare.do?seqNo=508181'});
    }
  }
  if (!withList) return doc;
  if (!options.smartphone) {
    const table = add(root, 'table', '連絡通知 ');
    add(add(table, 'tr', '件名'), 'a', '', {href: 'campussquare.do'});
    doc.rows = [
      add(table, 'tr', '授業アンケートのお願い'),
      add(table, 'tr', '重要なお知らせ')
    ];
    add(doc.rows[0], 'a', '', {href: 'campussquare.do?seqNo=508182'});
    doc.listTable = table;
  } else {
    // All messages share this layout row and list table. Only the outer row of
    // each message contains both its category and its nested div.button row.
    const container = add(add(add(root, 'table'), 'tr'), 'td');
    doc.listTable = add(container, 'table');
    const body = add(doc.listTable, 'tbody');
    for (let index = 0; index < options.smartphoneMessageCount; index += 1) {
      const row = add(body, 'tr');
      doc.rows.push(row);
      const itemBody = add(add(add(row, 'td'), 'table', '', {class: 'bgnone'}), 'tbody');
      add(add(itemBody, 'tr'), 'td', index === 1 ? 'セキュリティ' : '授業連絡',
        {class: 'center category-frame'});
      const button = add(add(add(itemBody, 'tr'), 'td'), 'div', '', {
        class: 'button',
        onclick: "location.href='campussquare.do?seqNo=" + (508182 + index) + "'"
      });
      add(button, 'p', index === 0 ? '情報セキュリティ概論 第4回 授業資料'
        : index === 1 ? '重要なお知らせ' : '授業アンケートのお願い');
    }
  }
  doc.rows.forEach((row, index) => { row.style.display = initialDisplays[index] || ''; });
  return doc;
}

const document = makeDocument(options.frame !== 'list');
if (!options.smartphone) {
  const target = add(document.root, 'div');
  target.id = 'tabmenutable';
}
let frameDocument;
if (['empty', 'list', 'both'].includes(options.frame)) {
  frameDocument = makeDocument(options.frame !== 'empty');
  document.frame = {contentWindow: {document: frameDocument}};
} else if (options.frame === 'sameDocument') {
  document.frame = {contentWindow: {document}};
} else if (options.frame === 'inaccessible') {
  document.frame = {get contentWindow() { throw new Error('Cross-origin frame'); }};
}
const documents = frameDocument ? [document, frameDocument] : [document];
const listDocument = options.frame === 'list' ? frameDocument : document;
for (const doc of documents) {
  for (let index = 0; index < options.initialStatusCount; index += 1) {
    const status = add(doc.root, 'span', 'stale status');
    status.id = 'mbg-message-filter-status';
  }
}

let nextIntervalId = 1;
const activeIntervals = new Map();
const window = {
  document,
  clearInterval(id) { activeIntervals.delete(id); },
  setInterval(callback, delay) {
    if (delay !== 500) throw new Error('Expected a 500 ms interval');
    const id = nextIntervalId++;
    activeIntervals.set(id, callback);
    return id;
  }
};
window.window = window;
const context = {window, document};

function documentSnapshot(doc) {
  const rows = doc.rows;
  const elements = doc.querySelectorAll('*');
  const status = doc.getElementById('mbg-message-filter-status');
  const table = doc.listTable;
  const navigation = doc.navigationTable;
  const sum = (nodes, field) => nodes.reduce((total, node) => total + node[field], 0);
  return {
    rowDisplays: rows.map(row => row.style.display || ''),
    rowAttributes: rows.map(row => ({...row.attributes})),
    rowTextReads: sum(elements.filter(node => node.tagName === 'TR'), 'textReads'),
    tableTextReads: sum(elements.filter(node => node.tagName === 'TABLE'), 'textReads'),
    attributeWrites: sum(elements, 'attributeWrites'),
    displayWrites: sum(elements, 'displayWrites'),
    statusWrites: status ? status.textWrites : 0,
    statusText: status ? status.textContent : null,
    statusCount: doc.querySelectorAll('[id="mbg-message-filter-status"]').length,
    hasTabMenu: !!doc.getElementById('tabmenutable'),
    statusInTabMenu: !!status && status.parentNode === doc.getElementById('tabmenutable'),
    navigationRowDisplays: navigation ? navigation.querySelectorAll('tr').map(row => row.style.display || '') : [],
    navigationUntouched: !navigation || [navigation, ...navigation.querySelectorAll('*')].every(node =>
      node.attributeWrites === 0 && node.displayWrites === 0 && node.textWrites === 0),
    statusBeforeList: !!status && status.parentNode === table?.parentNode &&
      status.parentNode.children.indexOf(status) + 1 === status.parentNode.children.indexOf(table),
    onlyMessageUnitsTouched: elements.filter(node => !rows.includes(node)).every(node =>
      node.displayWrites === 0 && !Object.keys(node.attributes).some(key => key.startsWith('data-mbg-message-filter')))
  };
}

const snapshots = [];
for (const script of scripts) {
  for (const doc of documents) {
    for (const element of doc.querySelectorAll('*')) {
      element.textReads = 0;
      element.textWrites = 0;
      element.attributeWrites = 0;
      element.displayWrites = 0;
    }
  }
  vm.runInNewContext(script, context);
  for (let pass = 0; pass < options.intervalPasses; pass += 1) {
    for (const callback of activeIntervals.values()) callback();
  }
  snapshots.push({...documentSnapshot(listDocument),
    documents: documents.map(documentSnapshot), activeIntervalCount: activeIntervals.size});
}
process.stdout.write(JSON.stringify(snapshots));
''';
