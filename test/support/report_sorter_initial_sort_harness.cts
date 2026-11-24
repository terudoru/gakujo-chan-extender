import type {} from 'node:fs';
const payload = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const checks = `
(function() {
  Date.now = () => Date.parse('2026-11-24T00:00:00Z');
  function createTable() {
    const rows = [
      ['c', 'Zebra', 'Not submitted', 'A', '2020/01/01'],
      ['a', 'Alpha', 'Submitted', 'C', '2099/01/01'],
      ['b', 'Beta', 'Not submitted', 'B', '2099/02/02'],
    ].map(([id, title, status, number, deadline]) => ({id,
      cells: ['', title, status, number, '', '', '', deadline].map(text => ({innerText: text, style: {}}))}));
    const result = {rows: [{cells: []}, ...rows], tBodies: []};
    result.tBodies = [{appendChild(row) {
      result.rows.splice(result.rows.indexOf(row), 1);
      result.rows.push(row);
    }}];
    return result;
  }
  let table = createTable();
  document.querySelector = selector => selector === '#enqListForm table:nth-of-type(2)' ? table : null;
  function expectOrder(ids, label) {
    const actual = table.rows.slice(1).map(row => row.id);
    if (JSON.stringify(actual) !== JSON.stringify(ids)) throw new Error(label + ': ' + JSON.stringify(actual));
  }
  ${payload.script}
  expectOrder(${JSON.stringify(payload.expected)}, 'initial sort');
  document.getElementById('mbg-report-number-button').click();
  expectOrder(['c','b','a'], 'manual course number');
  document.getElementById('mbg-report-date-button').click();
  expectOrder(['b','a','c'], 'manual deadline');
  document.getElementById('mbg-report-title-button').click();
  expectOrder(['a','b','c'], 'manual title');
  window.__MBG_REPORT_SORTER_UPDATE();
  expectOrder(['a','b','c'], 'poll retains manual sort');
  ${payload.reconfigureScript}
  expectOrder(['a','b','c'], 'reinjection retains manual sort');
  const getElementById = document.getElementById;
  let onReports = false;
  document.getElementById = id => id === 'main-frame-if'
    ? {contentWindow: {document: {querySelector: () => onReports ? table : null}}}
    : getElementById(id);
  const querySelector = document.querySelector;
  document.querySelector = selector => onReports ? querySelector(selector) : null;
  window.__MBG_REPORT_SORTER_UPDATE();
  onReports = true;
  window.__MBG_REPORT_SORTER_UPDATE();
  expectOrder(['a','b','c'], 'return retains manual sort on same table');
  table = createTable();
  window.__MBG_REPORT_SORTER_UPDATE();
  expectOrder(${JSON.stringify(payload.reconfiguredExpected)}, 'replacement table uses new default');
})();
`;
process.argv = [process.argv[0], process.argv[1], 'report', checks, '', '', 'once'];
require('./page_script_dom_harness.cts');
