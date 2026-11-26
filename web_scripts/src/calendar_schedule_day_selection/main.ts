import { calendarControls, findInCalendarFrames, monthInDocument, textOf } from '../shared/calendar_schedule_dom.js';

declare const __mbgConfig: { targetDate: string };

function calendarScheduleDaySelection() {
  var targetDate = __mbgConfig.targetDate;
  var parts = targetDate.split('/');
  var targetYear = Number(parts[0]);
  var targetMonth = Number(parts[1]);
  var targetDay = Number(parts[2]);
  function clickDay(doc: Document) {
    var month = monthInDocument(doc);
    if (!month || month.year !== targetYear || month.month !== targetMonth) {
      return null;
    }
    var controls = calendarControls(doc);
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
  return JSON.stringify(findInCalendarFrames(window, clickDay) || {
    status: 'not_found',
    date: targetDate,
    label: ''
  });
}

__mbgEntryResult = calendarScheduleDaySelection();
