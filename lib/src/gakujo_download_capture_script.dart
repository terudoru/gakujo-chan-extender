class GakujoDownloadCaptureScript {
  const GakujoDownloadCaptureScript._();

  static const channelName = 'MoreBetterGakujoDownloads';

  static String build() {
    return r'''
(function() {
  var captureVersion = 6;
  if (window.__MBG_DOWNLOAD_CAPTURE_VERSION === captureVersion) {
    return;
  }
  window.__MBG_DOWNLOAD_CAPTURE_VERSION = captureVersion;

  if (window.__MBG_DOWNLOAD_CAPTURE_HANDLER) {
    document.removeEventListener('click', window.__MBG_DOWNLOAD_CAPTURE_HANDLER, true);
  }

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

  function collectDocuments() {
    var documents = [];
    function collect(win) {
      try {
        if (win.document) {
          documents.push(win.document);
        }
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {}
    }
    collect(window);
    return documents;
  }

  function firstUsefulText(selectors) {
    var documents = collectDocuments();
    for (var i = 0; i < selectors.length; i += 1) {
      for (var d = 0; d < documents.length; d += 1) {
        var elements = documents[d].querySelectorAll(selectors[i]);
        for (var j = 0; j < elements.length; j += 1) {
          var text = textOf(elements[j]);
          if (text && !isIgnoredCourseName(normalizeCourseName(text))) {
            return text;
          }
        }
      }
    }
    return '';
  }

  function estimateCourseName() {
    var tableCourse = firstCourseNameFromTables();
    if (tableCourse) {
      return normalizeCourseName(tableCourse);
    }

    var explicitCourse = firstMatchingCourseNameText([
      'tr',
      'dl',
      'div',
      'p',
      'span'
    ]);
    if (explicitCourse) {
      return normalizeCourseName(explicitCourse);
    }

    var candidate = firstUsefulText([
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
    return normalizeCourseName(candidate);
  }

  window.__MBG_ESTIMATE_COURSE_NAME = estimateCourseName;

  function firstCourseNameFromTables() {
    var documents = collectDocuments();
    for (var d = 0; d < documents.length; d += 1) {
      var tables = documents[d].querySelectorAll('table');
      for (var t = 0; t < tables.length; t += 1) {
        var rows = tables[t].querySelectorAll('tr');
        for (var r = 0; r < rows.length; r += 1) {
          var cells = rows[r].querySelectorAll('th,td');
          var courseIndex = -1;
          for (var c = 0; c < cells.length; c += 1) {
            if (textOf(cells[c]) === '科目名') {
              courseIndex = c;
              break;
            }
          }
          if (courseIndex < 0) {
            continue;
          }
          for (var same = courseIndex + 1; same < cells.length; same += 1) {
            var sameRowValue = textOf(cells[same]);
            if (sameRowValue) {
              return sameRowValue;
            }
          }
          for (var next = r + 1; next < rows.length; next += 1) {
            var nextCells = rows[next].querySelectorAll('th,td');
            if (nextCells.length <= courseIndex) {
              continue;
            }
            var value = textOf(nextCells[courseIndex]);
            if (value) {
              return value;
            }
          }
        }
      }
    }
    return '';
  }

  function firstMatchingCourseNameText(selectors) {
    var documents = collectDocuments();
    for (var i = 0; i < selectors.length; i += 1) {
      for (var d = 0; d < documents.length; d += 1) {
        var elements = documents[d].querySelectorAll(selectors[i]);
        for (var j = 0; j < elements.length; j += 1) {
          var text = textOf(elements[j]);
          var extracted = extractCourseNameFromText(text);
          if (extracted) {
            return extracted;
          }
        }
      }
    }
    return '';
  }

  function normalizeCourseName(text) {
    var normalized = (text || '').replace(/\s+/g, ' ').trim();
    var extracted = extractCourseNameFromText(normalized);
    if (extracted) {
      return extracted;
    }
    var codeMatch = normalized.match(/^[A-Z0-9]{4,}\s+(.+)$/i);
    if (codeMatch) {
      return codeMatch[1].trim();
    }
    var enrolledStudentsMatch = normalized.match(/([^\s、。]+?)の履修者各位/);
    if (enrolledStudentsMatch) {
      return enrolledStudentsMatch[1].trim();
    }
    if (isIgnoredCourseName(normalized)) {
      return '未分類';
    }
    return normalized || '未分類';
  }

  function extractCourseNameFromText(text) {
    var normalized = (text || '').replace(/\s+/g, ' ').trim();
    var labeledMatch = normalized.match(/(?:授業科目名|授業科目|科目名|授業名|講義名|科目\s*[:：])\s*[:：]?\s*(?:[A-Z0-9]{4,}\s+)?(.+)$/i);
    if (!labeledMatch) {
      return '';
    }
    var extracted = trimAtKnownFieldLabel(labeledMatch[1].trim());
    return isIgnoredCourseName(extracted) ? '' : extracted;
  }

  function trimAtKnownFieldLabel(text) {
    var match = text.match(/\s(?:担当教員|担当|教員|曜日|時限|開講|年度|学期|単位|対象|授業コード|科目区分|シラバス|提出期限|課題)(?:\s|$)/);
    return (match ? text.slice(0, match.index) : text).trim();
  }

  function isIgnoredCourseName(text) {
    var lower = (text || '').toLowerCase();
    var genericPageLabels = [
      '開設一覧',
      '連絡通知',
      '掲示一覧',
      '授業ポートフォリオ',
      'レポート・小テスト・アンケート提出',
      'レポート提出',
      '小テスト',
      'アンケート',
      '年度 開講所属 開講番号 科目名',
      'タイトル'
    ];
    if (genericPageLabels.indexOf(text) >= 0) {
      return true;
    }
    return (
      lower.indexOf('campussquare') >= 0 ||
      lower.indexOf('more better gakujo') >= 0 ||
      text.indexOf('学務情報システム') >= 0
    );
  }

  function isDownloadLike(element, url) {
    var text = textOf(element).toLowerCase();
    var href = (url || '').toLowerCase();
    return hasStrongDownloadSignal(element, url) || href.indexOf('campussquare.do') >= 0;
  }

  function hasStrongDownloadSignal(element, url) {
    var text = textOf(element).toLowerCase();
    var href = (url || '').toLowerCase();
    return (
      element.hasAttribute('download') ||
      text.indexOf('ダウンロード') >= 0 ||
      text.indexOf('download') >= 0 ||
      href.indexOf('download') >= 0 ||
      href.indexOf('file') >= 0 ||
      /\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|csv|txt)(?:[?#].*)?$/.test(href)
    );
  }

  function normalizedActionText(element) {
    return textOf(element).replace(/\s+/g, '').toLowerCase();
  }

  function isSubmissionWorkflowAction(element) {
    var text = normalizedActionText(element);
    if (!text) {
      return false;
    }
    return (
      /^(提出|提出する|送信|送信する)$/.test(text) ||
      /^(取消|取消し|取り消し|取り消す|キャンセル|中止)$/.test(text) ||
      /^(戻る|前へ|次へ|進む|確認|確認する)$/.test(text) ||
      /^(レポート|小テスト)?提出(確認)?$/.test(text) ||
      /^(レポート|小テスト)?提出(用)?(画面|ページ)(へ|に進む|へ進む)?$/.test(text)
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

  window.__MBG_DOWNLOAD_CAPTURE_HANDLER = function(event) {
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
    if (isSubmissionWorkflowAction(submitter) && !hasStrongDownloadSignal(submitter, absoluteAction)) {
      return;
    }

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
  };

  document.addEventListener('click', window.__MBG_DOWNLOAD_CAPTURE_HANDLER, true);
})();
''';
  }
}
