export {};
function courseNameTables(): string {
  function textOf(element: HTMLElement) {
    return ((element && (element.innerText || element.textContent)) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }
  function inlineCourseName(cells: HTMLTableCellElement[]) {
    let sawValueCell = false;
    for (const cell of cells) {
      if (cell.tagName.toLowerCase() === 'th') {
        if (sawValueCell) break; // The next labelled field starts here.
        continue;
      }
      sawValueCell = true;
      const value = textOf(cell);
      if (value) return value;
    }
    return '';
  }
  function collectDocuments() {
    var documents: Document[] = [];
    function collect(win: Window) {
      try {
        if (win.document) {
          documents.push(win.document);
        }
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {}
    }
    collect(window);
    return documents;
  }
  const courseNameCandidates: string[] = [];
  for (const doc of collectDocuments()) {
    for (const table of Array.from(doc.querySelectorAll('table'))) {
      let courseColumn = -1;
      for (const row of Array.from(table.rows)) {
        const cells = Array.from(row.cells);
        const label = cells.findIndex(cell => textOf(cell) === '科目名');
        if (label >= 0) {
          const value = inlineCourseName(cells.slice(label + 1));
          if (value) courseNameCandidates.push(value);
          // With no inline value, the label identifies a column below.
          courseColumn = value ? -1 : label;
        } else if (courseColumn >= 0) {
          const cell = cells[courseColumn];
          if (!cell) continue;
          // A new header section ends the old course column. A row
          // header can itself contain the course for that data row.
          if (cell.scope === 'col' || row.parentElement?.tagName === 'THEAD' ||
              (cells.length > 1 && cells.every(value => value.tagName.toLowerCase() === 'th'))) {
            courseColumn = -1;
            continue;
          }
          const value = textOf(cell);
          if (value) courseNameCandidates.push(value);
        }
      }
    }
  }
  return JSON.stringify({courseNameCandidates});
}

__mbgEntryResult = courseNameTables();
