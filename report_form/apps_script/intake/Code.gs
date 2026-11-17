const HEADERS_ = ['receipt', 'submissionKey', 'createdAt', 'client', 'type', 'title', 'content', 'steps', 'expected', 'version', 'platform', 'diagnosticStatus', 'diagnostic', 'status', 'issueDraft', 'payloadHash'];
const LIMITS_ = { title: 80, content: 4000, steps: 2000, expected: 1000, version: 40, diagnostic: 20000 };
const PLATFORMS_ = ['', 'windows', 'macos', 'linux', 'android', 'ios', 'other'];
const REPORT_TYPES_ = {
  bug: { label: 'バグ報告', content: '起きたこと', labels: 'bug,from-form' },
  request: { label: '機能追加の要望', content: '実現したい機能', labels: 'enhancement,from-form' },
  improvement: { label: '既存機能の改善要望', content: '今困っている点と、どう変わると良いか', labels: 'enhancement,from-form' },
  other: { label: 'その他', content: '内容', labels: 'from-form' }
};
const MAX_BYTES_ = 65536;

function doGet() {
  try {
    if (config_()) {
      return HtmlService.createHtmlOutputFromFile('Form')
        .setTitle('不具合・要望を送る | More Better Gakujo')
        .addMetaTag('viewport', 'width=device-width, initial-scale=1')
        .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
    }
  } catch (_) { /* Fail closed without exposing account or sheet details. */ }
  return HtmlService.createHtmlOutput('<!doctype html><html lang="ja"><head><meta charset="utf-8"></head><body><main><h1>現在は受け付けていません</h1><p>しばらくしてから、もう一度お試しください。</p><p><a href="https://github.com/terudoru/gakujo-chan-extender/issues" target="_blank" rel="noopener noreferrer">GitHub Issues（アカウントが必要・投稿は公開、新しいタブで開きます）</a></p></main></body></html>')
    .setTitle('現在は受け付けていません')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

function doPost(e) {
  let result;
  try {
    const post = e && e.postData;
    if (!post || typeof post.contents !== 'string') result = error_('invalid');
    // Check the advertised and actual body sizes before JSON.parse.
    else if (Number(post.length) > MAX_BYTES_ || post.contents.length > MAX_BYTES_ || utf8Size_(post.contents) > MAX_BYTES_) result = error_('too_large');
    else if (typeof post.type !== 'string' || !/^application\/json(?:\s*;.*)?$/i.test(post.type)) result = error_('invalid');
    else {
      let payload;
      try { payload = JSON.parse(post.contents); } catch (_) { result = error_('invalid'); }
      if (!result) result = receive_(payload, 'app');
    }
  } catch (_) { result = error_('unavailable'); }
  return ContentService.createTextOutput(JSON.stringify(result)).setMimeType(ContentService.MimeType.JSON);
}

function submitReport(payload) {
  try { return receive_(payload, 'web'); }
  catch (_) { return error_('unavailable'); }
}

function config_() {
  const props = PropertiesService.getScriptProperties().getProperties();
  if (props.ENABLED !== 'true' || typeof props.SHEET_ID !== 'string' || !/^[\w-]{10,}$/.test(props.SHEET_ID)) return null;
  const config = { SHEET_ID: props.SHEET_ID, ISSUE_REPO: props.ISSUE_REPO === undefined ? 'terudoru/gakujo-chan-extender' : props.ISSUE_REPO };
  if (!/^[\w.-]+\/[\w.-]+$/.test(config.ISSUE_REPO) || config.ISSUE_REPO.length > 200) return null;
  const defaults = { HOURLY_LIMIT: 20, DAILY_LIMIT: 100, MAX_ROWS: 5000 };
  for (const key of Object.keys(defaults)) {
    const raw = props[key];
    if (raw !== undefined && !/^[1-9]\d*$/.test(raw)) return null;
    config[key] = raw === undefined ? defaults[key] : Number(raw);
    if (!Number.isSafeInteger(config[key]) || config[key] <= 0) return null;
  }
  return config;
}

function sheet_(config) {
  const sheet = SpreadsheetApp.openById(config.SHEET_ID).getSheetByName('reports');
  if (!sheet) throw new Error('Report sheet unavailable');
  if (sheet.getLastRow() === 0) throw new Error('Report header unavailable');
  const header = sheet.getRange(1, 1, 1, HEADERS_.length).getValues()[0];
  if (!HEADERS_.every(function (name, i) { return header[i] === name; })) throw new Error('Report schema unavailable');
  return sheet;
}

function receive_(input, client) {
  const config = config_();
  if (!config) return error_('unavailable');
  if (utf8Size_(JSON.stringify(input) || '') > MAX_BYTES_) return error_('too_large');
  const validated = validate_(input, client);
  if (Object.keys(validated.fields).length) return { ok: false, code: 'invalid', fields: validated.fields };
  const value = validated.value;
  const hash = payloadHash_(value, client);
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return error_('busy');
  try {
    const sheet = sheet_(config);
    const lastRow = sheet.getLastRow();
    if (lastRow > 1) {
      const match = sheet.getRange(2, 2, lastRow - 1, 1).createTextFinder(value.submissionKey)
        .matchEntireCell(true).matchCase(true).findNext();
      if (match) {
        const existing = sheet.getRange(match.getRow(), 1, 1, HEADERS_.length).getValues()[0];
        // Admin has a separate lock and may have deleted rows after the search.
        if (existing[1] !== value.submissionKey) return error_('busy');
        if (existing[15] !== hash) return error_('conflict');
        return { ok: true, receipt: existing[0], duplicate: true };
      }
    }
    const now = Date.now();
    const properties = PropertiesService.getScriptProperties();
    const quotas = [
      { key: 'quota_h_' + Math.floor(now / 3600000), limit: config.HOURLY_LIMIT, period: 3600000 },
      { key: 'quota_d_' + Math.floor(now / 86400000), limit: config.DAILY_LIMIT, period: 86400000 }
    ];
    let retry = 0;
    quotas.forEach(function (quota) {
      const stored = properties.getProperty(quota.key);
      if (stored !== null && !/^\d+$/.test(stored)) throw new Error('Counter unavailable');
      quota.count = stored === null ? 0 : Number(stored);
      if (!Number.isSafeInteger(quota.count)) throw new Error('Counter unavailable');
      if (quota.count >= quota.limit) retry = Math.max(retry, Math.ceil((quota.period - now % quota.period) / 1000));
    });
    if (retry) return { ok: false, code: 'rate_limited', retryAfterSeconds: retry };
    if (lastRow - 1 >= config.MAX_ROWS) return error_('full');
    const receipt = receipt_();
    const draftLink = issueUrl_(config.ISSUE_REPO, value);
    // Reserve quota before writes: an interrupted write cannot bypass the cap.
    const updates = {};
    quotas.forEach(function (quota) { updates[quota.key] = String(quota.count + 1); });
    pruneCounters_(properties, now);
    properties.setProperties(updates);
    const row = [receipt, value.submissionKey, new Date(now).toISOString(), client, value.type,
      value.title, value.content, value.steps, value.expected, value.version, value.platform,
      client === 'web' ? 'web_none' : value.type !== 'bug' ? 'not_applicable' : value.diagnostic === null ? 'omitted_by_user' : 'attached',
      value.diagnostic === null ? '' : value.diagnostic, 'new', draftLink, hash];
    row.forEach(function (cell, i) {
      // Preserve text such as version 1.10 and titles like 3/4, as well as formulas.
      if (i !== 2 && i !== 14) row[i] = sheetText_(cell);
    });
    // Append the entire report once. Never reuse a row index across admin deletions.
    sheet.appendRow(row);
    return { ok: true, receipt: receipt, duplicate: false };
  } finally {
    try { SpreadsheetApp.flush(); } finally { lock.releaseLock(); }
  }
}

function validate_(input, client) {
  const fields = {};
  const value = {};
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { fields: { form: '入力内容を確認してください。' }, value: value };
  if (input.v !== 1) fields.v = '送信形式を確認してください。';
  if (input.client !== client) fields.client = '送信元を確認してください。';
  if (typeof input.submissionKey !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(input.submissionKey)) fields.submissionKey = '送信番号を確認してください。';
  value.submissionKey = input.submissionKey;
  value.diagnosticOmitted = client === 'app' ? input.diagnosticOmitted : false;
  value.type = input.type;
  if (typeof input.type !== 'string' || !Object.prototype.hasOwnProperty.call(REPORT_TYPES_, input.type)) fields.type = '種類を選んでください。';
  value.platform = input.platform;
  if (!PLATFORMS_.includes(input.platform)) fields.platform = 'OS を選び直してください。';
  if (input.consent !== true) fields.consent = '確認してチェックを入れてください。';
  for (const key of ['title', 'content', 'steps', 'expected', 'version']) {
    if (typeof input[key] !== 'string') { fields[key] = '文字で入力してください。'; value[key] = ''; continue; }
    value[key] = cleanText_(input[key]);
    if (value[key].length > LIMITS_[key]) fields[key] = LIMITS_[key] + '文字以内で入力してください。';
  }
  for (const key of ['title', 'content']) {
    if (!value[key] && !fields[key]) fields[key] = '入力してください。';
  }
  if (value.type !== 'bug') { value.steps = ''; value.expected = ''; }
  if (client === 'web' || value.type !== 'bug') {
    if (input.diagnostic !== null) fields.diagnostic = 'この報告では診断情報を送れません。';
    value.diagnostic = null;
  }
  if (client === 'app') {
    if (typeof input.diagnosticOmitted !== 'boolean') fields.diagnosticOmitted = '診断情報の送信方法を確認してください。';
  }
  if (client === 'app' && value.type === 'bug') {
    if (input.diagnostic === null) {
      value.diagnostic = null;
      if (input.diagnosticOmitted !== true) fields.diagnostic = '診断情報なしで送ることを選んでください。';
    } else if (typeof input.diagnostic !== 'string') fields.diagnostic = '診断情報の形式を確認してください。';
    else {
      value.diagnostic = cleanText_(input.diagnostic);
      if (value.diagnostic.length > LIMITS_.diagnostic) fields.diagnostic = LIMITS_.diagnostic + '文字以内にしてください。';
    }
  }
  return { fields: fields, value: value };
}

function cleanText_(value) {
  return value.replace(/[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/g, '').trim();
}

function sheetText_(value) {
  return value === '' ? '' : "'" + value;
}

function payloadHash_(value, client) {
  const canonical = JSON.stringify({ type: value.type, title: value.title, content: value.content, steps: value.steps, expected: value.expected, version: value.version, platform: value.platform, diagnostic: value.diagnostic, diagnosticOmitted: value.diagnosticOmitted, client: client });
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, canonical, Utilities.Charset.UTF_8)
    .map(function (byte) { return (byte & 255).toString(16).padStart(2, '0'); }).join('');
}

function pruneCounters_(properties, now) {
  Object.keys(properties.getProperties()).forEach(function (key) {
    const match = /^quota_([hd])_(\d+)$/.exec(key);
    if (match && Number(match[2]) !== Math.floor(now / (match[1] === 'h' ? 3600000 : 86400000))) properties.deleteProperty(key);
  });
}

function receipt_() {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ23456789';
  const hex = Utilities.getUuid().replace(/-/g, '');
  let bits = '';
  // Skip the fixed UUID version/variant bits; use 50 random bits for the receipt.
  for (const char of hex.slice(0, 12) + hex.slice(13, 16)) bits += parseInt(char, 16).toString(2).padStart(4, '0');
  let result = 'R-';
  for (let i = 0; i < 50; i += 5) result += alphabet[parseInt(bits.slice(i, i + 5), 2)];
  return result;
}

function issueUrl_(repo, report) {
  const neutralize = function (value) { return value.replace(/@/g, '@\u200b'); };
  const type = REPORT_TYPES_[report.type];
  const sections = [['種類', type.label], [type.content, report.content]];
  if (report.type === 'bug') sections.push(['問題が起きるまでの手順', report.steps], ['本来どうなってほしかったか', report.expected]);
  sections.push(['アプリのバージョン', report.version], ['OS', report.platform]);
  const body = sections.filter(function (section) { return section[1]; }).map(function (section) { return '### ' + section[0] + '\n' + neutralize(section[1]); }).join('\n\n');
  const base = 'https://github.com/' + repo + '/issues/new?title=' + urlComponent_(neutralize(report.title)) + '&labels=' + urlComponent_(type.labels) + '&body=';
  if ((base + urlComponent_(body)).length <= 6000) return base + urlComponent_(body);
  const note = '\n\n（URL の長さ制限のため省略しました。スプレッドシートで本文を確認してください。）';
  const chars = Array.from(body);
  let low = 0;
  let high = chars.length;
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    if ((base + urlComponent_(chars.slice(0, mid).join('') + note)).length <= 6000) low = mid;
    else high = mid - 1;
  }
  return base + urlComponent_(chars.slice(0, low).join('') + note);
}

function wellFormed_(value) {
  // JSON can carry isolated UTF-16 surrogates; keep draft URLs encodable.
  return value.replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, '\uFFFD');
}

function urlComponent_(value) { return encodeURIComponent(wellFormed_(value)); }
function utf8Size_(value) { return urlComponent_(value).replace(/%[0-9A-F]{2}|./g, 'x').length; }
function error_(code) { return { ok: false, code: code }; }
