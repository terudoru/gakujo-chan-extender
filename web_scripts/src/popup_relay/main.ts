export {};
function popupRelay() {
if (window.opener && window.parent === window) {
  window.addEventListener('message', function(event) {
    if (event.source === window.opener && event.data instanceof ArrayBuffer) {
      window.postMessage(event.data, '*', [event.data]);
    } else if (event.source === window && typeof event.data === 'string' &&
               event.data.indexOf('mbg-preview-') === 0) {
      window.opener.postMessage(event.data, '*');
    }
  });
}
}

popupRelay();
