// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/timeout_popup/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoTimeoutPopupJs = r'''
"use strict";
(() => {
  // web_scripts/src/timeout_popup/main.ts
  function timeoutPopup() {
    function addButton(banner, label, action) {
      var button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      button.style.cssText = "font:inherit;padding:8px 12px;min-height:44px;color:#332701;background:#fff;border:1px solid #b38b00;border-radius:4px;cursor:pointer;";
      button.addEventListener("click", action);
      banner.appendChild(button);
    }
    function showBanner(isWarning, sourceWindow) {
      var banner = document.getElementById("mbg-timeout-banner");
      if (!banner) {
        banner = document.createElement("div");
        banner.id = "mbg-timeout-banner";
        banner.setAttribute("role", "status");
        banner.style.cssText = "position:fixed;top:0;left:0;right:0;z-index:2147483647;box-sizing:border-box;padding:12px 16px;display:flex;align-items:center;flex-wrap:wrap;gap:8px 12px;font:16px/1.5 sans-serif;color:#332701;background:#fff3cd;border-bottom:1px solid #b38b00;max-height:100vh;overflow:auto;";
        (document.body || document.documentElement).appendChild(banner);
      }
      banner.textContent = "";
      var message = document.createElement("span");
      message.style.cssText = "flex:1 1 240px;min-width:0;overflow-wrap:anywhere;";
      message.textContent = isWarning ? "学務のセッションは残り約5分で切れます。" : "学務のセッションが切れました。入力中のレポートは下書きに保存されています。もう一度開くと復元されます。";
      banner.appendChild(message);
      if (isWarning) {
        addButton(banner, "延長する", function() {
          function extend(target) {
            if (target && typeof target.extendSession === "function") {
              target.extendSession();
              banner.remove();
              return true;
            }
            return false;
          }
          try {
            if (extend(sourceWindow)) return;
          } catch (e) {
          }
          try {
            if (extend(window.top)) return;
          } catch (e) {
          }
          try {
            if (extend(window.parent)) return;
          } catch (e) {
          }
          if (typeof window.extendSession === "function") {
            window.extendSession();
            banner.remove();
          }
        });
      }
      addButton(banner, "閉じる", function() {
        banner.remove();
      });
      return banner;
    }
    function wrapWindow(target) {
      try {
        if (!target || !target.document || target.__MBG_TIMEOUT_POPUP_WRAPPED) {
          return;
        }
        var originalOpen = target.open;
        target.open = function(url) {
          var candidate = String(url);
          try {
            var base = target.location.href;
            if (!/^https?:\/\//i.test(base)) base = window.location.href;
            candidate = new URL(url, base).href;
          } catch (e) {
          }
          var match = candidate.match(
            /\/theme\/default\/(TimeoutAlert|Timeout)\.html(?:[?#]|$)/
          );
          if (!match) {
            return originalOpen.apply(this, arguments);
          }
          var banner = showBanner(match[1] === "TimeoutAlert", target);
          var token = {};
          banner.__MBG_TIMEOUT_TOKEN = token;
          return {
            closed: false,
            focus: function() {
            },
            blur: function() {
            },
            close: function() {
              this.closed = true;
              if (banner.__MBG_TIMEOUT_TOKEN === token) banner.remove();
            },
            document: null,
            location: null
          };
        };
        target.__MBG_TIMEOUT_POPUP_WRAPPED = true;
      } catch (e) {
      }
    }
    wrapWindow(window);
    try {
      var frame = document.getElementById("main-frame-if");
      if (frame) {
        if (!frame.__MBG_TIMEOUT_POPUP_ATTACHED) {
          frame.addEventListener("load", function() {
            wrapWindow(frame.contentWindow);
          });
          frame.__MBG_TIMEOUT_POPUP_ATTACHED = true;
        }
        wrapWindow(frame.contentWindow);
      }
    } catch (e) {
    }
  }
  timeoutPopup();
})();
''';
