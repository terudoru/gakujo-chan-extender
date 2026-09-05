class GakujoMessageReaderScript {
  const GakujoMessageReaderScript._();

  static String build() {
    return r'''
(function() {
  var version = 3;
  if (window.__MBG_MESSAGE_READER_VERSION === version) {
    if (window.__MBG_MESSAGE_READER_UPDATE) {
      window.__MBG_MESSAGE_READER_UPDATE();
    }
    return;
  }
  if (window.__MBG_MESSAGE_READER_DISPOSE) {
    window.__MBG_MESSAGE_READER_DISPOSE();
  }
  window.__MBG_MESSAGE_READER_VERSION = version;
  var disposed = false;
  var reading = false;
  var reloadTimeout;
  var cancelPendingFrame;

  window.__MBG_MESSAGE_READER_DISPOSE = function() {
    disposed = true;
    window.clearTimeout(reloadTimeout);
    if (cancelPendingFrame) {
      cancelPendingFrame();
    }
  };

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
      var settled = false;
      var timeoutId;

      function finish(success) {
        if (settled) {
          return;
        }
        settled = true;
        cancelPendingFrame = null;
        window.clearTimeout(timeoutId);
        frame.remove();
        resolve(success);
      }

      frame.setAttribute('data-mbg-message-reader-owned', 'true');
      cancelPendingFrame = function() { finish(false); };
      frame.style.display = 'none';
      frame.onload = function() {
        finish(true);
      };
      frame.onerror = function() {
        finish(false);
      };
      timeoutId = window.setTimeout(function() {
        finish(false);
      }, 5000);
      frame.src = url;
      document.body.appendChild(frame);
    });
  }

  async function markRead(url) {
    try {
      var response = await fetch(url, { credentials: 'include' });
      if (response.ok) {
        return true;
      }
      return false;
    } catch (e) {
      // Fall through to the iframe request.
    }
    if (disposed) {
      return false;
    }
    try {
      return await markReadWithFrame(url);
    } catch (e) {
      return false;
    }
  }

  function statusElement() {
    var status = document.getElementById('mbg-read-status');
    if (status) {
      return status;
    }
    var target = document.getElementById('tabmenutable');
    if (!target) {
      return null;
    }
    status = document.createElement('span');
    status.id = 'mbg-read-status';
    status.setAttribute('data-mbg-message-reader-owned', 'true');
    status.setAttribute('aria-live', 'polite');
    target.appendChild(status);
    return status;
  }

  function showStatus(successCount, failureCount) {
    var status = statusElement();
    if (status) {
      status.textContent = successCount + '件を既読にしました（失敗' +
        failureCount + '件）';
    }
  }

  async function readerCall() {
    if (disposed || reading || reloadTimeout) {
      return;
    }
    var urls = unreadUrls(inputValue());
    if (!urls.length) {
      return;
    }
    reading = true;
    var button = document.getElementById('mbg-read-button');
    if (button) {
      button.disabled = true;
    }
    var successCount = 0;
    var failureCount = 0;
    try {
      for (var i = 0; i < urls.length && !disposed; i += 1) {
        if (await markRead(urls[i])) {
          successCount += 1;
        } else {
          failureCount += 1;
        }
      }
      if (disposed) {
        return;
      }
      showStatus(successCount, failureCount);
      if (failureCount > 0) {
        return;
      }
      reloadTimeout = window.setTimeout(function() {
        reloadTimeout = null;
        if (!disposed) {
          location.reload();
        }
      }, 1000);
    } finally {
      reading = false;
      if (button && !disposed && !reloadTimeout) {
        button.disabled = false;
      }
    }
  }

  function addControls() {
    if (disposed) {
      return false;
    }
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
      button.setAttribute('data-mbg-message-reader-owned', 'true');
      button.textContent = '指定した個数を既読にする';
      button.addEventListener('click', readerCall);
      target.appendChild(button);
    }
    if (!document.getElementById('mbg-read-num-input')) {
      var input = document.createElement('input');
      input.id = 'mbg-read-num-input';
      input.type = 'number';
      input.setAttribute('data-mbg-message-reader-owned', 'true');
      input.defaultValue = '5';
      input.pattern = '\\d*';
      input.placeholder = '既読にする数(半角数字)';
      target.appendChild(input);
    }
    statusElement();
    return true;
  }

  window.__MBG_MESSAGE_READER_UPDATE = addControls;
  addControls();
  window.clearInterval(window.__MBG_MESSAGE_READER_INTERVAL);
  window.__MBG_MESSAGE_READER_INTERVAL = window.setInterval(addControls, 500);
})();
''';
  }

  static String buildTeardown() {
    return r'''
(function() {
  if (window.__MBG_MESSAGE_READER_DISPOSE) {
    window.__MBG_MESSAGE_READER_DISPOSE();
  }
  delete window.__MBG_MESSAGE_READER_DISPOSE;
  window.clearInterval(window.__MBG_MESSAGE_READER_INTERVAL);
  delete window.__MBG_MESSAGE_READER_INTERVAL;
  delete window.__MBG_MESSAGE_READER_VERSION;
  delete window.__MBG_MESSAGE_READER_UPDATE;

  var controls = document.querySelectorAll(
    '[data-mbg-message-reader-owned="true"]'
  );
  for (var i = 0; i < controls.length; i += 1) {
    controls[i].remove();
  }
})();
''';
  }
}
