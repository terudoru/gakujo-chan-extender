export {};
function calendarScheduleMonthViewActivation(): string {
  function textOf(node: HTMLInputElement) {
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
  function inspect(doc: Document) {
    var controls = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,[onclick]')
    );
    var monthControl = null;
    var monthLabel = '';
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = textOf(control);
      var normalized = label.toLowerCase();
      if (normalized.indexOf('changecalunitweek') >= 0 ||
          label.indexOf('週単位') >= 0) {
        return {
          status: 'ready',
          label: label,
          url: doc.location && doc.location.href || ''
        };
      }
      if (!monthControl &&
          (normalized.indexOf('changecalunitmonth') >= 0 ||
              label.indexOf('月単位') >= 0)) {
        monthControl = control;
        monthLabel = label;
      }
    }
    if (!monthControl) {
      return null;
    }
    try {
      monthControl.click();
      return {
        status: 'clicked',
        label: monthLabel,
        url: doc.location && doc.location.href || ''
      };
    } catch (e) {
      return {
        status: 'exception',
        label: monthLabel,
        url: doc.location && doc.location.href || '',
        message: String(e && (e as Error).message || e)
      };
    }
  }
  function collect(win: Window): {status: string; label: string; url: string; message?: string} | null {
    try {
      var found = inspect(win.document);
      if (found) {
        return found;
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        found = collect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {}
    return null;
  }
  return JSON.stringify(collect(window) || {
    status: 'not_found',
    label: '',
    url: ''
  });
}

__mbgEntryResult = calendarScheduleMonthViewActivation();
