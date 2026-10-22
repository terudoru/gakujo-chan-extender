import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:test/test.dart';

void main() {
  for (final scenario in [
    'unread',
    'genre',
    'allGenre',
    'missingHeaders',
    'iframe',
  ]) {
    test('$scenario list stars precede titles and do not open messages',
        () async {
      final result = await _evaluate(
          _starDomHarness,
          [
            GakujoMessageStarScript.build(),
            GakujoMessageStarScript.buildRefresh(['1|40|507762']),
            GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
            GakujoMessageStarScript.buildTeardown(),
            GakujoMessageStarScript.build(),
          ],
          scenario);
      expect(result['beforeTitle'], isTrue);
      expect(result['prevented'], isTrue);
      expect(result['stopped'], isTrue);
      expect(result['label'], 'スター');
      expect(result['counts'], [1, 1, 1, 0, 1]);
      expect(result['buttonTexts'], ['', '', '', null, '']);
      expect(result['pressedStates'], ['false', 'true', 'true', null, 'false']);
      expect(result['styleCounts'], [1, 1, 1, 0, 1]);
      expect(result['outerStyleCounts'],
          scenario == 'iframe' ? [0, 0, 0, 0, 0] : [1, 1, 1, 0, 1]);
      expect(
        (result['styleTexts'] as List).whereType<String>(),
        everyElement(allOf(
          contains('button[data-mbg-message-star]::before { content: "☆"; }'),
          contains(
              'button[data-mbg-message-star][aria-pressed="true"]::before { content: "★"; }'),
        )),
      );
      expect(result['rowTexts'], everyElement(result['originalRowText']));
      expect(result['originalRowText'], isNot(contains(RegExp('[☆★]'))));
      expect(result['intervalCounts'], [1, 1, 1, 0, 1]);
      expect(result['listenerCounts'], [1, 1, 1, 0, 1]);
      final payload = (result['messages'] as List).first as Map;
      expect(payload, {
        'action': 'toggle',
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '507762',
        'title': '授業のお知らせ',
        'genre': scenario == 'missingHeaders' ? '' : '授業連絡',
        'sender': scenario == 'allGenre' || scenario == 'missingHeaders'
            ? ''
            : scenario == 'genre'
                ? '担当教員'
                : '工学部 ／ 担当教員',
        'period': scenario == 'missingHeaders' ? '' : '2026/10/01～2026/11/01',
        'postedAt': scenario == 'missingHeaders' ? '' : '2026/10/01 09:00',
        'body': '',
      });
      expect(jsonEncode(payload), isNot(contains('_flowExecutionKey')));
      expect((result['messages'] as List).length, 1);
    });
  }

  for (final scenario in ['detail', 'detailAttachment']) {
    test('$scenario extracts saved text and stable identity', () async {
      final result = await _evaluate(
          _starDomHarness,
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
            GakujoMessageStarScript.build(starredIds: ['1|40|507762']),
          ],
          scenario);
      expect(result['beforeTitle'], isTrue);
      expect(result['buttonTexts'], ['', '']);
      expect(result['pressedStates'], ['true', 'true']);
      expect(result['styleCounts'], [1, 1]);
      final messages = result['messages'] as List;
      expect(messages.length, 2); // one silent refresh and one explicit toggle
      final detail = messages.first as Map;
      expect(detail['action'], 'detail');
      expect(detail['keijitype'], '1');
      expect(detail['genrecd'], '40');
      expect(detail['seqNo'], '507762');
      expect(detail['title'], '授業のお知らせ');
      expect(detail['genre'], '授業連絡通知 授業連絡');
      expect(detail['sender'], '担当教員');
      expect(detail['period'], '2026/10/01～2026/11/01');
      expect(detail['postedAt'], '2026/10/01 09:00');
      expect(detail['body'], '本文の一行目\n二行目');
      expect((messages.last as Map)['action'], 'toggle');
      final duplicateGenre = await _evaluate(
          _starDomHarness,
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
          ],
          'detailDuplicateGenre');
      expect((duplicateGenre['messages'] as List).first['genre'], '全学連絡通知');
    });
  }

  test('unstarred detail is not saved and long detail bodies are capped',
      () async {
    final unstarred = await _evaluate(
        _starDomHarness, [GakujoMessageStarScript.build()], 'detail');
    expect((unstarred['messages'] as List).length, 1);
    expect((unstarred['messages'] as List).single['action'], 'toggle');
    final long = await _evaluate(
        _starDomHarness,
        [
          GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
        ],
        'detailLong');
    expect(((long['messages'] as List).first['body'] as String).length, 4000);
  });

  test('iframe navigation discovers detail without reinjection', () async {
    final result = await _evaluate(
        _starDomHarness,
        [
          GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
        ],
        'navigate');
    expect(result['navigatedTitle'], '授業のお知らせ [新着]');
    expect(result['navigatedButtonText'], '');
    expect(result['navigatedPressed'], 'true');
    expect(result['navigatedStyleCount'], 1);
    expect((result['messages'] as List).last['action'], 'detail');
    expect((result['messages'] as List).last['title'], '授業のお知らせ');
  });

  for (final scenario in ['rememberedUnread', 'rememberedGenre']) {
    test('$scenario title click resolves attachment-free detail and reload',
        () async {
      final result = await _evaluate(
          _starDomHarness,
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
          ],
          scenario);
      expect(result['capture'], isTrue);
      expect(result['rememberedBeforeClick'], isNull);
      expect(result['remembered'], {
        'keijitype': '1',
        'genrecd': '40',
        'seqNo': '507762',
        'title': '授業のお知らせ',
      });
      expect(result['oldListListenerRemoved'], isTrue);
      expect(result['navigatedButtonText'], '');
      expect(result['navigatedPressed'], 'true');
      expect(result['navigatedStyleCount'], 1);
      expect(result['reloadedButtonText'], '');
      expect(result['reloadedPressed'], 'true');
      expect(result['reloadedStyleCount'], 1);
      expect(result['rememberedAfterReload'], result['remembered']);
      final details = (result['messages'] as List)
          .where((message) => message['action'] == 'detail')
          .toList();
      expect(details.length, 2);
      for (final detail in details) {
        expect(detail['keijitype'], '1');
        expect(detail['genrecd'], '40');
        expect(detail['seqNo'], '507762');
        expect(detail['title'], '授業のお知らせ');
        expect(detail['body'], '本文の一行目\n二行目');
      }
    });
  }

  for (final scenario in ['rememberedMismatch', 'rememberedStorageDenied']) {
    test('$scenario does not resolve attachment-free detail', () async {
      final result = await _evaluate(
          _starDomHarness,
          [
            GakujoMessageStarScript.build(starredIds: ['1|40|507762'])
          ],
          scenario);
      expect(result['navigatedButtonText'], isNull);
      expect(result['navigatedPressed'], isNull);
      expect(result['navigatedStyleCount'], 0);
      expect(result['reloadedButtonText'], isNull);
      expect(result['reloadedPressed'], isNull);
      expect(result['reloadedStyleCount'], 0);
      expect((result['messages'] as List).length, 1);
      expect((result['messages'] as List).single['action'], 'toggle');
    });
  }

  test('reopen rotates keys, checks genre and 500-row list before navigation',
      () async {
    final result = await _open('ok');
    expect(result['result']['status'], 'ok');
    expect(result['beforeNavigationCount'], 3);
    final requests = (result['requests'] as List).cast<String>();
    expect(
        Uri.parse(requests[0]).queryParameters['_flowId'], 'KJW0001100-flow');
    expect(Uri.parse(requests[1]).queryParameters, {
      '_flowExecutionKey': 'first key',
      '_eventId': 'dispKeijiListGenre',
      'keijitype': '1',
      'genrecd': '40',
    });
    expect(Uri.parse(requests[2]).queryParameters, {
      '_flowExecutionKey': 'second-key',
      '_eventId': 'paging',
      '_displayCount': '500',
    });
    expect(Uri.parse(requests[3]).queryParameters, {
      '_flowExecutionKey': 'third-key',
      '_eventId': 'confirm',
      'keijitype': '1',
      'genrecd': '40',
      'seqNo': '507762',
    });
    expect(result['navigatedResponse'], 'detail response');
    expect(result['remembered'], {
      'keijitype': '1',
      'genrecd': '40',
      'seqNo': '507762',
      'title': '授業のお知らせ',
    });
  });

  test('reopen still navigates when session storage is unavailable', () async {
    final result = await _open('storageDenied');
    expect(result['result']['status'], 'ok');
    expect(result['navigatedResponse'], 'detail response');
    expect(result['remembered'], isNull);
  });

  for (final scenario in ['gone', 'wrongGenre']) {
    test('reopen $scenario preserves saved text without opening a detail',
        () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'gone');
      expect((result['requests'] as List).length, 3);
      expect(result['remembered'], isNull);
    });
  }

  for (final scenario in ['missing0', 'missing1', 'missing2', 'otherOrigin']) {
    test('reopen $scenario asks for sign in', () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'missing');
      expect((result['requests'] as List).length,
          scenario == 'otherOrigin' ? 0 : int.parse(scenario.substring(7)) + 1);
    });
  }

  for (final scenario in ['httpError', 'systemError', 'noKey']) {
    test('reopen $scenario returns error without navigation', () async {
      final result = await _open(scenario);
      expect(result['result']['status'], 'error');
      expect((result['requests'] as List).length, 1);
    });
  }
}

Future<Map<String, dynamic>> _open(String scenario) => _evaluate(
    _openHarness,
    [
      GakujoMessageStarScript.buildOpen(
        keijitype: '1',
        genrecd: '40',
        seqNo: '507762',
      )
    ],
    scenario);

Future<Map<String, dynamic>> _evaluate(
    String harness, List<String> scripts, String scenario) async {
  final directory = Directory.systemTemp.createTempSync('gakujo_message_star_');
  try {
    final harnessFile = File.fromUri(directory.uri.resolve('harness.js'))
      ..writeAsStringSync(harness, encoding: utf8);
    final inputFile = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({'scripts': scripts, 'scenario': scenario}),
          encoding: utf8);
    final result = await Process.run('node', [harnessFile.path, inputFile.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}

const _starDomHarness = r'''
const vm = require('node:vm');
const {scripts, scenario} = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
class Element {
  constructor(tag, value = '') {
    this.tagName = tag.toUpperCase(); this._text = value; this.children = [];
    this.attributes = {}; this.style = {}; this.listeners = {}; this.captures = {}; this.parentNode = null;
  }
  get textContent() { return this._text + this.children.map(e => e.textContent).join(''); }
  set textContent(value) { this._text = value; this.children = []; }
  get innerText() { return this.textContent; }
  setAttribute(key, value) { this.attributes[key] = value; }
  getAttribute(key) { return this.attributes[key] || null; }
  addEventListener(key, callback, capture) { this.listeners[key] = callback; this.captures[key] = capture; }
  removeEventListener(key, callback, capture) {
    if (this.listeners[key] === callback && this.captures[key] === capture) {
      delete this.listeners[key]; delete this.captures[key];
    }
  }
  appendChild(child) { return this.insertBefore(child, null); }
  insertBefore(child, before) {
    child.parentNode = this; child.ownerDocument = this.ownerDocument;
    const index = before ? this.children.indexOf(before) : this.children.length;
    this.children.splice(index, 0, child); return child;
  }
  remove() {
    if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(e => e !== this);
    this.parentNode = null;
  }
  get isConnected() { return this.parentNode !== null; }
  get nextElementSibling() {
    return this.parentNode.children[this.parentNode.children.indexOf(this) + 1] || null;
  }
  get cells() { return this.children.filter(e => e.tagName === 'TD' || e.tagName === 'TH'); }
  closest(selector) {
    for (let e = this; e; e = e.parentNode) if (e.matches(selector)) return e;
    return null;
  }
  matches(selector) {
    const parts = /^(\w+)(?:\.([\w-]+))?(?:\[(\w+)(?:\*="([^"]*)")?\])?$/.exec(selector);
    if (!parts || this.tagName !== parts[1].toUpperCase()) return false;
    if (parts[2] && this.attributes.class !== parts[2]) return false;
    if (parts[3] && !(parts[3] in this.attributes)) return false;
    if (parts[4] && !this.attributes[parts[3]].includes(parts[4])) return false;
    return true;
  }
  querySelectorAll(selector) {
    const result = [];
    for (const child of this.children) {
      if (child.matches(selector)) result.push(child);
      result.push(...child.querySelectorAll(selector));
    }
    return result;
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function doc(url) {
  const root = new Element('html'); root.ownerDocument = root;
  root.baseURI = base + url; root.URL = root.baseURI; root.location = {href: root.baseURI};
  root.createElement = tag => { const e = new Element(tag); e.ownerDocument = root; return e; };
  root.getElementById = id => id === 'main-frame-if' ? root.frame || null
    : root.querySelectorAll('style').find(e => e.id === id) || null;
  root.head = root.appendChild(root.createElement('head'));
  root.body = root.appendChild(root.createElement('body'));
  return root;
}
function add(parent, tag, text = '', attrs = {}) {
  const e = parent.ownerDocument.createElement(tag); e.textContent = text;
  Object.entries(attrs).forEach(([k,v]) => e.setAttribute(k,v)); return parent.appendChild(e);
}
function list(genre, allGenre = false, missingHeaders = false) {
  const d = doc('campussquare.do?_flowId=KJW0001100-flow');
  const table = add(d.body, 'table'); const header = add(table, 'tr');
  const labels = missingHeaders ? ['表題','未読','返信未読'] : allGenre
    ? ['ジャンル','表題','未読','返信未読','連絡通知期間','掲載日時'] : genre
    ? ['ジャンル','科目名','担当者','開講学期','曜日時限','表題','未読','返信未読','連絡通知期間','掲載日時']
    : ['掲載日時','表題','返信未読','ジャンル','所属','氏名','連絡通知期間'];
  const values = missingHeaders ? [null,'○','-'] : allGenre
    ? ['授業連絡',null,'○','-','2026/10/01～2026/11/01','2026/10/01 09:00'] : genre
    ? ['授業連絡','科目','担当教員','後期','月1',null,'','','2026/10/01～2026/11/01','2026/10/01 09:00']
    : ['2026/10/01 09:00',null,'','授業連絡','工学部','担当教員','2026/10/01～2026/11/01'];
  // Split headers across rows so lookup must include every th.
  let lowerHeader;
  function secondHeader() { return lowerHeader || (lowerHeader = add(table, 'tr')); }
  labels.forEach((label, index) => add(index < 5 ? header : secondHeader(), 'th', label));
  const row = add(table, 'tr');
  values.forEach(value => {
    const cell = add(row, 'td', value || '');
    if (value === null) d.heading = add(cell, 'a', '授業のお知らせ [新着]', {
      href: 'campussquare.do?_flowExecutionKey=temporary&_eventId=' +
        (genre || allGenre ? 'confirm' : 'displayMidoku') + '&keijitype=1&genrecd=40&seqNo=507762'
    });
  });
  return d;
}
function detail(attachment, longBody, noIds = false) {
  const d = doc('campussquare.do?' + (attachment || noIds ? '_flowExecutionKey=temporary' : 'keijitype=1&genrecd=40&seqNo=507762'));
  d.heading = add(d.body, 'span', '授業のお知らせ [新着]', {class: 'keiji-title'});
  add(d.body, 'span', scenario === 'detailDuplicateGenre'
    ? '[全学連絡通知 全学連絡通知]' : '[授業連絡通知 授業連絡]', {class: 'keiji-t-genre'});
  add(d.body, 'div', longBody ? '文'.repeat(4001) : ' 本文の一行目\n二行目 ', {class: 'keiji-naiyo'});
  for (const [label, value] of Object.entries({
    '連絡通知元': '担当教員', '連絡通知期間': '2026/10/01～2026/11/01',
    'メール送信': '送信済み', '送信日時': '2026/10/01 09:00', '添付ファイル': ''
  })) {
    const table = add(d.body, 'table', '', {class: 'keiji-normal'});
    add(add(table, 'tr'), 'th', label); const cell = add(add(table, 'tr'), 'td', value);
    if (label === '添付ファイル' && attachment) add(cell, 'a', '資料.pdf', {
      href: 'campussquare.do?_flowExecutionKey=temporary&_eventId=download&keijitype=1&genrecd=40&seqNo=507762&index=0'
    });
  }
  return d;
}
const isDetail = scenario.startsWith('detail');
const remembers = scenario.startsWith('remembered');
let inner = isDetail ? detail(scenario === 'detailAttachment', scenario === 'detailLong')
  : list(scenario === 'genre' || scenario === 'rememberedGenre', scenario === 'allGenre', scenario === 'missingHeaders');
const outer = scenario === 'iframe' || scenario === 'navigate' || remembers ? doc('campusportal.do') : inner;
if (outer !== inner) outer.frame = {contentWindow: {document: inner}};
const messages = []; const intervals = new Map(); let intervalId = 0;
const context = {document: outer, URL, Set, window: null};
context.window = context;
const storage = new Map();
const storageKey = '__MBG_MESSAGE_STARS_OPEN_MESSAGE';
// A separate top object catches accidental use of the frame's own storage.
context.top = {get sessionStorage() {
  if (scenario === 'rememberedStorageDenied') throw new Error('storage denied');
  return {setItem: (key, value) => storage.set(key, value), getItem: key => storage.get(key) || null};
}};
context.GakujoMessageStars = {postMessage: value => messages.push(JSON.parse(value))};
context.setInterval = fn => { intervals.set(++intervalId, fn); return intervalId; };
context.clearInterval = id => intervals.delete(id);
vm.createContext(context);
const counts = [], buttonTexts = [], pressedStates = [], intervalCounts = [], listenerCounts = [];
const styleCounts = [], styleTexts = [], outerStyleCounts = [], rowTexts = [];
const originalRowText = inner.heading.closest('tr')?.innerText || null;
let beforeTitle, label, prevented = false, stopped = false, oldButton;
scripts.forEach((script, index) => {
  vm.runInContext(script, context);
  const buttons = inner.querySelectorAll('button');
  counts.push(buttons.length);
  buttonTexts.push(buttons[0] ? buttons[0].textContent : null);
  pressedStates.push(buttons[0] ? buttons[0].getAttribute('aria-pressed') : null);
  const styles = inner.querySelectorAll('style');
  styleCounts.push(styles.length);
  styleTexts.push(inner.getElementById('mbg-message-star-style')?.textContent || null);
  outerStyleCounts.push(outer.querySelectorAll('style').length);
  rowTexts.push(inner.heading.closest('tr')?.innerText || null);
  intervalCounts.push(intervals.size);
  listenerCounts.push(inner.listeners.click ? 1 : 0);
  if (index === 0 && buttons[0]) {
    oldButton = buttons[0]; label = oldButton.getAttribute('aria-label');
    beforeTitle = oldButton.nextElementSibling === inner.heading;
    oldButton.listeners.click({preventDefault() { prevented = true; }, stopPropagation() { stopped = true; }});
  }
  if (index === 3) oldButton.listeners.click({preventDefault() {}, stopPropagation() {}});
});
let navigatedTitle, navigatedButtonText, navigatedPressed, navigatedStyleCount;
let reloadedButtonText, reloadedPressed, reloadedStyleCount, capture, oldListListenerRemoved;
let rememberedBeforeClick, remembered, rememberedAfterReload;
if (scenario === 'navigate' || remembers) {
  const oldList = inner;
  if (remembers) {
    rememberedBeforeClick = JSON.parse(storage.get(storageKey) || 'null');
    capture = inner.captures.click;
    inner.listeners.click({target: add(inner.heading, 'span')});
    remembered = JSON.parse(storage.get(storageKey) || 'null');
  }
  inner = detail(false, false, remembers); outer.frame.contentWindow.document = inner;
  if (scenario === 'rememberedMismatch') inner.heading.textContent = '別の連絡通知';
  // The detail need not retain the list's [新着] suffix.
  else if (remembers) inner.heading.textContent = '授業のお知らせ';
  for (const callback of intervals.values()) callback();
  oldListListenerRemoved = !oldList.listeners.click;
  navigatedTitle = inner.heading.textContent;
  navigatedButtonText = inner.querySelector('button')?.textContent ?? null;
  navigatedPressed = inner.querySelector('button')?.getAttribute('aria-pressed') || null;
  navigatedStyleCount = inner.querySelectorAll('style').length;
  if (remembers) {
    const heading = inner.heading.textContent;
    inner = detail(false, false, true); inner.heading.textContent = heading;
    outer.frame.contentWindow.document = inner;
    for (const callback of intervals.values()) callback();
    reloadedButtonText = inner.querySelector('button')?.textContent ?? null;
    reloadedPressed = inner.querySelector('button')?.getAttribute('aria-pressed') || null;
    reloadedStyleCount = inner.querySelectorAll('style').length;
    rememberedAfterReload = JSON.parse(storage.get(storageKey) || 'null');
  }
}
process.stdout.write(JSON.stringify({counts, buttonTexts, pressedStates, styleCounts, styleTexts,
  outerStyleCounts, originalRowText, rowTexts, intervalCounts, listenerCounts, beforeTitle, label,
  prevented, stopped, messages, navigatedTitle, navigatedButtonText, navigatedPressed,
  navigatedStyleCount, reloadedButtonText, reloadedPressed, reloadedStyleCount, capture,
  oldListListenerRemoved, rememberedBeforeClick, remembered, rememberedAfterReload}));
''';

const _openHarness = r'''
const vm = require('node:vm');
const {scripts, scenario} = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const script = scripts[0];
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const requests = [];
const link = href => ({getAttribute: () => href, textContent: '  授業のお知らせ  [新着]  '});
function makeDoc(index) {
  const missing = scenario === 'missing' + index;
  const hasKey = scenario !== 'noKey';
  return {
    title: missing ? 'ログイン' : scenario === 'systemError' ? 'SYSTEM ERROR' : '連絡通知一覧',
    body: {textContent: ''},
    querySelector(selector) {
      if (selector.startsWith('a[')) return hasKey && index !== 1
        ? link('campussquare.do?_flowExecutionKey=' + (index === 0 ? 'first%20key' : 'third-key')) : null;
      return hasKey && index === 1 ? {value: 'second-key'} : null;
    },
    querySelectorAll() {
      if (index !== 2 || scenario === 'gone') return [];
      return [link('campussquare.do?_flowExecutionKey=third-key&_eventId=confirm&keijitype=1&genrecd=' +
        (scenario === 'wrongGenre' ? '41' : '40') + '&seqNo=507762')];
    }
  };
}
// Three list responses followed by the detail response consumed by WebView.
const responses = [0, 1, 2, 3].map(index => ({
  status: scenario === 'httpError' ? 500 : 200,
  text: index === 3 ? 'detail response' : String(index)
}));
class XHR {
  open(method, url, async) { this.url = url; this.async = async; }
  send() {
    requests.push(this.url);
    const response = responses.shift();
    if (!response) throw new Error('unexpected detail fetch');
    this.status = response.status; this.responseText = response.text;
  }
}
const context = {URL, XMLHttpRequest: XHR,
  DOMParser: class { parseFromString(text) { return makeDoc(Number(text)); } },
  location: {origin: scenario === 'otherOrigin' ? 'https://login.example.test' : 'https://gakujo.iess.niigata-u.ac.jp'}
};
const storage = new Map();
context.window = {top: {get sessionStorage() {
  if (scenario === 'storageDenied') throw new Error('storage denied');
  return {setItem: (key, value) => storage.set(key, value)};
}}};
const result = JSON.parse(vm.runInNewContext(script, context));
const beforeNavigationCount = requests.length;
let navigatedResponse;
if (result.status === 'ok') {
  const navigation = new XHR(); navigation.open('GET', result.url, true); navigation.send();
  navigatedResponse = navigation.responseText;
}
const remembered = JSON.parse(storage.get('__MBG_MESSAGE_STARS_OPEN_MESSAGE') || 'null');
process.stdout.write(JSON.stringify({result, requests, beforeNavigationCount, navigatedResponse, remembered}));
''';
