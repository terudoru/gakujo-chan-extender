export function textOf(node: HTMLElement & { value?: string }) {
  if (!node) {
    return '';
  }
  return [
    node.innerText || node.textContent || '',
    node.value || '',
    node.getAttribute && node.getAttribute('title') || '',
    node.getAttribute && node.getAttribute('onclick') || '',
    node.getAttribute && node.getAttribute('href') || ''
  ].join(' ').replace(/\s+/g, ' ').trim();
}

export function monthInDocument(doc: Document) {
  const text = textOf((doc.body || doc) as HTMLElement);
  const match = text.match(/(20[0-9]{2})\s*年\s*([0-9]{1,2})\s*月/);
  return match ? { year: Number(match[1]), month: Number(match[2]) } : null;
}

export function calendarControls(doc: Document): HTMLElement[] {
  return Array.prototype.slice.call(doc.querySelectorAll('a,button,input,[onclick]'));
}

export function findInCalendarFrames<T>(
  win: Window,
  inspect: (doc: Document) => T | null,
): T | null {
  try {
    if (!win || !win.document) {
      return null;
    }
    const result = inspect(win.document);
    if (result) {
      return result;
    }
    for (let i = 0; i < win.frames.length; i += 1) {
      const found = findInCalendarFrames(win.frames[i], inspect);
      if (found) {
        return found;
      }
    }
  } catch (e) {
    // An inaccessible frame cannot prevent its siblings from being inspected.
  }
  return null;
}
