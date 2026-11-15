#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_WHEEL_SCROLL_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_WHEEL_SCROLL_H_

#include <gdk/gdk.h>

enum class WheelScrollAction { kNone, kZoom, kScroll };

struct WheelScrollInput {
  gdouble dx = 0;
  gdouble dy = 0;
  WheelScrollAction action = WheelScrollAction::kNone;
};

// More Better Gakujo patch: normalize native wheel input for the app.
inline WheelScrollInput wheel_scroll_input(const GdkEventScroll *event) {
  WheelScrollInput input;
  switch (event->direction) {
  case GDK_SCROLL_SMOOTH:
    gdk_event_get_scroll_deltas(reinterpret_cast<const GdkEvent *>(event),
                                &input.dx, &input.dy);
    break;
  case GDK_SCROLL_UP:
    input.dy = -1;
    break;
  case GDK_SCROLL_DOWN:
    input.dy = 1;
    break;
  case GDK_SCROLL_LEFT:
    input.dx = -1;
    break;
  case GDK_SCROLL_RIGHT:
    input.dx = 1;
    break;
  }
  // Includes smooth scroll stop events with no remaining delta.
  if (input.dx == 0 && input.dy == 0) {
    return input;
  }
  const guint modifiers = event->state &
      (GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_MOD1_MASK | GDK_SUPER_MASK);
  if (modifiers == GDK_CONTROL_MASK) {
    input.action = WheelScrollAction::kZoom;
  } else if (modifiers == 0 && input.dx != 0) {
    input.action = WheelScrollAction::kScroll;
  }
  return input;
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_WHEEL_SCROLL_H_
