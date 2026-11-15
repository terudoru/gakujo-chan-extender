#include "../src/webview/webview_history_navigation.h"

#include <initializer_list>

static void mouse_buttons_test() {
  GdkEventButton event = {};
  event.type = GDK_BUTTON_PRESS;
  event.button = 8;
  g_assert_cmpstr(history_navigation_direction(&event), ==, "back");
  event.button = 9;
  g_assert_cmpstr(history_navigation_direction(&event), ==, "forward");
  for (guint button : {1u, 2u, 3u, 4u, 5u, 6u, 7u, 10u}) {
    event.button = button;
    g_assert_null(history_navigation_direction(&event));
  }
  for (GdkEventType type : {GDK_2BUTTON_PRESS, GDK_3BUTTON_PRESS,
                            GDK_BUTTON_RELEASE}) {
    event.type = type;
    for (guint button : {8u, 9u}) {
      event.button = button;
      g_assert_null(history_navigation_direction(&event));
    }
  }
}

static void history_keys_test() {
  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  event.keyval = GDK_KEY_Back;
  g_assert_cmpstr(history_navigation_direction(&event), ==, "back");
  event.keyval = GDK_KEY_Forward;
  g_assert_cmpstr(history_navigation_direction(&event), ==, "forward");
  for (guint key : {GDK_KEY_Left, GDK_KEY_Right}) {
    event.keyval = key;
    event.state = GDK_MOD1_MASK;
    g_assert_cmpstr(history_navigation_direction(&event), ==,
                    key == GDK_KEY_Left ? "back" : "forward");
    event.state = GDK_MOD1_MASK | GDK_LOCK_MASK;
    g_assert_nonnull(history_navigation_direction(&event));
    const guint modifiers[] = {0, GDK_CONTROL_MASK, GDK_SHIFT_MASK,
                               GDK_SUPER_MASK};
    for (guint modifier : modifiers) {
      event.state = modifier;
      g_assert_null(history_navigation_direction(&event));
      if (modifier != 0) {
        event.state |= GDK_MOD1_MASK;
        g_assert_null(history_navigation_direction(&event));
      }
    }
  }
  event.keyval = GDK_KEY_plus;
  event.state = GDK_CONTROL_MASK;
  g_assert_null(history_navigation_direction(&event));
  event.keyval = GDK_KEY_a;
  event.state = GDK_MOD1_MASK;
  g_assert_null(history_navigation_direction(&event));
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/history/mouse-buttons", mouse_buttons_test);
  g_test_add_func("/history/keys", history_keys_test);
  return g_test_run();
}
