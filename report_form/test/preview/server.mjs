// Local preview only. No Google requests, credentials, spreadsheet writes or dependencies.
import http from 'node:http';
import { readFileSync } from 'node:fs';

const fake = `<script>
(() => {
  const scenario = new URLSearchParams(location.search).get('scenario') || 'success';
  let success, failure;
  const run = {
    withSuccessHandler(fn) { success = fn; return run; },
    withFailureHandler(fn) { failure = fn; return run; },
    submitReport(payload) {
      if (scenario === 'pending') {
        window.finishPreview = result => success(result);
        window.failPreview = () => failure(new Error('Local preview failure'));
        return;
      }
      setTimeout(() => {
        if (scenario === 'transport') { failure(new Error('Local preview failure')); return; }
        const results = {
          success: { ok: true, receipt: 'R-PREVIEW234', duplicate: false },
          rate_limited: { ok: false, code: 'rate_limited', retryAfterSeconds: 90 },
          busy: { ok: false, code: 'busy' }, unavailable: { ok: false, code: 'unavailable' }, full: { ok: false, code: 'full' }, conflict: { ok: false, code: 'conflict' },
          invalid: { ok: false, code: 'invalid', fields: { title: '件名を確認してください。' } }
        };
        success(results[scenario] || results.success);
      }, 300);
    }
  };
  window.google = { script: { run } };
})();
</script>`;

export function createPreviewServer() {
  return http.createServer((request, response) => {
    const path = new URL(request.url, 'http://localhost').pathname;
    let html;
    if (path === '/' || path === '/form') html = readFileSync(new URL('../../apps_script/intake/Form.html', import.meta.url), 'utf8').replace('<script>', fake + '\n<script>');
    else if (path === '/site') html = readFileSync(new URL('../../../site/report/index.html', import.meta.url), 'utf8');
    else { response.writeHead(404); response.end('Not found'); return; }
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }); response.end(html);
  });
}

// Node's default test discovery also visits test/preview/. Never start a listener there.
if (!process.env.NODE_TEST_CONTEXT) {
  const port = Number(process.env.PORT || 8788);
  createPreviewServer().listen(port, '127.0.0.1', () => console.log(`Local preview: http://127.0.0.1:${port}/form (fake submission only); /site for the unconfigured Pages page`));
}
