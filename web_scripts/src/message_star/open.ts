import { messageOnclickUrl, readSmartphoneMessageRow } from '../shared/smartphone_message_rows.js';

declare const __mbgConfig: { message: { keijitype: string; genrecd: string; seqNo: string; title?: string; [key: string]: string | undefined } };

// Only explicit student actions run this script. The final GET is left to
// WebView navigation because opening a detail marks that message as read.
function messageStarOpen() {

  var message = __mbgConfig.message;
  var base = location.origin + '/campusweb/';
  function result(status: string, url?: string) { return JSON.stringify({status: status, url: url}); }
  function key(doc: Document) {
    var link = doc.querySelector('a[href*="_flowExecutionKey="]');
    if (link) {
      var value = new URL(link.getAttribute('href')!, base).searchParams.get('_flowExecutionKey');
      if (value) return value;
    }
    var input = doc.querySelector<HTMLInputElement>('input[name="_flowExecutionKey"]');
    if (input && input.value) return input.value;
    var actions = doc.querySelectorAll('[onclick*="_flowExecutionKey="]');
    for (var i = 0; i < actions.length; i += 1) {
      var href = messageOnclickUrl(actions[i]);
      if (!href) continue;
      var value = new URL(href, base).searchParams.get('_flowExecutionKey');
      if (value) return value;
    }
    return '';
  }
  function get(url: string) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, false);
    xhr.send(null);
    if (xhr.status < 200 || xhr.status >= 400) throw new Error('http');
    var doc = new DOMParser().parseFromString(xhr.responseText, 'text/html');
    var body = String(doc.body && (doc.body.innerText || doc.body.textContent) || '');
    if (/実行権限エラー|SYSTEM ERROR/.test(String(doc.title)) ||
        /^\s*(実行権限エラー|SYSTEM ERROR)/.test(body)) throw new Error('system');
    if (String(doc.title || '').indexOf('連絡通知') < 0 && body.indexOf('連絡通知') < 0) throw new Error('missing');
    return doc;
  }
  function url(flowKey: string, event: string) {
    if (!flowKey) throw new Error('key');
    return base + 'campussquare.do?_flowExecutionKey=' + encodeURIComponent(flowKey) +
      '&_eventId=' + event;
  }
  function nextPage(doc: Document) {
    var controls = doc.querySelectorAll<HTMLInputElement>('a,button,input[type="button"],input[type="submit"]');
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = String(control.textContent || control.value || '') + ' ' +
        (control.getAttribute('aria-label') || control.getAttribute('title') || '');
      if ((!/次へ|次のページ|次ページ|next/i.test(label) &&
          control.getAttribute('rel') !== 'next') || control.disabled ||
          control.getAttribute('aria-disabled') === 'true') continue;
      var href = control.getAttribute('href') || '';
      if (!href || /^(?:javascript:|#)/i.test(href)) {
        href = messageOnclickUrl(control) ||
          ((control.getAttribute('onclick') || href).match(
            /['"]([^'"]*[?&](?:_eventId=paging|_displayOffset=)[^'"]*)['"]/)
            || [])[1];
      }
      if (!href) continue;
      var target = new URL(href.replace(/&amp;/g, '&'), base + 'campussquare.do');
      if (target.origin !== location.origin ||
          target.pathname !== '/campusweb/campussquare.do' ||
          (target.searchParams.get('_eventId') !== 'paging' &&
           !target.searchParams.has('_displayOffset'))) continue;
      target.searchParams.set('_flowExecutionKey', key(doc));
      target.searchParams.set('_eventId', 'paging');
      return target.href;
    }
    return '';
  }
  try {
    if (location.origin !== 'https://gakujo.iess.niigata-u.ac.jp') return result('missing');
    for (var name of ['keijitype', 'genrecd', 'seqNo']) {
      if (!/^[0-9]+$/.test(message[name]!)) return result('error');
    }
    var genre = '&keijitype=' + encodeURIComponent(message.keijitype) +
                '&genrecd=' + encodeURIComponent(message.genrecd);
    var doc = get(base + 'campussquare.do?_flowId=KJW0001100-flow');
    doc = get(url(key(doc), 'dispKeijiListGenre') + genre);
    doc = get(url(key(doc), 'paging') + '&_displayCount=500');
    var found;
    var seenPages = new Set();
    for (var page = 0; page < 20; page += 1) {
      var links = Array.from(doc.querySelectorAll('a[href*="seqNo="]')).concat(
        Array.from(doc.querySelectorAll('[onclick*="seqNo="]')));
      var identities = [];
      for (var i = 0; i < links.length; i += 1) {
        var href = links[i].getAttribute('href') || messageOnclickUrl(links[i]);
        if (!href) continue;
        var params = new URL(href, base).searchParams;
        identities.push([params.get('keijitype'), params.get('genrecd'), params.get('seqNo')]);
        if (params.get('seqNo') === message.seqNo &&
            params.get('keijitype') === message.keijitype &&
            params.get('genrecd') === message.genrecd) {
          found = links[i];
          break;
        }
      }
      if (found) break;
      var next = nextPage(doc);
      if (!next) return result('gone');
      var signature = JSON.stringify(identities);
      if (seenPages.has(signature) || page === 19) return result('error');
      seenPages.add(signature);
      doc = get(next);
    }
    if (!found) return result('gone');
    var targetUrl = url(key(doc), 'confirm') + genre + '&seqNo=' + encodeURIComponent(message.seqNo);
    if (found.getAttribute('onclick') && found.querySelector) found = found.querySelector('p') || found;
    message.title = String((found as HTMLElement).innerText || found.textContent || '')
      .replace(/\s+/g, ' ').trim().replace(/\s*\[新着\]\s*$/, '');
    try {
      window.top!.sessionStorage.setItem('__MBG_MESSAGE_STARS_OPEN_MESSAGE', JSON.stringify(message));
    } catch (e) {}
    return result('ok', targetUrl);
  } catch (e) { return result((e as Error).message === 'missing' ? 'missing' : 'error'); }
}
__mbgEntryResult = messageStarOpen();
