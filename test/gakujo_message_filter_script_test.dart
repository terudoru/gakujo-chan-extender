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
}

Future<List<dynamic>> _evaluateMessageFilterScripts(
  List<String> scripts, {
  List<String> initialDisplays = const ['', ''],
  bool directTable = true,
  int intervalPasses = 0,
}) async {
  final result = await Process.run(
    'node',
    [
      '-e',
      _messageFilterDomHarness,
      jsonEncode(scripts),
      jsonEncode(initialDisplays),
      jsonEncode({
        'directTable': directTable,
        'intervalPasses': intervalPasses,
      }),
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as List<dynamic>;
}

const _messageFilterDomHarness = r'''
const vm = require('node:vm');
const scripts = JSON.parse(process.argv[1]);
const options = JSON.parse(process.argv[3]);

class FakeElement {
  constructor(tag, text = '') {
    this.tagName = tag.toUpperCase();
    this.id = '';
    this.text = text;
    this.textReads = 0;
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
    return this.text;
  }

  get textContent() {
    this.textReads += 1;
    return this.text;
  }

  set textContent(value) {
    this.text = value;
  }

  setAttribute(name, value) {
    this.attributeWrites += 1;
    this.attributes[name] = String(value);
  }

  getAttribute(name) {
    return this.attributes[name] ?? null;
  }

  removeAttribute(name) {
    this.attributeWrites += 1;
    delete this.attributes[name];
  }

  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    return child;
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

const target = new FakeElement('div');
target.id = 'tabmenutable';
const header = new FakeElement('tr', '件名');
const survey = new FakeElement('tr', '授業アンケートのお願い');
const important = new FakeElement('tr', '重要なお知らせ');
[survey.style.display, important.style.display] = JSON.parse(process.argv[2]);
const rows = [header, survey, important];
const table = new FakeElement(
  'table',
  '連絡通知 ' + rows.map((row) => row.text).join(' '),
);
table.querySelector = (selector) => selector === 'a[href]' ? {} : null;
table.querySelectorAll = (selector) => selector === 'tr' ? rows : [];

let nextIntervalId = 1;
const activeIntervals = new Map();
const document = {
  getElementById(id) {
    if (id === 'main-frame-if') return null;
    if (id === 'tabmenutable') return target;
    return findById(target, id);
  },
  querySelector(selector) {
    return options.directTable && selector === 'table.normal:nth-child(9)'
      ? table : null;
  },
  querySelectorAll(selector) {
    if (selector === 'table') return [table];
    if (selector === 'tr[data-mbg-message-filter-display]') {
      return rows.filter((row) =>
        row.getAttribute('data-mbg-message-filter-display') !== null);
    }
    return [];
  },
  createElement(tag) {
    return new FakeElement(tag);
  }
};
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

function snapshot() {
  const status = document.getElementById('mbg-message-filter-status');
  return {
    rowDisplays: [survey.style.display || '', important.style.display || ''],
    rowAttributes: [survey, important].map((row) => ({...row.attributes})),
    rowTextReads: rows.reduce((sum, row) => sum + row.textReads, 0),
    tableTextReads: table.textReads,
    attributeWrites: rows.reduce((sum, row) => sum + row.attributeWrites, 0),
    displayWrites: rows.reduce((sum, row) => sum + row.displayWrites, 0),
    statusText: status ? status.textContent : null,
    activeIntervalCount: activeIntervals.size
  };
}

const snapshots = [];
for (const script of scripts) {
  for (const element of [...rows, table]) {
    element.textReads = 0;
    element.attributeWrites = 0;
    element.displayWrites = 0;
  }
  vm.runInNewContext(script, context);
  for (let pass = 0; pass < options.intervalPasses; pass += 1) {
    for (const callback of activeIntervals.values()) callback();
  }
  snapshots.push(snapshot());
}
process.stdout.write(JSON.stringify(snapshots));
''';
