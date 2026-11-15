// Run under xvfb-run: this tests GTK dispatch on a real WebKitWebView.
#include <webkit2/webkit2.h>

#include <vector>

#include "../src/webview/webview_pinch_zoom.h"
#include "javascript_test_helpers.h"

static void received(const PinchZoomInput &input, gpointer user_data) {
  static_cast<std::vector<PinchZoomInput> *>(user_data)->push_back(input);
}

static gboolean later_event_cb(GtkWidget *, GdkEvent *, gpointer user_data) {
  ++*static_cast<guint *>(user_data);
  return TRUE;
}

static void widget_dispatch_test() {
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  WebKitWebView *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_window_set_default_size(GTK_WINDOW(window), 800, 600);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  std::vector<PinchZoomInput> inputs;
  guint later_events = 0;
  // The plugin connects this same handler, supplying its event-channel sender.
  g_signal_connect(view, "event", G_CALLBACK(pinch_zoom_event_cb<received>),
                   &inputs);
  gtk_widget_show_all(window);
  webview_test::load_html(view, "<body>Pinch target</body>",
                         "http://sender.example/pinch");
  // Observe only the synthetic input, after startup focus/configure events.
  g_signal_connect(view, "event", G_CALLBACK(later_event_cb), &later_events);

  GdkWindow *gdk_window = gtk_widget_get_window(GTK_WIDGET(view));
  g_assert_nonnull(gdk_window);
  GdkSeat *seat = gdk_display_get_default_seat(gtk_widget_get_display(
      GTK_WIDGET(view)));
  g_assert_nonnull(seat);
  GdkDevice *pointer = gdk_seat_get_pointer(seat);
  g_assert_nonnull(pointer);
  const struct {
    GdkTouchpadGesturePhase phase;
    const gchar *expected;
    gdouble scale;
    gdouble x;
    gdouble y;
  } cases[] = {
      {GDK_TOUCHPAD_GESTURE_PHASE_BEGIN, "begin", 1, 120, 45.5},
      {GDK_TOUCHPAD_GESTURE_PHASE_UPDATE, "update", 1.25, 121.5, 46},
      // Scale remains relative to BEGIN, not the previous UPDATE.
      {GDK_TOUCHPAD_GESTURE_PHASE_UPDATE, "update", 1.5, 123, 48.25},
      {GDK_TOUCHPAD_GESTURE_PHASE_END, "end", 1.5, 123, 48.25},
      {GDK_TOUCHPAD_GESTURE_PHASE_BEGIN, "begin", 1, 50, 60},
      {GDK_TOUCHPAD_GESTURE_PHASE_UPDATE, "update", 0.75, 51, 61},
      {GDK_TOUCHPAD_GESTURE_PHASE_CANCEL, "end", 0.75, 51, 61},
  };
  for (const auto &test : cases) {
    GdkEvent *event = gdk_event_new(GDK_TOUCHPAD_PINCH);
    event->touchpad_pinch.window = GDK_WINDOW(g_object_ref(gdk_window));
    event->touchpad_pinch.send_event = TRUE;
    event->touchpad_pinch.phase = test.phase;
    event->touchpad_pinch.n_fingers = 2;
    event->touchpad_pinch.time = GDK_CURRENT_TIME;
    event->touchpad_pinch.scale = test.scale;
    event->touchpad_pinch.x = test.x;
    event->touchpad_pinch.y = test.y;
    gdk_event_set_device(event, pointer);
    const auto previous_count = inputs.size();
    g_assert_true(gtk_widget_event(GTK_WIDGET(view), event));
    g_assert_cmpuint(inputs.size(), ==, previous_count + 1);
    const PinchZoomInput &input = inputs.back();
    g_assert_cmpstr(input.phase, ==, test.expected);
    g_assert_cmpfloat(input.scale, ==, test.scale);
    g_assert_cmpfloat(input.x, ==, test.x);
    g_assert_cmpfloat(input.y, ==, test.y);
    // TRUE must stop emission before subsequent handlers and WebKit defaults.
    g_assert_cmpuint(later_events, ==, 0);
    gdk_event_free(event);
  }

  // A smooth scroll still reaches the next handler without becoming a pinch.
  GdkEvent *scroll = gdk_event_new(GDK_SCROLL);
  scroll->scroll.window = GDK_WINDOW(g_object_ref(gdk_window));
  scroll->scroll.direction = GDK_SCROLL_SMOOTH;
  scroll->scroll.delta_x = 0.75;
  gdk_event_set_device(scroll, pointer);
  const auto previous_count = inputs.size();
  g_assert_true(gtk_widget_event(GTK_WIDGET(view), scroll));
  g_assert_cmpuint(inputs.size(), ==, previous_count);
  g_assert_cmpuint(later_events, ==, 1);
  gdk_event_free(scroll);
  gtk_widget_destroy(window);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/pinch/widget-dispatch", widget_dispatch_test);
  return g_test_run();
}
