#include "../src/webview/webview_pinch_zoom.h"

static void count_received(const PinchZoomInput &, gpointer user_data) {
  ++*static_cast<guint *>(user_data);
}

static void phases_test() {
  const struct {
    GdkTouchpadGesturePhase phase;
    const gchar *expected;
    gdouble scale;
  } cases[] = {
      {GDK_TOUCHPAD_GESTURE_PHASE_BEGIN, "begin", 1},
      {GDK_TOUCHPAD_GESTURE_PHASE_UPDATE, "update", 1.25},
      {GDK_TOUCHPAD_GESTURE_PHASE_END, "end", 1.5},
      {GDK_TOUCHPAD_GESTURE_PHASE_CANCEL, "end", 0.75},
  };
  for (const auto &test : cases) {
    GdkEvent event = {};
    event.touchpad_pinch.type = GDK_TOUCHPAD_PINCH;
    event.touchpad_pinch.phase = test.phase;
    event.touchpad_pinch.scale = test.scale;
    event.touchpad_pinch.x = 120.5;
    event.touchpad_pinch.y = 45.25;
    // Translation and rotation do not become pan/history input.
    event.touchpad_pinch.dx = 12;
    event.touchpad_pinch.dy = -34;
    event.touchpad_pinch.angle_delta = 0.25;
    const PinchZoomInput input = pinch_zoom_input(&event);
    g_assert_cmpstr(input.phase, ==, test.expected);
    g_assert_cmpfloat(input.scale, ==, test.scale);
    g_assert_cmpfloat(input.x, ==, 120.5);
    g_assert_cmpfloat(input.y, ==, 45.25);
  }
}

static void other_events_test() {
  guint received = 0;
  for (int type = GDK_NOTHING; type < GDK_EVENT_LAST; ++type) {
    if (type == GDK_TOUCHPAD_PINCH) {
      continue;
    }
    GdkEvent event = {};
    event.type = static_cast<GdkEventType>(type);
    g_assert_null(pinch_zoom_input(&event).phase);
    g_assert_false(pinch_zoom_event_cb<count_received>(nullptr, &event,
                                                       &received));
  }
  g_assert_cmpuint(received, ==, 0);
  GdkEvent event = {};
  event.touchpad_pinch.type = GDK_TOUCHPAD_PINCH;
  event.touchpad_pinch.phase = -1;
  g_assert_null(pinch_zoom_input(&event).phase);
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/pinch/phases", phases_test);
  g_test_add_func("/pinch/other-events", other_events_test);
  return g_test_run();
}
