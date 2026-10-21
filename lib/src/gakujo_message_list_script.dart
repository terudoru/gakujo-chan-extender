/// Fetches the newest rows of the 連絡通知 未読一覧 without leaving the
/// current page, in the shape the page scan reads them (title, link and row
/// text), so keyword notifications arrive without opening 連絡通知. Status
/// is "missing" when Gakujo answers with something else, such as its login
/// page.
const gakujoMessageListFetchScript = r'''
(function() {
  function text(node) {
    return String(node && (node.innerText || node.textContent) || '')
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
    if (String(doc.title || '').indexOf('連絡通知') < 0) {
      return JSON.stringify({status: 'missing', items: []});
    }
    var base = location.origin + '/campusweb/';
    var items = [];
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
        url: new URL(link.getAttribute('href'), base).href,
        text: text(rows[i])
      });
    }
    return JSON.stringify({status: 'ok', items: items});
  } catch (e) {
    return JSON.stringify({status: 'error', items: []});
  }
})()
''';
