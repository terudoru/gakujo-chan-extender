import { visitWindowFrames } from '../shared/visit_window_frames.js';
function courseNameBodyText(): string {
  var texts: string[] = [];
  visitWindowFrames(window, function(win) {
    if (win.document && win.document.body) {
      texts.push(win.document.body.innerText || '');
    }
  });
  return texts.join('\n\n');
}

__mbgEntryResult = courseNameBodyText();
