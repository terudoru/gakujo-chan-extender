#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_PINCH_ZOOM_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_PINCH_ZOOM_H_

#include <gtk/gtk.h>

struct PinchZoomInput {
  const gchar *phase = nullptr;
  gdouble scale = 1;
  gdouble x = 0;
  gdouble y = 0;
};

// More Better Gakujo patch: keep WebKit pinch input in the app's zoom state.
inline PinchZoomInput pinch_zoom_input(const GdkEvent *event) {
  PinchZoomInput input;
  if (event->type != GDK_TOUCHPAD_PINCH) {
    return input;
  }
  const GdkEventTouchpadPinch &pinch = event->touchpad_pinch;
  switch (pinch.phase) {
  case GDK_TOUCHPAD_GESTURE_PHASE_BEGIN:
    input.phase = "begin";
    break;
  case GDK_TOUCHPAD_GESTURE_PHASE_UPDATE:
    input.phase = "update";
    break;
  case GDK_TOUCHPAD_GESTURE_PHASE_END:
  case GDK_TOUCHPAD_GESTURE_PHASE_CANCEL:
    input.phase = "end";
    break;
  default:
    return input;
  }
  input.scale = pinch.scale;
  input.x = pinch.x;
  input.y = pinch.y;
  return input;
}

// Connect to ::event, before WebKit's default handlers and gesture controllers.
// The callback is supplied by the plugin or the native GTK dispatch test.
template <void (*SendInput)(const PinchZoomInput &, gpointer)>
inline gboolean pinch_zoom_event_cb(GtkWidget *, GdkEvent *event,
                                    gpointer user_data) {
  if (event->type != GDK_TOUCHPAD_PINCH) {
    return FALSE;
  }
  const PinchZoomInput input = pinch_zoom_input(event);
  if (input.phase != nullptr) {
    SendInput(input, user_data);
  }
  // Consume every pinch phase so WebKit cannot apply its own page scale.
  return TRUE;
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_PINCH_ZOOM_H_
