#include "../../../../linux/runner/notification_activation.h"

static constexpr const char* kId = "8e608183-9320-4082-8e81-078dc11a9dde";
static constexpr const char* kUrl =
    "https://gakujo.iess.niigata-u.ac.jp/campusweb/report";

static void action_target_test() {
  g_autoptr(GVariant) target = g_variant_ref_sink(g_variant_new("(ss)", kId, kUrl));
  const gchar* id;
  const gchar* url;
  g_assert_true(notification_activation_target(target, &id, &url));
  g_assert_cmpstr(id, ==, kId);
  g_assert_cmpstr(url, ==, kUrl);
}

static void invalid_target_test() {
  const gchar* id;
  const gchar* url;
  g_assert_false(notification_activation_target(nullptr, &id, &url));
  g_autoptr(GVariant) wrong_type = g_variant_ref_sink(g_variant_new_string(kUrl));
  g_assert_false(notification_activation_target(wrong_type, &id, &url));
  g_autoptr(GVariant) bad_id =
      g_variant_ref_sink(g_variant_new("(ss)", "not-an-id", kUrl));
  g_assert_false(notification_activation_target(bad_id, &id, &url));
  g_autoptr(GVariant) empty_url =
      g_variant_ref_sink(g_variant_new("(ss)", kId, ""));
  g_assert_false(notification_activation_target(empty_url, &id, &url));
  g_autofree gchar* oversized = g_strnfill(32769, 'a');
  g_autoptr(GVariant) too_large =
      g_variant_ref_sink(g_variant_new("(ss)", kId, oversized));
  g_assert_false(notification_activation_target(too_large, &id, &url));
}

static void cold_start_test() {
  NotificationActivation activation = {};
  g_assert_true(defer_notification_url(&activation, kUrl));
  g_autofree gchar* pending = take_pending_notification_url(&activation);
  g_assert_cmpstr(pending, ==, kUrl);
  g_assert_null(take_pending_notification_url(&activation));
  // Once Dart is ready, later clicks go through the existing live channel.
  g_assert_false(defer_notification_url(&activation, kUrl));
  g_assert_null(activation.pending_url);
}

static void latest_click_test() {
  NotificationActivation activation = {};
  g_assert_true(defer_notification_url(&activation, "https://example.invalid/"));
  g_assert_true(defer_notification_url(&activation, kUrl));
  g_autofree gchar* pending = take_pending_notification_url(&activation);
  g_assert_cmpstr(pending, ==, kUrl);
}

static void no_click_test() {
  NotificationActivation activation = {};
  g_assert_null(take_pending_notification_url(&activation));
  g_assert_false(defer_notification_url(&activation, kUrl));
}

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/notification/activation-target", action_target_test);
  g_test_add_func("/notification/invalid-target", invalid_target_test);
  g_test_add_func("/notification/cold-start", cold_start_test);
  g_test_add_func("/notification/latest-click", latest_click_test);
  g_test_add_func("/notification/no-click", no_click_test);
  return g_test_run();
}
