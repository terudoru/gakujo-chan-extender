import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_deadline_auto_save_script.dart';
import 'package:test/test.dart';

void main() {
  test('reads the end of the submission period', () async {
    final result = await _run({
      'parse': [
        '提出期間 2026/10/20(火) 09:00 ～ 2026/10/27(火) 23:59 前回ログイン日時 2026/10/27 23:58',
        '提出期限：２０２６年１０月２７日 ２４：００',
        '公開期間 2026/10/01 00:00 ～ 2026/12/31 00:00 提出期間 2026/10/20 09:00 ～ 2026/10/27 18:00',
        '本文のみ 2026/10/27 23:59',
      ],
    });

    expect(result['parsed'], [
      '2026-10-27T23:59',
      '2026-10-28T00:00',
      '2026-10-27T18:00',
      null,
    ]);
  });

  test('presses 確定保存 after a cancellable countdown near the deadline',
      () async {
    final result = await _run({'minutesLeft': 4, 'answer': '回答本文'});

    expect(result['bannerAt0'], contains('秒後に「確定保存」を自動で押します'));
    expect(result['clicksBefore'], 0);
    expect(result['clicks'], 1);
    expect(result['confirmDuringClick'], isTrue);
    expect(result['confirmRestored'], isTrue);
    expect(result['bannerRemoved'], isTrue);
  });

  test('does not press again on the same page and deadline', () async {
    final result = await _run({
      'minutesLeft': 4,
      'answer': '回答本文',
      'extraMinutes': 2,
    });

    expect(result['clicks'], 1);
  });

  test('does nothing without an answer', () async {
    final result = await _run({'minutesLeft': 4, 'answer': '  '});

    expect(result['bannerAt0'], isNull);
    expect(result['clicks'], 0);
  });

  test('waits until the deadline is within five minutes', () async {
    final result = await _run({'minutesLeft': 20, 'answer': '回答本文'});

    expect(result['bannerAt0'], isNull);
    expect(result['clicks'], 0);
  });

  test('cancel keeps the form untouched', () async {
    final result = await _run({
      'minutesLeft': 4,
      'answer': '回答本文',
      'cancel': true,
    });

    expect(result['clicks'], 0);
    expect(result['bannerRemoved'], isTrue);
  });

  test('turning the feature off during the countdown stops the press',
      () async {
    final result = await _run({
      'minutesLeft': 4,
      'answer': '回答本文',
      'teardown': true,
    });

    expect(result['clicks'], 0);
    expect(result['bannerRemoved'], isTrue);
  });
}

Future<Map<String, dynamic>> _run(Map<String, Object?> scenario) async {
  final result = await Process.run(
    'node',
    [
      '-e',
      _harness,
      GakujoDeadlineAutoSaveScript.build(),
      GakujoDeadlineAutoSaveScript.buildTeardown(),
      jsonEncode(scenario),
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _harness = r'''
const vm = require('node:vm');
const [build, teardown, rawScenario] = process.argv.slice(1);
const scenario = JSON.parse(rawScenario);

let clock = new Date(2026, 9, 27, 12, 0).getTime();
const timers = [];
let nextId = 1;
function addTimer(fn, ms, repeat) {
  const id = nextId++;
  timers.push({ id, fn, at: clock + ms, ms, repeat });
  return id;
}
function clearTimer(id) {
  const index = timers.findIndex((t) => t.id === id);
  if (index >= 0) timers.splice(index, 1);
}
function advance(ms) {
  const end = clock + ms;
  for (;;) {
    timers.sort((a, b) => a.at - b.at);
    const due = timers.find((t) => t.at <= end);
    if (!due) break;
    clock = due.at;
    if (due.repeat) due.at += due.ms; else clearTimer(due.id);
    due.fn();
  }
  clock = end;
}
class FakeDate extends Date {
  constructor(...args) { if (args.length) super(...args); else super(clock); }
  static now() { return clock; }
}

function node(tag) {
  const element = {
    tagName: tag.toUpperCase(),
    style: {},
    children: [],
    isConnected: true,
    listeners: {},
    textContent: '',
    setAttribute() {},
    appendChild(child) { element.children.push(child); child.isConnected = true; },
    addEventListener(type, fn) { element.listeners[type] = fn; },
    remove() { element.isConnected = false; },
    getClientRects: () => [1],
  };
  return element;
}

const deadline = new Date(clock + (scenario.minutesLeft || 0) * 60000);
const pad = (n) => String(n).padStart(2, '0');
const deadlineText = `${deadline.getFullYear()}/${pad(deadline.getMonth() + 1)}/` +
  `${pad(deadline.getDate())} ${pad(deadline.getHours())}:${pad(deadline.getMinutes())}`;

let clicks = 0;
let confirmDuringClick = null;
const originalConfirm = () => false;
const context = {};
const button = node('button');
button.textContent = '確定保存';
button.click = () => {
  clicks += 1;
  confirmDuringClick = context.confirm() === true;
};
const textarea = node('textarea');
textarea.value = scenario.answer || '';
let banner = null;
const document = {
  body: node('body'),
  location: { href: 'https://gakujo.example/report?id=1' },
  querySelectorAll(selector) {
    if (selector.indexOf('iframe') === 0) return [];
    if (selector.indexOf('button') === 0) return [button];
    if (selector.indexOf('textarea') === 0) return [textarea];
    return [];
  },
  createElement(tag) {
    const element = node(tag);
    if (tag === 'div') banner = element;
    return element;
  },
};
for (const element of [button, textarea, document.body]) {
  element.ownerDocument = document;
}
document.body.textContent = `レポート提出 提出期間 2026/10/01 00:00 ～ ${deadlineText}`;
const storage = {};
Object.assign(context, {
  document,
  Date: FakeDate,
  Math, Number, String, isNaN,
  confirm: originalConfirm,
  getComputedStyle: () => ({ display: 'block', visibility: 'visible' }),
  sessionStorage: {
    getItem: (key) => storage[key] || null,
    setItem: (key, value) => { storage[key] = value; },
  },
  setTimeout: (fn, ms) => addTimer(fn, ms, false),
  clearTimeout: clearTimer,
  setInterval: (fn, ms) => addTimer(fn, ms, true),
  clearInterval: clearTimer,
});
context.window = context;
document.defaultView = context;
vm.createContext(context);
vm.runInContext(build, context);

const out = {};
if (scenario.parse) {
  out.parsed = scenario.parse.map((text) => {
    const date = context.__MBG_AUTO_SAVE_PARSE_DEADLINE(text);
    if (!date) return null;
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
      `T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  });
}

function bannerText() {
  if (!banner || !banner.isConnected) return null;
  return banner.children.map((child) => child.textContent).join(' ');
}
out.bannerAt0 = bannerText();
advance(10000);
out.clicksBefore = clicks;
if (scenario.cancel && banner) banner.children[2].listeners.click();
if (scenario.teardown) vm.runInContext(teardown, context);
advance(25000);
if (scenario.extraMinutes) advance(scenario.extraMinutes * 60000);
out.clicks = clicks;
out.confirmDuringClick = confirmDuringClick;
out.confirmRestored = context.confirm === originalConfirm;
out.bannerRemoved = !!banner && !banner.isConnected;
process.stdout.write(JSON.stringify(out));
''';
