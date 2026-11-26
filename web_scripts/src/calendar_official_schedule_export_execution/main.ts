import { configureInputs, diagnosticsFor, isExportForm, normalize, textOf } from '../shared/calendar_export_form.js';

declare const __mbgConfig: { shouldActivate: boolean; startDate: string; endDate: string };

function calendarOfficialScheduleExportExecution() {
  var shouldActivate = __mbgConfig.shouldActivate;
  var startDate = __mbgConfig.startDate;
  var endDate = __mbgConfig.endDate;
  function exportButton(form: HTMLFormElement) {
    var controls = Array.prototype.slice.call(
      form.querySelectorAll('button,input,a,[onclick]')
    );
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = normalize(textOf(control));
      var type = String(control.getAttribute && control.getAttribute('type') || '').toLowerCase();
      if (type === 'hidden') {
        continue;
      }
      if (label.indexOf('クリア') >= 0 ||
          label.indexOf('戻る') >= 0 ||
          label.indexOf('back') >= 0 ||
          label.indexOf('clear') >= 0) {
        continue;
      }
      if (label.indexOf('エクスポート実行') >= 0 ||
          label.indexOf('executeexport') >= 0 ||
          label.indexOf('エクスポート') >= 0) {
        return control;
      }
    }
    return null;
  }
  function inspectDocument(doc: Document) {
    var forms = Array.prototype.slice.call(doc.querySelectorAll('form'));
    var missingCandidate = null;
    for (var f = 0; f < forms.length; f += 1) {
      var form = forms[f];
      if (!isExportForm(form)) {
        continue;
      }
      configureInputs(form, startDate, endDate, true);
      var eventId = form.querySelector('input[name="_eventId"]');
      if (eventId && !eventId.value) {
        eventId.value = 'executeExport';
      }
      var button = exportButton(form);
      if (!button) {
        missingCandidate = missingCandidate || {
          status: 'not_found',
          label: '',
          url: '',
          diagnostics: diagnosticsFor(doc, form)
        };
        continue;
      }
      if (shouldActivate) {
        button.click();
        return {
          status: 'clicked',
          label: textOf(button),
          url: '',
          diagnostics: diagnosticsFor(doc, form)
        };
      }
      return {
        status: 'clickable',
        label: textOf(button),
        url: '',
        diagnostics: diagnosticsFor(doc, form)
      };
    }
    return missingCandidate;
  }
  function collect(win: Window): ReturnType<typeof inspectDocument> {
    try {
      if (!win || !win.document) {
        return null;
      }
      var found = inspectDocument(win.document);
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
  function formCounts() {
    var values: { url: string; title: string; formCount: number }[] = [];
    function collectCounts(win: Window) {
      try {
        if (!win || !win.document) {
          return;
        }
        values.push({
          url: String(win.document.location.href || '').split('?')[0],
          title: win.document.title || '',
          formCount: win.document.querySelectorAll('form').length
        });
        for (var i = 0; i < win.frames.length; i += 1) {
          collectCounts(win.frames[i]);
        }
      } catch (e) {}
    }
    collectCounts(window);
    return values;
  }
  return JSON.stringify(collect(window) || {
    status: 'not_found',
    label: '',
    url: '',
    diagnostics: {
      documents: formCounts()
    }
  });
}

__mbgEntryResult = calendarOfficialScheduleExportExecution();
