#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_HISTORY_NAVIGATION_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_HISTORY_NAVIGATION_H_

#include <gdk/gdk.h>
#include <gdk/gdkkeysyms.h>

// More Better Gakujo patch: share input filtering with the native unit test.
inline const gchar *history_navigation_direction(const GdkEventButton *event) {
  if (event->type != GDK_BUTTON_PRESS) {
    return nullptr;
  }
  switch (event->button) {
  case 8:
    return "back";
  case 9:
    return "forward";
  default:
    return nullptr;
  }
}

inline const gchar *history_navigation_direction(const GdkEventKey *event) {
  switch (event->keyval) {
  case GDK_KEY_Back:
    return "back";
  case GDK_KEY_Forward:
    return "forward";
  default:
    break;
  }
  if ((event->state & GDK_MOD1_MASK) != 0 &&
      (event->state & (GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_SUPER_MASK)) == 0) {
    if (event->keyval == GDK_KEY_Left) {
      return "back";
    }
    if (event->keyval == GDK_KEY_Right) {
      return "forward";
    }
  }
  return nullptr;
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_HISTORY_NAVIGATION_H_
