#include "../src/webview/webview_load_errors.h"

static void tls_error_test() {
  g_autoptr(GError) tls = g_error_new_literal(
      G_TLS_ERROR, G_TLS_ERROR_BAD_CERTIFICATE, "Certificate has expired.");
  g_assert_cmpstr(error_type_name_from_error(tls), ==, "failedSslHandshake");
  g_autoptr(GError) network = g_error_new_literal(
      WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_FAILED, "Connection failed.");
  g_assert_cmpstr(error_type_name_from_error(network), ==, "connect");
}

static void process_termination_test() {
  g_assert_nonnull(web_process_termination_description(WEBKIT_WEB_PROCESS_CRASHED));
  g_assert_nonnull(web_process_termination_description(
      WEBKIT_WEB_PROCESS_EXCEEDED_MEMORY_LIMIT));
  g_assert_null(web_process_termination_description(
      WEBKIT_WEB_PROCESS_TERMINATED_BY_API));
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/load-errors/tls", tls_error_test);
  g_test_add_func("/load-errors/process-termination", process_termination_test);
  return g_test_run();
}
