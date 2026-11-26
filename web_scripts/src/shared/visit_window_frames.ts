export function visitWindowFrames(win: Window, visit: (win: Window) => void | false) {
  try {
    if (visit(win) === false) return;
    for (var i = 0; i < win.frames.length; i += 1) {
      visitWindowFrames(win.frames[i], visit);
    }
  } catch (_) {
    // Stop this branch and let its parent continue iterating.
  }
}
