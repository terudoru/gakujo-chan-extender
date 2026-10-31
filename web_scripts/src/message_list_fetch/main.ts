import { messageOnclickUrl, readSmartphoneMessageRow } from '../shared/smartphone_message_rows.js';

function messageListFetch() {

  function text(node: Element | null) {
    return String(node && ((node as HTMLElement).innerText || node.textContent) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }
  try {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/campusweb/campussquare.do?_flowId=KJW0001100-flow', false);
    xhr.send(null);
    if (xhr.status < 200 || xhr.status >= 400) {
      return JSON.stringify({status: 'error', items: []});
    }
    var doc = new DOMParser().parseFromString(xhr.responseText, 'text/html');
    var mobile = doc.querySelectorAll<HTMLElement>('div.button[onclick*="seqNo="]');
    var smartphone = mobile.length > 0 && text(doc.body).indexOf('連絡通知') >= 0;
    if (String(doc.title || '').indexOf('連絡通知') < 0 && !smartphone) {
      return JSON.stringify({status: 'missing', items: []});
    }
    var base = location.origin + '/campusweb/';
    var items = [];
    if (smartphone) {
      for (var m = 0; m < mobile.length && items.length < 60; m += 1) {
        var item = readSmartphoneMessageRow(mobile[m], base);
        if (item) items.push({title: item.title, url: item.url, text: item.text});
      }
      return JSON.stringify({status: 'ok', items: items});
    }
    var rows = doc.querySelectorAll('tr');
    for (var i = 0; i < rows.length && items.length < 60; i += 1) {
      var cells = rows[i].cells;
      var link = rows[i].querySelector('a[href]');
      if (!cells || cells.length < 3 || !link || rows[i].querySelector('tr') ||
          !/^[0-9]{4}\/[0-9]{1,2}\/[0-9]{1,2}/.test(text(cells[0]))) {
        continue;
      }
      items.push({
        title: text(link),
        url: new URL(link.getAttribute('href')!, base).href,
        text: text(rows[i])
      });
    }
    return JSON.stringify({status: 'ok', items: items});
  } catch (e) {
    return JSON.stringify({status: 'error', items: []});
  }
}
__mbgEntryResult = messageListFetch();
