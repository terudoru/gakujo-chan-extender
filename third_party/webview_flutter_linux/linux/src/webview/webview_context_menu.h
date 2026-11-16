#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_CONTEXT_MENU_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_CONTEXT_MENU_H_

#include <webkit2/webkit2.h>

// More Better Gakujo patch: downloads must go through the app's handling.
inline void remove_unmanaged_download_items(WebKitContextMenu *menu) {
  bool previous_is_separator = true;
  for (GList *link = webkit_context_menu_get_items(menu); link != nullptr;) {
    auto *item = WEBKIT_CONTEXT_MENU_ITEM(link->data);
    // Removing an item also frees its list node.
    link = link->next;
    switch (webkit_context_menu_item_get_stock_action(item)) {
    case WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_LINK_TO_DISK:
    case WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_IMAGE_TO_DISK:
    case WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_VIDEO_TO_DISK:
    case WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_AUDIO_TO_DISK:
      webkit_context_menu_remove(menu, item);
      continue;
    default:
      break;
    }

    const bool is_separator = webkit_context_menu_item_is_separator(item);
    if (is_separator && previous_is_separator) {
      webkit_context_menu_remove(menu, item);
      continue;
    }
    previous_is_separator = is_separator;
  }

  WebKitContextMenuItem *last = webkit_context_menu_last(menu);
  if (last != nullptr && webkit_context_menu_item_is_separator(last)) {
    webkit_context_menu_remove(menu, last);
  }
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_CONTEXT_MENU_H_
