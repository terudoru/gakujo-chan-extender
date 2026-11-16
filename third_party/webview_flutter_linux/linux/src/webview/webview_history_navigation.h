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

enum class BrowserKeyAction {
  kNone,
  kReload,
  kReloadBypassCache,
  kPrint,
  kFind,
  kFindNext,
  kFindPrevious,
  kZoomIn,
  kZoomOut,
  kZoomReset,
};

inline BrowserKeyAction browser_key_action(const GdkEventKey *event) {
  const guint modifiers = event->state &
      (GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_MOD1_MASK | GDK_SUPER_MASK);
  // Ignore Caps Lock and Num Lock, but no other modifiers for find shortcuts.
  const guint find_modifiers = event->state &
      (GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_MOD1_MASK | GDK_MOD3_MASK |
       GDK_MOD4_MASK | GDK_MOD5_MASK | GDK_SUPER_MASK | GDK_HYPER_MASK |
       GDK_META_MASK);
  const bool zoom_shortcut = (event->state & GDK_CONTROL_MASK) != 0 &&
      (event->state & (GDK_MOD1_MASK | GDK_SUPER_MASK | GDK_META_MASK |
                       GDK_HYPER_MASK)) == 0;
  switch (event->keyval) {
  case GDK_KEY_equal:
  case GDK_KEY_plus:
  case GDK_KEY_KP_Add:
    if (zoom_shortcut) {
      return BrowserKeyAction::kZoomIn;
    }
    break;
  case GDK_KEY_minus:
  case GDK_KEY_KP_Subtract:
    if (zoom_shortcut) {
      return BrowserKeyAction::kZoomOut;
    }
    break;
  case GDK_KEY_0:
  case GDK_KEY_KP_0:
    if (zoom_shortcut) {
      return BrowserKeyAction::kZoomReset;
    }
    break;
  case GDK_KEY_f:
  case GDK_KEY_F:
    if (find_modifiers == GDK_CONTROL_MASK) {
      return BrowserKeyAction::kFind;
    }
    break;
  case GDK_KEY_g:
  case GDK_KEY_G:
    if (find_modifiers == GDK_CONTROL_MASK) {
      return BrowserKeyAction::kFindNext;
    }
    if (find_modifiers == (GDK_CONTROL_MASK | GDK_SHIFT_MASK)) {
      return BrowserKeyAction::kFindPrevious;
    }
    break;
  case GDK_KEY_F3:
    if (find_modifiers == 0) {
      return BrowserKeyAction::kFindNext;
    }
    if (find_modifiers == GDK_SHIFT_MASK) {
      return BrowserKeyAction::kFindPrevious;
    }
    break;
  case GDK_KEY_F5:
    if (modifiers == 0) {
      return BrowserKeyAction::kReload;
    }
    if (modifiers == GDK_SHIFT_MASK) {
      return BrowserKeyAction::kReloadBypassCache;
    }
    break;
  case GDK_KEY_r:
  case GDK_KEY_R:
    if (modifiers == GDK_CONTROL_MASK) {
      return BrowserKeyAction::kReload;
    }
    if (modifiers == (GDK_CONTROL_MASK | GDK_SHIFT_MASK)) {
      return BrowserKeyAction::kReloadBypassCache;
    }
    break;
  case GDK_KEY_p:
  case GDK_KEY_P:
    if (modifiers == GDK_CONTROL_MASK) {
      return BrowserKeyAction::kPrint;
    }
    break;
  default:
    break;
  }
  return BrowserKeyAction::kNone;
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_HISTORY_NAVIGATION_H_
