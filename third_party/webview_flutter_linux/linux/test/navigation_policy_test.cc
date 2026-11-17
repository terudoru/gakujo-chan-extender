#include "../src/webview/webview_navigation_policy.h"

static void main_frame_targets_test() {
  const gchar *names[] = {nullptr, "", "_self", "_top", "_parent"};
  for (const gchar *name : names) {
    g_assert_true(navigation_target_is_main_frame(
        WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION, name));
  }
}

static void other_frame_targets_test() {
  g_assert_false(navigation_target_is_main_frame(
      WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION, "course-frame"));
  const gchar *names[] = {nullptr, "", "_blank", "new-window"};
  for (const gchar *name : names) {
    g_assert_false(navigation_target_is_main_frame(
        WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION, name));
  }
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/navigation-policy/main-targets", main_frame_targets_test);
  g_test_add_func("/navigation-policy/other-targets", other_frame_targets_test);
  return g_test_run();
}
