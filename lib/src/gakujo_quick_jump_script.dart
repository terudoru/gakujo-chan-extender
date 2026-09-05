import 'dart:convert';

class GakujoQuickJumpScript {
  const GakujoQuickJumpScript._();

  static String build(String label) => '''
(function() {
  var label = ${jsonEncode(label)};
  var documents = [];
  function collect(win) {
    try {
      if (!win || !win.document || documents.indexOf(win.document) !== -1) return;
      documents.push(win.document);
      for (var i = 0; i < win.frames.length; i += 1) collect(win.frames[i]);
    } catch (e) {}
  }
  function normalized(value) { return String(value || '').replace(/\\s+/g, '').trim(); }
  label = normalized(label);
  if (!label) return false;
  collect(window);
  var matches = [];
  for (var d = 0; d < documents.length; d += 1) {
    var doc = documents[d];
    var candidates = doc.querySelectorAll(
      'a, button, input[type="button"], input[type="submit"], input[type="image"], ' +
      '[role="tab"], [role="button"], [role="menuitem"], [onclick]'
    );
    for (var i = 0; i < candidates.length; i += 1) {
      var node = candidates[i];
      if (node.disabled || node.matches(':disabled') ||
          node.closest('[aria-disabled="true"], [inert]') ||
          !node.getClientRects().length) continue;
      var style = doc.defaultView.getComputedStyle(node);
      if (style.visibility === 'hidden' || style.visibility === 'collapse') continue;
      var texts = [node.innerText || node.textContent || ''];
      ['alt', 'title', 'value', 'aria-label'].forEach(function(name) {
        texts.push(node.getAttribute(name) || '');
      });
      var images = node.querySelectorAll('img[alt]');
      for (var j = 0; j < images.length; j += 1) texts.push(images[j].getAttribute('alt'));
      var score = 2;
      for (var t = 0; t < texts.length; t += 1) {
        var text = normalized(texts[t]);
        if (text === label) { score = 0; break; }
        if (text.indexOf(label) !== -1) score = 1;
      }
      if (score < 2) matches.push({node: node, score: score, order: matches.length});
    }
  }
  matches.sort(function(a, b) { return a.score - b.score || a.order - b.order; });
  for (var m = 0; m < matches.length; m += 1) {
    try { matches[m].node.click(); return true; } catch (e) {}
  }
  return false;
})()
''';
}
