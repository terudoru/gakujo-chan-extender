import { calendarControls, findInCalendarFrames, monthInDocument, textOf } from '../shared/calendar_schedule_dom.js';

declare const __mbgConfig: { targetYear: number; targetMonth: number };

function calendarScheduleMonthNavigation() {
  var targetYear = __mbgConfig.targetYear;
  var targetMonth = __mbgConfig.targetMonth;
  function clickControl(doc: Document, direction: number) {
    var view = doc.defaultView || window;
    try {
      if (direction > 0 && typeof view.loadNextMonth === 'function') {
        view.loadNextMonth();
        return true;
      }
      if (direction < 0 && typeof view.loadBeforeMonth === 'function') {
        view.loadBeforeMonth();
        return true;
      }
    } catch (e) {}
    var controls = calendarControls(doc);
    var fallback = null;
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = textOf(control).toLowerCase();
      var onclick = String(
        control.getAttribute && control.getAttribute('onclick') || ''
      ).toLowerCase();
      if (direction > 0) {
        if (onclick.indexOf('loadnextmonth') >= 0 ||
            label.indexOf('loadnextmonth') >= 0) {
          control.click();
          return true;
        }
        if (!fallback &&
            (label.indexOf('next') >= 0 ||
            label.indexOf('次') >= 0)) {
          fallback = control;
        }
      } else if (direction < 0) {
        if (onclick.indexOf('loadbeforemonth') >= 0 ||
            label.indexOf('loadbeforemonth') >= 0) {
          control.click();
          return true;
        }
        if (!fallback &&
            (label.indexOf('prev') >= 0 ||
            label.indexOf('前') >= 0)) {
          fallback = control;
        }
      }
    }
    if (fallback) {
      fallback.click();
      return true;
    }
    return false;
  }
  function inspect(doc: Document) {
    var current = monthInDocument(doc);
    if (!current) {
      return null;
    }
    var diff = (targetYear - current.year) * 12 +
      (targetMonth - current.month);
    if (diff === 0) {
      return {
        status: 'ready',
        year: current.year,
        month: current.month
      };
    }
    if (clickControl(doc, diff > 0 ? 1 : -1)) {
      return {
        status: 'clicked',
        year: current.year,
        month: current.month,
        direction: diff > 0 ? 'next' : 'prev'
      };
    }
    return null;
  }
  return JSON.stringify(findInCalendarFrames(window, inspect) || {
    status: 'not_found',
    year: 0,
    month: 0
  });
}

__mbgEntryResult = calendarScheduleMonthNavigation();
