import { readAssignmentRows } from '../shared/assignment_rows.js';

function assignmentListFetch() {

  try {
    var base = location.origin + '/campusweb/campussquare.do';
    var url = '/campusweb/campussquare.do?_flowId=ENW3411100-flow';
    var rows: ReturnType<typeof readAssignmentRows> = [];
    var seenRows = new Set();
    var visited = new Set();
    var total = -1;
    var complete = false;
    var expanded = false;
    for (var page = 0; page < 10 && url && !visited.has(url); page += 1) {
      visited.add(url);
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, false);
      xhr.send(null);
      if (xhr.status < 200 || xhr.status >= 400) {
        if (!page) return JSON.stringify({status: 'error', rows: []});
        break;
      }
      var doc = new DOMParser().parseFromString(xhr.responseText, 'text/html');
      var form = doc.querySelector('#enqListForm');
      if (!form) {
        if (!page) return JSON.stringify({status: 'missing', rows: []});
        break;
      }
      // The list states its total as 「11件」 or 「1～11/11件」.
      var content = String(form.textContent || '');
      var counts = content.match(/([0-9]+)件/g) || [];
      total = counts.length ? parseInt(counts[0]!, 10) : -1;
      var pageRows = readAssignmentRows(doc);
      var previousLength = rows.length;
      pageRows.forEach(function(row) {
        var key = JSON.stringify(row);
        if (!seenRows.has(key)) {
          seenRows.add(key);
          rows.push(row);
        }
      });
      if (total >= 0 && rows.length === total) {
        complete = true;
        break;
      }
      if (page && rows.length === previousLength) break;
      var next = '';
      var controls = form.querySelectorAll<HTMLInputElement>('a, button, input[type="submit"]');
      for (var c = 0; c < controls.length; c += 1) {
        var control = controls[c];
        var label = String(control.textContent || control.value || '');
        if (!/次へ/.test(label) || control.disabled ||
            control.getAttribute('aria-disabled') === 'true') continue;
        var href = control.getAttribute('href') || '';
        var onclick = control.getAttribute('onclick') || '';
        var target: string & URL = ((onclick || href).match(/['"]([^'"]*[?&]_eventId=[^'"]+)['"]/) || [])[1] as string & URL;
        if (!target && href && !/^(?:javascript:|#)/i.test(href)) target = href as string & URL;
        if (target) {
          var candidate = new URL(target.replace(/&amp;/g, '&'), base);
          if (candidate.origin === location.origin &&
              candidate.pathname === '/campusweb/campussquare.do') {
            next = candidate.href;
            break;
          }
        }
      }
      var displayCount = form.querySelector<HTMLSelectElement & HTMLInputElement>('select[name="_displayCount"], input[name="_displayCount"]');
      var paging = /次へ|前へ/.test(content) ||
        form.querySelector('[onclick*="paging"], [href*="paging"]') || displayCount;
      if (!next && !expanded && displayCount) {
        var target: string & URL = new URL(form.getAttribute('action') || url, base) as unknown as string & URL;
        var hidden = form.querySelectorAll<HTMLInputElement>('input[type="hidden"]');
        for (var h = 0; h < hidden.length; h += 1) {
          if (hidden[h].name) target.searchParams.set(hidden[h].name, hidden[h].value);
        }
        var sizes = Array.from(displayCount.options || [])
          .map(function(option) { return parseInt(option.value, 10); })
          .filter(function(size) { return size > pageRows.length && size <= 500; });
        var size = displayCount.options ? Math.max.apply(null, sizes) : 500;
        if (target.searchParams.has('_flowExecutionKey') && size > pageRows.length &&
            target.origin === location.origin &&
            target.pathname === '/campusweb/campussquare.do') {
          target.searchParams.set('_eventId', 'paging');
          target.searchParams.set('_displayCount', String(size));
          next = target.href;
          expanded = true;
        }
      }
      // Without a count, only a smartphone list without paging is complete.
      if (total < 0 && !next && !paging && form.querySelector('ul.campussmart-list')) {
        total = rows.length;
        complete = true;
      }
      url = next;
    }
    return JSON.stringify({
      status: 'ok',
      total: complete ? total : -1,
      rows: rows
    });
  } catch (e) {
    return JSON.stringify({status: 'error', rows: []});
  }
}
__mbgEntryResult = assignmentListFetch();
