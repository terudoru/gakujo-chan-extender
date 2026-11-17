import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { randomUUID, createHash } from 'node:crypto';
import vm from 'node:vm';

export const source = readFileSync(new URL('../apps_script/intake/Code.gs', import.meta.url), 'utf8');
export const adminSource = readFileSync(new URL('../apps_script/admin/Code.gs', import.meta.url), 'utf8');
export const formHtml = readFileSync(new URL('../apps_script/intake/Form.html', import.meta.url), 'utf8');
export const headers = ['receipt', 'submissionKey', 'createdAt', 'client', 'type', 'title', 'content', 'steps', 'expected', 'version', 'platform', 'diagnosticStatus', 'diagnostic', 'status', 'issueDraft', 'payloadHash'];
export function payload(overrides = {}) {
  return { v: 1, client: 'app', submissionKey: randomUUID(), type: 'bug', title: '通知が開けない', content: '通知を押すと閉じます。', steps: '通知を押す', expected: '通知の内容を開く', version: '1.2.3', platform: 'windows', consent: true, diagnostic: '{"error":"private-test-only"}', diagnosticOmitted: false, ...overrides };
}

export function environment(options = {}) {
  let now = Date.parse('2026-11-17T03:15:00.000Z');
  const intakeLock = { held: false }; const adminLock = { held: false };
  const held = () => intakeLock.held || adminLock.held;
  const env = { rows: (options.rows ?? [headers]).map(row => [...row]), rich: new Map(), writes: [], reads: [], searches: [], formulas: [], releases: 0, attempts: [], lockAvailable: true, failOpen: false, failAppend: false, failDigest: false, beforeAppend: null, beforeMatchRead: null, flushes: 0 };
  function storedCell(value, row, column) {
    if (typeof value !== 'string' || value === '') return value;
    if (value.startsWith("'")) return value.slice(1);
    if (value.startsWith('=')) { env.formulas.push({ row, column, formula: value }); return '#FAKE_FORMULA'; }
    if (/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value)) return Number(value);
    const date = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{4}))?$/.exec(value);
    if (date) return new Date(Date.UTC(Number(date[3] || new Date(now).getUTCFullYear()), Number(date[1]) - 1, Number(date[2])));
    return value;
  }
  const properties = { SHEET_ID: 'test_spreadsheet_id', ENABLED: 'true', ...options.properties };
  env.properties = properties;
  const propertyApi = {
    getProperties() { return { ...properties }; },
    getProperty(key) { if (key.startsWith('quota_')) assert.ok(intakeLock.held, 'quota lookup must hold intake lock'); return Object.hasOwn(properties, key) ? properties[key] : null; },
    setProperty(key, value) { assert.ok(intakeLock.held); properties[key] = String(value); return this; },
    setProperties(values) { assert.ok(intakeLock.held); for (const [key, value] of Object.entries(values)) properties[key] = String(value); env.writes.push({ properties: { ...values } }); return this; },
    deleteProperty(key) { assert.ok(intakeLock.held); delete properties[key]; return this; }
  };
  const sheet = {
    getLastRow() { assert.ok(held(), 'sheet read must hold lock'); return env.rows.length; },
    getDataRange() { assert.fail('Do not load the entire report sheet for dedupe'); },
    appendRow(row) {
      assert.ok(intakeLock.held); assert.equal(row.length, headers.length);
      if (env.failAppend) throw Error('Injected pre-write failure');
      if (env.beforeAppend) { const hook = env.beforeAppend; env.beforeAppend = null; hook(); }
      env.rows.push(Array.from(row, (cell, column) => storedCell(cell, env.rows.length + 1, column + 1))); env.writes.push({ append: [...row] }); return this;
    },
    getRange(row, column, count = 1, columns = 1) {
      assert.ok(held(), 'sheet range must hold lock');
      assert.ok(row >= 1 && column >= 1 && count >= 1 && columns >= 1);
      return {
        getValues() {
          assert.ok(held());
          if (env.beforeMatchRead && count === 1 && columns === headers.length && row > 1) { const hook = env.beforeMatchRead; env.beforeMatchRead = null; hook(); }
          env.reads.push({ row, column, count, columns });
          return Array.from({ length: count }, (_, i) => Array.from({ length: columns }, (_, j) => env.rows[row - 1 + i]?.[column - 1 + j] ?? ''));
        },
        getRow() { return row; },
        createTextFinder(text) {
          assert.ok(intakeLock.held);
          const search = { text, row, column, count, columns, entire: false, caseSensitive: false }; env.searches.push(search);
          return {
            matchEntireCell(value) { search.entire = value; return this; },
            matchCase(value) { search.caseSensitive = value; return this; },
            findNext() {
              assert.ok(intakeLock.held);
              for (let i = row; i < row + count; i++) for (let j = column; j < column + columns; j++) {
                let value = String(env.rows[i - 1]?.[j - 1] ?? ''); let needle = String(text);
                if (!search.caseSensitive) { value = value.toLowerCase(); needle = needle.toLowerCase(); }
                if (search.entire ? value === needle : value.includes(needle)) return sheet.getRange(i, j);
              }
              return null;
            }
          };
        },
        setValues(values) {
          assert.ok(held()); assert.equal(values.length, count);
          values.forEach((valuesRow, i) => { assert.equal(valuesRow.length, columns); env.rows[row - 1 + i] ??= []; valuesRow.forEach((value, j) => { env.rows[row - 1 + i][column - 1 + j] = storedCell(value, row + i, column + j); }); });
          env.writes.push({ setValues: { row, column, values: values.map(value => [...value]) } });
          return this;
        },
        setRichTextValue(value) {
          assert.ok(held()); assert.equal(count, 1); assert.equal(columns, 1);
          assert.equal(value.kind, 'RichTextValue');
          env.rows[row - 1] ??= []; env.rows[row - 1][column - 1] = value.text;
          env.rich.set(`${row}:${column}`, value); return this;
        },
        setFormula() { assert.fail('Formulas are prohibited'); }
      };
    },
    deleteRows(start, count) {
      assert.ok(adminLock.held); assert.ok(start > 1 && count > 0 && start + count - 1 <= env.rows.length);
      env.rows.splice(start - 1, count);
      const shifted = new Map();
      for (const [key, value] of env.rich) {
        const [row, col] = key.split(':').map(Number);
        if (row < start) shifted.set(key, value);
        else if (row >= start + count) shifted.set(`${row - count}:${col}`, value);
      }
      env.rich = shifted; env.writes.push({ deleted: [start, count] }); return this;
    }
  };
  class FakeDate extends Date { constructor(...args) { super(...(args.length ? args : [now])); } static now() { return now; } }
  function htmlOutput(content) {
    return { content, frameMode: null, meta: [], setTitle(title) { this.title = title; return this; }, addMetaTag(name, value) { this.meta.push([name, value]); return this; }, setXFrameOptionsMode(mode) { this.frameMode = mode; return this; } };
  }
  const globals = {
    Date: FakeDate,
    SpreadsheetApp: {
      openById(id) { assert.ok(intakeLock.held); assert.equal(id, properties.SHEET_ID); if (env.failOpen) throw Error('Injected service failure'); return { getSheetByName(name) { assert.equal(name, 'reports'); return options.missingSheet ? null : sheet; } }; },
      getActiveSpreadsheet() { assert.ok(adminLock.held); return { getSheetByName(name) { assert.equal(name, 'reports'); return options.missingSheet ? null : sheet; } }; },
      flush() { assert.ok(held()); env.flushes++; },
      newRichTextValue() { return { text: '', link: null, setText(text) { this.text = text; return this; }, setLinkUrl(link) { this.link = link; return this; }, build() { return { kind: 'RichTextValue', text: this.text, link: this.link }; } }; }
    },
    LockService: locks(intakeLock),
    PropertiesService: { getScriptProperties() { return propertyApi; } },
    ContentService: { MimeType: { JSON: 'application/json' }, createTextOutput(text) { return { text, setMimeType(type) { this.mimeType = type; return this; } }; } },
    HtmlService: { XFrameOptionsMode: { ALLOWALL: 'ALLOWALL' }, createHtmlOutput: htmlOutput, createHtmlOutputFromFile(name) { assert.equal(name, 'Form'); return htmlOutput(formHtml); } },
    Utilities: { getUuid: randomUUID, DigestAlgorithm: { SHA_256: 'SHA_256' }, Charset: { UTF_8: 'UTF-8' }, computeDigest(algorithm, value, charset) { assert.equal(algorithm, 'SHA_256'); assert.equal(charset, 'UTF-8'); if (env.failDigest) throw Error('Injected digest failure'); return [...createHash('sha256').update(value, 'utf8').digest()].map(byte => byte > 127 ? byte - 256 : byte); } },
    console: { log() { assert.fail('Never log reports'); }, error() { assert.fail('Never log reports'); } }
  };
  function locks(state) {
    return { getScriptLock() { return { tryLock(timeout) { env.attempts.push(timeout); assert.equal(timeout, 10000); if (!env.lockAvailable) return false; assert.equal(state.held, false); state.held = true; return true; }, releaseLock() { assert.ok(state.held); assert.ok(env.flushes > env.releases, 'flush before release'); state.held = false; env.releases++; } }; } };
  }
  env.context = vm.createContext({ ...globals });
  new vm.Script(source, { filename: 'Code.gs' }).runInContext(env.context);
  const adminProperties = { ...options.adminProperties }; env.adminProperties = adminProperties;
  const adminPropertyApi = {
    getProperty(key) { return Object.hasOwn(adminProperties, key) ? adminProperties[key] : null; },
    setProperty(key, value) { assert.ok(adminLock.held); adminProperties[key] = String(value); return this; },
    getProperties() { return { ...adminProperties }; }
  };
  env.adminContext = vm.createContext({ ...globals, LockService: locks(adminLock), PropertiesService: { getScriptProperties() { return adminPropertyApi; } } });
  new vm.Script(adminSource, { filename: 'admin/Code.gs' }).runInContext(env.adminContext);
  env.setNow = value => { now = typeof value === 'number' ? value : Date.parse(value); };
  env.now = () => now;
  env.isLocked = held;
  env.intakeIsLocked = () => intakeLock.held;
  env.adminIsLocked = () => adminLock.held;
  env.app = (value, postOverrides = {}) => {
    const contents = JSON.stringify(value);
    const result = env.context.doPost({ postData: { contents, length: Buffer.byteLength(contents), type: 'application/json', ...postOverrides } });
    assert.equal(result.mimeType, 'application/json');
    return JSON.parse(result.text);
  };
  env.web = value => JSON.parse(JSON.stringify(env.context.submitReport(value)));
  env.output = event => JSON.parse(env.context.doPost(event).text);
  return env;
}
