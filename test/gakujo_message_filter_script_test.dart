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
    expect(script, contains("row.style.display = hide ? 'none' : ''"));
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
}

Future<List<dynamic>> _evaluateMessageFilterScripts(
    List<String> scripts) async {
  final result = await Process.run(
    'node',
    ['-e', _messageFilterDomHarness, jsonEncode(scripts)],
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

class FakeElement {
  constructor(tag, text = '') {
    this.tagName = tag.toUpperCase();
    this.id = '';
    this.innerText = text;
    this.textContent = text;
    this.value = '';
    this.style = {};
    this.attributes = {};
    this.children = [];
    this.parentNode = null;
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value);
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
const rows = [header, survey, important];
const table = new FakeElement(
  'table',
  rows.map((row) => row.innerText).join(' '),
);
table.querySelector = (selector) => selector === 'a[href]' ? {} : null;
table.querySelectorAll = (selector) => selector === 'tr' ? rows : [];

let nextIntervalId = 1;
const activeIntervals = new Set();
const document = {
  getElementById(id) {
    if (id === 'main-frame-if') return null;
    if (id === 'tabmenutable') return target;
    return findById(target, id);
  },
  querySelector(selector) {
    return selector === 'table.normal:nth-child(9)' ? table : null;
  },
  querySelectorAll(selector) {
    return selector === 'table' ? [table] : [];
  },
  createElement(tag) {
    return new FakeElement(tag);
  }
};
const window = {
  document,
  clearInterval(id) { activeIntervals.delete(id); },
  setInterval() {
    const id = nextIntervalId++;
    activeIntervals.add(id);
    return id;
  }
};
window.window = window;
const context = {window, document};

function snapshot() {
  const status = document.getElementById('mbg-message-filter-status');
  return {
    rowDisplays: [survey.style.display || '', important.style.display || ''],
    statusText: status ? status.textContent : null,
    activeIntervalCount: activeIntervals.size
  };
}

const snapshots = [];
for (const script of scripts) {
  vm.runInNewContext(script, context);
  snapshots.push(snapshot());
}
process.stdout.write(JSON.stringify(snapshots));
''';
