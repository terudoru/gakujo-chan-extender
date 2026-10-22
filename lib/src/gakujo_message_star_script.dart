import 'dart:convert';

class GakujoMessageStarScript {
  const GakujoMessageStarScript._();

  static const channelName = 'GakujoMessageStars';

  static String build({Iterable<String> starredIds = const []}) =>
      _script.replaceAll('__STARRED_IDS__', jsonEncode(starredIds.toList()));

  static String buildRefresh(Iterable<String> starredIds) =>
      'if (window.__MBG_MESSAGE_STARS_REFRESH) {'
      'window.__MBG_MESSAGE_STARS_REFRESH(${jsonEncode(starredIds.toList())});'
      '}';

  static String buildTeardown() => r'''
(function() {
  if (window.__MBG_MESSAGE_STARS_DISPOSE) window.__MBG_MESSAGE_STARS_DISPOSE();
})()
''';

  static String buildOpen({
    required String keijitype,
    required String genrecd,
    required String seqNo,
  }) =>
      _openScript.replaceAll(
          '__MESSAGE__',
          jsonEncode({
            'keijitype': keijitype,
            'genrecd': genrecd,
            'seqNo': seqNo,
          }));

  static const _script = r'''
(function() {
  var initialIds = __STARRED_IDS__;
  var version = 3;
  if (window.__MBG_MESSAGE_STARS_VERSION === version) {
    window.__MBG_MESSAGE_STARS_REFRESH(initialIds);
    return;
  }
  if (window.__MBG_MESSAGE_STARS_DISPOSE) window.__MBG_MESSAGE_STARS_DISPOSE();
  window.__MBG_MESSAGE_STARS_VERSION = version;
  var disposed = false;
  var ids = new Set(initialIds);
  var buttons = [];
  var styles = [];
  var lastDetailDocument;
  var lastDetailSignature;
  var listDocument;
  var openedMessageKey = '__MBG_MESSAGE_STARS_OPEN_MESSAGE';

  function mainFrameDocument() {
    try {
      var frame = document.getElementById('main-frame-if');
      return frame && frame.contentWindow && frame.contentWindow.document || document;
    } catch (e) { return document; }
  }
  function text(node) {
    return String(node && (node.innerText || node.textContent) || '')
      .replace(/\s+/g, ' ').trim();
  }
  function title(node) { return text(node).replace(/\s*\[新着\]\s*$/, ''); }
  function remember(data) {
    try {
      window.top.sessionStorage.setItem(openedMessageKey, JSON.stringify({
        keijitype: data.keijitype, genrecd: data.genrecd,
        seqNo: data.seqNo, title: data.title
      }));
    } catch (e) {}
  }
  function identity(href, doc) {
    try {
      var url = new URL(href, doc.baseURI || 'https://gakujo.iess.niigata-u.ac.jp/campusweb/');
      var result = {};
      for (var key of ['keijitype', 'genrecd', 'seqNo']) {
        var value = url.searchParams.get(key) || '';
        if (!/^[0-9]+$/.test(value)) return null;
        result[key] = value;
      }
      return result;
    } catch (e) { return null; }
  }
  function id(data) { return data.keijitype + '|' + data.genrecd + '|' + data.seqNo; }
  function send(action, data) {
    if (disposed) return;
    var channel = window.GakujoMessageStars;
    if (channel && channel.postMessage) {
      channel.postMessage(JSON.stringify(Object.assign({action: action}, data)));
    }
  }
  function paint(entry) {
    var starred = ids.has(entry.id);
    entry.button.setAttribute('aria-pressed', String(starred));
  }
  function ensureStyle(doc) {
    if (doc.getElementById('mbg-message-star-style')) return;
    var style = doc.createElement('style');
    style.id = 'mbg-message-star-style';
    // Generated content keeps stars out of scanned row text and dedupe keys.
    style.textContent = 'button[data-mbg-message-star]::before { content: "☆"; }' +
      'button[data-mbg-message-star][aria-pressed="true"]::before { content: "★"; }';
    (doc.head || doc.documentElement).appendChild(style);
    styles.push(style);
  }
  function addButton(target, data, doc) {
    if (buttons.some(function(entry) { return entry.target === target; })) return;
    ensureStyle(doc);
    var button = doc.createElement('button');
    button.type = 'button';
    button.setAttribute('data-mbg-message-star', 'true');
    button.setAttribute('aria-label', 'スター');
    button.title = 'スター';
    button.style.cssText = 'font:inherit;font-size:18px;line-height:1.2;padding:2px 5px;margin-right:4px;cursor:pointer;';
    button.addEventListener('click', function(event) {
      event.preventDefault();
      event.stopPropagation();
      send('toggle', data());
    });
    target.parentNode.insertBefore(button, target);
    var entry = {button: button, target: target, id: id(data())};
    buttons.push(entry);
    paint(entry);
  }
  function rowData(link, doc) {
    var data = identity(link.getAttribute('href'), doc);
    var row = link.closest('tr');
    if (!data || !row || !row.cells) return null;
    var cells = row.cells;
    var table = row.closest('table');
    var headers = table ? Array.from(table.querySelectorAll('th')).map(text) : [];
    function field(label) {
      var index = headers.indexOf(label);
      return index >= 0 ? text(cells[index]) : '';
    }
    data.genre = field('ジャンル');
    data.sender = [field('所属'), field('氏名') || field('担当者')].filter(Boolean).join(' ／ ');
    data.period = field('連絡通知期間');
    data.postedAt = field('掲載日時');
    data.title = title(link);
    data.body = '';
    return data;
  }
  function rememberClickedMessage(event) {
    var link = event.target && event.target.closest && event.target.closest('a[href*="seqNo="]');
    if (!link) return;
    var doc = link.ownerDocument;
    var params = new URL(link.getAttribute('href'), doc.baseURI).searchParams;
    if (params.get('_eventId') !== 'displayMidoku' && params.get('_eventId') !== 'confirm') return;
    var data = identity(link.getAttribute('href'), doc);
    if (data) {
      data.title = title(link);
      remember(data);
    }
  }
  function detailData(doc, heading) {
    var data = identity(doc.location && doc.location.href || doc.URL || '', doc);
    if (!data) {
      var attachments = doc.querySelectorAll('a[href*="_eventId=download"]');
      for (var i = 0; i < attachments.length && !data; i += 1) {
        data = identity(attachments[i].getAttribute('href'), doc);
      }
    }
    if (!data) {
      try {
        var remembered = JSON.parse(window.top.sessionStorage.getItem(openedMessageKey));
        if (remembered && typeof remembered.title === 'string' &&
            title({textContent: remembered.title}) === title(heading) &&
            ['keijitype', 'genrecd', 'seqNo'].every(function(key) {
              return typeof remembered[key] === 'string' && /^[0-9]+$/.test(remembered[key]);
            })) {
          data = {keijitype: remembered.keijitype, genrecd: remembered.genrecd, seqNo: remembered.seqNo};
        }
      } catch (e) {}
    }
    if (!data) return null;
    data.title = title(heading);
    var genre = text(doc.querySelector('span.keiji-t-genre')).replace(/^\[|\]$/g, '').trim();
    var genres = genre.split(/\s+/);
    data.genre = genres.length === 2 && genres[0] === genres[1] ? genres[0] : genre;
    data.body = String((doc.querySelector('div.keiji-naiyo') || {}).innerText ||
                      (doc.querySelector('div.keiji-naiyo') || {}).textContent || '').trim().slice(0, 4000);
    data.sender = '';
    data.period = '';
    data.postedAt = '';
    var fields = {'連絡通知元': 'sender', '連絡通知期間': 'period', '送信日時': 'postedAt'};
    var tables = doc.querySelectorAll('table.keiji-normal');
    for (var j = 0; j < tables.length; j += 1) {
      var th = tables[j].querySelector('th');
      var field = fields[text(th)];
      var row = th && th.closest('tr');
      var next = row && row.nextElementSibling;
      if (field && next) data[field] = text(next.querySelector('td'));
    }
    return data;
  }
  function update() {
    if (disposed) return;
    var doc = mainFrameDocument();
    if (doc !== listDocument) {
      if (listDocument) listDocument.removeEventListener('click', rememberClickedMessage, true);
      listDocument = doc;
      listDocument.addEventListener('click', rememberClickedMessage, true);
    }
    // Release buttons belonging to a frame document that has navigated away.
    buttons = buttons.filter(function(entry) {
      if (entry.target.ownerDocument === doc && entry.target.isConnected !== false) return true;
      entry.button.remove();
      return false;
    });
    var links = doc.querySelectorAll('a[href*="seqNo="]');
    for (var i = 0; i < links.length; i += 1) {
      var event = new URL(links[i].getAttribute('href'), doc.baseURI).searchParams.get('_eventId');
      if (event !== 'displayMidoku' && event !== 'confirm') continue;
      if (rowData(links[i], doc)) {
        (function(link) { addButton(link, function() { return rowData(link, doc); }, doc); })(links[i]);
      }
    }
    var heading = doc.querySelector('span.keiji-title');
    var detail = heading && detailData(doc, heading);
    if (detail) {
      addButton(heading, function() { return detailData(doc, heading); }, doc);
      var signature = JSON.stringify(detail);
      if (ids.has(id(detail)) &&
          (doc !== lastDetailDocument || signature !== lastDetailSignature)) {
        lastDetailDocument = doc;
        lastDetailSignature = signature;
        send('detail', detail);
      }
    }
    buttons.forEach(paint);
  }
  window.__MBG_MESSAGE_STARS_REFRESH = function(nextIds) {
    ids = new Set(nextIds);
    update();
  };
  var timer = window.setInterval(update, 700);
  window.__MBG_MESSAGE_STARS_DISPOSE = function() {
    disposed = true;
    window.clearInterval(timer);
    if (listDocument) listDocument.removeEventListener('click', rememberClickedMessage, true);
    listDocument = null;
    buttons.forEach(function(entry) { entry.button.remove(); });
    buttons = [];
    styles.forEach(function(style) { style.remove(); });
    styles = [];
    delete window.__MBG_MESSAGE_STARS_VERSION;
    delete window.__MBG_MESSAGE_STARS_REFRESH;
    delete window.__MBG_MESSAGE_STARS_DISPOSE;
  };
  update();
})()
''';

  // Only explicit student actions run this script. The final GET is left to
  // WebView navigation because opening a detail marks that message as read.
  static const _openScript = r'''
(function() {
  var message = __MESSAGE__;
  var base = location.origin + '/campusweb/';
  function result(status, url) { return JSON.stringify({status: status, url: url}); }
  function key(doc) {
    var link = doc.querySelector('a[href*="_flowExecutionKey="]');
    if (link) {
      var value = new URL(link.getAttribute('href'), base).searchParams.get('_flowExecutionKey');
      if (value) return value;
    }
    var input = doc.querySelector('input[name="_flowExecutionKey"]');
    return input && input.value || '';
  }
  function get(url) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, false);
    xhr.send(null);
    if (xhr.status < 200 || xhr.status >= 400) throw new Error('http');
    var doc = new DOMParser().parseFromString(xhr.responseText, 'text/html');
    var body = String(doc.body && (doc.body.innerText || doc.body.textContent) || '');
    if (/実行権限エラー|SYSTEM ERROR/.test(String(doc.title)) ||
        /^\s*(実行権限エラー|SYSTEM ERROR)/.test(body)) throw new Error('system');
    if (String(doc.title || '').indexOf('連絡通知') < 0) throw new Error('missing');
    return doc;
  }
  function url(flowKey, event) {
    if (!flowKey) throw new Error('key');
    return base + 'campussquare.do?_flowExecutionKey=' + encodeURIComponent(flowKey) +
      '&_eventId=' + event;
  }
  try {
    if (location.origin !== 'https://gakujo.iess.niigata-u.ac.jp') return result('missing');
    for (var name of ['keijitype', 'genrecd', 'seqNo']) {
      if (!/^[0-9]+$/.test(message[name])) return result('error');
    }
    var genre = '&keijitype=' + encodeURIComponent(message.keijitype) +
                '&genrecd=' + encodeURIComponent(message.genrecd);
    var doc = get(base + 'campussquare.do?_flowId=KJW0001100-flow');
    doc = get(url(key(doc), 'dispKeijiListGenre') + genre);
    doc = get(url(key(doc), 'paging') + '&_displayCount=500');
    var links = doc.querySelectorAll('a[href*="seqNo="]');
    var found;
    for (var i = 0; i < links.length; i += 1) {
      var params = new URL(links[i].getAttribute('href'), base).searchParams;
      if (params.get('seqNo') === message.seqNo &&
          params.get('keijitype') === message.keijitype &&
          params.get('genrecd') === message.genrecd) {
        found = links[i];
        break;
      }
    }
    if (!found) return result('gone');
    var targetUrl = url(key(doc), 'confirm') + genre + '&seqNo=' + encodeURIComponent(message.seqNo);
    message.title = String(found.innerText || found.textContent || '')
      .replace(/\s+/g, ' ').trim().replace(/\s*\[新着\]\s*$/, '');
    try {
      window.top.sessionStorage.setItem('__MBG_MESSAGE_STARS_OPEN_MESSAGE', JSON.stringify(message));
    } catch (e) {}
    return result('ok', targetUrl);
  } catch (e) { return result(e.message === 'missing' ? 'missing' : 'error'); }
})()
''';
}
