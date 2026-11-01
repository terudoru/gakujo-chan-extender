import type {} from 'node:fs';
const vm: any = require('node:vm');
const {generatedScript, spec, listScript, deleteScript, exportScript, importScript} = JSON.parse(
  require('node:fs').readFileSync(process.argv[2], 'utf8')
);
const storageValues: any = new Map();
let xssExecutionCount: any = 0;
let nextTimerId: any = 1;
const pendingTimers: any = new Map();

class FakeEvent {
  [key: string]: any;
  constructor(type: any, options?: any) {
    this.type = type;
    Object.assign(this, options || {});
  }
}

class FakeStorage {
  [key: string]: any;
  constructor(values: any = storageValues) { this.values = values; }
  get length() { return this.values.size; }
  getItem(key: any) { return this.values.get(key) || null; }
  setItem(key: any, value: any) {
    if (this.failWrite) throw new Error('QuotaExceededError');
    this.values.set(key, String(value));
  }
  removeItem(key: any) {
    if (this.failRemove) throw new Error('SecurityError');
    this.values.delete(key);
  }
  key(index: any) { return Array.from(this.values.keys())[index] || null; }
}

class FakeStatusElement {
  [key: string]: any;
  constructor(tag: any) {
    this.tagName = tag.toUpperCase();
    this.id = '';
    this.type = '';
    this.textContent = '';
    this.style = {};
    this.children = [];
    this.listeners = {};
  }

  appendChild(child: any) { this.children.push(child); }
  addEventListener(type: any, callback: any) { this.listeners[type] = callback; }
  remove() {}
}

function findById(node: any, id: any) {
  if (!node) return null;
  if (node.id === id) return node;
  for (const child of node.children || []) {
    const match: any = findById(child, id);
    if (match) return match;
  }
  return null;
}

class FakeContentEditable {
  [key: string]: any;
  constructor(doc: any, html: any, text: any) {
    this.tagName = 'DIV';
    this.ownerDocument = doc;
    this.disabled = false;
    this.readOnly = false;
    this.style = {};
    this.listeners = {};
    this.attributes = spec.scenario === 'selfRowContentEditable'
      ? {contenteditable: 'true', id: 'draft', 'aria-label': '??'}
      : {contenteditable: 'true', name: 'answer'};
    this.events = [];
    this._innerHTML = html;
    this._text = text;
    this.parentNode = {
      insertBefore: (node: any) => { doc.insertedStatus = node; }
    };
    this.parentElement = spec.scenario === 'selfRowContentEditable'
      ? {closest: () => ({cloneNode: () => textClone(doc, true)})}
      : null;
  }

  get id() { return this.attributes.id || ''; }
  get innerHTML() { return this._innerHTML; }
  set innerHTML(value: any) {
    this._innerHTML = String(value);
    if (/<script\b|\bonerror\s*=|\bonload\s*=/i.test(this._innerHTML)) {
      xssExecutionCount += 1;
    }
    this._text = this._innerHTML.replace(/<[^>]*>/g, '');
  }
  get innerText() { return this._text; }
  set innerText(value: any) { this.textContent = value; }
  get textContent() { return this._text; }
  set textContent(value: any) {
    this._text = String(value);
    this._innerHTML = this._text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  appendChild(node: any) {
    if (node.nodeType === 3) {
      const text: any = String(node.textContent || '');
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

  getAttribute(name: any) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name)
      ? this.attributes[name]
      : null;
  }
  getClientRects() { return [{}]; }
  matches(selector: any) { return selector === '[contenteditable]'; }
  closest(selector?: any): any {
    return spec.scenario === 'selfRowContentEditable' &&
      selector === 'tr,div,p,li,section' ? this : null;
  }
  cloneNode() {
    const text = this._text;
    return {innerText: text, textContent: text, querySelectorAll() { return []; }};
  }
  addEventListener(type: any, callback: any) {
    (this.listeners[type] ||= []).push(callback);
  }
  dispatchEvent(event: any) {
    this.events.push(event.type);
    for (const callback of this.listeners[event.type] || []) callback(event);
    return true;
  }
}

class FakeControl extends FakeContentEditable {
  [key: string]: any;
  constructor(doc: any, tag: any, attributes: any = {}, options: any = {}) {
    super(doc, '', '');
    this.tagName = tag.toUpperCase();
    this.parentElement = {closest: (selector: any) => this.closest(selector)};
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
  set value(value: any) { this._value = String(value); }
  get checked() { return this._checked; }
  set checked(value: any) {
    if (value && this.attributes.type === 'radio' && this.attributes.name) {
      for (const field of this.ownerDocument.fields || []) {
        if (field !== this && field.attributes.type === 'radio' &&
            field.attributes.name === this.attributes.name) field._checked = false;
      }
    }
    this._checked = value;
  }
  matches() { return false; }
  closest(selector: any) {
    return selector === 'form' ? null : {cloneNode: () => textClone(this.ownerDocument, true)};
  }
}

function textClone(doc: any, rowOnly: any = false) {
  let removed: any = false;
  const counter: any = {
    getAttribute(name: any) {
      return name === 'id' ? 'gakuCommentCOUNT' : 'countField';
    },
    remove() { removed = true; }
  };
  return {
    get innerText() {
      const base: any = rowOnly ? '' : doc.pageText;
      return base + (doc.counter == null ? '' :
        ' 入力文字数：' + (removed ? '' : doc.counter) + '/200文字');
    },
    get textContent() { return this.innerText; },
    querySelectorAll(selector: any) {
      return selector === '[id],[class]' && doc.counterElement ? [counter] : [];
    }
  };
}

function createPage(html: any, text: any, storage: any, options: any = {}) {
  const document: any = {
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
    createElement(tag: any) { return new FakeStatusElement(tag); },
    createTextNode(text: any) { return {nodeType: 3, textContent: String(text)}; },
    getElementById(id: any) { return findById(this.insertedStatus, id); },
    addEventListener(type: any, callback: any) {
      (this.listeners[type] ||= []).push(callback);
    },
    querySelectorAll(selector: any) {
      if (selector === 'textarea,input,[contenteditable]') {
        return (this.fields || (this.field ? [this.field] : []))
          .filter((field: any) => field.tagName !== 'SELECT');
      }
      if (selector === 'textarea,input,select,[contenteditable]') {
        return this.fields || (this.field ? [this.field] : []);
      }
      if (selector === 'iframe,frame') return this.frame ? [this.frame] : [];
      if (selector === 'tr') return this.rows || [];
      return [];
    },
    querySelector(selector: any) {
      return selector === 'iframe#main-frame-if' ? this.frame || null : null;
    }
  };
  const window: any = {
    document,
    localStorage: storage,
    CSS: null,
    listeners: {},
    Event: FakeEvent,
    InputEvent: FakeEvent,
    HTMLTextAreaElement: FakeControl,
    HTMLInputElement: FakeControl,
    getComputedStyle() { return {display: 'block', visibility: 'visible'}; },
    clearTimeout(id: any) { pendingTimers.delete(id); },
    setTimeout(callback: any) {
      const id: any = nextTimerId++;
      if (spec.deferSaveTimer || this.deferSaveTimer) {
        pendingTimers.set(id, callback);
      } else {
        callback();
      }
      return id;
    },
    clearInterval() {},
    setInterval() { return 1; },
    addEventListener(type: any, callback: any) {
      (this.listeners[type] ||= []).push(callback);
    }
  };
  window.window = window;
  document.defaultView = window;
  document.field = new FakeContentEditable(document, html, text);
  return {window, document, field: document.field};
}

function runPage(page: any, script: any = generatedScript) {
  return vm.runInNewContext(script, {
    window: page.window,
    document: page.document,
    console: {log() {}}
  });
}

function statusFor(page: any) {
  return page.document.getElementById('mbg-report-draft-status-label').textContent;
}

function textPage(storage: any, options: any = {}) {
  const page: any = createPage('', '', storage, options);
  page.field = new FakeControl(page.document, 'textarea',
    options.anonymous ? {} : {name: 'gakuComment', id: 'gakuComment'},
    {value: options.value});
  page.document.field = page.field;
  return page;
}

function choicePage(storage: any, options: any = {}) {
  const page: any = createPage('', '', storage, options);
  const doc: any = page.document;
  function input(type: any, name: any, value: any, defaultChecked: any = false) {
    return new FakeControl(doc, 'input', {type, name}, {value, defaultChecked});
  }
  function select(name: any, multiple: any) {
    return new FakeControl(doc, 'select', {name}, {
      multiple,
      options: ['a', 'b', 'c'].map((value: any) => ({
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

function setSelection(field: any, values: any) {
  for (const option of field.options) option.selected = values.includes(option.value);
}

function choiceState(page: any) {
  const fields: any = page.document.fields;
  const selected: any = (field: any) => field.options.filter((option: any) => option.selected).map((option: any) => option.value);
  return {
    radio: fields.slice(0, 2).map((field: any) => field.checked),
    checkbox: fields.slice(2, 4).map((field: any) => field.checked),
    select: selected(fields[4]), multiple: selected(fields[5])
  };
}

function hidePage(page: any) {
  for (const callback of page.window.listeners.pagehide || []) callback();
}

function runExtendedScenario() {
  const storage: any = new FakeStorage();
  if (spec.scenario === 'legacyMigrationReopenedEmpty') {
    // Same captured v0.70.0 draft, but the reopened form's counter shows 0.
    const legacyKey: any = 'mbg-report-draft:v1:cmm5xw';
    storage.setItem(legacyKey, JSON.stringify({
      savedAt: Date.now() - 60000,
      title: 'レポート提出', url: 'https://gakujo.example/report/input',
      fields: [
        {key: 'textarea||gakuComment gakuComment 入力文字数：17/200文字|0', value: 'Legacy answer'},
        {key: 'textarea||Q2 入力文字数：17/200文字|1', value: 'Second legacy answer'}
      ]
    }));
    const page: any = textPage(storage, {counter: 0, counterElement: true});
    page.document.fields = [page.field,
      new FakeControl(page.document, 'select', {name: 'choice'}),
      new FakeControl(page.document, 'textarea', {name: 'Q2'})];
    runPage(page);
    return {restored: [page.field.value, page.document.fields[2].value],
      legacyRemoved: storage.getItem(legacyKey) === null};
  }
  if (spec.scenario === 'legacyMigration') {
    const legacyKey: any = 'mbg-report-draft:v1:cmm5xw';
    // Captured from v0.70.0's script on this form, including its counter text.
    const oldDraft: any = {
      savedAt: Date.now() - 60000,
      title: 'レポート提出', url: 'https://gakujo.example/report/input',
      fields: [
        {key: 'textarea||gakuComment gakuComment 入力文字数：17/200文字|0', value: 'Legacy answer'},
        {key: 'textarea||Q2 入力文字数：17/200文字|1', value: 'Second legacy answer'}
      ]
    };
    function form(value?: any) {
      const page: any = textPage(storage, {value, counter: 17, counterElement: true});
      page.document.fields = [page.field,
        new FakeControl(page.document, 'select', {name: 'choice'}),
        new FakeControl(page.document, 'textarea', {name: 'Q2'})];
      return page;
    }
    storage.setItem(legacyKey, JSON.stringify(oldDraft));
    const page: any = form();
    runPage(page);
    const key: any = storage.key(0);
    const migrated: any = JSON.parse(storage.getItem(key));
    const restored: any = [page.field.value, page.document.fields[2].value];
    const legacyRemoved: any = storage.getItem(legacyKey) === null;
    const again: any = form();
    runPage(again);
    const restoredAgain: any = [again.field.value, again.document.fields[2].value];
    storage.values.clear();
    storage.setItem(legacyKey, JSON.stringify(oldDraft));
    const conflicting: any = form('Server answer');
    runPage(conflicting);
    const conflictingValue: any = conflicting.field.value;
    const button: any = conflicting.document.getElementById('mbg-report-draft-replace');
    const replacementVisible: any = button.style.display !== 'none';
    const storedConflict: any = JSON.parse(storage.getItem(key)).fields[0].value;
    button.listeners.click();
    return {restored, key, legacyRemoved,
      savedAtPreserved: migrated.savedAt === oldDraft.savedAt,
      restoredAgain, conflictingValue, replacementVisible, storedConflict,
      afterReplace: conflicting.field.value};
  }
  if (spec.scenario === 'beforeBinding') {
    const page: any = textPage(storage, {value: 'Server value'});
    let expectedValue: any = 'Typed before binding';
    if (spec.kind === 'contenteditable') {
      page.field = new FakeContentEditable(page.document, 'Server value', 'Server value');
    } else if (spec.kind !== 'textarea') {
      page.field = new FakeControl(page.document,
        spec.kind === 'select' ? 'select' : 'input',
        {name: 'answer', type: spec.kind, 'aria-label': '回答'}, {
          value: 'Server value', defaultChecked: true,
          options: ['a', 'b'].map((value: any) => ({
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
    const touched: any = !!page.field.__MBG_REPORT_DRAFT_TOUCHED;
    const dirty: any = !!page.field.__MBG_REPORT_DRAFT_DIRTY;
    const countBeforeHide: any = storage.length;
    const target: any = spec.event === 'visibilitychange' ? page.document : page.window;
    page.document.visibilityState = 'hidden';
    for (const callback of target.listeners[spec.event] || []) callback();
    const draft: any = storage.length ? JSON.parse(storage.getItem(storage.key(0))) : null;
    return {bound: !!page.field.__MBG_REPORT_DRAFT_BOUND,
      touched, dirty, countBeforeHide, count: storage.length,
      savedValue: draft && draft.fields[0].value, expectedValue};
  }
  if (spec.scenario === 'counterLatest') {
    const page: any = textPage(storage, {counter: 0, counterElement: true});
    runPage(page);
    page.document.counter = 21;
    page.field.value = '最初の本文';
    page.field.dispatchEvent(new FakeEvent('input'));
    page.document.counter = 30;
    page.field.value = '文字数が変わった後の最新の本文';
    page.field.dispatchEvent(new FakeEvent('input'));
    const savedStatus: any = statusFor(page);
    const restored: any = textPage(storage, {counter: 0, counterElement: true});
    runPage(restored);
    return {count: storage.length, restoredText: restored.field.value,
      savedStatus, restoredStatus: statusFor(restored),
      fieldKey: JSON.parse(storage.getItem(storage.key(0))).fields[0].key};
  }
  if (spec.scenario === 'restoredUntouched') {
    const source: any = textPage(storage);
    runPage(source);
    source.field.value = '保存済みの本文';
    source.field.dispatchEvent(new FakeEvent('input'));
    const key: any = storage.key(0);
    const before: any = storage.getItem(key);
    const restored: any = textPage(storage);
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
    function keys(anonymous: any, counterElement: any) {
      return [0, 21, '２１'].map((counter: any) => {
        const page: any = textPage(storage, {counter, counterElement, anonymous});
        runPage(page);
        return page.document.__MBG_REPORT_DRAFT_IDENTITY.key;
      });
    }
    const different: any = textPage(storage, {counter: 0,
      pageText: 'レポート提出 本文 入力 科目名 263T0506 タイトル レポート３'});
    runPage(different);
    return {keys: keys(false, false), elementKeys: keys(false, true),
      anonymousKeys: keys(true, false),
      differentAssignmentKey: different.document.__MBG_REPORT_DRAFT_IDENTITY.key};
  }
  if (spec.scenario === 'keyCache') {
    const page: any = textPage(storage);
    runPage(page);
    const initialKey: any = page.document.__MBG_REPORT_DRAFT_IDENTITY.key;
    page.document.pageText += ' ページ内の動的な表示';
    page.window.__MBG_REPORT_DRAFT_UPDATE();
    const cachedKey: any = page.document.__MBG_REPORT_DRAFT_IDENTITY.key;
    page.document.field = new FakeControl(page.document, 'textarea',
      {name: 'gakuComment', id: 'gakuComment'});
    page.window.__MBG_REPORT_DRAFT_UPDATE();
    return {initialKey, cachedKey, replacementKey: page.document.__MBG_REPORT_DRAFT_IDENTITY.key};
  }
  if (['choicesDefault', 'choicesTouched', 'choicesNonDefault', 'choicesEmpty',
      'choicesReordered'].includes(spec.scenario)) {
    const page: any = choicePage(storage);
    runPage(page);
    const fields: any = page.document.fields;
    fields[1].checked = true;
    fields[2].checked = false;
    fields[3].checked = true;
    setSelection(fields[4], ['b']);
    setSelection(fields[5], ['b', 'c']);
    fields[1].dispatchEvent(new FakeEvent('change'));
    const key: any = storage.key(0);
    const original: any = JSON.parse(storage.getItem(key));
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
    const restoring: any = choicePage(storage);
    if (spec.scenario === 'choicesReordered') {
      const current: any = restoring.document.fields;
      [current[2], current[3]] = [current[3], current[2]];
      runPage(restoring);
      restoring.document.getElementById('mbg-report-draft-replace').listeners.click();
      return {sameKey: restoring.document.__MBG_REPORT_DRAFT_IDENTITY.key === key,
        checksByValue: Object.fromEntries(current.slice(2, 4).map((field: any) => [field.value, field.checked]))};
    }
    if (spec.scenario === 'choicesTouched') {
      storage.removeItem(key);
      runPage(restoring);
      for (const field of restoring.document.fields) field.dispatchEvent(new FakeEvent('change'));
      storage.setItem(key, JSON.stringify(original));
      restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    } else {
      if (spec.scenario === 'choicesNonDefault') {
        const current: any = restoring.document.fields;
        current[1].checked = true;
        current[2].checked = false;
        current[3].checked = true;
        setSelection(current[4], ['c']);
        setSelection(current[5], ['c']);
      }
      runPage(restoring);
      if (['choicesDefault', 'choicesEmpty'].includes(spec.scenario)) {
        restoring.document.getElementById('mbg-report-draft-replace').listeners.click();
      }
    }
    const eventCount: any = () => restoring.document.fields.reduce((sum: any, field: any) => sum + field.events.length, 0);
    const eventsAfterRestore: any = eventCount();
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    const beforeHide: any = storage.getItem(key);
    hidePage(restoring);
    return {...choiceState(restoring), kinds: original.fields.map((item: any) => item.kind),
      count: storage.length,
      eventsDispatched: restoring.document.fields.every((field: any) =>
        field.events.includes('input') && field.events.includes('change')),
      eventsAfterRestore, eventsAfterSecondUpdate: eventCount(),
      pendingAfterRestore: !!restoring.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT,
      touchedAfterRestore: restoring.document.fields.some((field: any) => field.__MBG_REPORT_DRAFT_TOUCHED),
      dirtyAfterRestore: restoring.document.fields.some((field: any) => field.__MBG_REPORT_DRAFT_DIRTY),
      unchangedAfterHide: storage.getItem(key) === beforeHide,
      originalSavedAt: original.savedAt,
      restoredSavedAt: JSON.parse(storage.getItem(key)).savedAt};
  }
  if (spec.scenario === 'choiceOnly') {
    const quiz: any = choicePage(storage, {title: '小テスト回答', pageText: '小テスト回答 解答'});
    quiz.document.location = {href: 'https://gakujo.example/flow', pathname: '/flow'};
    runPage(quiz);
    quiz.document.fields[1].checked = true;
    quiz.document.fields[1].dispatchEvent(new FakeEvent('change'));
    const unrelated: any = choicePage(storage, {title: '検索', pageText: '検索 条件'});
    unrelated.document.location = {href: 'https://gakujo.example/search', pathname: '/search'};
    runPage(unrelated);
    const login: any = textPage(storage);
    login.document.field = new FakeControl(login.document, 'input', {type: 'text', name: 'username'});
    runPage(login);
    return {quizBound: !!quiz.document.insertedStatus,
      unrelatedBound: !!unrelated.document.insertedStatus,
      loginBound: !!login.document.insertedStatus, count: storage.length};
  }
  if (spec.scenario === 'reportList') {
    const list: any = choicePage(storage, {
      title: 'レポート・小テスト・アンケート提出',
      pageText: 'レポート・小テスト・アンケート提出 一覧 提出期間 表示件数'
    });
    list.document.location = {href: 'https://gakujo.example/flow', pathname: '/flow'};
    list.document.fields = [new FakeControl(list.document, 'select', {name: '_displayCount'}, {
      options: ['5', '10', '20'].map((value: any) => ({value, selected: value === '5', defaultSelected: value === '5'}))
    })];
    runPage(list);
    return {listBound: !!list.document.insertedStatus, count: storage.length};
  }
  if (spec.scenario === 'conflictOtherField') {
    function form(value?: any) {
      const page: any = textPage(storage, {value});
      page.document.fields = [page.field,
        new FakeControl(page.document, 'textarea', {name: 'Q2'})];
      return page;
    }
    const page: any = form('local newer');
    runPage(page);
    page.field.dispatchEvent(new FakeEvent('input'));
    const key: any = storage.key(0);
    const restoring: any = form('server old');
    runPage(restoring);
    const beforeEdit: any = restoring.field.value;
    restoring.document.fields[1].value = 'another answer';
    restoring.document.fields[1].dispatchEvent(new FakeEvent('input'));
    const saved: any = JSON.parse(storage.getItem(key));
    const button: any = restoring.document.getElementById('mbg-report-draft-replace');
    const replaceVisible: any = button.style.display !== 'none';
    button.listeners.click();
    const afterReplace: any = restoring.field.value;
    restoring.field.value = 'student edit';
    restoring.field.dispatchEvent(new FakeEvent('input'));
    return {beforeEdit, storedQ1: saved.fields[0].value,
      storedQ2: saved.fields[1].value, replaceVisible, afterReplace,
      afterOwnEdit: JSON.parse(storage.getItem(key)).fields[0].value};
  }
  if (spec.scenario === 'choiceServerAnswers') {
    const source: any = choicePage(storage);
    runPage(source);
    const fields: any = source.document.fields;
    fields[1].checked = true;
    fields[2].checked = false;
    fields[3].checked = true;
    setSelection(fields[4], ['b']);
    setSelection(fields[5], ['b', 'c']);
    fields[1].dispatchEvent(new FakeEvent('change'));
    const key: any = storage.key(0), original: any = storage.getItem(key);
    function restore(serverAnswers: any) {
      const page: any = choicePage(storage);
      if (serverAnswers) {
        for (const field of page.document.fields) {
          for (const option of field.options) option.defaultSelected = option.selected;
        }
      } else {
        for (const field of page.document.fields) {
          field.defaultChecked = false;
          field.checked = false;
          for (const option of field.options) {
            option.defaultSelected = false;
            if (field.multiple) option.selected = false;
          }
        }
      }
      runPage(page);
      const before: any = choiceState(page);
      const button: any = page.document.getElementById('mbg-report-draft-replace');
      const replaceVisible: any = button.style.display !== 'none';
      hidePage(page);
      const unchangedAfterHide: any = storage.getItem(key) === original;
      if (replaceVisible) button.listeners.click();
      return {before, replaceVisible, unchangedAfterHide, after: choiceState(page)};
    }
    return {server: restore(true), implicit: restore(false)};
  }
  if (spec.scenario === 'conflictNavigation') {
    const page: any = textPage(storage, {value: '端末の新しい下書き'});
    runPage(page);
    page.field.dispatchEvent(new FakeEvent('input'));
    const key: any = storage.key(0), original: any = storage.getItem(key);
    const restoring: any = textPage(storage, {value: 'サーバー側の古い本文'});
    runPage(restoring);
    restoring.field.dispatchEvent(new FakeEvent(
      spec.event === 'change' ? 'change' : 'keyup',
      {key: spec.event === 'ArrowLeft' ? 'ArrowLeft' : 'c', ctrlKey: spec.event === 'Ctrl+C'}));
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    hidePage(restoring);
    const result: any = {
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
    const page: any = textPage(storage, {value: '端末の下書き'});
    runPage(page);
    page.field.dispatchEvent(new FakeEvent('input'));
    const restoring: any = textPage(storage, {value: 'サーバー側の一時保存'});
    runPage(restoring);
    const beforeReplace: any = restoring.field.value, beforeStatus: any = statusFor(restoring);
    hidePage(restoring);
    const storedAfterPageHide: any = JSON.parse(storage.getItem(storage.key(0))).fields[0].value;
    const button: any = restoring.document.getElementById('mbg-report-draft-replace');
    button.listeners.click();
    return {beforeReplace, beforeStatus, storedAfterPageHide,
      afterReplace: restoring.field.value, afterStatus: statusFor(restoring),
      replaceHidden: button.style.display === 'none', events: restoring.field.events};
  }
  if (spec.scenario === 'conflictWithCheckbox') {
    function form(value?: any) {
      const page: any = textPage(storage, {value});
      page.document.fields = [page.field, new FakeControl(page.document, 'input',
        {type: 'checkbox', name: 'agree'}, {value: 'yes'})];
      return page;
    }
    const page: any = form('端末の下書き');
    runPage(page);
    page.document.fields[1].checked = true;
    page.field.dispatchEvent(new FakeEvent('input'));
    const key: any = storage.key(0), original: any = storage.getItem(key);
    const restoring: any = form('サーバー側の一時保存');
    runPage(restoring);
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    const fields: any = restoring.document.fields;
    const touched: any = fields.some((field: any) => field.__MBG_REPORT_DRAFT_TOUCHED);
    const dirty: any = fields.some((field: any) => field.__MBG_REPORT_DRAFT_DIRTY);
    const replaceVisible: any = restoring.document.getElementById('mbg-report-draft-replace').style.display !== 'none';
    const target: any = spec.event === 'visibilitychange' ? restoring.document : restoring.window;
    restoring.document.visibilityState = 'hidden';
    for (const callback of target.listeners[spec.event] || []) callback();
    const unchangedAfterHide: any = storage.getItem(key) === original;
    const text: any = restoring.field.value;
    restoring.field.value = '実際の編集';
    restoring.field.dispatchEvent(new FakeEvent('keyup'));
    return {text, checkbox: fields[1].checked, touched, dirty, replaceVisible,
      unchangedAfterHide, storedAfterInput: JSON.parse(storage.getItem(key)).fields[0].value};
  }
  if (spec.scenario === 'missingSelectOption') {
    function form() {
      const page: any = choicePage(storage);
      page.document.fields = [page.document.fields[spec.multiple ? 5 : 4]];
      return page;
    }
    const page: any = form();
    runPage(page);
    setSelection(page.document.fields[0], spec.multiple ? ['b', 'c'] : ['b']);
    page.document.fields[0].dispatchEvent(new FakeEvent('change'));
    const key: any = storage.key(0), original: any = storage.getItem(key);
    const restoring: any = form();
    const field: any = restoring.document.fields[0];
    field.options = field.options.filter((option: any) => option.value !== 'b');
    runPage(restoring);
    restoring.window.__MBG_REPORT_DRAFT_UPDATE();
    const status: any = statusFor(restoring);
    hidePage(restoring);
    return {selection: field.options.filter((option: any) => option.selected).map((option: any) => option.value),
      events: field.events, status, unchangedAfterHide: storage.getItem(key) === original};
  }
  if (spec.scenario === 'heading') {
    const page: any = textPage(storage, {value: '本文'});
    const cell: any = (tagName: any, textContent: any) => ({tagName, textContent});
    page.document.rows = [
      {children: [cell('TH', '科目名'), cell('TD', '263T0506'), cell('TD', 'プログラミング基礎Ⅰ')]},
      {children: [cell('TD', 'タイトル'), cell('TD', 'レポート２')]}
    ];
    runPage(page);
    page.field.dispatchEvent(new FakeEvent('input'));
    const heading: any = JSON.parse(storage.getItem(storage.key(0))).heading;
    page.document.rows = [];
    page.field.dispatchEvent(new FakeEvent('input'));
    return {heading, fallback: JSON.parse(storage.getItem(storage.key(0))).heading};
  }
  if (spec.scenario === 'list' || spec.scenario === 'cleanup') {
    const now: any = Date.now();
    for (const version of [1, 2]) {
      storage.setItem('mbg-report-draft:v' + version + ':expired', JSON.stringify({
        savedAt: now - 15 * 24 * 60 * 60 * 1000, fields: []}));
      storage.setItem('mbg-report-draft:v' + version + ':invalid', 'not json');
      storage.setItem('mbg-report-draft:v' + version + ':invalidTime', JSON.stringify({savedAt: 'bad', fields: []}));
    }
    storage.setItem('other-key', 'unrelated');
    const old: any = {savedAt: now - 2000, title: '旧タイトル', fields: [{key: 'old', value: '<b>旧本文</b>'}]};
    storage.setItem('mbg-report-draft:v1:valid', JSON.stringify(old));
    const top: any = textPage(storage);
    if (spec.scenario === 'cleanup') {
      runPage(top);
      return {remainingKeys: Array.from(storage.values.keys()).sort()};
    }
    const draft: any = {savedAt: now - 1000, title: 'タイトル', heading: '科目 / レポート２', fields: [
      {kind: 'text', value: 'あ'.repeat(130)}, {kind: 'checkbox', value: true},
      {kind: 'text', value: '次の回答'}]};
    storage.setItem('mbg-report-draft:v2:valid', JSON.stringify(draft));
    const frameStorage: any = new FakeStorage(new Map());
    frameStorage.setItem('mbg-report-draft:v2:valid', JSON.stringify({...draft, savedAt: now}));
    const frame: any = textPage(frameStorage);
    top.document.frame = {contentWindow: frame.window};
    const entries: any = JSON.parse(runPage(top, listScript));
    const expiredAndInvalidRemoved: any = !Array.from(storage.values.keys()).some((key: any) => /expired|invalid/.test(key));
    top.document.frame = {get contentWindow() { throw new Error('Cross origin'); }};
    return {entries, expiredAndInvalidRemoved, unrelatedRetained: storage.getItem('other-key') === 'unrelated',
      crossOriginCount: JSON.parse(runPage(top, listScript)).length};
  }
  if (spec.scenario === 'delete') {
    const target: any = 'mbg-report-draft:v2:delete"\\key';
    const payload: any = JSON.stringify({savedAt: Date.now(), fields: []});
    const top: any = textPage(storage);
    runPage(top);
    top.document.__MBG_REPORT_DRAFT_IDENTITY.key = target;
    top.window.deferSaveTimer = true;
    top.field.value = '保留中の本文';
    top.field.dispatchEvent(new FakeEvent('input'));
    storage.setItem(target, payload);
    storage.setItem('mbg-report-draft:v1:other', payload);
    storage.setItem('other-key', 'unrelated');
    const frameStorage: any = new FakeStorage(new Map([[target, payload], ['other-key', 'unrelated']]));
    const frame: any = textPage(frameStorage);
    top.document.frame = {contentWindow: frame.window};
    const deleted: any = runPage(top, deleteScript);
    const pendingCancelled: any = !top.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT && pendingTimers.size === 0;
    hidePage(top);
    const remainingAfterPageHide: any = storage.getItem(target) !== null;
    const targetRemovedEverywhere: any = storage.getItem(target) === null && frameStorage.getItem(target) === null;
    storage.setItem(target, payload);
    storage.failRemove = true;
    const failedDelete: any = runPage(top, deleteScript);
    return {deleted, targetRemovedEverywhere, pendingCancelled, remainingAfterPageHide, failedDelete,
      retainedAfterFailure: storage.getItem(target) === payload,
      otherKeysRetained: storage.getItem('mbg-report-draft:v1:other') === payload &&
        storage.getItem('other-key') === 'unrelated' && frameStorage.getItem('other-key') === 'unrelated'};
  }
  return null;
}

(function runScenario() {
const extended: any = runExtendedScenario();
if (extended) return process.stdout.write(JSON.stringify(extended));
const storage: any = new FakeStorage();
const savingPage: any = createPage(spec.initialHtml, spec.initialText, storage);
runPage(savingPage);
if (spec.scenario === 'notifications') {
  const messages: any[] = [];
  savingPage.window.GakujoMessageStars = {postMessage(message: any) { messages.push(JSON.parse(message)); }};
  storage.failWrite = true;
  savingPage.field.textContent = 'draft';
  savingPage.field.dispatchEvent(new FakeEvent('input', {bubbles: true}));
  storage.failWrite = false;
  savingPage.document.__MBG_REPORT_DRAFT_FLUSH();
  storage.failRemove = true;
  savingPage.document.insertedStatus.children.find((child: any) => child.textContent === '\u4e0b\u66f8\u304d\u3092\u524a\u9664').listeners.click();
  storage.failRemove = false;
  savingPage.document.insertedStatus.children.find((child: any) => child.textContent === '\u4e0b\u66f8\u304d\u3092\u524a\u9664').listeners.click();
  return process.stdout.write(JSON.stringify({messages}));
}
if (['dirtyImport', 'pendingExport', 'touchedImport', 'untouchedImport'].includes(spec.scenario)) {
  savingPage.window.deferSaveTimer = true;
  const key = savingPage.document.__MBG_REPORT_DRAFT_IDENTITY.key;
  const original = {savedAt: 1234567890000, fields: []};
  // Use a current timestamp so both records pass retention validation.
  original.savedAt = Date.now();
  storage.setItem(key, JSON.stringify(original));
  storage.setItem('mbg-report-draft:v2:other', JSON.stringify(original));
  if (spec.scenario !== 'untouchedImport') {
    savingPage.field.textContent = 'pending edit';
    savingPage.field.dispatchEvent(new FakeEvent('input', {bubbles: true}));
  }
  if (spec.scenario === 'touchedImport') {
    savingPage.document.__MBG_REPORT_DRAFT_FLUSH();
    storage.setItem(key, JSON.stringify(original));
  }
  if (spec.scenario === 'pendingExport') {
    const result = JSON.parse(runPage(savingPage, exportScript));
    return process.stdout.write(JSON.stringify({value: result[key].fields[0].value,
      pending: !!savingPage.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT}));
  }
  const replacement = {...original, fields: [{key: 'remote', value: 'remote', kind: 'text'}]};
  const script = importScript.replaceAll('placeholder-key', key.slice('mbg-report-draft:v2:'.length))
    .replaceAll('1234567890000', String(original.savedAt));
  // Change both records so the failed import must be atomic.
  const before = JSON.stringify(Array.from(storage.values.entries()));
  const matched = runPage(savingPage, script.replace('var matched = true;',
    'drafts[' + JSON.stringify(key) + '] = ' + JSON.stringify(replacement) + ';\n' +
    'drafts["mbg-report-draft:v2:other"] = ' + JSON.stringify(replacement) + ';\n' +
    'var matched = true;'));
  return process.stdout.write(JSON.stringify({matched,
    dirty: !!savingPage.field.__MBG_REPORT_DRAFT_DIRTY,
    touched: !!savingPage.field.__MBG_REPORT_DRAFT_TOUCHED,
    unchanged: before === JSON.stringify(Array.from(storage.values.entries()))}));
}
if (spec.scenario === 'saveFailure') storage.failWrite = true;
savingPage.field.dispatchEvent(new FakeEvent('input', {bubbles: true}));
function statusText() { return savingPage.document.getElementById('mbg-report-draft-status-label').textContent; }
function pageHide() { for (const callback of savingPage.window.listeners.pagehide || []) callback(); }
function clearDraft() { savingPage.document.insertedStatus.children.find((child: any) =>child.textContent==='下書きを削除').listeners.click(); }
function retry() {
  const button: any=savingPage.document.insertedStatus.children.find((child: any) =>child.textContent==='再試行');
  if(button)button.listeners.click();
  return !!button;
}
function flushTimers() { const callbacks: any=Array.from(pendingTimers.values());pendingTimers.clear();for(const callback of callbacks)callback(); }
if (spec.scenario === 'selfRowContentEditable') {
  flushTimers();
  savingPage.field.textContent = 'first second';
  savingPage.field.dispatchEvent(new FakeEvent('input', {bubbles: true}));
  flushTimers();
  const restoringPage = createPage('', '', storage);
  runPage(restoringPage);
  const storedValues = Array.from(storage.values.values()).map((value: any) => JSON.parse(value).fields[0].value);
  return process.stdout.write(JSON.stringify({draftKeyCount: storage.length,
    storedValues, restoredText: restoringPage.field.textContent}));
}
if (spec.scenario === 'saveFailure') {
  const failureStatus: any=statusText(), dirtyAfterFailure: any=!!savingPage.field.__MBG_REPORT_DRAFT_DIRTY;
  const pendingAfterFailure: any=!!savingPage.window.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
  storage.failWrite=false;
  savingPage.document.field=null;
  pageHide();
  const saved: any=storage.key(0) && JSON.parse(storage.getItem(storage.key(0)));
  return process.stdout.write(JSON.stringify({failureStatus,dirtyAfterFailure,pendingAfterFailure,storedAfterRetry:saved && saved.fields[0].value}));
}
if (spec.scenario === 'deleteFailure') {
  storage.failRemove=true;clearDraft();const failureStatus: any=statusText();
  storage.failRemove=false;const hasRetry: any=retry();
  return process.stdout.write(JSON.stringify({failureStatus,hasRetry,remainingAfterRetry:storage.length}));
}
if (spec.scenario === 'deletePending') {
  clearDraft();flushTimers();pageHide();const remainingAfterPageHide: any=storage.length;
  savingPage.field.textContent='新しい入力';savingPage.field.dispatchEvent(new FakeEvent('input',{}));flushTimers();
  const saved: any=JSON.parse(storage.getItem(storage.key(0)));
  return process.stdout.write(JSON.stringify({remainingAfterPageHide,storedAfterNewInput:saved.fields[0].value}));
}
if (spec.scenario === 'clearFailure') {
  storage.failRemove=true;savingPage.field.textContent='';savingPage.field.dispatchEvent(new FakeEvent('input',{}));
  const failureStatus: any=statusText(),dirtyAfterFailure: any=!!savingPage.field.__MBG_REPORT_DRAFT_DIRTY;
  savingPage.window.__MBG_REPORT_DRAFT_UPDATE();
  return process.stdout.write(JSON.stringify({failureStatus,dirtyAfterFailure,textAfterUpdate:savingPage.field.textContent}));
}
if (spec.dropFieldBeforePageHide) {
  savingPage.document.field = null;
}
if (spec.firePageHide) {
  for (const callback of savingPage.window.listeners.pagehide || []) callback();
}

const key: any = storage.key(0);
if (!key) throw new Error('Draft was not saved');
const savedDraft: any = JSON.parse(storage.getItem(key));
const storedValue: any = savedDraft.fields[0].value;
if (Object.prototype.hasOwnProperty.call(spec, 'legacyValue')) {
  savedDraft.fields[0].value = spec.legacyValue;
  storage.setItem(key, JSON.stringify(savedDraft));
}

let sameDocumentRestoredText: any = null;
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

const restoringPage: any = createPage('', '', storage);
runPage(restoringPage);

process.stdout.write(JSON.stringify({
  storedValue,
  restoredText: restoringPage.field.textContent,
  restoredHtml: restoringPage.field.innerHTML,
  sameDocumentRestoredText,
  xssExecutionCount
}));
})();
