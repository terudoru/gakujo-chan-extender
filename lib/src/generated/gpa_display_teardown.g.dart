// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/gpa_display/teardown.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoGpaDisplayTeardownJs = r'''
"use strict";
(() => {
  // web_scripts/src/gpa_display/teardown.ts
  function teardownGpaDisplay() {
    window.clearTimeout(window.__MBG_GPA_DISPLAY_TIMER);
    var startupTimers = window.__MBG_GPA_DISPLAY_STARTUP_TIMERS || [];
    for (var timerIndex = 0; timerIndex < startupTimers.length; timerIndex += 1) {
      window.clearTimeout(startupTimers[timerIndex]);
    }
    window.clearInterval(window.__MBG_GPA_DISPLAY_INTERVAL);
    var observers = window.__MBG_GPA_DISPLAY_OBSERVERS || [];
    for (var observerIndex = 0; observerIndex < observers.length; observerIndex += 1) {
      try {
        observers[observerIndex].disconnect();
      } catch (e) {
      }
    }
    var documents = [];
    function addDocument(documentRef) {
      if (documentRef && documents.indexOf(documentRef) < 0) {
        documents.push(documentRef);
      }
    }
    var observedDocuments = window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS || [];
    for (var documentIndex = 0; documentIndex < observedDocuments.length; documentIndex += 1) {
      addDocument(observedDocuments[documentIndex]);
    }
    function collectDocuments(win) {
      try {
        addDocument(win.document);
        for (var frameIndex = 0; frameIndex < win.frames.length; frameIndex += 1) {
          collectDocuments(win.frames[frameIndex]);
        }
      } catch (e) {
      }
    }
    collectDocuments(window);
    try {
      var mainFrame = window.document.getElementById("main-frame-if");
      if (mainFrame && mainFrame.contentWindow) {
        addDocument(mainFrame.contentWindow.document);
      }
    } catch (e) {
    }
    var controlIds = [
      "mbg-grade-no-button",
      "mbg-grade-open-number-button",
      "mbg-grade-score-button"
    ];
    for (var i = 0; i < documents.length; i += 1) {
      try {
        var ownedElements = documents[i].querySelectorAll(
          '[data-mbg-gpa-display-owned="true"]'
        );
        for (var ownedIndex = 0; ownedIndex < ownedElements.length; ownedIndex += 1) {
          ownedElements[ownedIndex].remove();
        }
        var legacyDisplays = documents[i].querySelectorAll(".mbg-gpa-display");
        for (var displayIndex = 0; displayIndex < legacyDisplays.length; displayIndex += 1) {
          legacyDisplays[displayIndex].remove();
        }
        for (var controlIndex = 0; controlIndex < controlIds.length; controlIndex += 1) {
          var legacyControl = documents[i].getElementById(
            controlIds[controlIndex]
          );
          if (legacyControl) {
            legacyControl.remove();
          }
        }
      } catch (e) {
      }
    }
    delete window.__MBG_GPA_DISPLAY_TIMER;
    delete window.__MBG_GPA_DISPLAY_STARTUP_TIMERS;
    delete window.__MBG_GPA_DISPLAY_INTERVAL;
    delete window.__MBG_GPA_DISPLAY_OBSERVERS;
    delete window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS;
    delete window.__MBG_UPDATE_GPA_DISPLAY;
    delete window.__MBG_GPA_DISPLAY_VERSION;
    delete window.__MBG_GPA_LAST_REPORTED;
  }
  teardownGpaDisplay();
})();
''';
