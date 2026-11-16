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

static void reload_keys_test() {
  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  const guint locks[] = {0, GDK_LOCK_MASK, GDK_MOD2_MASK,
                         GDK_LOCK_MASK | GDK_MOD2_MASK};
  for (guint lock : locks) {
    event.keyval = GDK_KEY_F5;
    event.state = lock;
    g_assert_true(browser_key_action(&event) == BrowserKeyAction::kReload);
    event.state = GDK_SHIFT_MASK | lock;
    g_assert_true(browser_key_action(&event) ==
                  BrowserKeyAction::kReloadBypassCache);
    for (guint key : {GDK_KEY_r, GDK_KEY_R}) {
      event.keyval = key;
      event.state = GDK_CONTROL_MASK | lock;
      g_assert_true(browser_key_action(&event) == BrowserKeyAction::kReload);
      event.state = GDK_CONTROL_MASK | GDK_SHIFT_MASK | lock;
      g_assert_true(browser_key_action(&event) ==
                    BrowserKeyAction::kReloadBypassCache);
    }
  }
}

static void print_keys_test() {
  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  const guint locks[] = {0, GDK_LOCK_MASK, GDK_MOD2_MASK,
                         GDK_LOCK_MASK | GDK_MOD2_MASK};
  for (guint key : {GDK_KEY_p, GDK_KEY_P}) {
    event.keyval = key;
    for (guint lock : locks) {
      event.state = GDK_CONTROL_MASK | lock;
      g_assert_true(browser_key_action(&event) == BrowserKeyAction::kPrint);
    }
  }
}

static void find_keys_test() {
  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  const guint locks[] = {0, GDK_LOCK_MASK, GDK_MOD2_MASK,
                         GDK_LOCK_MASK | GDK_MOD2_MASK};
  for (guint lock : locks) {
    for (guint key : {GDK_KEY_f, GDK_KEY_F}) {
      event.keyval = key;
      event.state = GDK_CONTROL_MASK | lock;
      g_assert_true(browser_key_action(&event) == BrowserKeyAction::kFind);
    }
    for (guint key : {GDK_KEY_g, GDK_KEY_G}) {
      event.keyval = key;
      event.state = GDK_CONTROL_MASK | lock;
      g_assert_true(browser_key_action(&event) == BrowserKeyAction::kFindNext);
      event.state = GDK_CONTROL_MASK | GDK_SHIFT_MASK | lock;
      g_assert_true(browser_key_action(&event) == BrowserKeyAction::kFindPrevious);
    }
    event.keyval = GDK_KEY_F3;
    event.state = lock;
    g_assert_true(browser_key_action(&event) == BrowserKeyAction::kFindNext);
    event.state = GDK_SHIFT_MASK | lock;
    g_assert_true(browser_key_action(&event) == BrowserKeyAction::kFindPrevious);
  }

  // Neither other modifier combinations nor unrelated keys trigger find.
  const guint other_modifiers[] = {
      GDK_MOD1_MASK, GDK_SUPER_MASK, GDK_META_MASK, GDK_HYPER_MASK,
      GDK_MOD3_MASK, GDK_MOD4_MASK, GDK_MOD5_MASK};
  const guint invalid_find_modifiers[] = {
      0, GDK_SHIFT_MASK, GDK_CONTROL_MASK | GDK_SHIFT_MASK};
  for (guint key : {GDK_KEY_f, GDK_KEY_F}) {
    event.keyval = key;
    for (guint modifiers : invalid_find_modifiers) {
      event.state = modifiers;
      g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
    }
    for (guint modifiers : other_modifiers) {
      for (guint lock : locks) {
        event.state = modifiers | lock;
        g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
        event.state |= GDK_CONTROL_MASK;
        g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
      }
    }
  }
  for (guint key : {GDK_KEY_g, GDK_KEY_G}) {
    event.keyval = key;
    event.state = 0;
    g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
    event.state = GDK_CONTROL_MASK | GDK_MOD1_MASK;
    g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
  }
  event.keyval = GDK_KEY_F3;
  const guint extra_modifiers[] = {0, GDK_CONTROL_MASK, GDK_SHIFT_MASK};
  for (guint modifiers : other_modifiers) {
    for (guint extra : extra_modifiers) {
      event.state = modifiers | extra;
      g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
    }
  }
  event.state = GDK_CONTROL_MASK;
  g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
  event.state |= GDK_SHIFT_MASK;
  g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
}

static void zoom_keys_test() {
  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  const guint locks[] = {0, GDK_LOCK_MASK, GDK_MOD2_MASK,
                         GDK_LOCK_MASK | GDK_MOD2_MASK};
  const guint shifts[] = {0, GDK_SHIFT_MASK};
  const guint other_modifiers[] = {
      GDK_MOD1_MASK, GDK_SUPER_MASK, GDK_META_MASK, GDK_HYPER_MASK};
  const struct {
    guint key;
    BrowserKeyAction action;
  } cases[] = {
      {GDK_KEY_equal, BrowserKeyAction::kZoomIn},
      {GDK_KEY_plus, BrowserKeyAction::kZoomIn},
      {GDK_KEY_KP_Add, BrowserKeyAction::kZoomIn},
      {GDK_KEY_minus, BrowserKeyAction::kZoomOut},
      {GDK_KEY_KP_Subtract, BrowserKeyAction::kZoomOut},
      {GDK_KEY_0, BrowserKeyAction::kZoomReset},
      {GDK_KEY_KP_0, BrowserKeyAction::kZoomReset},
  };
  for (const auto &test : cases) {
    event.keyval = test.key;
    for (guint lock : locks) {
      for (guint shift : shifts) {
        event.state = GDK_CONTROL_MASK | shift | lock;
        g_assert_true(browser_key_action(&event) == test.action);
        for (guint modifier : other_modifiers) {
          event.state = GDK_CONTROL_MASK | modifier | shift | lock;
          g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
        }
        event.state = shift | lock;
        g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
      }
    }
  }
}

static void unhandled_browser_keys_test() {
  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  const struct {
    guint key;
    guint modifiers;
  } cases[] = {
      {GDK_KEY_r, 0},
      {GDK_KEY_R, GDK_SHIFT_MASK},
      {GDK_KEY_r, GDK_MOD1_MASK},
      {GDK_KEY_R, GDK_CONTROL_MASK | GDK_MOD1_MASK},
      {GDK_KEY_r, GDK_CONTROL_MASK | GDK_SUPER_MASK},
      {GDK_KEY_R, GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_MOD1_MASK},
      {GDK_KEY_R, GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_SUPER_MASK},
      {GDK_KEY_p, 0},
      {GDK_KEY_P, GDK_MOD1_MASK},
      {GDK_KEY_p, GDK_CONTROL_MASK | GDK_MOD1_MASK},
      {GDK_KEY_P, GDK_CONTROL_MASK | GDK_SHIFT_MASK},
      {GDK_KEY_p, GDK_CONTROL_MASK | GDK_SUPER_MASK},
      {GDK_KEY_F5, GDK_CONTROL_MASK},
      {GDK_KEY_F5, GDK_MOD1_MASK},
      {GDK_KEY_F5, GDK_SUPER_MASK},
      {GDK_KEY_F5, GDK_SHIFT_MASK | GDK_CONTROL_MASK},
      {GDK_KEY_F5, GDK_SHIFT_MASK | GDK_MOD1_MASK},
      {GDK_KEY_F5, GDK_SHIFT_MASK | GDK_SUPER_MASK},
      {GDK_KEY_Left, GDK_MOD1_MASK},
      {GDK_KEY_Right, GDK_MOD1_MASK},
      {GDK_KEY_Back, 0},
      {GDK_KEY_Forward, 0},
      {GDK_KEY_a, GDK_CONTROL_MASK},
  };
  for (const auto &test : cases) {
    event.keyval = test.key;
    event.state = test.modifiers;
    g_assert_true(browser_key_action(&event) == BrowserKeyAction::kNone);
  }
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/history/mouse-buttons", mouse_buttons_test);
  g_test_add_func("/history/keys", history_keys_test);
  g_test_add_func("/browser/reload-keys", reload_keys_test);
  g_test_add_func("/browser/print-keys", print_keys_test);
  g_test_add_func("/browser/find-keys", find_keys_test);
  g_test_add_func("/browser/zoom-keys", zoom_keys_test);
  g_test_add_func("/browser/unhandled-keys", unhandled_browser_keys_test);
  return g_test_run();
}
