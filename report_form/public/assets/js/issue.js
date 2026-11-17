const neutralize = (value) => String(value ?? '').replace(/@/g, '@\u200b');

// An explicit allowlist prevents private fields being included even if the schema grows.
export function issueDraft(report) {
  const sections = [
    ['種類', report.type === 'bug' ? '不具合' : '要望・改善案'],
    ['内容', report.content],
    ...(report.type === 'bug' ? [['問題が起きるまでの手順', report.steps], ['本来どうなってほしかったか', report.expected]] : []),
    ['アプリのバージョン', report.version],
    ['OS', report.platform],
  ];
  return {
    title: neutralize(report.title),
    body: sections.filter(([, value]) => value).map(([label, value]) => `### ${label}\n${neutralize(value)}`).join('\n\n'),
    labels: `${report.type === 'bug' ? 'bug' : 'enhancement'},from-form`,
  };
}

export function issueUrl(repo, report, maxLength = 6000) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Invalid repository');
  const draft = issueDraft(report);
  const build = (body) => {
    const url = new URL(`https://github.com/${repo}/issues/new`);
    url.search = new URLSearchParams({ title: draft.title, body, labels: draft.labels }).toString();
    return url.href;
  };
  if (build(draft.body).length <= maxLength) return build(draft.body);
  const note = '\n\n（URL の長さ制限のため省略しました。管理画面で本文を確認してください。）';
  // Search by Unicode characters, never splitting a surrogate pair.
  const chars = Array.from(draft.body);
  let low = 0;
  let high = chars.length;
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    if (build(chars.slice(0, mid).join('') + note).length <= maxLength) low = mid;
    else high = mid - 1;
  }
  return build(chars.slice(0, low).join('') + note);
}
