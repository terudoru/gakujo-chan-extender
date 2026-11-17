import { issueDraft, issueUrl } from './issue.js';

const byId = (id) => document.getElementById(id);
let page = 1;
let selected;
let busy = false;
let generation = 0;
const statuses = { new: '未確認', issued: 'Issue にした', dismissed: '対応しない' };
const message = (text) => { byId('status').textContent = text; };
async function api(path, options = {}) {
  const response = await fetch(`/api/dashboard/reports${path}`, { cache: 'no-store', ...options });
  const result = await response.json();
  if (!response.ok) throw new Error(result.message || '操作に失敗しました。');
  return result;
}
async function list() {
  const current = ++generation;
  message('読み込んでいます。');
  try {
    const result = await api(`?status=${encodeURIComponent(byId('filter').value)}&page=${page}`);
    if (current !== generation) return;
    const items = result.reports.map((report) => {
      const li = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = `#${report.id} ${report.title}`;
      button.addEventListener('click', () => detail(report.id));
      li.append(button);
      return li;
    });
    byId('reports').replaceChildren(...items);
    byId('previous').disabled = page === 1;
    byId('next').disabled = !result.hasMore;
    byId('page').textContent = `${page}ページ目`;
    message(items.length ? '' : 'この状態の報告はありません。');
  } catch (error) { if (current === generation) message(error.message); }
}
async function detail(id) {
  const current = ++generation;
  message('読み込んでいます。');
  try {
    const { report, repo } = await api(`/${id}`);
    if (current !== generation) return;
    selected = report;
    byId('report-title').textContent = `#${report.id} ${report.title}`;
    byId('report-meta').textContent = `${new Date(report.created_at * 1000).toLocaleString('ja-JP')} / ${statuses[report.status]}${report.issue_number ? ` / Issue #${report.issue_number}` : ''}`;
    const fields = [['種類', report.type === 'bug' ? '不具合' : '要望・改善案'], ['内容', report.content], ['問題が起きるまでの手順', report.steps], ['本来どうなってほしかったか', report.expected], ['アプリのバージョン', report.version], ['OS（Windows・Mac・Android など）', report.platform]];
    const nodes = [];
    for (const [label, value] of fields) {
      if (!value) continue;
      const heading = document.createElement('h3'); heading.textContent = label;
      const text = document.createElement('p'); text.className = 'report-text'; text.textContent = value;
      nodes.push(heading, text);
    }
    byId('public-fields').replaceChildren(...nodes);
    byId('diagnostic').textContent = report.diagnostic || '添付なし';
    byId('issue-link').href = issueUrl(repo, report);
    byId('list-view').hidden = true;
    byId('detail-view').hidden = false;
    byId('report-title').focus();
    message('');
  } catch (error) { if (current === generation) message(error.message); }
}
async function update(status) {
  if (busy || !selected) return;
  const body = { status };
  if (status === 'issued') {
    const answer = window.prompt('作成した GitHub Issue の番号を入力してください。', selected.issue_number || '');
    if (answer === null) return;
    if (!/^[1-9]\d*$/.test(answer) || !Number.isSafeInteger(Number(answer))) { message('Issue 番号を半角数字で入力してください。'); return; }
    body.issueNumber = Number(answer);
  }
  busy = true;
  try {
    await api(`/${selected.id}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    await detail(selected.id);
    message('状態を保存しました。');
  } catch (error) { message(error.message); }
  finally { busy = false; }
}
byId('filter').addEventListener('change', () => { page = 1; void list(); });
byId('previous').addEventListener('click', () => { if (page > 1) { page--; void list(); } });
byId('next').addEventListener('click', () => { page++; void list(); });
byId('back').addEventListener('click', () => { if (busy) return; selected = undefined; byId('detail-view').hidden = true; byId('list-view').hidden = false; void list(); });
byId('copy').addEventListener('click', async () => {
  if (!selected) return;
  const draft = issueDraft(selected);
  try { await navigator.clipboard.writeText(`# ${draft.title}\n\n${draft.body}`); message('公開欄だけをコピーしました。貼り付け先でも内容を確認してください。'); }
  catch { message('コピーできませんでした。ブラウザのクリップボード権限を確認してください。'); }
});
for (const status of ['new', 'issued', 'dismissed']) byId(status).addEventListener('click', () => { void update(status); });
byId('delete').addEventListener('click', async () => {
  if (busy || !selected || !window.confirm('この報告と診断情報を削除します。元に戻せません。削除しますか？')) return;
  busy = true;
  try {
    await api(`/${selected.id}`, { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    selected = undefined;
    byId('detail-view').hidden = true; byId('list-view').hidden = false;
    await list(); message('報告を削除しました。');
  } catch (error) { message(error.message); }
  finally { busy = false; }
});
void list();
