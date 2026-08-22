import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_report_draft_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds report submission draft autosave script', () {
    final script = GakujoReportDraftScript.build();

    expect(script, contains('__MBG_REPORT_DRAFT_VERSION'));
    expect(script, contains('var version = 4;'));
    expect(script, contains("document.querySelectorAll('iframe,frame')"));
    expect(script, contains('mbg-report-draft:v1:'));
    expect(script, contains('localStorage'));
    expect(script,
        contains("doc.querySelectorAll('textarea,input,[contenteditable]')"));
    expect(script, contains('hasDraftWorthyField'));
    expect(script, contains('function stablePageTextForKey'));
    expect(script, contains('残り約'));
    expect(script, contains('前回ログイン日時'));
    expect(script, contains('レポート・小テスト・アンケート提出'));
    expect(script, contains('レポート提出(?!日)'));
    expect(script, contains('アンケート(?:提出(?!期限)|回答)'));
    expect(script, contains('下書きを保存しました'));
    expect(script, contains('保存済みの下書きを復元しました'));
    expect(script, contains('下書きを削除'));
    expect(script, contains('function removeStatus'));
    expect(script, contains('beforeunload'));
    expect(script, contains('form.addEventListener'));
    expect(script, isNot(contains('field.innerHTML')));
  });

  test(
      'stores and restores contenteditable display text without executing HTML',
      () async {
    const payload = '<img src=x onerror="globalThis.xssExecuted=true">安全な本文';
    final result = await _evaluateContentEditableDraft(
      initialHtml: payload,
      initialText: '安全な本文',
    );

    expect(result['storedValue'], '安全な本文');
    expect(result['restoredText'], '安全な本文');
    expect(result['xssExecutionCount'], 0);
  });

  test('restores legacy HTML draft values as literal text', () async {
    const legacyValue = '<img src=x onerror="globalThis.xssExecuted=true">旧下書き';
    final result = await _evaluateContentEditableDraft(
      initialHtml: '保存形式を作るための本文',
      initialText: '保存形式を作るための本文',
      legacyValue: legacyValue,
    );

    expect(result['restoredText'], legacyValue);
    expect(result['xssExecutionCount'], 0);
  });

  test('restores multiline contenteditable drafts with visible line breaks',
      () async {
    const text = '一段落目\n二段落目';
    final result = await _evaluateContentEditableDraft(
      initialHtml: '<p>一段落目</p><p>二段落目</p>',
      initialText: text,
    );

    expect(result['storedValue'], text);
    expect(result['restoredText'], text);
    expect(result['restoredHtml'], '一段落目<br>二段落目');
    expect(result['xssExecutionCount'], 0);
  });
}

Future<Map<String, dynamic>> _evaluateContentEditableDraft({
  required String initialHtml,
  required String initialText,
  String? legacyValue,
}) async {
  final result = await Process.run(
      'node',
      [
        '-e',
        _nodeDomHarness,
        GakujoReportDraftScript.build(),
        jsonEncode({
          'initialHtml': initialHtml,
          'initialText': initialText,
          if (legacyValue != null) 'legacyValue': legacyValue,
        }),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _nodeDomHarness = r'''
const vm = require('node:vm');
const generatedScript = process.argv[1];
const spec = JSON.parse(process.argv[2]);
const storageValues = new Map();
let xssExecutionCount = 0;

class FakeEvent {
  constructor(type, options) {
    this.type = type;
    Object.assign(this, options || {});
  }
}

class FakeStorage {
  get length() { return storageValues.size; }
  getItem(key) { return storageValues.get(key) || null; }
  setItem(key, value) { storageValues.set(key, String(value)); }
  removeItem(key) { storageValues.delete(key); }
  key(index) { return Array.from(storageValues.keys())[index] || null; }
}

class FakeStatusElement {
  constructor(tag) {
    this.tagName = tag.toUpperCase();
    this.id = '';
    this.type = '';
    this.textContent = '';
    this.style = {};
    this.children = [];
    this.listeners = {};
  }

  appendChild(child) { this.children.push(child); }
  addEventListener(type, callback) { this.listeners[type] = callback; }
  remove() {}
}

function findById(node, id) {
  if (!node) return null;
  if (node.id === id) return node;
  for (const child of node.children || []) {
    const match = findById(child, id);
    if (match) return match;
  }
  return null;
}

class FakeContentEditable {
  constructor(doc, html, text) {
    this.tagName = 'DIV';
    this.ownerDocument = doc;
    this.disabled = false;
    this.readOnly = false;
    this.style = {};
    this.listeners = {};
    this.attributes = {contenteditable: 'true', name: 'answer'};
    this._innerHTML = html;
    this._text = text;
    this.parentNode = {
      insertBefore: (node) => { doc.insertedStatus = node; }
    };
  }

  get id() { return ''; }
  get innerHTML() { return this._innerHTML; }
  set innerHTML(value) {
    this._innerHTML = String(value);
    if (/<script\b|\bonerror\s*=|\bonload\s*=/i.test(this._innerHTML)) {
      xssExecutionCount += 1;
    }
    this._text = this._innerHTML.replace(/<[^>]*>/g, '');
  }
  get innerText() { return this._text; }
  set innerText(value) { this.textContent = value; }
  get textContent() { return this._text; }
  set textContent(value) {
    this._text = String(value);
    this._innerHTML = this._text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  appendChild(node) {
    if (node.nodeType === 3) {
      const text = String(node.textContent || '');
      this._text += text;
      this._innerHTML += text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      return node;
    }
    if (node.tagName === 'BR') {
      this._text += '\n';
      this._innerHTML += '<br>';
    }
    return node;
  }

  getAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name)
      ? this.attributes[name]
      : null;
  }
  getClientRects() { return [{}]; }
  matches(selector) { return selector === '[contenteditable]'; }
  closest() { return null; }
  addEventListener(type, callback) {
    (this.listeners[type] ||= []).push(callback);
  }
  dispatchEvent(event) {
    for (const callback of this.listeners[event.type] || []) callback(event);
    return true;
  }
}

function createPage(html, text, storage) {
  const bodyClone = {
    innerText: 'レポート提出 本文 入力',
    textContent: 'レポート提出 本文 入力',
    querySelectorAll() { return []; }
  };
  const document = {
    title: 'レポート提出',
    location: {
      href: 'https://gakujo.example/report/input',
      pathname: '/report/input'
    },
    defaultView: null,
    insertedStatus: null,
    body: { cloneNode() { return bodyClone; } },
    createElement(tag) { return new FakeStatusElement(tag); },
    createTextNode(text) { return {nodeType: 3, textContent: String(text)}; },
    getElementById(id) { return findById(this.insertedStatus, id); },
    querySelectorAll(selector) {
      if (selector === 'textarea,input,[contenteditable]') return [this.field];
      return [];
    }
  };
  const window = {
    document,
    localStorage: storage,
    CSS: null,
    Event: FakeEvent,
    InputEvent: FakeEvent,
    getComputedStyle() { return {display: 'block', visibility: 'visible'}; },
    clearTimeout() {},
    setTimeout(callback) { callback(); return 1; },
    clearInterval() {},
    setInterval() { return 1; },
    addEventListener() {}
  };
  window.window = window;
  document.defaultView = window;
  document.field = new FakeContentEditable(document, html, text);
  return {window, document, field: document.field};
}

function runPage(page) {
  vm.runInNewContext(generatedScript, {
    window: page.window,
    document: page.document,
    console: {log() {}}
  });
}

const storage = new FakeStorage();
const savingPage = createPage(spec.initialHtml, spec.initialText, storage);
runPage(savingPage);
savingPage.field.dispatchEvent(new FakeEvent('input', {bubbles: true}));

const key = storage.key(0);
if (!key) throw new Error('Draft was not saved');
const savedDraft = JSON.parse(storage.getItem(key));
const storedValue = savedDraft.fields[0].value;
if (Object.prototype.hasOwnProperty.call(spec, 'legacyValue')) {
  savedDraft.fields[0].value = spec.legacyValue;
  storage.setItem(key, JSON.stringify(savedDraft));
}

const restoringPage = createPage('', '', storage);
runPage(restoringPage);

process.stdout.write(JSON.stringify({
  storedValue,
  restoredText: restoringPage.field.textContent,
  restoredHtml: restoringPage.field.innerHTML,
  xssExecutionCount
}));
''';
