/// Shared smartphone row extraction for fetches, page scans and stars.
export function messageOnclickUrl(node: Element | null) {
  var match = String(node && node.getAttribute('onclick') || '')
    .match(/\blocation\.href\s*=\s*(['"])(.*?)\1/);
  return match ? match[2].replace(/&amp;/g, '&') : '';
}
export function readSmartphoneMessageRow(button: Element, base: string) {
  function text(node: Element | null) {
    return String(node && ((node as HTMLElement).innerText || node.textContent) || '')
      .replace(/\s+/g, ' ').trim();
  }
  var heading = button.querySelector('p');
  var href = messageOnclickUrl(button);
  if (!heading || !text(heading) || !href) return null;
  var row = button.closest('tr');
  var table = button.closest('table.bgnone');
  var dateCell = row && row.cells && row.cells[0];
  var dateRows = dateCell ? dateCell.querySelectorAll('tr') : [];
  var month = text(dateRows[0]).match(/([0-9]{4})\s*\/\s*([0-9]{1,2})/);
  var day = text(dateCell && dateCell.querySelector('b')).match(/^[0-9]{1,2}$/);
  var time = text(dateRows[1]).match(/[0-9]{1,2}:[0-9]{2}:[0-9]{2}/);
  var postedAt = month && day && time ? month[1] + '/' +
    month[2].padStart(2, '0') + '/' + day[0].padStart(2, '0') + ' ' + time[0] : '';
  var genre = text(table && table.querySelector('td.category-frame'));
  var sender = '';
  // Read only the text after the title and before the first line break.
  for (var node = heading.nextSibling; node; node = node.nextSibling) {
    if (node.nodeName === 'BR') break;
    sender += node.textContent || '';
  }
  sender = sender.replace(/\s+/g, ' ').trim();
  var period = (text(button).match(/掲示期間[：:]\s*(.*)/) || [])[1] || '';
  period = period.replace(/\s*[～〜~]\s*/, 'から ') + (period ? 'まで' : '');
  var label = text(heading);
  return {
    title: label,
    url: new URL(href, base).href,
    text: [postedAt, label, '-', genre, sender, period].filter(Boolean).join(' '),
    genre: genre, sender: sender, period: period, postedAt: postedAt
  };
}
