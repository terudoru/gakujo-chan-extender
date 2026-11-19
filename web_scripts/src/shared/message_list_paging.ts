import { messageOnclickUrl } from './smartphone_message_rows.js';

export function messageListFlowKey(doc: Document, base: string) {
  var link = doc.querySelector('a[href*="_flowExecutionKey="]');
  if (link) {
    var value = new URL(link.getAttribute('href')!, base).searchParams.get('_flowExecutionKey');
    if (value) return value;
  }
  var input = doc.querySelector<HTMLInputElement>('input[name="_flowExecutionKey"]');
  if (input && input.value) return input.value;
  var actions = doc.querySelectorAll('[onclick*="_flowExecutionKey="]');
  for (var i = 0; i < actions.length; i += 1) {
    var href = messageOnclickUrl(actions[i]);
    if (!href) continue;
    var value = new URL(href, base).searchParams.get('_flowExecutionKey');
    if (value) return value;
  }
  return '';
}

/** An empty string means no next control. Null means it cannot be followed safely. */
export function nextMessageListPage(doc: Document, base: string): string | null {
  var controls = doc.querySelectorAll<HTMLInputElement>('a,button,input[type="button"],input[type="submit"]');
  var hasNextControl = false;
  for (var i = 0; i < controls.length; i += 1) {
    var control = controls[i];
    var label = String(control.textContent || control.value || '') + ' ' +
      (control.getAttribute('aria-label') || control.getAttribute('title') || '');
    if ((!/次へ|次のページ|次ページ|next/i.test(label) &&
        control.getAttribute('rel') !== 'next') || control.disabled ||
        control.getAttribute('aria-disabled') === 'true') continue;
    hasNextControl = true;
    var href = control.getAttribute('href') || '';
    if (!href || /^(?:javascript:|#)/i.test(href)) {
      href = messageOnclickUrl(control) ||
        ((control.getAttribute('onclick') || href).match(
          /['"]([^'"]*[?&](?:_eventId=paging|_displayOffset=)[^'"]*)['"]/)
          || [])[1];
    }
    if (!href) continue;
    var target = new URL(href.replace(/&amp;/g, '&'), base + 'campussquare.do');
    if (target.origin !== new URL(base).origin ||
        target.pathname !== '/campusweb/campussquare.do' ||
        (target.searchParams.get('_eventId') !== 'paging' &&
         !target.searchParams.has('_displayOffset'))) continue;
    const flowKey = messageListFlowKey(doc, base);
    if (!flowKey || target.searchParams.has('seqNo') ||
        target.username || target.password) continue;
    target.searchParams.set('_flowExecutionKey', flowKey);
    target.searchParams.set('_eventId', 'paging');
    return target.href;
  }
  return hasNextControl ? null : '';
}

/** Offer only display counts advertised by the list's own control. */
export function largerMessageListPage(doc: Document, base: string) {
  const control = doc.querySelector<HTMLSelectElement>('select[name="_displayCount"]');
  if (!control || control.disabled) return null;
  const sizes = Array.from(control.options, option => Number(option.value))
    .filter(size => Number.isInteger(size) && size > 0 && size <= 500);
  const largest = Math.max(...sizes);
  if (!Number.isFinite(largest) || !(largest > Number(control.value))) return null;
  const flowKey = messageListFlowKey(doc, base);
  if (!flowKey) return null;
  const url = new URL('campussquare.do', base);
  url.searchParams.set('_flowExecutionKey', flowKey);
  url.searchParams.set('_eventId', 'paging');
  url.searchParams.set('_displayCount', String(largest));
  url.searchParams.set('_displayOffset', '0');
  return {url: url.href, count: largest};
}
