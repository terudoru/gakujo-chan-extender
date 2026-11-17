#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_FIND_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_FIND_H_

#include <webkit2/webkit2.h>

inline void recount_find_matches(WebKitFindController *controller,
                                  const gchar *text) {
  if (text == nullptr || *text == '\0') return;
  // found-text may report just the selected match after search_next/previous.
  webkit_find_controller_count_matches(
      controller, text, webkit_find_controller_get_options(controller), G_MAXUINT);
}

#endif // WEBVIEW_ALL_LINUX_WEBVIEW_FIND_H_
