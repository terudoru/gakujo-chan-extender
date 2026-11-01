// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/pdf_preview_orientation/main.ts
// Regenerate with: npm --prefix web_scripts run build

// web_scripts/src/pdf_preview_orientation/main.ts
window.addEventListener("orientationchange", function() {
  var focused = document.activeElement;
  if (focused && typeof focused.blur === "function") focused.blur();
});
