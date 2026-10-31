export {};

declare const __mbgConfig: { targetDate: string };

function calendarScheduleDaySelection() {
  var targetDate = __mbgConfig.targetDate;
  var parts = targetDate.split('/');
  var targetYear = Number(parts[0]);
  var targetMonth = Number(parts[1]);
  var targetDay = Number(parts[2]);
  function textOf(node: HTMLElement & { value?: string }) {
    if (!node) {
      return '';
    }
    return [
      node.innerText || node.textContent || '',
      node.value || '',
      node.getAttribute && node.getAttribute('title') || '',
      node.getAttribute && node.getAttribute('onclick') || '',
      node.getAttribute && node.getAttribute('href') || ''
    ].join(' ').replace(/\s+/g, ' ').trim();
  }
  function documentMonthMatches(doc: Document) {
    var text = textOf((doc.body || doc) as HTMLElement);
    var match = text.match(/(20[0-9]{2})\s*年\s*([0-9]{1,2})\s*月/);
    return !!match &&
      Number(match[1]) === targetYear &&
      Number(match[2]) === targetMonth;
  }
  function clickDay(doc: Document) {
    if (!documentMonthMatches(doc)) {
      return null;
    }
    var view = doc.defaultView || window;
    var controls = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,[onclick]')
    );
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = textOf(control);
      var compact = label.replace(/\s+/g, '');
      var onclick = String(
        control.getAttribute && control.getAttribute('onclick') || ''
      );
      var href = String(
        control.getAttribute && control.getAttribute('href') || ''
      );
      var datePattern = new RegExp(
        targetYear + '[^0-9]+' + targetMonth + '[^0-9]+' + targetDay + '(?![0-9])'
      );
      if (compact === String(targetDay)) {
        control.click();
        return {
          status: 'clicked',
          label: label,
          date: targetDate
        };
      }
      if (datePattern.test(onclick) || datePattern.test(href)) {
        control.click();
        return {
          status: 'clicked',
          label: label || onclick || href,
          date: targetDate
        };
      }
      var dayOnlyPattern = new RegExp(
        '(?:^|[^0-9])' + targetDay + '(?:[^0-9]|\$)'
      );
      if (onclick.toLowerCase().indexOf('myschlistreload') >= 0 &&
          dayOnlyPattern.test(onclick + ' ' + href) &&
          compact.indexOf(String(targetDay)) >= 0) {
        control.click();
        return {
          status: 'clicked',
          label: label || onclick || href,
          date: targetDate
        };
      }
    }
    return null;
  }
  function inspect(win: Window): { status: string; label: string; date: string } | null {
    try {
      if (!win || !win.document) {
        return null;
      }
      var found = clickDay(win.document);
      if (found) {
        return found;
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        found = inspect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {}
    return null;
  }
  return JSON.stringify(inspect(window) || {
    status: 'not_found',
    date: targetDate,
    label: ''
  });
}

__mbgEntryResult = calendarScheduleDaySelection();
