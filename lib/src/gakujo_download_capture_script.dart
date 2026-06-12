class GakujoDownloadCaptureScript {
  const GakujoDownloadCaptureScript._();

  static const channelName = 'MoreBetterGakujoDownloads';

  static String build() {
    return r'''
(function() {
  if (window.__MBG_DOWNLOAD_CAPTURE_INSTALLED) {
    return;
  }
  window.__MBG_DOWNLOAD_CAPTURE_INSTALLED = true;

  function textOf(element) {
    if (!element) {
      return '';
    }
    return (
      element.innerText ||
      element.textContent ||
      element.value ||
      element.getAttribute('title') ||
      element.getAttribute('aria-label') ||
      ''
    ).replace(/\s+/g, ' ').trim();
  }

  function firstUsefulText(selectors) {
    for (var i = 0; i < selectors.length; i += 1) {
      var elements = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < elements.length; j += 1) {
        var text = textOf(elements[j]);
        if (text) {
          return text;
        }
      }
    }
    return '';
  }

  function estimateCourseName() {
    return firstUsefulText([
      'h1',
      'h2',
      'h3',
      '.breadcrumb',
      '.topic-path',
      '.course',
      '.jugyo',
      '.kamoku',
      '.selected',
      '.active'
    ]) || document.title || '未分類';
  }

  function isDownloadLike(element, url) {
    var text = textOf(element).toLowerCase();
    var href = (url || '').toLowerCase();
    return (
      element.hasAttribute('download') ||
      text.indexOf('ダウンロード') >= 0 ||
      text.indexOf('download') >= 0 ||
      href.indexOf('download') >= 0 ||
      href.indexOf('file') >= 0 ||
      href.indexOf('campussquare.do') >= 0 ||
      /\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|csv|txt)(?:[?#].*)?$/.test(href)
    );
  }

  function formFields(form, submitter) {
    var fields = {};
    if (!form) {
      return fields;
    }
    var data = new FormData(form);
    if (submitter && submitter.name) {
      data.set(submitter.name, submitter.value || textOf(submitter));
    }
    data.forEach(function(value, key) {
      if (typeof value === 'string') {
        fields[key] = value;
      }
    });
    return fields;
  }

  function post(payload) {
    window.MoreBetterGakujoDownloads.postMessage(JSON.stringify(payload));
  }

  document.addEventListener('click', function(event) {
    var target = event.target;
    if (!target || !target.closest) {
      return;
    }

    var anchor = target.closest('a[href]');
    if (anchor) {
      var absoluteUrl = new URL(anchor.getAttribute('href'), window.location.href).href;
      if (!isDownloadLike(anchor, absoluteUrl)) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      post({
        url: absoluteUrl,
        method: 'GET',
        fileName: textOf(anchor),
        courseName: estimateCourseName(),
        formFields: {}
      });
      return;
    }

    var submitter = target.closest('button, input[type="submit"], input[type="button"]');
    if (!submitter) {
      return;
    }

    var form = submitter.form || submitter.closest('form');
    if (!form && !isDownloadLike(submitter, window.location.href)) {
      return;
    }

    var action = form ? (form.getAttribute('action') || window.location.href) : window.location.href;
    var absoluteAction = new URL(action, window.location.href).href;
    if (!isDownloadLike(submitter, absoluteAction)) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    post({
      url: absoluteAction,
      method: form ? (form.getAttribute('method') || 'GET').toUpperCase() : 'GET',
      fileName: textOf(submitter),
      courseName: estimateCourseName(),
      formFields: formFields(form, submitter)
    });
  }, true);
})();
''';
  }
}
