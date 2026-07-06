class GakujoMessageReaderScript {
  const GakujoMessageReaderScript._();

  static String build() {
    return r'''
(function() {
  var version = 1;
  if (window.__MBG_MESSAGE_READER_VERSION === version) {
    if (window.__MBG_MESSAGE_READER_UPDATE) {
      window.__MBG_MESSAGE_READER_UPDATE();
    }
    return;
  }
  window.__MBG_MESSAGE_READER_VERSION = version;

  function mainFrameDocument() {
    try {
      var frame = document.getElementById('main-frame-if');
      return frame && frame.contentWindow && frame.contentWindow.document || document;
    } catch (e) {
      return document;
    }
  }

  function messageTable() {
    var doc = mainFrameDocument();
    return doc.querySelector('table.normal:nth-child(9)');
  }

  function absoluteCampusUrl(url) {
    if (!url) {
      return '';
    }
    return new URL(url, 'https://gakujo.iess.niigata-u.ac.jp/campusweb/').href;
  }

  function unreadUrls(limit) {
    var table = messageTable();
    if (!table) {
      return [];
    }
    var urls = [];
    for (var i = 1; i < table.rows.length && urls.length < limit; i += 1) {
      var link = table.rows[i].querySelector('a[href]');
      if (link) {
        urls.push(absoluteCampusUrl(link.getAttribute('href')));
      }
    }
    return urls;
  }

  function inputValue() {
    var input = document.getElementById('mbg-read-num-input');
    var value = input ? Number(input.value) : 0;
    return isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  function markReadWithFrame(url) {
    return new Promise(function(resolve) {
      var frame = document.createElement('iframe');
      frame.style.display = 'none';
      frame.onload = function() {
        window.setTimeout(function() {
          frame.remove();
          resolve();
        }, 1000);
      };
      frame.onerror = function() {
        frame.remove();
        resolve();
      };
      document.body.appendChild(frame);
      frame.src = url;
    });
  }

  async function markRead(url) {
    try {
      await fetch(url, { credentials: 'include' });
    } catch (e) {
      await markReadWithFrame(url);
    }
  }

  async function readerCall() {
    var urls = unreadUrls(inputValue());
    for (var i = 0; i < urls.length; i += 1) {
      await markRead(urls[i]);
    }
    window.setTimeout(function() {
      location.reload();
    }, 1000);
  }

  function addControls() {
    if (!messageTable()) {
      return false;
    }
    var target = document.getElementById('tabmenutable');
    if (!target) {
      return false;
    }
    if (!document.getElementById('mbg-read-button')) {
      var button = document.createElement('button');
      button.id = 'mbg-read-button';
      button.type = 'button';
      button.textContent = '指定した個数を既読にする';
      button.addEventListener('click', readerCall);
      target.appendChild(button);
    }
    if (!document.getElementById('mbg-read-num-input')) {
      var input = document.createElement('input');
      input.id = 'mbg-read-num-input';
      input.type = 'number';
      input.defaultValue = '5';
      input.pattern = '\\d*';
      input.placeholder = '既読にする数(半角数字)';
      target.appendChild(input);
    }
    return true;
  }

  window.__MBG_MESSAGE_READER_UPDATE = addControls;
  addControls();
  window.clearInterval(window.__MBG_MESSAGE_READER_INTERVAL);
  window.__MBG_MESSAGE_READER_INTERVAL = window.setInterval(addControls, 500);
})();
''';
  }
}
