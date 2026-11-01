export {};
function courseNameTables(): string {
  function textOf(element: HTMLElement) {
    return ((element && (element.innerText || element.textContent)) || '')
      .replace(/\s+/g, ' ')
      .trim();
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
  var documents = collectDocuments();
  for (var d = 0; d < documents.length; d += 1) {
    var tables = documents[d].querySelectorAll('table');
    for (var t = 0; t < tables.length; t += 1) {
      var rows = tables[t].querySelectorAll('tr');
      for (var r = 0; r < rows.length; r += 1) {
        var cells = rows[r].querySelectorAll('th,td');
        var courseIndex = -1;
        for (var c = 0; c < cells.length; c += 1) {
          if (textOf(cells[c] as HTMLElement) === '科目名') {
            courseIndex = c;
            break;
          }
        }
        if (courseIndex < 0) {
          continue;
        }
        for (var same = courseIndex + 1; same < cells.length; same += 1) {
          var sameRowValue = textOf(cells[same] as HTMLElement);
          if (sameRowValue) {
            return sameRowValue;
          }
        }
        for (var next = r + 1; next < rows.length; next += 1) {
          var nextCells = rows[next].querySelectorAll('th,td');
          if (nextCells.length <= courseIndex) {
            continue;
          }
          var value = textOf(nextCells[courseIndex] as HTMLElement);
          if (value) {
            return value;
          }
        }
      }
    }
  }
  return '';
}

__mbgEntryResult = courseNameTables();
