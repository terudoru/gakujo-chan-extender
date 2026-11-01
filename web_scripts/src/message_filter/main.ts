export {};

declare const __mbgConfig: { keywords: string[] };

function messageFilter() {
  var version = 5;
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
    if (direct) {
      return direct;
    }
    var tables = doc.querySelectorAll('table');
    for (var i = 0; i < tables.length; i += 1) {
      var table = tables[i];
      var text = compactText(table);
      if ((text.indexOf('連絡通知') >= 0 ||
           text.indexOf('全学連絡通知') >= 0 ||
           text.indexOf('掲示') >= 0) &&
          table.querySelector('a[href*="seqNo="]')) {
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
    var statuses = doc.querySelectorAll('[id="mbg-message-filter-status"]');
    Array.prototype.forEach.call(statuses, function(status) {
      if (activeStatuses.indexOf(status) < 0) status.remove();
    });
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
    if (!keywords.length) {
      restoreRows(doc);
      return true;
    }
    var rows = smartphoneMessageRows(doc);
    var table = rows.length ? null : messageTable(doc);
    if (table) {
      rows = Array.prototype.slice.call(table.querySelectorAll('tr'), 1);
    }
    if (!rows.length) {
      return false;
    }
    var listTable = table ? null : rows[0].closest('table');
    var hiddenCount = 0;
    rows.forEach(function(row) {
      var text = compactText(row);
      var hide = shouldHide(text);
      var originalDisplay = row.getAttribute('data-mbg-message-filter-display');
      if (hide) {
        if (originalDisplay === null) {
          originalDisplay = row.style.display || '';
          row.setAttribute('data-mbg-message-filter-display', originalDisplay);
        }
        if (row.style.display !== 'none') {
          row.style.display = 'none';
        }
        if (originalDisplay !== 'none') {
          hiddenCount += 1;
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
  window.__MBG_MESSAGE_FILTER_INTERVAL = window.setInterval(applyFilter, 500);
}

messageFilter();
