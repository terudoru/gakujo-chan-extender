export {};
function teardownReportSorter() {
  window.clearInterval(window.__MBG_REPORT_SORTER_INTERVAL);
  delete window.__MBG_REPORT_SORTER_INTERVAL;
  delete window.__MBG_REPORT_SORTER_VERSION;
  delete window.__MBG_REPORT_SORTER_UPDATE;
  delete window.__MBG_REPORT_SORTER_DID_INITIAL_SORT;

  var controls = document.querySelectorAll(
    '[data-mbg-report-sorter-owned="true"]'
  );
  for (var i = 0; i < controls.length; i += 1) {
    controls[i].remove();
  }
}

teardownReportSorter();
