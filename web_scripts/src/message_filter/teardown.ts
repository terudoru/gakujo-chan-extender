export {};

function messageFilterTeardown() {
  if (window.__MBG_MESSAGE_FILTER_DISPOSE) window.__MBG_MESSAGE_FILTER_DISPOSE();
}

messageFilterTeardown();
