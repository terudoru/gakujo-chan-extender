#include "../src/webview/webview_wheel_scroll.h"

static void smooth_scroll_test() {
  GdkEventScroll event = {};
  event.type = GDK_SCROLL;
  event.direction = GDK_SCROLL_SMOOTH;
  event.delta_x = -0.75;
  event.delta_y = 0.25;
  WheelScrollInput input = wheel_scroll_input(&event);
  g_assert_cmpfloat(input.dx, ==, -0.75);
  g_assert_cmpfloat(input.dy, ==, 0.25);
  g_assert_true(input.action == WheelScrollAction::kScroll);

  event.state = GDK_CONTROL_MASK;
  event.delta_x = 0.125;
  event.delta_y = -1.5;
  input = wheel_scroll_input(&event);
  g_assert_cmpfloat(input.dx, ==, 0.125);
  g_assert_cmpfloat(input.dy, ==, -1.5);
  g_assert_true(input.action == WheelScrollAction::kZoom);
}

static void discrete_scroll_test() {
  GdkEventScroll event = {};
  event.type = GDK_SCROLL;
  const struct {
    GdkScrollDirection direction;
    gdouble dx;
    gdouble dy;
    WheelScrollAction action;
  } cases[] = {
      {GDK_SCROLL_UP, 0, -1, WheelScrollAction::kNone},
      {GDK_SCROLL_DOWN, 0, 1, WheelScrollAction::kNone},
      {GDK_SCROLL_LEFT, -1, 0, WheelScrollAction::kScroll},
      {GDK_SCROLL_RIGHT, 1, 0, WheelScrollAction::kScroll},
  };
  for (const auto &test : cases) {
    event.direction = test.direction;
    // Discrete directions ignore any smooth delta fields.
    event.delta_x = 12;
    event.delta_y = 34;
    event.state = 0;
    WheelScrollInput input = wheel_scroll_input(&event);
    g_assert_cmpfloat(input.dx, ==, test.dx);
    g_assert_cmpfloat(input.dy, ==, test.dy);
    g_assert_true(input.action == test.action);
    event.state = GDK_CONTROL_MASK;
    input = wheel_scroll_input(&event);
    g_assert_cmpfloat(input.dx, ==, test.dx);
    g_assert_cmpfloat(input.dy, ==, test.dy);
    g_assert_true(input.action == WheelScrollAction::kZoom);
  }
}

static void modifiers_test() {
  GdkEventScroll event = {};
  event.type = GDK_SCROLL;
  event.direction = GDK_SCROLL_SMOOTH;
  event.delta_x = 0.5;
  event.delta_y = 0.25;
  const guint locks[] = {0, GDK_LOCK_MASK, GDK_MOD2_MASK,
                         GDK_LOCK_MASK | GDK_MOD2_MASK};
  const guint other_modifiers[] = {GDK_SHIFT_MASK, GDK_MOD1_MASK,
                                   GDK_SUPER_MASK};
  for (guint lock : locks) {
    event.state = lock;
    g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kScroll);
    event.state |= GDK_CONTROL_MASK;
    g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kZoom);
    for (guint modifier : other_modifiers) {
      event.state = lock | modifier;
      g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kNone);
      event.state |= GDK_CONTROL_MASK;
      g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kNone);
    }
  }
}

static void vertical_and_stop_test() {
  GdkEventScroll event = {};
  event.type = GDK_SCROLL;
  event.direction = GDK_SCROLL_SMOOTH;
  event.delta_y = 0.5;
  g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kNone);
  event.state = GDK_CONTROL_MASK;
  g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kZoom);

  event.delta_y = 0;
  // Ignore zero deltas both during scrolling and at the end of a gesture.
  for (guint stop = 0; stop <= 1; stop++) {
    event.is_stop = stop;
    event.state = 0;
    g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kNone);
    event.state = GDK_CONTROL_MASK;
    g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kNone);
  }
  event.delta_x = 0.25;
  event.state = 0;
  g_assert_true(wheel_scroll_input(&event).action == WheelScrollAction::kScroll);
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/wheel/smooth", smooth_scroll_test);
  g_test_add_func("/wheel/discrete", discrete_scroll_test);
  g_test_add_func("/wheel/modifiers", modifiers_test);
  g_test_add_func("/wheel/vertical-and-stop", vertical_and_stop_test);
  return g_test_run();
}
