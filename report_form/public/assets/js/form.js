import { LIMITS, PLATFORMS, TYPES, validateReport } from './report-schema.js';

const form = document.querySelector('#report-form');
const status = document.querySelector('#status');
const submit = document.querySelector('#submit');
const verificationRetry = document.querySelector('#verification-retry');
const key = document.querySelector('meta[name=turnstile-site-key]').content;
const available = document.querySelector('meta[name=report-available]').content === 'true';
let started = performance.now();
let token = '';
let widget;
let sending = false;
let retryAt = 0;
let retryTimer;
let attempted = false;
let verificationScript;
let statusKind = '';
let verificationMessage = '';

function data() {
  const input = Object.fromEntries(new FormData(form));
  input.consent = form.elements.consent.checked;
  input.turnstileToken = token;
  input.elapsedMs = Math.floor(performance.now() - started);
  return input;
}

function message(text, focus = false, kind = 'result') {
  status.textContent = text;
  statusKind = text ? kind : '';
  if (focus) { status.focus(); status.scrollIntoView({ block: 'center' }); }
}
function refreshButtons() {
  submit.disabled = sending || !available || !key || !token || Date.now() < retryAt;
  const help = document.querySelector('#verification-help');
  if (!available || !key) help.textContent = '現在は送信できません。GitHub アカウントをお持ちの方は、下のリンクから直接報告できます。';
  else if (sending) help.textContent = '送信しています。';
  else if (Date.now() < retryAt) help.textContent = `あと${Math.ceil((retryAt - Date.now()) / 60000)}分ほどお待ちください。待機中は送信できません。`;
  else if (!token) help.textContent = verificationRetry.hidden
    ? '認証が完了するまで送信できません。完了までお待ちください。'
    : verificationMessage || '認証が完了するまで送信できません。うまくいかない場合は「もう一度確認する」を押してください。';
  else help.textContent = '認証が完了しました。送信できます。';
}
function resetVerification() {
  token = '';
  if (widget !== undefined && window.turnstile) window.turnstile.reset(widget);
  refreshButtons();
}
function errors(fields = {}) {
  for (const name of [...Object.keys(LIMITS), 'type', 'platform', 'consent']) {
    const element = document.getElementById(`${name}-error`);
    element.textContent = fields[name] || '';
    const controls = name === 'type' ? form.querySelectorAll('[name=type]') : [form.elements[name]];
    for (const control of controls) control.setAttribute('aria-invalid', String(Boolean(fields[name])));
  }
}
function counters() {
  for (const [name, max] of Object.entries(LIMITS)) document.getElementById(`${name}-count`).textContent = `${form.elements[name].value.length} / ${max}文字`;
}
function focusFirst(fields) {
  const first = Object.keys(fields).find((name) => form.elements[name]);
  const control = first === 'type' ? form.querySelector('[name=type]') : form.elements[first];
  if (control) { control.focus(); control.scrollIntoView({ block: 'center' }); }
  else { status.focus(); status.scrollIntoView({ block: 'center' }); }
}
function changeType() {
  const bug = form.elements.type.value === 'bug';
  document.querySelector('#bug-fields').hidden = !bug;
  form.elements.steps.disabled = !bug;
  form.elements.expected.disabled = !bug;
  form.elements.content.placeholder = bug ? '何をしたら何が起きたか' : '何に困っていて、どうなると嬉しいか';
}
const query = new URLSearchParams(location.search);
if (TYPES.includes(query.get('type'))) form.elements.type.value = query.get('type');
form.elements.version.value = (query.get('version') || '').slice(0, LIMITS.version);
if (PLATFORMS.includes(query.get('platform'))) form.elements.platform.value = query.get('platform');
changeType();
counters();
refreshButtons();
form.addEventListener('input', () => { counters(); if (attempted) errors(validateReport(data()).errors); });
form.addEventListener('change', () => { changeType(); if (attempted) errors(validateReport(data()).errors); });

function verificationFailed(text) {
  token = '';
  if (form.hidden) return;
  verificationMessage = text;
  verificationRetry.hidden = false;
  verificationRetry.disabled = false;
  refreshButtons();
  if (statusKind !== 'result') message(text, true, 'verification');
}
function renderVerification() {
  widget = window.turnstile.render('#turnstile', {
    sitekey: key, action: 'report',
    callback: (value) => {
      token = value;
      verificationMessage = '';
      verificationRetry.hidden = true;
      refreshButtons();
      // A reset after a failed submission must not overwrite the submission result.
      if (statusKind === 'verification') message('');
    },
    'expired-callback': () => {
      verificationFailed('認証の有効期限が切れたので、確認をやり直しています。入力内容は残っています。');
      resetVerification();
    },
    'error-callback': () => verificationFailed('認証を確認できませんでした。通信環境を確認し、「もう一度確認する」を押してください。入力内容は残っています。'),
  });
}
function loadVerification() {
  verificationRetry.disabled = true;
  verificationScript?.remove();
  const script = document.createElement('script');
  verificationScript = script;
  script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
  script.async = true;
  script.onload = () => window.turnstile.ready(() => {
    verificationRetry.disabled = false;
    renderVerification();
  });
  script.onerror = () => verificationFailed('認証を読み込めませんでした。通信環境を確認し、「もう一度確認する」を押してください。入力内容は残っています。');
  document.head.append(script);
}
verificationRetry.addEventListener('click', () => {
  verificationMessage = '認証を確認しています。入力内容は残っています。';
  if (statusKind !== 'result') message(verificationMessage, false, 'verification');
  if (window.turnstile && widget !== undefined) resetVerification();
  else loadVerification();
});
if (!available || !key) {
  message('現在は送信できません。GitHub アカウントをお持ちの方は、下のリンクから直接報告できます。');
  for (const control of form.querySelectorAll('input, textarea, select, fieldset')) control.disabled = true;
} else loadVerification();

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (sending || !available || !key || Date.now() < retryAt) return;
  attempted = true;
  const input = data();
  const validation = validateReport(input);
  errors(validation.errors);
  const first = Object.keys(validation.errors)[0];
  if (first) {
    message('入力内容を確認してください。');
    focusFirst(validation.errors);
    return;
  }
  if (!token) { message('認証が完了してから送信してください。', true); resetVerification(); return; }
  if (input.elapsedMs < 3000) { message('内容を確認し、3秒ほど待ってから送信してください。', true); return; }
  sending = true;
  submit.textContent = '送信中…';
  message('送信しています。');
  refreshButtons();
  try {
    const response = await fetch('/api/reports', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input), signal: AbortSignal.timeout(30000) });
    if (response.status >= 500) {
      message('現在は送信できません。サーバーで問題が起きました。しばらく待ってから、もう一度お試しください。入力内容は残っています。', true);
      return;
    }
    let result = {};
    try { result = await response.json(); } catch { /* HTTP status still determines the retry message. */ }
    if (response.status === 201 && Number.isSafeInteger(result.id)) {
      form.hidden = true;
      document.querySelector('#success').hidden = false;
      document.querySelector('#receipt').textContent = `受付番号: ${result.id}`;
      message('');
      document.querySelector('#success-title').focus();
      return;
    }
    if (response.status === 422) {
      errors(result.errors);
      message('入力内容を確認して、もう一度送信してください。');
      focusFirst(result.errors || {});
    }
    else if (response.status === 429) {
      const seconds = Math.max(1, Number(response.headers.get('Retry-After')) || Number(result.retryAfter) || 600);
      retryAt = Date.now() + seconds * 1000;
      message(`約${Math.ceil(seconds / 60)}分（${seconds}秒）待ってから、もう一度送信してください。入力内容は残っています。`, true);
      clearTimeout(retryTimer);
      retryTimer = setTimeout(() => {
        retryAt = 0;
        refreshButtons();
        message(token ? '待機時間が終わりました。送信できます。' : '待機時間が終わりました。認証が完了したら送信できます。');
      }, seconds * 1000);
    } else message(result.message || '現在は送信できません。入力内容を確認し、もう一度お試しください。', true);
  } catch {
    message('現在は送信できません。通信環境を確認してください。受け付けられた可能性がありますが、同じ内容を送り直しても問題ありません。開発者が重複をまとめます。入力内容は残っています。', true);
  } finally {
    sending = false;
    submit.textContent = form.hidden ? '送信する' : 'もう一度送信する';
    if (!form.hidden) { verificationRetry.hidden = false; resetVerification(); }
    else refreshButtons();
  }
});

document.querySelector('#another').addEventListener('click', () => {
  form.reset();
  attempted = false;
  started = performance.now();
  retryAt = 0;
  verificationMessage = '';
  verificationRetry.hidden = true;
  clearTimeout(retryTimer);
  errors(); counters(); changeType();
  message(''); submit.textContent = '送信する';
  document.querySelector('#success').hidden = true;
  form.hidden = false;
  resetVerification();
  form.elements.title.focus();
});
