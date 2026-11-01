/// JavaScript defining `readAssignmentRows(doc: Document)`, which reads the
/// レポート・小テスト・アンケート提出 list into rows for
/// [GakujoAssignment.fromReportRow]. Gakujo serves the list as a table in the
/// PC portal and as `ul.campussmart-list` groups for smartphones and for a
/// page fetched on its own.
export function readAssignmentRows(doc: Document) {
  function text(node: Element | null) {
    return String(node && ((node as HTMLElement).innerText || node.textContent) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }
  var rows = [];
  var table = doc.querySelector<HTMLTableElement>('#enqListForm table:nth-of-type(2)');
  if (table && table.rows) {
    for (var i = 1; i < table.rows.length; i += 1) {
      var cells = table.rows[i].cells;
      if (!cells || cells.length < 8 || !text(cells[1]) || !text(cells[7])) {
        continue;
      }
      rows.push({
        kind: text(cells[0]),
        title: text(cells[1]),
        status: text(cells[2]),
        code: text(cells[3]),
        course: text(cells[4]),
        period: text(cells[7])
      });
    }
  }
  var groups = doc.querySelectorAll('#enqListForm ul.campussmart-list');
  for (var g = 0; g < groups.length; g += 1) {
    var kind = text(groups[g].querySelector('li.header'));
    var titles = groups[g].querySelectorAll('span.h3');
    for (var t = 0; t < titles.length; t += 1) {
      var block = titles[t].closest('td') || titles[t].parentElement;
      var all = text(block);
      var beforePeriod = all.split('実施期間')[0];
      var courses = beforePeriod.match(/\([^()]* \/ [^()]*\)/g) || [];
      var course = courses.length ? courses[courses.length - 1].slice(1, -1) :
        (beforePeriod.match(/\(([^()]*)\)\s*$/) || [])[1] || '';
      var period = (all.match(/実施期間[：:]\s*(.+?)\s*(?:状態|$)/) || [])[1] || '';
      var row = titles[t].closest('tr') || block;
      var action = row!.querySelector('[onclick*="callEnqInfoSearch"]');
      var code = (String(action && action.getAttribute('onclick') || '')
        .match(/'([0-9]{3}[A-Z][0-9]{4})'\s*\)/) || [])[1] || '';
      if (!text(titles[t]) || !period) {
        continue;
      }
      rows.push({
        kind: kind,
        title: text(titles[t]),
        status: (all.match(/状態[：:]\s*(\S+)/) || [])[1] || '',
        code: code,
        course: course.split(' / ')[0].trim(),
        period: period
      });
    }
  }
  return rows;
}
