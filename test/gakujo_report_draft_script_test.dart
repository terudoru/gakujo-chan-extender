import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_report_draft_script.dart';
import 'package:test/test.dart';

void main() {
  test('failed storage keeps pending text and reports failure until retry',
      () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '未保存の本文', initialText: '未保存の本文', scenario: 'saveFailure');
    expect(result['failureStatus'], contains('保存できませんでした'));
    expect(result['dirtyAfterFailure'], isTrue);
    expect(result['pendingAfterFailure'], isTrue);
    expect(result['storedAfterRetry'], '未保存の本文');
  });

  test('failed deletion can be retried without claiming success', () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '削除対象', initialText: '削除対象', scenario: 'deleteFailure');
    expect(result['failureStatus'], contains('削除できませんでした'));
    expect(result['hasRetry'], isTrue);
    expect(result['remainingAfterRetry'], 0);
  });

  test('deleted drafts stay deleted through debounce and pagehide', () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '削除対象',
        initialText: '削除対象',
        scenario: 'deletePending',
        deferSaveTimer: true);
    expect(result['remainingAfterPageHide'], 0);
    expect(result['storedAfterNewInput'], '新しい入力');
  });

  test('failed removal of empty text does not restore the older draft',
      () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '古い下書き', initialText: '古い下書き', scenario: 'clearFailure');
    expect(result['textAfterUpdate'], '');
    expect(result['dirtyAfterFailure'], isTrue);
    expect(result['failureStatus'], contains('保存できませんでした'));
  });

  test('builds report submission draft autosave script', () {
    final script = GakujoReportDraftScript.build();

    expect(script, contains('__MBG_REPORT_DRAFT_VERSION'));
    expect(script, contains('var version = 9;'));
    expect(script, contains("document.querySelectorAll('iframe,frame')"));
    expect(script, contains('mbg-report-draft:v2:'));
    expect(script, contains('localStorage'));
    expect(
        script,
        contains(
            "doc.querySelectorAll('textarea,input,select,[contenteditable]')"));
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
    expect(script, contains('pagehide'));
    expect(script, contains('visibilitychange'));
    expect(script, contains('function currentDraftContext'));
    expect(script, contains('#mbg-report-draft-status'));
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

  test('restores a field replaced in the same document after timeout',
      () async {
    final result = await _evaluateContentEditableDraft(
      initialHtml: 'タイムアウト前の入力',
      initialText: 'タイムアウト前の入力',
      replaceFieldInSameDocument: true,
    );

    expect(result['sameDocumentRestoredText'], 'タイムアウト前の入力');
  });

  test('saves immediately when the page is hidden before debounce completes',
      () async {
    final result = await _evaluateContentEditableDraft(
      initialHtml: '画面遷移直前の入力',
      initialText: '画面遷移直前の入力',
      deferSaveTimer: true,
      firePageHide: true,
    );

    expect(result['storedValue'], '画面遷移直前の入力');
  });

  test('keeps the pending value when timeout replaces the form before unload',
      () async {
    final result = await _evaluateContentEditableDraft(
      initialHtml: 'フォーム消失直前の入力',
      initialText: 'フォーム消失直前の入力',
      deferSaveTimer: true,
      dropFieldBeforePageHide: true,
      firePageHide: true,
    );

    expect(result['storedValue'], 'フォーム消失直前の入力');
  });

  for (final kind in ['textarea', 'text', 'checkbox', 'radio', 'select']) {
    for (final event in ['pagehide', 'beforeunload', 'visibilitychange']) {
      test('saves $kind edited before binding on $event', () async {
        final result = await _evaluateDraft({
          'scenario': 'beforeBinding',
          'kind': kind,
          'edited': true,
          'event': event,
        });
        expect(result['bound'], isTrue);
        expect(result['touched'], isTrue);
        expect(result['dirty'], isTrue);
        expect(result['countBeforeHide'], 0);
        expect(result['count'], 1);
        expect(result['savedValue'], result['expectedValue']);
      });
    }
  }

  for (final kind in [
    'textarea',
    'text',
    'checkbox',
    'radio',
    'select',
    'contenteditable',
  ]) {
    test('does not save untouched prefilled $kind on pagehide', () async {
      final result = await _evaluateDraft({
        'scenario': 'beforeBinding',
        'kind': kind,
        'edited': false,
        'event': 'pagehide',
      });
      expect(result['bound'], isTrue);
      expect(result['touched'], isFalse);
      expect(result['dirty'], isFalse);
      expect(result['count'], 0);
    });
  }

  test('counter changes save one draft and restore the latest text', () async {
    final result = await _evaluateDraftScenario('counterLatest');
    expect(result['count'], 1);
    expect(result['restoredText'], '文字数が変わった後の最新の本文');
    expect(result['fieldKey'], 'textarea||gakuComment|0');
    expect(result['savedStatus'], matches(r'下書きを保存しました（\d{2}:\d{2}）'));
    expect(result['restoredStatus'],
        matches(r'保存済みの下書きを復元しました（\d+/\d+ \d{2}:\d{2} 保存）'));
  });

  test('fresh and nonzero counter pages have identical v2 keys', () async {
    final result = await _evaluateDraftScenario('counterKeys');
    expect(result['keys'], everyElement(result['keys'][0]));
    expect(result['elementKeys'], everyElement(result['elementKeys'][0]));
    expect(result['keys'][0], startsWith('mbg-report-draft:v2:'));
    expect(result['anonymousKeys'], everyElement(result['anonymousKeys'][0]));
    expect(result['differentAssignmentKey'], isNot(result['keys'][0]));
  });

  test('document key is cached until fields are replaced', () async {
    final result = await _evaluateDraftScenario('keyCache');
    expect(result['cachedKey'], result['initialKey']);
    expect(result['replacementKey'], isNot(result['initialKey']));
  });

  test('restores choices at defaults and dispatches input and change',
      () async {
    final result = await _evaluateDraftScenario('choicesDefault');
    expect(result['radio'], [false, true]);
    expect(result['checkbox'], [false, true]);
    expect(result['select'], ['b']);
    expect(result['multiple'], ['b', 'c']);
    expect(
        result['kinds'], ['radio', 'checkbox', 'checkbox', 'select', 'select']);
    expect(result['eventsDispatched'], isTrue);
    expect(result['eventsAfterSecondUpdate'], result['eventsAfterRestore']);
    expect(result['pendingAfterRestore'], isFalse);
    expect(result['restoredSavedAt'], result['originalSavedAt']);
    expect(result['touchedAfterRestore'], isFalse);
    expect(result['dirtyAfterRestore'], isFalse);
    expect(result['unchangedAfterHide'], isTrue);
  });

  test('restored text stays untouched through rebinding and pagehide',
      () async {
    final result = await _evaluateDraftScenario('restoredUntouched');
    expect(result['restoredText'], '保存済みの本文');
    expect(result['touched'], isFalse);
    expect(result['dirty'], isFalse);
    expect(result['unchangedAfterHide'], isTrue);
  });

  test('does not restore choices touched even if saved back at defaults',
      () async {
    final result = await _evaluateDraftScenario('choicesTouched');
    expect(result['radio'], [true, false]);
    expect(result['checkbox'], [true, false]);
    expect(result['select'], ['a']);
    expect(result['multiple'], ['a']);
  });

  test('does not restore choices changed from defaults without events',
      () async {
    final result = await _evaluateDraftScenario('choicesNonDefault');
    expect(result['radio'], [false, true]);
    expect(result['checkbox'], [false, true]);
    expect(result['select'], ['c']);
    expect(result['multiple'], ['c']);
    expect(result['eventsAfterRestore'], 0);
  });

  test('preserves unchecked and empty choice answers', () async {
    final result = await _evaluateDraftScenario('choicesEmpty');
    expect(result['radio'], [false, false]);
    expect(result['checkbox'], [false, false]);
    expect(result['select'], isEmpty);
    expect(result['multiple'], isEmpty);
    expect(result['count'], 1);
  });

  test('checkboxes match by name and value after reordering', () async {
    final result = await _evaluateDraftScenario('choicesReordered');
    expect(result['sameKey'], isTrue);
    expect(result['checksByValue'], {'a': false, 'b': true});
  });

  test('choice-only quizzes are draft-worthy and login forms are ignored',
      () async {
    final result = await _evaluateDraftScenario('choiceOnly');
    expect(result['quizBound'], isTrue);
    expect(result['unrelatedBound'], isFalse);
    expect(result['loginBound'], isFalse);
    expect(result['count'], 1);
  });

  test('conflicting text requires the replacement button', () async {
    final result = await _evaluateDraftScenario('conflict');
    expect(result['beforeReplace'], 'サーバー側の一時保存');
    expect(
        result['beforeStatus'], matches(r'保存済みの下書きがあります（\d+/\d+ \d{2}:\d{2}）'));
    expect(result['storedAfterPageHide'], '端末の下書き');
    expect(result['afterReplace'], '端末の下書き');
    expect(result['afterStatus'], contains('保存済みの下書きを復元しました'));
    expect(result['replaceHidden'], isTrue);
    expect(result['events'], containsAll(['input', 'change']));
  });

  for (final event in ['ArrowLeft', 'Ctrl+C', 'change']) {
    test('unchanged $event preserves the newer draft and replacement prompt',
        () async {
      final result = await _evaluateDraft({
        'scenario': 'conflictNavigation',
        'event': event,
      });
      expect(result['storedUnchanged'], isTrue);
      expect(result['replaceVisible'], isTrue);
      expect(result['pending'], isFalse);
      expect(result['touched'], isFalse);
      expect(result['storedAfterEdit'], '実際の編集');
      if (event == 'Ctrl+C') {
        expect(result['inputSavedUnchangedValue'], isTrue);
      }
    });
  }

  for (final event in ['pagehide', 'beforeunload', 'visibilitychange']) {
    test('restoring a checkbox preserves a conflicting draft on $event',
        () async {
      final result = await _evaluateDraft({
        'scenario': 'conflictWithCheckbox',
        'event': event,
      });
      expect(result['text'], 'サーバー側の一時保存');
      expect(result['checkbox'], isTrue);
      expect(result['touched'], isFalse);
      expect(result['dirty'], isFalse);
      expect(result['replaceVisible'], isTrue);
      expect(result['unchangedAfterHide'], isTrue);
      expect(result['storedAfterInput'], '実際の編集');
    });
  }

  for (final multiple in [false, true]) {
    test('skips a select with a missing saved option (multiple: $multiple)',
        () async {
      final result = await _evaluateDraft({
        'scenario': 'missingSelectOption',
        'multiple': multiple,
      });
      expect(result['selection'], ['a']);
      expect(result['events'], isEmpty);
      expect(result['status'], isNot(contains('復元しました')));
      expect(result['unchangedAfterHide'], isTrue);
    });
  }

  test('v2 heading joins course and assignment table values', () async {
    final result = await _evaluateDraftScenario('heading');
    expect(result['heading'], '263T0506 プログラミング基礎Ⅰ / レポート２');
    expect(result['fallback'], 'レポート提出');
  });

  test('lists v1 and v2 drafts from top and main frame newest first', () async {
    final result = await _evaluateDraftScenario('list');
    final entries = result['entries'] as List;
    expect(entries.map((entry) => entry['version']), [2, 1]);
    expect(entries[0]['heading'], '科目 / レポート２');
    expect(entries[0]['preview'], 'あ' * 120);
    expect(entries[0]['text'], '${'あ' * 130}\n\n次の回答');
    expect(entries[1]['heading'], '旧タイトル');
    expect(entries[1]['text'], '<b>旧本文</b>');
    expect(result['expiredAndInvalidRemoved'], isTrue);
    expect(result['unrelatedRetained'], isTrue);
    expect(result['crossOriginCount'], 2);
  });

  test('deletes only the given key and cancels its pending save', () async {
    final result = await _evaluateDraftScenario('delete');
    expect(result['deleted'], isTrue);
    expect(result['targetRemovedEverywhere'], isTrue);
    expect(result['otherKeysRetained'], isTrue);
    expect(result['pendingCancelled'], isTrue);
    expect(result['remainingAfterPageHide'], isFalse);
    expect(result['failedDelete'], isFalse);
    expect(result['retainedAfterFailure'], isTrue);
  });

  test('binding cleans expired and malformed v1 and v2 drafts', () async {
    final result = await _evaluateDraftScenario('cleanup');
    expect(result['remainingKeys'], ['mbg-report-draft:v1:valid', 'other-key']);
  });
}

Future<Map<String, dynamic>> _evaluateContentEditableDraft({
  required String initialHtml,
  required String initialText,
  String? legacyValue,
  bool replaceFieldInSameDocument = false,
  bool deferSaveTimer = false,
  bool firePageHide = false,
  bool dropFieldBeforePageHide = false,
  String? scenario,
}) async {
  return _evaluateDraft({
    'initialHtml': initialHtml,
    'initialText': initialText,
    if (legacyValue != null) 'legacyValue': legacyValue,
    'replaceFieldInSameDocument': replaceFieldInSameDocument,
    'deferSaveTimer': deferSaveTimer,
    'firePageHide': firePageHide,
    'dropFieldBeforePageHide': dropFieldBeforePageHide,
    'scenario': scenario,
  });
}

Future<Map<String, dynamic>> _evaluateDraftScenario(String scenario) {
  return _evaluateDraft({'scenario': scenario});
}

Future<Map<String, dynamic>> _evaluateDraft(Map<String, dynamic> spec) async {
  final directory =
      await Directory.systemTemp.createTemp('gakujo-report-draft-');
  try {
    final harness = File('${directory.path}/harness.cjs');
    final input = File('${directory.path}/input.json');
    await harness.writeAsString(_nodeDomHarness);
    await input.writeAsString(jsonEncode({
      'generatedScript': GakujoReportDraftScript.build(),
      'spec': spec,
      'listScript': GakujoReportDraftScript.buildList(),
      'deleteScript': GakujoReportDraftScript.buildDelete(
          'mbg-report-draft:v2:delete"\\key'),
    }));
    final result = await Process.run('node', [harness.path, input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    await directory.delete(recursive: true);
  }
}

const _nodeDomHarness = r'''
const vm = require('node:vm');
const {generatedScript, spec, listScript, deleteScript} = JSON.parse(
  require('node:fs').readFileSync(process.argv[2], 'utf8')
);
const storageValues = new Map();
let xssExecutionCount = 0;
let nextTimerId = 1;
const pendingTimers = new Map();

class FakeEvent {
  constructor(type, options) {
    this.type = type;
    Object.assign(this, options || {});
  }
}

class FakeStorage {
  constructor(values = storageValues) { this.values = values; }
  get length() { return this.values.size; }
  getItem(key) { return this.values.get(key) || null; }
  setItem(key, value) {
    if (this.failWrite) throw new Error('QuotaExceededError');
    this.values.set(key, String(value));
  }
  removeItem(key) {
    if (this.failRemove) throw new Error('SecurityError');
    this.values.delete(key);
  }
  key(index) { return Array.from(this.values.keys())[index] || null; }
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
    this.events = [];
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
    this.events.push(event.type);
    for (const callback of this.listeners[event.type] || []) callback(event);
    return true;
  }
}

class FakeControl extends FakeContentEditable {
  constructor(doc, tag, attributes = {}, options = {}) {
    super(doc, '', '');
    this.tagName = tag.toUpperCase();
    this.attributes = attributes;
    this.value = options.value || '';
    this.defaultValue = this.value;
    this.defaultChecked = !!options.defaultChecked;
    this._checked = this.defaultChecked;
    this.options = options.options || [];
    this.multiple = !!options.multiple;
  }
  get id() { return this.attributes.id || ''; }
  get value() { return this._value; }
  set value(value) { this._value = String(value); }
  get checked() { return this._checked; }
  set checked(value) {
    if (value && this.attributes.type === 'radio' && this.attributes.name) {
      for (const field of this.ownerDocument.fields || []) {
        if (field !== this && field.attributes.type === 'radio' &&
            field.attributes.name === this.attributes.name) field._checked = false;
      }
    }
    this._checked = value;
  }
  matches() { return false; }
  closest(selector) {
    return selector === 'form' ? null : {cloneNode: () => textClone(this.ownerDocument, true)};
  }
}

function textClone(doc, rowOnly = false) {
  let removed = false;
  const counter = {
    getAttribute(name) {
      return name === 'id' ? 'gakuCommentCOUNT' : 'countField';
    },
    remove() { removed = true; }
  };
  return {
    get innerText() {
      const base = rowOnly ? '' : doc.pageText;
      return base + (doc.counter == null ? '' :
        ' 入力文字数：' + (removed ? '' : doc.counter) + '/200文字');
    },
    get textContent() { return this.innerText; },
    querySelectorAll(selector) {
      return selector === '[id],[class]' && doc.counterElement ? [counter] : [];
    }
  };
}

function createPage(html, text, storage, options = {}) {
  const document = {
    title: options.title || 'レポート提出',
    pageText: options.pageText || 'レポート提出 本文 入力',
    counter: options.counter,
    counterElement: options.counterElement,
    location: {
      href: 'https://gakujo.example/report/input',
      pathname: '/report/input'
    },
    defaultView: null,
    insertedStatus: null,
    listeners: {},
    body: { cloneNode() { return textClone(document); } },
    createElement(tag) { return new FakeStatusElement(tag); },
    createTextNode(text) { return {nodeType: 3, textContent: String(text)}; },
    getElementById(id) { return findById(this.insertedStatus, id); },
    addEventListener(type, callback) {
      (this.listeners[type] ||= []).push(callback);
    },
    querySelectorAll(selector) {
      if (selector === 'textarea,input,select,[contenteditable]') {
        return this.fields || (this.field ? [this.field] : []);
      }
      if (selector === 'iframe,frame') return this.frame ? [this.frame] : [];
      if (selector === 'tr') return this.rows || [];
      return [];
    },
    querySelector(selector) {
      return selector === 'iframe#main-frame-if' ? this.frame || null : null;
    }
  };
  const window = {
    document,
    localStorage: storage,
    CSS: null,
    listeners: {},
    Event: FakeEvent,
    InputEvent: FakeEvent,
    HTMLTextAreaElement: FakeControl,
    HTMLInputElement: FakeControl,
    getComputedStyle() { return {display: 'block', visibility: 'visible'}; },
    clearTimeout(id) { pendingTimers.delete(id); },
    setTimeout(callback) {
      const id = nextTimerId++;
      if (spec.deferSaveTimer || this.deferSaveTimer) {
        pendingTimers.set(id, callback);
      } else {
        callback();
      }
      return id;
    },
    clearInterval() {},
    setInterval() { return 1; },
    addEventListener(type, callback) {
      (this.listeners[type] ||= []).push(callback);
    }
  };
  window.window = window;
  document.defaultView = window;
  document.field = new FakeContentEditable(document, html, text);
  return {window, document, field: document.field};
}

function runPage(page, script = generatedScript) {
  return vm.runInNewContext(script, {
    window: page.window,
    document: page.document,
    console: {log() {}}
  });
}

function statusFor(page) {
  return page.document.getElementById('mbg-report-draft-status-label').textContent;
}

function textPage(storage, options = {}) {
  const page = createPage('', '', storage, options);
  page.field = new FakeControl(page.document, 'textarea',
    options.anonymous ? {} : {name: 'gakuComment', id: 'gakuComment'},
    {value: options.value});
  page.document.field = page.field;
  return page;
}

function choicePage(storage, options = {}) {
  const page = createPage('', '', storage, options);
  const doc = page.document;
  function input(type, name, value, defaultChecked = false) {
    return new FakeControl(doc, 'input', {type, name}, {value, defaultChecked});
  }
  function select(name, multiple) {
    return new FakeControl(doc, 'select', {name}, {
      multiple,
      options: ['a', 'b', 'c'].map(value => ({
        value, selected: value === 'a', defaultSelected: multiple && value === 'a'
      }))
    });
  }
  doc.fields = [
    input('radio', 'answer', 'a', true), input('radio', 'answer', 'b'),
    input('checkbox', 'checks', 'a', true), input('checkbox', 'checks', 'b'),
    select('single', false), select('multiple', true)
  ];
  return page;
}

function setSelection(field, values) {
  for (const option of field.options) option.selected = values.includes(option.value);
}

function choiceState(page) {
  const fields = page.document.fields;
  const selected = field => field.options.filter(option => option.selected).map(option => option.value);
  return {
    radio: fields.slice(0, 2).map(field => field.checked),
    checkbox: fields.slice(2, 4).map(field => field.checked),
    select: selected(fields[4]), multiple: selected(fields[5])
  };
}

function hidePage(page) {
  for (const callback of page.window.listeners.pagehide || []) callback();
}

function runExtendedScenario() {
  const storage = new FakeStorage();
  if (spec.scenario === 'beforeBinding') {
    const page = textPage(storage, {value: 'Server value'});
    let expectedValue = 'Typed before binding';
    if (spec.kind === 'contenteditable') {
      page.field = new FakeContentEditable(page.document, 'Server value', 'Server value');
    } else if (spec.kind !== 'textarea') {
      page.field = new FakeControl(page.document,
        spec.kind === 'select' ? 'select' : 'input',
        {name: 'answer', type: spec.kind, 'aria-label': '回答'}, {
          value: 'Server value', defaultChecked: true,
          options: ['a', 'b'].map(value => ({
            value, selected: value === 'a', defaultSelected: value === 'a'
          }))
        });
    }
    page.document.field = page.field;
    if (spec.edited) {
      if (spec.kind === 'checkbox' || spec.kind === 'radio') {
        page.field.checked = false;
        expectedValue = spec.kind === 'radio' ? null : false;
      } else if (spec.kind === 'select') {
        setSelection(page.field, ['b']);
        expectedValue = ['b'];
      } else {
        page.field.value = expectedValue;
      }
    }
    runPage(page);
    const touched = !!page.field.__MBG_REPORT_DRAFT_TOUCHED;
    const dirty = !!page.field.__MBG_REPORT_DRAFT_DIRTY;
    const countBeforeHide = storage.length;
    const target = spec.event === 'visibilitychange' ? page.document : page.window;
    page.document.visibilityState = 'hidden';
    for (const callback of target.listeners[spec.event] || []) callback();
    const draft = storage.length ? JSON.parse(storage.getItem(storage.key(0))) : null;
    return {bound: !!page.field.__MBG_REPORT_DRAFT_BOUND,
      touched, dirty, countBeforeHide, count: storage.length,
      savedValue: draft && draft.fields[0].value, expectedValue};
  }
  if (spec.scenario === 'counterLatest') {
    const page = textPage(storage, {counter: 0, counterElement: true});
    runPage(page);
    page.document.counter = 21;
    page.field.value = '最初の本文';
    page.field.dispatchEvent(new FakeEvent('input'));
    page.document.counter = 30;
    page.field.value = '文字数が変わった後の最新の本文';
    page.field.dispatchEvent(new FakeEvent('input'));
    const savedStatus = statusFor(page);
    const restored = textPage(storage, {counter: 0, counterElement: true});
    runPage(restored);
    return {count: storage.length, restoredText: restored.field.value,
      savedStatus, restoredStatus: statusFor(restored),
      fieldKey: JSON.parse(storage.getItem(storage.key(0))).fields[0].key};
  }
  if (spec.scenario === 'restoredUntouched') {
    const source = textPage(storage);
    runPage(source);
    source.field.value = '保存済みの本文';
    source.field.dispatchEvent(new FakeEvent('input'));
    const key = storage.key(0);
    const before = storage.getItem(key);
    const restored = textPage(storage);
    runPage(restored);
    restored.field.dispatchEvent(new FakeEvent('keyup', {key: 'ArrowLeft'}));
    restored.field.dispatchEvent(new FakeEvent('change'));
    restored.window.__MBG_REPORT_DRAFT_UPDATE();
    hidePage(restored);
    return {restoredText: restored.field.value,
      touched: !!restored.field.__MBG_REPORT_DRAFT_TOUCHED,
      dirty: !!restored.field.__MBG_REPORT_DRAFT_DIRTY,
      unchangedAfterHide: storage.getItem(key) === before};
  }
  if (spec.scenario === 'counterKeys') {
    function keys(anonymous, counterElement) {
      return [0, 21, '２１'].map(counter => {
        const page = textPage(storage, {counter, counterElement, anonymous});
        runPage(page);
        return page.document.__MBG_REPORT_DRAFT_IDENTITY.key;
      });
    }
    const different = textPage(storage, {counter: 0,
      pageText: 'レポート提出 本文 入力 科目名 263T0506 タイトル レポート３'});
    runPage(different);
    return {keys: keys(false, false), elementKeys: keys(false, true),
      anonymousKeys: keys(true, false),
      differentAssignmentKey: different.document.__MBG_REPORT_DRAFT_IDENTITY.key};
  }
  if (spec.scenario === 'keyCache') {
    const page = textPage(storage);
    runPage(page);
    const initialKey = page.document.__MBG_REPORT_DRAFT_IDENTITY.key;
    page.document.pageText += ' ページ内の動的な表示';
    page.window.__MBG_REPORT_DRAFT_UPDATE();
    const cachedKey = page.document.__MBG_REPORT_DRAFT_IDENTITY.key;
    page.document.field = new FakeControl(page.document, 'textarea',
      {name: 'gakuComment', id: 'gakuComment'});
    page.window.__MBG_REPORT_DRAFT_UPDATE();
    return {initialKey, cachedKey, replacementKey: page.document.__MBG_REPORT_DRAFT_IDENTITY.key};
  }
  if (['choicesDefault', 'choicesTouched', 'choicesNonDefault', 'choicesEmpty',
      'choicesReordered'].includes(spec.scenario)) {
    const page = choicePage(storage);
    runPage(page);
    const fields = page.document.fields;
    fields[1].checked = true;
    fields[2].checked = false;
    fields[3].checked = true;
    setSelection(fields[4], ['b']);
    setSelection(fields[5], ['b', 'c']);
    fields[1].dispatchEvent(new FakeEvent('change'));
    const key = storage.key(0);
    const original = JSON.parse(storage.getItem(key));
    if (spec.scenario === 'choicesNonDefault') {
      for (const item of original.fields) {
        if (item.kind === 'radio') item.value = 'a';
        if (item.kind === 'checkbox') item.value = item.key.includes('checks=a');
      }
      storage.setItem(key, JSON.stringify(original));
    }
    if (spec.scenario === 'choicesEmpty') {
      for (const item of original.fields) {
        item.value = item.kind === 'radio' ? null : item.kind === 'checkbox' ? false : [];
      }
      storage.setItem(key, JSON.stringify(original));
    }
    const restoring = choicePage(storage);
    if (spec.scenario === 'choicesReordered') {
      const current = restoring.document.fields;
      [current[2], current[3]] = [current[3], current[2]];
      runPage(restoring);
      return {sameKey: restoring.document.__MBG_REPORT_DRAFT_IDENTITY.key === key,
        checksByValue: Object.fromEntries(current.slice(2, 4).map(field => [field.value, field.checked]))};
    }
    if (spec.scenario === 'choicesTouched') {
      storage.removeItem(key);
      runPage(restoring);
      for (const field of restoring.document.fields) field.dispatchEvent(new FakeEvent('change'));
      storage.setItem(key, JSON.stringify(original));
      restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    } else {
      if (spec.scenario === 'choicesNonDefault') {
        const current = restoring.document.fields;
        current[1].checked = true;
        current[2].checked = false;
        current[3].checked = true;
        setSelection(current[4], ['c']);
        setSelection(current[5], ['c']);
      }
      runPage(restoring);
    }
    const eventCount = () => restoring.document.fields.reduce((sum, field) => sum + field.events.length, 0);
    const eventsAfterRestore = eventCount();
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    const beforeHide = storage.getItem(key);
    hidePage(restoring);
    return {...choiceState(restoring), kinds: original.fields.map(item => item.kind),
      count: storage.length,
      eventsDispatched: restoring.document.fields.every(field =>
        field.events.includes('input') && field.events.includes('change')),
      eventsAfterRestore, eventsAfterSecondUpdate: eventCount(),
      pendingAfterRestore: !!restoring.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT,
      touchedAfterRestore: restoring.document.fields.some(field => field.__MBG_REPORT_DRAFT_TOUCHED),
      dirtyAfterRestore: restoring.document.fields.some(field => field.__MBG_REPORT_DRAFT_DIRTY),
      unchangedAfterHide: storage.getItem(key) === beforeHide,
      originalSavedAt: original.savedAt,
      restoredSavedAt: JSON.parse(storage.getItem(key)).savedAt};
  }
  if (spec.scenario === 'choiceOnly') {
    const quiz = choicePage(storage, {title: '小テスト回答', pageText: '小テスト回答 解答'});
    quiz.document.location = {href: 'https://gakujo.example/flow', pathname: '/flow'};
    runPage(quiz);
    quiz.document.fields[1].checked = true;
    quiz.document.fields[1].dispatchEvent(new FakeEvent('change'));
    const unrelated = choicePage(storage, {title: '検索', pageText: '検索 条件'});
    unrelated.document.location = {href: 'https://gakujo.example/search', pathname: '/search'};
    runPage(unrelated);
    const login = textPage(storage);
    login.document.field = new FakeControl(login.document, 'input', {type: 'text', name: 'username'});
    runPage(login);
    return {quizBound: !!quiz.document.insertedStatus,
      unrelatedBound: !!unrelated.document.insertedStatus,
      loginBound: !!login.document.insertedStatus, count: storage.length};
  }
  if (spec.scenario === 'conflictNavigation') {
    const page = textPage(storage, {value: '端末の新しい下書き'});
    runPage(page);
    page.field.dispatchEvent(new FakeEvent('input'));
    const key = storage.key(0), original = storage.getItem(key);
    const restoring = textPage(storage, {value: 'サーバー側の古い本文'});
    runPage(restoring);
    restoring.field.dispatchEvent(new FakeEvent(
      spec.event === 'change' ? 'change' : 'keyup',
      {key: spec.event === 'ArrowLeft' ? 'ArrowLeft' : 'c', ctrlKey: spec.event === 'Ctrl+C'}));
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    hidePage(restoring);
    const result = {
      storedUnchanged: storage.getItem(key) === original,
      replaceVisible: restoring.document.getElementById('mbg-report-draft-replace').style.display !== 'none',
      pending: !!restoring.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT,
      touched: !!restoring.field.__MBG_REPORT_DRAFT_TOUCHED
    };
    // Input remains an edit even when the visible value is unchanged.
    if (spec.event === 'Ctrl+C') {
      restoring.field.dispatchEvent(new FakeEvent('input'));
      result.inputSavedUnchangedValue = JSON.parse(storage.getItem(key)).fields[0].value === restoring.field.value;
    }
    restoring.field.value = '実際の編集';
    restoring.field.dispatchEvent(new FakeEvent(spec.event === 'change' ? 'change' : 'keyup'));
    return {...result, storedAfterEdit: JSON.parse(storage.getItem(key)).fields[0].value};
  }
  if (spec.scenario === 'conflict') {
    const page = textPage(storage, {value: '端末の下書き'});
    runPage(page);
    page.field.dispatchEvent(new FakeEvent('input'));
    const restoring = textPage(storage, {value: 'サーバー側の一時保存'});
    runPage(restoring);
    const beforeReplace = restoring.field.value, beforeStatus = statusFor(restoring);
    hidePage(restoring);
    const storedAfterPageHide = JSON.parse(storage.getItem(storage.key(0))).fields[0].value;
    const button = restoring.document.getElementById('mbg-report-draft-replace');
    button.listeners.click();
    return {beforeReplace, beforeStatus, storedAfterPageHide,
      afterReplace: restoring.field.value, afterStatus: statusFor(restoring),
      replaceHidden: button.style.display === 'none', events: restoring.field.events};
  }
  if (spec.scenario === 'conflictWithCheckbox') {
    function form(value) {
      const page = textPage(storage, {value});
      page.document.fields = [page.field, new FakeControl(page.document, 'input',
        {type: 'checkbox', name: 'agree'}, {value: 'yes'})];
      return page;
    }
    const page = form('端末の下書き');
    runPage(page);
    page.document.fields[1].checked = true;
    page.field.dispatchEvent(new FakeEvent('input'));
    const key = storage.key(0), original = storage.getItem(key);
    const restoring = form('サーバー側の一時保存');
    runPage(restoring);
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    const fields = restoring.document.fields;
    const touched = fields.some(field => field.__MBG_REPORT_DRAFT_TOUCHED);
    const dirty = fields.some(field => field.__MBG_REPORT_DRAFT_DIRTY);
    const replaceVisible = restoring.document.getElementById('mbg-report-draft-replace').style.display !== 'none';
    const target = spec.event === 'visibilitychange' ? restoring.document : restoring.window;
    restoring.document.visibilityState = 'hidden';
    for (const callback of target.listeners[spec.event] || []) callback();
    const unchangedAfterHide = storage.getItem(key) === original;
    const text = restoring.field.value;
    restoring.field.value = '実際の編集';
    restoring.field.dispatchEvent(new FakeEvent('keyup'));
    return {text, checkbox: fields[1].checked, touched, dirty, replaceVisible,
      unchangedAfterHide, storedAfterInput: JSON.parse(storage.getItem(key)).fields[0].value};
  }
  if (spec.scenario === 'missingSelectOption') {
    function form() {
      const page = choicePage(storage);
      page.document.fields = [page.document.fields[spec.multiple ? 5 : 4]];
      return page;
    }
    const page = form();
    runPage(page);
    setSelection(page.document.fields[0], spec.multiple ? ['b', 'c'] : ['b']);
    page.document.fields[0].dispatchEvent(new FakeEvent('change'));
    const key = storage.key(0), original = storage.getItem(key);
    const restoring = form();
    const field = restoring.document.fields[0];
    field.options = field.options.filter(option => option.value !== 'b');
    runPage(restoring);
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    const status = statusFor(restoring);
    hidePage(restoring);
    return {selection: field.options.filter(option => option.selected).map(option => option.value),
      events: field.events, status, unchangedAfterHide: storage.getItem(key) === original};
  }
  if (spec.scenario === 'heading') {
    const page = textPage(storage, {value: '本文'});
    const cell = (tagName, textContent) => ({tagName, textContent});
    page.document.rows = [
      {children: [cell('TH', '科目名'), cell('TD', '263T0506'), cell('TD', 'プログラミング基礎Ⅰ')]},
      {children: [cell('TD', 'タイトル'), cell('TD', 'レポート２')]}
    ];
    runPage(page);
    page.field.dispatchEvent(new FakeEvent('input'));
    const heading = JSON.parse(storage.getItem(storage.key(0))).heading;
    page.document.rows = [];
    page.field.dispatchEvent(new FakeEvent('input'));
    return {heading, fallback: JSON.parse(storage.getItem(storage.key(0))).heading};
  }
  if (spec.scenario === 'list' || spec.scenario === 'cleanup') {
    const now = Date.now();
    for (const version of [1, 2]) {
      storage.setItem('mbg-report-draft:v' + version + ':expired', JSON.stringify({
        savedAt: now - 15 * 24 * 60 * 60 * 1000, fields: []}));
      storage.setItem('mbg-report-draft:v' + version + ':invalid', 'not json');
      storage.setItem('mbg-report-draft:v' + version + ':invalidTime', JSON.stringify({savedAt: 'bad', fields: []}));
    }
    storage.setItem('other-key', 'unrelated');
    const old = {savedAt: now - 2000, title: '旧タイトル', fields: [{key: 'old', value: '<b>旧本文</b>'}]};
    storage.setItem('mbg-report-draft:v1:valid', JSON.stringify(old));
    const top = textPage(storage);
    if (spec.scenario === 'cleanup') {
      runPage(top);
      return {remainingKeys: Array.from(storage.values.keys()).sort()};
    }
    const draft = {savedAt: now - 1000, title: 'タイトル', heading: '科目 / レポート２', fields: [
      {kind: 'text', value: 'あ'.repeat(130)}, {kind: 'checkbox', value: true},
      {kind: 'text', value: '次の回答'}]};
    storage.setItem('mbg-report-draft:v2:valid', JSON.stringify(draft));
    const frameStorage = new FakeStorage(new Map());
    frameStorage.setItem('mbg-report-draft:v2:valid', JSON.stringify({...draft, savedAt: now}));
    const frame = textPage(frameStorage);
    top.document.frame = {contentWindow: frame.window};
    const entries = JSON.parse(runPage(top, listScript));
    const expiredAndInvalidRemoved = !Array.from(storage.values.keys()).some(key => /expired|invalid/.test(key));
    top.document.frame = {get contentWindow() { throw new Error('Cross origin'); }};
    return {entries, expiredAndInvalidRemoved, unrelatedRetained: storage.getItem('other-key') === 'unrelated',
      crossOriginCount: JSON.parse(runPage(top, listScript)).length};
  }
  if (spec.scenario === 'delete') {
    const target = 'mbg-report-draft:v2:delete"\\key';
    const payload = JSON.stringify({savedAt: Date.now(), fields: []});
    const top = textPage(storage);
    runPage(top);
    top.document.__MBG_REPORT_DRAFT_IDENTITY.key = target;
    top.window.deferSaveTimer = true;
    top.field.value = '保留中の本文';
    top.field.dispatchEvent(new FakeEvent('input'));
    storage.setItem(target, payload);
    storage.setItem('mbg-report-draft:v1:other', payload);
    storage.setItem('other-key', 'unrelated');
    const frameStorage = new FakeStorage(new Map([[target, payload], ['other-key', 'unrelated']]));
    const frame = textPage(frameStorage);
    top.document.frame = {contentWindow: frame.window};
    const deleted = runPage(top, deleteScript);
    const pendingCancelled = !top.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT && pendingTimers.size === 0;
    hidePage(top);
    const remainingAfterPageHide = storage.getItem(target) !== null;
    const targetRemovedEverywhere = storage.getItem(target) === null && frameStorage.getItem(target) === null;
    storage.setItem(target, payload);
    storage.failRemove = true;
    const failedDelete = runPage(top, deleteScript);
    return {deleted, targetRemovedEverywhere, pendingCancelled, remainingAfterPageHide, failedDelete,
      retainedAfterFailure: storage.getItem(target) === payload,
      otherKeysRetained: storage.getItem('mbg-report-draft:v1:other') === payload &&
        storage.getItem('other-key') === 'unrelated' && frameStorage.getItem('other-key') === 'unrelated'};
  }
  return null;
}

(function runScenario() {
const extended = runExtendedScenario();
if (extended) return process.stdout.write(JSON.stringify(extended));
const storage = new FakeStorage();
const savingPage = createPage(spec.initialHtml, spec.initialText, storage);
runPage(savingPage);
if (spec.scenario === 'saveFailure') storage.failWrite = true;
savingPage.field.dispatchEvent(new FakeEvent('input', {bubbles: true}));
function statusText() { return savingPage.document.getElementById('mbg-report-draft-status-label').textContent; }
function pageHide() { for (const callback of savingPage.window.listeners.pagehide || []) callback(); }
function clearDraft() { savingPage.document.insertedStatus.children.find(child=>child.textContent==='下書きを削除').listeners.click(); }
function retry() {
  const button=savingPage.document.insertedStatus.children.find(child=>child.textContent==='再試行');
  if(button)button.listeners.click();
  return !!button;
}
function flushTimers() { const callbacks=Array.from(pendingTimers.values());pendingTimers.clear();for(const callback of callbacks)callback(); }
if (spec.scenario === 'saveFailure') {
  const failureStatus=statusText(), dirtyAfterFailure=!!savingPage.field.__MBG_REPORT_DRAFT_DIRTY;
  const pendingAfterFailure=!!savingPage.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
  storage.failWrite=false;
  savingPage.document.field=null;
  pageHide();
  const saved=storage.key(0) && JSON.parse(storage.getItem(storage.key(0)));
  return process.stdout.write(JSON.stringify({failureStatus,dirtyAfterFailure,pendingAfterFailure,storedAfterRetry:saved && saved.fields[0].value}));
}
if (spec.scenario === 'deleteFailure') {
  storage.failRemove=true;clearDraft();const failureStatus=statusText();
  storage.failRemove=false;const hasRetry=retry();
  return process.stdout.write(JSON.stringify({failureStatus,hasRetry,remainingAfterRetry:storage.length}));
}
if (spec.scenario === 'deletePending') {
  clearDraft();flushTimers();pageHide();const remainingAfterPageHide=storage.length;
  savingPage.field.textContent='新しい入力';savingPage.field.dispatchEvent(new FakeEvent('input',{}));flushTimers();
  const saved=JSON.parse(storage.getItem(storage.key(0)));
  return process.stdout.write(JSON.stringify({remainingAfterPageHide,storedAfterNewInput:saved.fields[0].value}));
}
if (spec.scenario === 'clearFailure') {
  storage.failRemove=true;savingPage.field.textContent='';savingPage.field.dispatchEvent(new FakeEvent('input',{}));
  const failureStatus=statusText(),dirtyAfterFailure=!!savingPage.field.__MBG_REPORT_DRAFT_DIRTY;
  savingPage.window.__MBG_REPORT_DRAFT_UPDATE();
  return process.stdout.write(JSON.stringify({failureStatus,dirtyAfterFailure,textAfterUpdate:savingPage.field.textContent}));
}
if (spec.dropFieldBeforePageHide) {
  savingPage.document.field = null;
}
if (spec.firePageHide) {
  for (const callback of savingPage.window.listeners.pagehide || []) callback();
}

const key = storage.key(0);
if (!key) throw new Error('Draft was not saved');
const savedDraft = JSON.parse(storage.getItem(key));
const storedValue = savedDraft.fields[0].value;
if (Object.prototype.hasOwnProperty.call(spec, 'legacyValue')) {
  savedDraft.fields[0].value = spec.legacyValue;
  storage.setItem(key, JSON.stringify(savedDraft));
}

let sameDocumentRestoredText = null;
if (spec.replaceFieldInSameDocument) {
  savingPage.document.field = new FakeContentEditable(
    savingPage.document,
    '',
    ''
  );
  savingPage.field = savingPage.document.field;
  savingPage.window.__MBG_REPORT_DRAFT_UPDATE();
  sameDocumentRestoredText = savingPage.field.textContent;
}

const restoringPage = createPage('', '', storage);
runPage(restoringPage);

process.stdout.write(JSON.stringify({
  storedValue,
  restoredText: restoringPage.field.textContent,
  restoredHtml: restoringPage.field.innerHTML,
  sameDocumentRestoredText,
  xssExecutionCount
}));
})();
''';
