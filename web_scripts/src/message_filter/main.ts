import { watchPage } from '../shared/page_watch.js';
import { largerMessageListPage } from '../shared/message_list_paging.js';
export {};

declare const __mbgConfig: { keywords: string[] };

function messageFilter() {
  var version = 7;
  var keywords = __mbgConfig.keywords.map(function(keyword) {
    return String(keyword || '').trim().toLowerCase();
  }).filter(Boolean);
  var signature = JSON.stringify(keywords);
  if (window.__MBG_MESSAGE_FILTER_VERSION === version &&
      window.__MBG_MESSAGE_FILTER_SIGNATURE === signature) {
    if (window.__MBG_MESSAGE_FILTER_UPDATE) {
      window.__MBG_MESSAGE_FILTER_UPDATE();
    }
    return;
  }
  window.__MBG_MESSAGE_FILTER_VERSION = version;
  window.__MBG_MESSAGE_FILTER_SIGNATURE = signature;

  function candidateDocuments() {
    var docs = [];
    try {
      var frame = document.getElementById('main-frame-if') as HTMLIFrameElement | null;
      var frameDoc = frame && frame.contentWindow && frame.contentWindow.document;
      if (frameDoc) docs.push(frameDoc);
    } catch (e) {}
    if (docs.indexOf(document) < 0) docs.push(document);
    return docs;
  }

  function compactText(element: HTMLElement & { value?: string }) {
    return (element && (element.innerText || element.textContent || element.value) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function messageTable(doc: Document) {
    var direct = doc.querySelector('table.normal:nth-child(9)');
    if (direct && direct.querySelector('a[href*="seqNo="]')) {
      return direct;
    }
    var tables = doc.querySelectorAll<HTMLTableElement>(keywords.length ? 'table' : 'table.normal');
    for (var i = 0; i < tables.length; i += 1) {
      var table = tables[i];
      if (!table.querySelector('a[href*="seqNo="]')) continue;
      var text = compactText(table);
      if ((text.indexOf('連絡通知') >= 0 ||
           text.indexOf('全学連絡通知') >= 0 ||
           text.indexOf('掲示') >= 0)) {
        return table;
      }
    }
    return null;
  }

  function smartphoneMessageRows(doc: Document) {
    var rows: HTMLElement[] = [];
    var buttons = doc.querySelectorAll('div.button[onclick*="seqNo="]');
    Array.prototype.forEach.call(buttons, function(button) {
      for (var row = button.parentNode; row; row = row.parentNode) {
        if (row.tagName === 'TR' && row.querySelector('td.category-frame')) {
          if (rows.indexOf(row) < 0) rows.push(row);
          break;
        }
      }
    });
    return rows;
  }

  function shouldHide(text: string) {
    var normalized = String(text || '').toLowerCase();
    for (var i = 0; i < keywords.length; i += 1) {
      if (normalized.indexOf(keywords[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  function updateStatus(doc: Document, hiddenCount: number, listTable: HTMLTableElement | null) {
    if (!keywords.length || hiddenCount <= 0) {
      return null;
    }
    var statusDoc = listTable ? doc : document;
    var target = listTable ? listTable.parentNode : statusDoc.getElementById('tabmenutable');
    if (!target) {
      return null;
    }
    var status = statusDoc.getElementById('mbg-message-filter-status');
    if (!status) {
      status = statusDoc.createElement('span');
      status.id = 'mbg-message-filter-status';
      status.style.marginLeft = '8px';
      status.style.fontSize = '12px';
      status.style.color = '#31543f';
    }
    if (status.parentNode !== target) {
      if (listTable) target.insertBefore(status, listTable);
      else target.appendChild(status);
    }
    var label = '除外中: ' + hiddenCount + '件';
    if (status.textContent !== label) status.textContent = label;
    return status;
  }

  function removeStaleStatuses(doc: Document, activeStatuses: HTMLElement[]) {
    ['mbg-message-filter-status', 'mbg-message-search'].forEach(function(id) {
      Array.prototype.forEach.call(doc.querySelectorAll('[id="' + id + '"]'), function(status) {
        if (activeStatuses.indexOf(status) < 0) status.remove();
      });
    });
  }

  function searchText(text: string) {
    return text.normalize('NFKC').toLowerCase().replace(/\s+/g, ' ').trim();
  }

  function searchToolbar(doc: Document, table: Element) {
    var toolbar = table.querySelector<HTMLElement>('caption[id="mbg-message-search"]');
    if (toolbar) return toolbar;

    // A caption leaves the list's position and its rows unchanged for the
    // bulk-read, star and activity scripts.
    toolbar = doc.createElement('caption');
    toolbar.id = 'mbg-message-search';
    toolbar.style.textAlign = 'start';
    toolbar.style.padding = '6px 0';
    toolbar.style.captionSide = 'top';
    var input = doc.createElement('input');
    input.type = 'search';
    input.placeholder = '連絡通知を検索';
    input.ariaLabel = '連絡通知を検索';
    input.style.font = 'inherit';
    input.style.maxWidth = '100%';
    var storageKey = 'mbg-message-search-query';
    try { input.value = window.sessionStorage.getItem(storageKey) || ''; } catch (_) {}
    input.addEventListener('keydown', function(event) {
      if (event.key === 'Enter' && !event.isComposing && event.keyCode !== 229) {
        event.preventDefault();
        event.stopPropagation();
      }
    });
    input.addEventListener('input', function() {
      try { window.sessionStorage.setItem(storageKey, input.value); } catch (_) {}
      window.__MBG_MESSAGE_FILTER_UPDATE?.();
    });
    toolbar.appendChild(input);
    var count = doc.createElement('span');
    count.ariaLive = 'polite';
    count.style.marginInlineStart = '8px';
    toolbar.appendChild(count);
    var hint = doc.createElement('div');
    hint.textContent = 'このページの表題・差出人・ジャンル・日付などを検索（本文を除く）';
    hint.style.fontSize = '12px';
    toolbar.appendChild(hint);
    if (doc.location?.origin === 'https://gakujo.iess.niigata-u.ac.jp') {
      var larger = largerMessageListPage(doc, doc.location.origin + '/campusweb/');
      if (larger) {
        var link = doc.createElement('a');
        link.href = larger.url;
        link.textContent = larger.count + '件表示して検索';
        hint.appendChild(doc.createTextNode(' '));
        hint.appendChild(link);
      }
    }
    table.insertBefore(toolbar, table.firstChild);
    return toolbar;
  }

  function restoreRows(doc: Document) {
    var hiddenRows = doc.querySelectorAll('tr[data-mbg-message-filter-display]');
    Array.prototype.forEach.call(hiddenRows, function(row) {
      var originalDisplay = row.getAttribute('data-mbg-message-filter-display');
      if (row.style.display !== originalDisplay) {
        row.style.display = originalDisplay;
      }
      row.removeAttribute('data-mbg-message-filter-display');
      if (row.getAttribute('data-mbg-message-filtered') !== 'false') {
        row.setAttribute('data-mbg-message-filtered', 'false');
      }
    });
  }

  function applyDocumentFilter(doc: Document, activeStatuses: HTMLElement[]) {
    var rows = smartphoneMessageRows(doc);
    var table = rows.length ? null : messageTable(doc);
    var terms: string[] = [];
    var count: HTMLElement | null = null;
    if (table) {
      rows = Array.from(table.querySelectorAll<HTMLElement>('tr')).filter(function(row) {
        return row.closest('table') === table && !!row.querySelector('a[href*="seqNo="]');
      });
      var toolbar = searchToolbar(doc, table);
      activeStatuses.push(toolbar);
      var query = searchText(toolbar.querySelector('input')!.value);
      if (query) terms = query.split(' ');
      count = toolbar.querySelector('span');
    }
    if (!keywords.length && !terms.length) restoreRows(doc);
    if (!rows.length) {
      return false;
    }
    var listTable = table ? null : rows[0].closest('table');
    var hiddenCount = 0;
    var totalCount = 0;
    var visibleCount = 0;
    rows.forEach(function(row) {
      var originalDisplay = row.getAttribute('data-mbg-message-filter-display');
      var pageShowsRow = (originalDisplay ?? row.style.display) !== 'none' && !row.hidden;
      if (pageShowsRow) totalCount += 1;
      if (!keywords.length && !terms.length) {
        if (pageShowsRow) visibleCount += 1;
        return;
      }
      // Read each cell separately because innerText on a hidden row can join
      // adjacent cells without any whitespace.
      var cells = (row as HTMLTableRowElement).cells;
      var text = table && cells?.length
        ? Array.from(cells, function(cell) {
            return (cell.textContent || '').replace(/\s+/g, ' ').trim();
          }).join(' ')
        : compactText(row);
      var excluded = shouldHide(text);
      var searchable = terms.length ? searchText(text) : '';
      var hide = excluded || terms.some(function(term) {
        return !searchable.includes(term);
      });
      if (pageShowsRow && excluded) hiddenCount += 1;
      if (pageShowsRow && !hide) visibleCount += 1;
      if (hide) {
        if (originalDisplay === null) {
          originalDisplay = row.style.display || '';
          row.setAttribute('data-mbg-message-filter-display', originalDisplay);
        }
        if (row.style.display !== 'none') {
          row.style.display = 'none';
        }
      } else if (originalDisplay !== null) {
        if (row.style.display !== originalDisplay) {
          row.style.display = originalDisplay;
        }
        row.removeAttribute('data-mbg-message-filter-display');
      }
      var filtered = hide ? 'true' : 'false';
      if (row.getAttribute('data-mbg-message-filtered') !== filtered) {
        row.setAttribute('data-mbg-message-filtered', filtered);
      }
    });
    var label = totalCount + '件中' + visibleCount + '件';
    if (count && count.textContent !== label) count.textContent = label;
    var status = updateStatus(doc, hiddenCount, listTable);
    if (status) activeStatuses.push(status);
    return true;
  }

  function applyFilter() {
    var applied = false;
    var docs = candidateDocuments();
    var activeStatuses: HTMLElement[] = [];
    docs.forEach(function(doc) {
      if (applyDocumentFilter(doc, activeStatuses)) applied = true;
    });
    // A frame's desktop list owns a status in the top document, which has no list.
    docs.forEach(function(doc) {
      removeStaleStatuses(doc, activeStatuses);
    });
    return applied;
  }

  window.__MBG_MESSAGE_FILTER_DISPOSE = function() {
    if (window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE) window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE();
    delete window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE;
    window.clearInterval(window.__MBG_MESSAGE_FILTER_INTERVAL);
    candidateDocuments().forEach(function(doc) {
      restoreRows(doc);
      removeStaleStatuses(doc, []);
    });
    delete window.__MBG_MESSAGE_FILTER_VERSION;
    delete window.__MBG_MESSAGE_FILTER_SIGNATURE;
    delete window.__MBG_MESSAGE_FILTER_UPDATE;
    delete window.__MBG_MESSAGE_FILTER_INTERVAL;
    delete window.__MBG_MESSAGE_FILTER_DISPOSE;
  };
  window.__MBG_MESSAGE_FILTER_UPDATE = applyFilter;
  applyFilter();
  window.clearInterval(window.__MBG_MESSAGE_FILTER_INTERVAL);
  if (window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE) window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE();
  window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE = watchPage(window, applyFilter, { fallbackMs: 5000, legacyIntervalMs: 500 });
}

messageFilter();
