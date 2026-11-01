export {};

declare const __mbgConfig: { label: string };

function quickJump() {
  var label = __mbgConfig.label;
  var documents: Document[] = [];
  function collect(win: Window) {
    try {
      if (!win || !win.document || documents.indexOf(win.document) !== -1) return;
      documents.push(win.document);
      for (var i = 0; i < win.frames.length; i += 1) collect(win.frames[i]);
    } catch (e) {}
  }
  function normalized(value: unknown) {
    var text = String(value || '');
    if (typeof text.normalize === 'function') text = text.normalize('NFKC');
    return text.replace(/\s+/g, '').trim();
  }
  function isExcluded(node: Element) {
    for (var current: Element | null = node; current; current = current.parentElement) {
      var action = (current.getAttribute('href') || '') + ' ' +
        (current.getAttribute('onclick') || '');
      if (/seqNo=|_eventId=confirm|displayMidoku/i.test(action) ||
          /(^|\s)mbg-/.test((current.id || '') + ' ' +
            (current.getAttribute('class') || ''))) return true;
      var attributes = current.attributes || [];
      for (var i = 0; i < attributes.length; i += 1) {
        if (attributes[i].name.indexOf('data-mbg-') === 0) return true;
      }
    }
    return false;
  }
  function isPortalTab(node: Element) {
    for (var current: Element | null = node; current; current = current.parentElement) {
      if (current.id === 'tabmenutable' ||
          /^tab-[a-z]+$/.test(current.id || '') &&
          /(^|\s)tabcell(\s|$)/.test(current.getAttribute('class') || '')) return true;
    }
    return false;
  }
  label = normalized(label);
  if (!label) return false;
  collect(window);
  var matches = [];
  for (var d = 0; d < documents.length; d += 1) {
    var doc = documents[d];
    var candidates = doc.querySelectorAll<HTMLElement & { disabled?: boolean }>(
      'a, button, input[type="button"], input[type="submit"], input[type="image"], ' +
      '[role="tab"], [role="button"], [role="menuitem"], [onclick], div.tabcell'
    );
    for (var i = 0; i < candidates.length; i += 1) {
      var node = candidates[i];
      if (isExcluded(node) || node.disabled || node.matches(':disabled') ||
          node.closest('[aria-disabled="true"], [inert]') ||
          !node.getClientRects().length) continue;
      var style = doc.defaultView!.getComputedStyle(node);
      if (style.visibility === 'hidden' || style.visibility === 'collapse') continue;
      var texts = [node.innerText || node.textContent || ''];
      ['alt', 'title', 'value', 'aria-label'].forEach(function(name) {
        texts.push(node.getAttribute(name) || '');
      });
      var images = node.querySelectorAll('img[alt]');
      for (var j = 0; j < images.length; j += 1) texts.push(images[j].getAttribute('alt')!);
      var score = 2;
      for (var t = 0; t < texts.length; t += 1) {
        var text = normalized(texts[t]);
        if (text === label) { score = 0; break; }
        if (text.indexOf(label) !== -1) score = 1;
      }
      if (score < 2) matches.push({
        node: node, portal: isPortalTab(node) ? 0 : 1, score: score, order: matches.length
      });
    }
  }
  matches.sort(function(a, b) {
    return a.portal - b.portal || a.score - b.score || a.order - b.order;
  });
  for (var m = 0; m < matches.length; m += 1) {
    try { matches[m].node.click(); return true; } catch (e) {}
  }
  return false;
}

__mbgEntryResult = quickJump();
