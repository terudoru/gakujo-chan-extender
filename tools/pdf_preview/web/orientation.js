// Android can repeatedly resize a focused embedded viewer when the device is
// rotated with its keyboard open. Keep the search text, but dismiss the input
// until the user chooses to edit it again in the new orientation.
window.addEventListener('orientationchange', function () {
  var focused = document.activeElement;
  if (focused && typeof focused.blur === 'function') focused.blur();
});
