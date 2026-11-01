import { isDraftKey, draftDocuments } from './storage_helpers.js';

declare const __mbgConfig: { key: string };

function reportDraftDelete() {
  var key = __mbgConfig.key;

  if (!isDraftKey(key)) return false;
  var removed = false;
  var failed = false;
  draftDocuments().forEach(function(doc) {
    try {
      doc.defaultView!.localStorage.removeItem(key);
      var win = doc.defaultView!;
      var suppressed = win.__MBG_REPORT_DRAFT_DELETED_KEYS ||
        (win.__MBG_REPORT_DRAFT_DELETED_KEYS = Object.create(null));
      suppressed[key] = true;
      var pending = win.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      if (pending && pending.key === key) {
        win.clearTimeout(win.__MBG_REPORT_DRAFT_SAVE_TIMER);
        delete win.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      }
      var status = doc.getElementById('mbg-report-draft-status');
      if (status && status.__MBG_REPORT_DRAFT_KEY === key) {
        Array.prototype.forEach.call(
          doc.querySelectorAll('textarea,input,select,[contenteditable]'),
          function(field) { delete field.__MBG_REPORT_DRAFT_CONFLICT; }
        );
        var label = doc.getElementById('mbg-report-draft-status-label');
        if (label) label.textContent = '下書きを削除しました';
        ['mbg-report-draft-retry', 'mbg-report-draft-replace'].forEach(function(id) {
          var button = doc.getElementById(id);
          if (button) button.style.display = 'none';
        });
        status.__MBG_REPORT_DRAFT_RETRY = null;
        status.__MBG_REPORT_DRAFT_REPLACE = null;
      }
      removed = true;
    } catch (e) {
      failed = true;
    }
  });
  return removed && !failed;

}

__mbgEntryResult = reportDraftDelete();
