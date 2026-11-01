import { messageOnclickUrl, readSmartphoneMessageRow } from '../shared/smartphone_message_rows.js';
import { readAssignmentRows } from '../shared/assignment_rows.js';

function pageTextActivity() {

  var texts: string[] = [];
  var messageItems: { title: string; url: string; text: string }[] = [];
  var reportItems: ReturnType<typeof readAssignmentRows> = [];
  var seenMessageItems: Record<string, boolean> = {};
  var datePattern = /((?:令和[0-9]{1,2}年|(?:20)?[0-9]{2}(?:[\/.\-]|年))[0-9]{1,2}(?:[\/.\-]|月)[0-9]{1,2}日?(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}[\/.][0-9]{1,2}(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}月[0-9]{1,2}日(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?)/;
  function compactText(element: (Element & { innerText?: string; value?: string }) | null) {
    return (element && (element.innerText || element.textContent || element.value) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }
  function compactRawText(text: string) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }
  function normalizeDateText(text: string) {
    return String(text || '')
      .replace(/[０-９]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 0xFEE0);
      })
      .replace(/：/g, ':')
      .replace(/／/g, '/')
      .replace(/．/g, '.')
      .replace(/[－−]/g, '-');
  }
  function isPortalNoiseText(text: string) {
    var normalized = normalizeDateText(compactRawText(text));
    if (!normalized) {
      return true;
    }
    if (normalized.indexOf('MYスケジュール') >= 0 ||
        normalized.indexOf('前回ログイン日時') >= 0 ||
        normalized.indexOf('ログアウト') >= 0 ||
        normalized.indexOf('残り約') >= 0 ||
        /^Copyright/.test(normalized)) {
      return true;
    }
    if (/^[0-9]{4}\/[0-9]{1,2}\/[0-9]{1,2}\([A-Za-z]+\)$/.test(normalized)) {
      return true;
    }
    if (/^[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日\s*[0-9]{1,2}時[0-9]{1,2}分\s*(から|まで)?$/.test(normalized)) {
      return true;
    }
    return false;
  }
  function hasDate(text: string) {
    return datePattern.test(normalizeDateText(text));
  }
  function messageTable(doc: Document) {
    var direct = doc.querySelector('table.normal:nth-child(9)');
    if (direct) {
      return direct;
    }
    var tables = doc.querySelectorAll('table');
    for (var i = 0; i < tables.length; i += 1) {
      var text = compactText(tables[i]);
      if ((text.indexOf('掲示') >= 0 || text.indexOf('連絡') >= 0) &&
          tables[i].querySelector('a[href]')) {
        return tables[i];
      }
    }
    return null;
  }
  function messageUrl(doc: Document, node: Element) {
    var link = node && node.closest && node.closest<HTMLAnchorElement>('a[href]');
    if (!link && node && node.querySelector) {
      link = node.querySelector<HTMLAnchorElement>('a[href]');
    }
    var href = link && link.href || '';
    if (href && !/^javascript:/i.test(href)) {
      return href;
    }
    try {
      return doc.location.href || document.location.href;
    } catch (e) {
      return document.location.href;
    }
  }
  function messageTitle(node: Element, text: string) {
    var link = node && node.querySelector && node.querySelector('a, button:not([data-mbg-message-star]), input');
    var label = compactText(link || node);
    if (!label || label.length > 120) {
      label = text.split(/(?:\s{2,}| \/ |\n)/)[0] || text;
    }
    return label.length > 120 ? label.substring(0, 120) + '...' : label;
  }
  function addMessageData(doc: Document, title: string, url: string, text: string) {
    text = compactRawText(text);
    title = compactRawText(title);
    if (text.length < 6 || isPortalNoiseText(text) || !hasDate(text)) {
      return;
    }
    if (!title || title.length > 120) {
      title = text.split(/(?:\s{2,}| \/ |\n)/)[0] || text;
    }
    if (title.length > 120) {
      title = title.substring(0, 120) + '...';
    }
    url = url || doc.location.href || document.location.href;
    var key = title + '|' + url + '|' + text;
    if (seenMessageItems[key]) {
      return;
    }
    seenMessageItems[key] = true;
    messageItems.push({
      title: title,
      url: url,
      text: text
    });
  }
  function addMessageItem(doc: Document, node: Element) {
    var text = compactText(node);
    addMessageData(doc, messageTitle(node, text), messageUrl(doc, node), text);
  }
  function collectNoticeDetail(doc: Document) {
    var raw = doc.body && (doc.body.innerText || doc.body.textContent) || '';
    if (!raw || raw.indexOf('連絡通知元') < 0) {
      return false;
    }
    var lines = raw.split(/\r?\n/)
      .map(function(line) { return line.replace(/\s+/g, ' ').trim(); })
      .filter(Boolean);
    var start = -1;
    for (var i = 0; i < lines.length; i += 1) {
      if (lines[i] === '連絡通知') {
        start = i + 1;
        break;
      }
    }
    if (start < 0) {
      start = 0;
    }
    while (start < lines.length && (
      lines[start] === '[image]' ||
      lines[start] === '連絡通知' ||
      lines[start].indexOf('指定した個数を既読') >= 0
    )) {
      start += 1;
    }
    if (start >= lines.length) {
      return false;
    }
    var end = lines.findIndex(function(line, index) {
      return index > start && (
        line === '連絡通知元' ||
        line === '連絡通知期間' ||
        line === 'メール送信' ||
        line === '送信日時' ||
        line === '対象学生所属'
      );
    });
    if (end < 0) {
      end = lines.length;
    }
    var title = lines[start].replace(/\s*\[[^\]]+\]\s*$/g, '').trim();
    var body = lines.slice(start, end).join(' ');
    if (!hasDate(body)) {
      return false;
    }
    addMessageData(doc, title, doc.location.href, body);
    return true;
  }
  function collectMessageItems(doc: Document) {
    try {
      var mobile = doc.querySelectorAll('div.button[onclick*="seqNo="]');
      if (mobile.length && compactText(doc.body).indexOf('連絡通知') >= 0) {
        for (var m = 0; m < mobile.length; m += 1) {
          var item = readSmartphoneMessageRow(mobile[m], doc.baseURI || doc.location.href);
          if (item) addMessageData(doc, item.title, item.url, item.text);
        }
        return;
      }
      if (collectNoticeDetail(doc)) {
        return;
      }
      var table = messageTable(doc);
      var candidates = table ?
        table.querySelectorAll('tr') :
        doc.querySelectorAll('tr, li, a, button:not([data-mbg-message-star])');
      for (var i = 0; i < candidates.length; i += 1) {
        addMessageItem(doc, candidates[i]);
      }
    } catch (e) {}
  }

  function collectReportRows(doc: Document) {
    var rows = [];
    try {
      var items = readAssignmentRows(doc);
      for (var i = 0; i < items.length; i += 1) {
        var item = items[i];
        reportItems.push(item);
        rows.push(
          'レポート課題: ' + item.title +
          (item.code ? ' / 開講番号: ' + item.code : '') +
          (item.status ? ' / 状態: ' + item.status : '') +
          ' / 提出期間: ' + item.period
        );
      }
    } catch (e) {}
    return rows;
  }
  function collect(win: Window) {
    try {
      if (win.document && win.document.body) {
        texts.push(win.document.body.innerText || '');
        collectMessageItems(win.document);
        var reportRows = collectReportRows(win.document);
        if (reportRows.length) {
          texts.push(reportRows.join('\n'));
        }
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (e) {}
  }
  collect(window);
  return JSON.stringify({
    title: document.title || '',
    text: texts.join('\n'),
    messageItems: messageItems,
    reportItems: reportItems
  });
}
__mbgEntryResult = pageTextActivity();
