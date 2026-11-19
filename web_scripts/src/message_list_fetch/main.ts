import { largerMessageListPage, nextMessageListPage } from '../shared/message_list_paging.js';
import { readSmartphoneMessageRow } from '../shared/smartphone_message_rows.js';

declare const __mbgExpandMessageList: boolean | undefined;

function messageListFetch() {
  function text(node: Element | null) {
    return String(node && ((node as HTMLElement).innerText || node.textContent) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function fetchList(url: string) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, false);
    xhr.send(null);
    if (xhr.status < 200 || xhr.status >= 400) throw new Error('http');
    var doc = new DOMParser().parseFromString(xhr.responseText, 'text/html');
    var mobile = doc.querySelectorAll<HTMLElement>('div.button[onclick*="seqNo="]');
    var smartphone = mobile.length > 0 && text(doc.body).indexOf('連絡通知') >= 0;
    if (String(doc.title || '').indexOf('連絡通知') < 0 && !smartphone) return null;
    return {doc, mobile, smartphone};
  }

  try {
    var expanded = typeof __mbgExpandMessageList !== 'undefined' && __mbgExpandMessageList;
    var base = location.origin + '/campusweb/';
    var page = fetchList('/campusweb/campussquare.do?_flowId=KJW0001100-flow');
    if (!page) return JSON.stringify({status: 'missing', items: []});

    var items: {title: string; url: string; text: string}[] = [];
    var seen = new Set<string>();
    var limit = expanded ? 500 : 60;
    var partial = false;
    function add(item: typeof items[number]) {
      if (expanded) {
        var params = new URL(item.url).searchParams;
        var identity = JSON.stringify([params.get('keijitype'), params.get('genrecd'), params.get('seqNo')]);
        if (params.has('seqNo') && seen.has(identity)) return;
        seen.add(identity);
      }
      items.push({title: item.title, url: item.url, text: item.text});
    }

    // A bounded scan keeps the synchronous WebView fetch short. Pagination
    // only reads the existing list, using the flow key from the last response.
    for (var index = 0; page && index < 4; index += 1) {
      var previousCount = items.length;
      if (page.smartphone) {
        for (var m = 0; m < page.mobile.length && items.length < limit; m += 1) {
          var item = readSmartphoneMessageRow(page.mobile[m], base);
          if (item) add(item);
        }
      } else {
        var rows = page.doc.querySelectorAll('tr');
        for (var i = 0; i < rows.length && items.length < limit; i += 1) {
          var cells = rows[i].cells;
          var link = rows[i].querySelector('a[href]');
          if (!cells || cells.length < 3 || !link || rows[i].querySelector('tr') ||
              !/^[0-9]{4}\/[0-9]{1,2}\/[0-9]{1,2}/.test(text(cells[0]))) continue;
          add({
            title: text(link),
            url: new URL(link.getAttribute('href')!, base).href,
            // In a detached document, textContent does not separate cells.
            text: expanded
              ? Array.from(cells, text).filter(Boolean).join(' ')
              : text(rows[i])
          });
        }
      }

      if (!expanded || items.length >= limit || index === 3 ||
          location.origin !== 'https://gakujo.iess.niigata-u.ac.jp') break;
      if (items.length === previousCount && index > 0) break;
      try {
        var larger = index === 0 ? largerMessageListPage(page.doc, base) : null;
        var next = larger?.url || nextMessageListPage(page.doc, base);
        if (!next) break;
        page = fetchList(next);
        if (!page) partial = true;
      } catch (_) {
        partial = true;
        break;
      }
    }

    return JSON.stringify({status: partial ? 'partial' : 'ok', items: items});
  } catch (e) {
    return JSON.stringify({status: 'error', items: []});
  }
}
__mbgEntryResult = messageListFetch();
