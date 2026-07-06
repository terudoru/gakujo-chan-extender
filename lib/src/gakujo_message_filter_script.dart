import 'dart:convert';

import 'gakujo_app_settings.dart';

class GakujoMessageFilterScript {
  const GakujoMessageFilterScript._();

  static String build({required List<String> keywords}) {
    final encodedKeywords = jsonEncode(
      normalizeMessageExcludeKeywords(keywords),
    );
    return '''
(function() {
  var version = 1;
  var keywords = $encodedKeywords.map(function(keyword) {
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

  function mainFrameDocument() {
    try {
      var frame = document.getElementById('main-frame-if');
      return frame && frame.contentWindow && frame.contentWindow.document || document;
    } catch (e) {
      return document;
    }
  }

  function compactText(element) {
    return (element && (element.innerText || element.textContent || element.value) || '')
      .replace(/\\s+/g, ' ')
      .trim();
  }

  function messageTable() {
    var doc = mainFrameDocument();
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
          table.querySelector('a[href]')) {
        return table;
      }
    }
    return null;
  }

  function shouldHide(text) {
    var normalized = String(text || '').toLowerCase();
    for (var i = 0; i < keywords.length; i += 1) {
      if (normalized.indexOf(keywords[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  function updateStatus(doc, hiddenCount) {
    var target = doc.getElementById('tabmenutable');
    var status = doc.getElementById('mbg-message-filter-status');
    if (!keywords.length || hiddenCount <= 0) {
      if (status) {
        status.remove();
      }
      return;
    }
    if (!target) {
      return;
    }
    if (!status) {
      status = doc.createElement('span');
      status.id = 'mbg-message-filter-status';
      status.style.marginLeft = '8px';
      status.style.fontSize = '12px';
      status.style.color = '#31543f';
      target.appendChild(status);
    }
    status.textContent = '除外中: ' + hiddenCount + '件';
  }

  function applyFilter() {
    var doc = mainFrameDocument();
    var table = messageTable();
    if (!table) {
      updateStatus(doc, 0);
      return false;
    }
    var rows = Array.prototype.slice.call(table.querySelectorAll('tr'));
    var hiddenCount = 0;
    rows.forEach(function(row, index) {
      if (index === 0) {
        return;
      }
      var text = compactText(row);
      var hide = keywords.length > 0 && shouldHide(text);
      row.style.display = hide ? 'none' : '';
      row.setAttribute('data-mbg-message-filtered', hide ? 'true' : 'false');
      if (hide) {
        hiddenCount += 1;
      }
    });
    updateStatus(doc, hiddenCount);
    return true;
  }

  window.__MBG_MESSAGE_FILTER_UPDATE = applyFilter;
  applyFilter();
  window.clearInterval(window.__MBG_MESSAGE_FILTER_INTERVAL);
  window.__MBG_MESSAGE_FILTER_INTERVAL = window.setInterval(applyFilter, 500);
})();
''';
  }
}
