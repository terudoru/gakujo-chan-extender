import { calendarControls, findInCalendarFrames, textOf } from '../shared/calendar_schedule_dom.js';

function calendarScheduleMonthViewActivation(): string {
  function inspect(doc: Document) {
    var controls = calendarControls(doc);
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
  return JSON.stringify(findInCalendarFrames(window, inspect) || {
    status: 'not_found',
    label: '',
    url: ''
  });
}

__mbgEntryResult = calendarScheduleMonthViewActivation();
