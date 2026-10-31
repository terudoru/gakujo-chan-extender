export {};
function downloadCapture() {
  var captureVersion = 18;
  if (window.__MBG_DOWNLOAD_CAPTURE_VERSION === captureVersion) {
    if (window.__MBG_DOWNLOAD_CAPTURE_ATTACH) {
      window.__MBG_DOWNLOAD_CAPTURE_ATTACH();
    }
    return;
  }
  window.__MBG_DOWNLOAD_CAPTURE_VERSION = captureVersion;

  if (window.__MBG_DOWNLOAD_CAPTURE_HANDLER &&
      window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS) {
    for (var oldDocIndex = 0;
        oldDocIndex < window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS.length;
        oldDocIndex += 1) {
      try {
        window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS[oldDocIndex].removeEventListener(
          'click',
          window.__MBG_DOWNLOAD_CAPTURE_HANDLER!,
          true
        );
        window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS[oldDocIndex].removeEventListener(
          'submit',
          window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_HANDLER!,
          true
        );
      } catch (e) {}
    }
  }
  window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS = [];

  if (window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER &&
      window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS) {
    for (var oldLoadDocIndex = 0;
        oldLoadDocIndex < window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS.length;
        oldLoadDocIndex += 1) {
      try {
        window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS[oldLoadDocIndex]
          .removeEventListener(
            'load',
            window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER!,
            true
          );
      } catch (e) {}
    }
  }
  window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS = [];
  restoreFormSubmits();
  var formSubmitters = new WeakMap<HTMLFormElement, HTMLButtonElement | HTMLInputElement>();

  function textOf(element: (HTMLElement & {value?: string}) | null | undefined) {
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

  function looksLikeFileName(text: string) {
    return /\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|csv|txt|odt|ods|odp|jpg|jpeg|png|gif|mp4|mov|7z|rar)$/i
      .test((text || '').trim());
  }

  function isGenericDownloadActionText(text: string) {
    var normalized = (text || '').replace(/\s+/g, '').toLowerCase();
    return /^(ダウンロード(?:する)?|download(?:file)?|保存(?:する)?|save(?:file)?)$/.test(normalized);
  }

  function normalizedDisplayedFileName(text: string) {
    var normalized = (text || '').replace(/\s+/g, ' ').trim();
    var labeled = normalized.match(
      /^(?:ファイル名|資料名|添付ファイル名?|文書名|タイトル)\s*[:：]\s*(.+)$/
    );
    return (labeled ? labeled[1] : normalized).trim();
  }

  function isUsefulDisplayedFileName(text: string) {
    var normalized = normalizedDisplayedFileName(text);
    if (!normalized || normalized.length > 240 ||
        isGenericDownloadActionText(normalized)) {
      return false;
    }
    var compact = normalized.replace(/\s+/g, '').toLowerCase();
    return !/^(?:ファイル名|資料名|添付ファイル名?|文書名|タイトル|開く|閲覧|詳細|削除)$/.test(compact);
  }

  function looksLikeMetadataValue(text: string) {
    var normalized = (text || '').replace(/\s+/g, ' ').trim();
    return (
      /^\d+$/.test(normalized) ||
      /^\d{4}[\/.-]\d{1,2}[\/.-]\d{1,2}(?:\s+\d{1,2}:\d{2})?$/.test(normalized) ||
      /^\d+(?:\.\d+)?\s*(?:bytes?|kb|mb|gb)$/i.test(normalized)
    );
  }

  function directTableCells(row: Element | null) {
    var cells: HTMLElement[] = [];
    if (!row) {
      return cells;
    }
    var children = row.children || [];
    for (var i = 0; i < children.length; i += 1) {
      var tagName = (children[i].tagName || '').toLowerCase();
      if (tagName === 'th' || tagName === 'td') {
        cells.push(children[i] as HTMLElement);
      }
    }
    if (!cells.length && row.querySelectorAll) {
      var queried = row.querySelectorAll<HTMLElement>('th, td');
      for (var j = 0; j < queried.length; j += 1) {
        cells.push(queried[j]);
      }
    }
    return cells;
  }

  function tableHeaderNameScore(actionElement: HTMLElement, candidateElement: HTMLElement) {
    try {
      if (!actionElement.closest || !candidateElement.closest) {
        return 0;
      }
      var row = actionElement.closest('tr');
      var cell = candidateElement.closest<HTMLElement>('th, td');
      var table = row && row.closest ? row.closest('table') : null;
      if (!row || !cell || !table || !table.querySelectorAll) {
        return 0;
      }
      var cells = directTableCells(row);
      var columnIndex = cells.indexOf(cell);
      if (columnIndex < 0) {
        return 0;
      }
      var rows = table.querySelectorAll('tr');
      for (var i = 0; i < rows.length; i += 1) {
        if (rows[i] === row) {
          break;
        }
        var headerCells = directTableCells(rows[i]);
        if (columnIndex >= headerCells.length) {
          continue;
        }
        var header = textOf(headerCells[columnIndex]).replace(/\s+/g, '');
        if (/(?:ファイル|資料|文書|添付).*(?:名|タイトル)?|^(?:タイトル|名称|件名)$/.test(header)) {
          return 700;
        }
        if (/^(?:番号|no\.?|公開日|掲載日|登録日|更新日|日時|日付|サイズ|容量|操作)$/i.test(header)) {
          return -400;
        }
      }
    } catch (e) {}
    return 0;
  }

  function displayedFileNameScore(actionElement: HTMLElement, candidateElement: HTMLElement, text: string) {
    if (!isUsefulDisplayedFileName(text) || looksLikeMetadataValue(text)) {
      return -1;
    }
    var score = Math.min(text.length, 120);
    if (looksLikeFileName(text)) {
      score += 1000;
    }
    score += tableHeaderNameScore(actionElement, candidateElement);
    var semanticHint = (
      candidateElement.id || ''
    ) + ' ' + (
      typeof candidateElement.className === 'string'
        ? candidateElement.className
        : ''
    ) + ' ' + (
      candidateElement.getAttribute
        ? candidateElement.getAttribute('name') || ''
        : ''
    );
    if (/(?:file.?name|filename|attach|document|material|title|name)/i.test(semanticHint)) {
      score += 500;
    }
    var tagName = (candidateElement.tagName || '').toLowerCase();
    if (/^(?:a|label|strong|dd)$/.test(tagName)) {
      score += 120;
    } else if (tagName === 'span') {
      score += 60;
    }
    return score;
  }

  function fileNameFromForm(form: HTMLFormElement | null) {
    if (!form || !form.querySelectorAll) {
      return '';
    }
    var fields = form.querySelectorAll<HTMLInputElement>('input[name], input[id]');
    for (var i = 0; i < fields.length; i += 1) {
      var field = fields[i];
      var fieldName = (
        field.name ||
        field.getAttribute && field.getAttribute('name') ||
        field.id ||
        field.getAttribute && field.getAttribute('id') ||
        ''
      ).toLowerCase();
      var value = (field.value || '').replace(/\s+/g, ' ').trim();
      if (value &&
          /(file.?name|filename|attach.?name|document.?name)/.test(fieldName)) {
        return value;
      }
    }
    return '';
  }

  function nearbyDisplayedFileName(element: HTMLElement | null | undefined) {
    if (!element || !element.closest) {
      return '';
    }
    var container = element.closest(
      'tr, li, .file, .attachment, .document, .download'
    );
    if (!container || !container.querySelectorAll) {
      return '';
    }
    var candidates = container.querySelectorAll<HTMLElement>(
      'th, td, dt, dd, a, span, label, strong, p'
    );
    var bestName = '';
    var bestScore = -1;
    for (var i = 0; i < candidates.length; i += 1) {
      var candidateElement = candidates[i];
      try {
        if (candidateElement === element ||
            candidateElement.contains && candidateElement.contains(element)) {
          continue;
        }
      } catch (e) {}
      var candidate = normalizedDisplayedFileName(textOf(candidateElement));
      var score = displayedFileNameScore(
        element,
        candidateElement,
        candidate
      );
      if (score > bestScore) {
        bestName = candidate;
        bestScore = score;
      }
    }
    return bestName;
  }

  function downloadFileName(element: HTMLElement | null | undefined, form: HTMLFormElement | null) {
    var directName = normalizedDisplayedFileName(textOf(element));
    if (isUsefulDisplayedFileName(directName)) {
      return directName;
    }
    var nearbyName = nearbyDisplayedFileName(element);
    if (nearbyName) {
      return nearbyName;
    }
    var explicitName = element && element.getAttribute
      ? (element.getAttribute('download') || '').trim()
      : '';
    if (explicitName) {
      return explicitName;
    }
    return fileNameFromForm(form);
  }

  function collectDocuments() {
    var documents: Document[] = [];
    function collect(win: Window) {
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

  function firstUsefulText(selectors: string[]) {
    var documents = collectDocuments();
    for (var i = 0; i < selectors.length; i += 1) {
      for (var d = 0; d < documents.length; d += 1) {
        var elements = documents[d].querySelectorAll<HTMLElement>(selectors[i]);
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
          var cells = rows[r].querySelectorAll<HTMLElement>('th,td');
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
            var nextCells = rows[next].querySelectorAll<HTMLElement>('th,td');
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

  function firstMatchingCourseNameText(selectors: string[]) {
    var documents = collectDocuments();
    for (var i = 0; i < selectors.length; i += 1) {
      for (var d = 0; d < documents.length; d += 1) {
        var elements = documents[d].querySelectorAll<HTMLElement>(selectors[i]);
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

  function normalizeCourseName(text: string) {
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

  function extractCourseNameFromText(text: string) {
    var normalized = (text || '').replace(/\s+/g, ' ').trim();
    var labeledMatch = normalized.match(/(?:授業科目名|授業科目|科目名|授業名|講義名|科目\s*[:：])\s*[:：]?\s*(?:[A-Z0-9]{4,}\s+)?(.+)$/i);
    if (!labeledMatch) {
      return '';
    }
    var extracted = trimAtKnownFieldLabel(labeledMatch[1].trim());
    return isIgnoredCourseName(extracted) ? '' : extracted;
  }

  function trimAtKnownFieldLabel(text: string) {
    var match = text.match(/\s(?:担当教員|担当|教員|曜日|時限|開講|年度|学期|単位|対象|授業コード|科目区分|シラバス|提出期限|課題)(?:\s|$)/);
    return (match ? text.slice(0, match.index) : text).trim();
  }

  function isIgnoredCourseName(text: string) {
    if (!text || text.length > 100) {
      return true;
    }
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

  function isDownloadLike(element: HTMLElement, url: string) {
    if (element.hasAttribute('download')) return true;
    var parsed = new URL(url);
    if (!/filerefer/i.test(parsed.searchParams.get('_flowId') || '') &&
        (/\/(campussquare|campusportal)\.do$/i.test(parsed.pathname) ||
         parsed.searchParams.has('seqNo') ||
         /^(displayMidoku|confirm)$/i.test(parsed.searchParams.get('_eventId') || ''))) {
      return false;
    }
    var text = textOf(element).toLowerCase();
    var href = (url || '').toLowerCase();
    return (
      text.indexOf('ダウンロード') >= 0 ||
      text.indexOf('download') >= 0 ||
      href.indexOf('download') >= 0 ||
      href.indexOf('file') >= 0 ||
      /\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|csv|txt)(?:[?#].*)?$/.test(href)
    );
  }

  function hasStrongDownloadSignal(url: string, fields: Record<string, string>) {
    if (/\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|csv|txt|odt|ods|odp|jpg|jpeg|png|gif|mp4|mov|7z|rar)(?:[?#].*)?$/i.test(url)) {
      return true;
    }
    var found = false;
    function check(value: string, key: string) {
      if (/^_eventId$/i.test(key) && /download/i.test(value) ||
          /^_eventId_.*download/i.test(key) ||
          /^(file.?download|download.?file)$/i.test(key)) found = true;
    }
    new URL(url).searchParams.forEach(check);
    Object.keys(fields || {}).forEach(function(key) { check(fields[key], key); });
    return found;
  }

  function isAppOwned(element: HTMLElement) {
    for (var node: HTMLElement | null = element; node; node = node.parentElement) {
      if (/(^|\s)mbg-/.test((node.id || '') + ' ' +
          (node.getAttribute('class') || ''))) return true;
      var attributes = node.attributes || [];
      for (var i = 0; i < attributes.length; i += 1) {
        if (attributes[i].name.indexOf('data-mbg-') === 0) return true;
      }
    }
    return false;
  }

  function normalizedActionText(element: HTMLElement) {
    return textOf(element).replace(/\s+/g, '').toLowerCase();
  }

  function isSubmissionWorkflowAction(element: HTMLElement) {
    var text = normalizedActionText(element);
    if (!text) {
      return false;
    }
    return (
      /^(提出|提出する|送信|送信する)$/.test(text) ||
      /^(取消|取消し|取り消し|取り消す|キャンセル|中止)$/.test(text) ||
      /^(戻る|前へ|次へ|進む|確認|確認する)$/.test(text) ||
      /^(確定保存|一時保存|保存|クリア|削除|登録|確定)(する)?$/.test(text) ||
      /^(save|submit|confirm|back|clear|delete|register|cancel)$/.test(text) ||
      /^(レポート|小テスト)?提出(確認)?$/.test(text) ||
      /^(レポート|小テスト)?提出(用)?(画面|ページ)(へ|に進む|へ進む)?$/.test(text)
    );
  }

  function formFields(form: HTMLFormElement | null, submitter: HTMLButtonElement | HTMLInputElement | null | undefined) {
    var fields: Record<string, string> = {};
    if (!form) {
      return fields;
    }
    var data = new FormData(form);
    if (submitter && submitter.name) {
      data.set(submitter.name, submitter.value || '');
    }
    data.forEach(function(value, key) {
      if (typeof value === 'string') {
        fields[key] = value;
      }
    });
    return fields;
  }

  function post(payload: {url: string; method: string; fileName: string; courseName: string; formFields: Record<string, string>}) {
    window.MoreBetterGakujoDownloads.postMessage(JSON.stringify(payload));
  }

  function baseUrlOf(element: HTMLElement | null) {
    try {
      var ownerDocument = element && element.ownerDocument;
      if (ownerDocument) {
        return ownerDocument.baseURI ||
          ownerDocument.location && ownerDocument.location.href ||
          window.location.href;
      }
    } catch (e) {}
    return window.location.href;
  }

  function absoluteUrlOf(element: HTMLElement | null, rawUrl: string | null) {
    return new URL(rawUrl || '', baseUrlOf(element)).href;
  }

  function shouldCapture(element: HTMLElement, url: string, fields: Record<string, string>) {
    if (isAppOwned(element) ||
        new URL(url).host !== 'gakujo.iess.niigata-u.ac.jp') return false;
    if (isSubmissionWorkflowAction(element) && !hasStrongDownloadSignal(url, fields)) {
      return false;
    }
    return hasStrongDownloadSignal(url, fields) || isDownloadLike(element, url);
  }

  function formDownloadSignals(url: string, fields: Record<string, string>) {
    var parsed = new URL(url);
    var params = parsed.searchParams;
    var explicit = /download/i.test(url) ||
      /\.(pdf|docx?|xlsx?|pptx?|zip|csv|txt|png|jpe?g)$/i.test(parsed.pathname);
    var workflow = false;
    var fileRefer = false;
    var hasFileId = false;
    function check(value: string, key: string) {
      var namedEvent = /^_eventId_(.*)$/i.exec(key);
      if (/^_eventId$/i.test(key) || namedEvent) {
        if (namedEvent) value = namedEvent[1];
        if (/download/i.test(value)) explicit = true;
        else if (/(confirm|entry|submit|save|regist|update|delete|back|clear|cancel|next|prev|complete|finish)/i.test(value)) workflow = true;
      }
      if (/^(file.?download|download.?file|downloadType)$/i.test(key)) explicit = true;
      if (/^_flowId$/i.test(key) && /filerefer/i.test(value)) fileRefer = true;
      if (/^fileId$/i.test(key) && value.trim()) hasFileId = true;
    }
    params.forEach(check);
    Object.keys(fields).forEach(function(key) { check(fields[key], key); });
    if (fileRefer && hasFileId) explicit = true;
    return {explicit: explicit, workflow: workflow};
  }

  function submissionAttribute(form: HTMLFormElement, submitter: HTMLButtonElement | HTMLInputElement | null | undefined, name: string) {
    return submitter && submitter.hasAttribute('form' + name)
      ? submitter.getAttribute('form' + name) : form.getAttribute(name);
  }

  function captureForm(form: HTMLFormElement | null, submitter: HTMLButtonElement | HTMLInputElement | null | undefined, explicitOnly?: boolean) {
    if (!form || isAppOwned(form) || submitter && isAppOwned(submitter)) return false;
    var action = submissionAttribute(form, submitter, 'action') || baseUrlOf(form);
    var method = (submissionAttribute(form, submitter, 'method') || 'GET').toUpperCase();
    var enctype = (submissionAttribute(form, submitter, 'enctype') ||
      'application/x-www-form-urlencoded').toLowerCase();
    var target = submissionAttribute(form, submitter, 'target') || '_self';
    // The native request cannot replay other encodings or browsing contexts.
    if (!/^(GET|POST)$/.test(method) ||
        method === 'POST' && enctype !== 'application/x-www-form-urlencoded' ||
        !/^_self$/i.test(target)) return false;
    var absoluteAction = absoluteUrlOf(form, action);
    var fields = formFields(form, submitter);
    var signals = formDownloadSignals(absoluteAction, fields);
    if (signals.workflow) return false;
    if (explicitOnly) {
      if (new URL(absoluteAction).host !== 'gakujo.iess.niigata-u.ac.jp' ||
          !signals.explicit) return false;
    } else if (!shouldCapture(submitter || form, absoluteAction, fields)) return false;
    post({
      url: absoluteAction,
      method: method,
      fileName: downloadFileName(submitter, form),
      courseName: estimateCourseName(),
      formFields: fields
    });
    return true;
  }

  window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_HANDLER = function(event) {
    var form = event.target as HTMLFormElement;
    var submitter = (event as SubmitEvent).submitter as HTMLButtonElement | HTMLInputElement | null || formSubmitters.get(form);
    formSubmitters.delete(form);
    if (captureForm(form, submitter, true)) {
      event.preventDefault();
      event.stopPropagation();
    }
  };

  window.__MBG_DOWNLOAD_CAPTURE_HANDLER = function(event) {
    var target = event.target as HTMLElement | null;
    if (!target || !target.closest || isAppOwned(target)) {
      return;
    }

    var anchor = target.closest<HTMLElement>('a[href]');
    if (anchor) {
      var href = (anchor.getAttribute('href') || '').trim();
      if (href.charAt(0) === '#' || /^javascript:/i.test(href)) return;
      var absoluteUrl = absoluteUrlOf(anchor, href);
      var params = new URL(absoluteUrl).searchParams;
      if (anchor.hasAttribute('onclick') &&
          !hasStrongDownloadSignal(absoluteUrl, {}) &&
          !(/filerefer/i.test(params.get('_flowId') || '') &&
            (params.get('fileId') || '').trim() &&
            (!params.has('_eventId') || /download/i.test(params.get('_eventId')!)))) {
        return;
      }
      if (!shouldCapture(anchor, absoluteUrl, {})) {
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      post({
        url: absoluteUrl,
        method: 'GET',
        fileName: downloadFileName(anchor, null),
        courseName: estimateCourseName(),
        formFields: {}
      });
      return;
    }

    var submitter = target.closest<HTMLButtonElement | HTMLInputElement>('button, input[type="submit"], input[type="button"]');
    if (!submitter) {
      return;
    }

    var form = submitter.form || submitter.closest('form');
    // The page's onclick may select the file and event before submitting.
    if (submitter.hasAttribute('onclick')) {
      if (form) formSubmitters.set(form, submitter);
      return;
    }
    if (form) {
      if (captureForm(form, submitter)) {
        event.preventDefault();
        event.stopPropagation();
      }
      return;
    }
    var submitterPageUrl = baseUrlOf(submitter);
    if (!shouldCapture(submitter, submitterPageUrl, {})) {
      return;
    }

    event.preventDefault();
    event.stopPropagation();
    post({
      url: submitterPageUrl,
      method: 'GET',
      fileName: downloadFileName(submitter, null),
      courseName: estimateCourseName(),
      formFields: {}
    });
  };

  function restoreFormSubmits() {
    var prototypes = window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES || [];
    prototypes.forEach(function(entry) {
      var owner = entry.prototype as unknown as Record<string, MbgSubmitHookFunction>;
      var key = 'submit';
      while (owner[key] && owner[key] !== entry.wrapper && owner[key].__mbgFormSubmitHook) {
        owner = owner[key].__mbgFormSubmitHook as unknown as Record<string, MbgSubmitHookFunction>;
        key = 'original';
      }
      if (owner[key] === entry.wrapper) owner[key] = entry.original;
    });
    window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES = [];
  }

  function wrapFormSubmit(doc: Document) {
    // requestSubmit fires the submit event and uses the existing handler.
    var view = doc.defaultView as (Window & typeof globalThis) | null;
    var prototype = view && view.HTMLFormElement && view.HTMLFormElement.prototype;
    if (!prototype) return;
    var entry: MbgSubmitHookEntry = { prototype: prototype, original: prototype.submit };
    var wrapper: MbgSubmitHookFunction = function(this: HTMLFormElement) {
      formSubmitters.delete(this);
      if (!captureForm(this, null, true)) return entry.original.apply(this, arguments as unknown as []);
    };
    wrapper.__mbgFormSubmitHook = entry;
    entry.wrapper = wrapper;
    prototype.submit = wrapper;
    window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES!.push(entry);
  }

  window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER = function(event) {
    var target = event && event.target as HTMLElement | null;
    var tagName = (target && target.tagName || '').toLowerCase();
    if (tagName !== 'iframe' && tagName !== 'frame') {
      return;
    }
    if (window.__MBG_DOWNLOAD_CAPTURE_ATTACH) {
      window.__MBG_DOWNLOAD_CAPTURE_ATTACH();
    }
  };

  function attachClickHandlers() {
    if (window.__MBG_DOWNLOAD_CAPTURE_HANDLER &&
        window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS) {
      for (var oldDocIndex = 0;
          oldDocIndex < window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS.length;
          oldDocIndex += 1) {
        try {
          window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS[oldDocIndex].removeEventListener(
            'click',
            window.__MBG_DOWNLOAD_CAPTURE_HANDLER!,
            true
          );
          window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS[oldDocIndex].removeEventListener(
            'submit',
            window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_HANDLER!,
            true
          );
        } catch (e) {}
      }
    }
    window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS = [];
    if (window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER &&
        window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS) {
      for (var oldLoadDocIndex = 0;
          oldLoadDocIndex < window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS.length;
          oldLoadDocIndex += 1) {
        try {
          window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS[oldLoadDocIndex]
            .removeEventListener(
              'load',
              window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER!,
              true
            );
        } catch (e) {}
      }
    }
    window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS = [];
    restoreFormSubmits();
    var documents = collectDocuments();
    for (var i = 0; i < documents.length; i += 1) {
      try {
        documents[i].addEventListener(
          'click',
          window.__MBG_DOWNLOAD_CAPTURE_HANDLER!,
          true
        );
        window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS!.push(documents[i]);
        documents[i].addEventListener(
          'submit',
          window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_HANDLER!,
          true
        );
        wrapFormSubmit(documents[i]);
        documents[i].addEventListener(
          'load',
          window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER!,
          true
        );
        window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS!.push(documents[i]);
      } catch (e) {}
    }
  }

  window.__MBG_DOWNLOAD_CAPTURE_ATTACH = attachClickHandlers;
  attachClickHandlers();
}

downloadCapture();
