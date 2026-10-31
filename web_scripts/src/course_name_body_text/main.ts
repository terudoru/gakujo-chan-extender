export {};
function courseNameBodyText(): string {
  var texts: string[] = [];
  function collect(win: Window) {
    try {
      if (win.document && win.document.body) {
        texts.push(win.document.body.innerText || '');
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (e) {}
  }
  collect(window);
  return texts.join('\n\n');
}

__mbgEntryResult = courseNameBodyText();
