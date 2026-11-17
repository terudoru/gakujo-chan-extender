#include "../src/webview/webview_load_errors.h"

#include <libsoup/soup.h>

#include <initializer_list>

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

static void resolver_error_test() {
  for (gint code : {G_RESOLVER_ERROR_NOT_FOUND, G_RESOLVER_ERROR_TEMPORARY_FAILURE,
                    G_RESOLVER_ERROR_INTERNAL}) {
    g_autoptr(GError) error =
        g_error_new_literal(G_RESOLVER_ERROR, code, "Name resolution failed.");
    g_assert_cmpstr(error_type_name_from_error(error), ==, "hostLookup");
    g_assert_true(should_suppress_connectivity_error_page(error, true));
    g_assert_false(should_suppress_connectivity_error_page(error, false));
  }
}

static void socket_error_test() {
  for (gint code : {G_IO_ERROR_CONNECTION_REFUSED, G_IO_ERROR_HOST_UNREACHABLE,
                    G_IO_ERROR_NETWORK_UNREACHABLE, G_IO_ERROR_CONNECTION_CLOSED,
                    G_IO_ERROR_NOT_CONNECTED, G_IO_ERROR_PROXY_FAILED}) {
    g_autoptr(GError) error =
        g_error_new_literal(G_IO_ERROR, code, "Could not connect.");
    g_assert_cmpstr(error_type_name_from_error(error), ==, "connect");
    g_assert_true(should_suppress_connectivity_error_page(error, true));
  }
  g_autoptr(GError) host = g_error_new_literal(
      G_IO_ERROR, G_IO_ERROR_HOST_NOT_FOUND, "Host not found.");
  g_assert_cmpstr(error_type_name_from_error(host), ==, "hostLookup");
  g_autoptr(GError) timeout = g_error_new_literal(
      G_IO_ERROR, G_IO_ERROR_TIMED_OUT, "Connection timed out.");
  g_assert_cmpstr(error_type_name_from_error(timeout), ==, "timeout");
  g_autoptr(GError) webkit_timeout = g_error_new_literal(
      WEBKIT_NETWORK_ERROR, -1001, "Request timed out.");
  g_assert_cmpstr(error_type_name_from_error(webkit_timeout), ==, "timeout");
}

static void non_connectivity_error_test() {
  for (gint code : {G_IO_ERROR_CANCELLED, G_IO_ERROR_PERMISSION_DENIED,
                    G_IO_ERROR_FAILED}) {
    g_autoptr(GError) error =
        g_error_new_literal(G_IO_ERROR, code, "Not a connectivity error.");
    g_assert_cmpstr(error_type_name_from_error(error), ==, "unknown");
    g_assert_false(should_suppress_connectivity_error_page(error, true));
  }
  g_autoptr(GError) cancelled = g_error_new_literal(
      WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED, "Cancelled.");
  g_assert_false(should_suppress_connectivity_error_page(cancelled, true));
  g_autoptr(GError) tls = g_error_new_literal(
      G_TLS_ERROR, G_TLS_ERROR_BAD_CERTIFICATE, "Certificate has expired.");
  g_assert_false(should_suppress_connectivity_error_page(tls, true));
  g_assert_false(should_suppress_connectivity_error_page(nullptr, true));
}

static void error_domain_test() {
  g_autoptr(GError) foreign = g_error_new_literal(
      g_quark_from_static_string("other-error-domain"),
      WEBKIT_NETWORK_ERROR_FAILED, "Unrelated failure with the same code.");
  g_assert_cmpstr(error_type_name_from_error(foreign), ==, "unknown");
  g_autoptr(GError) soup = g_error_new_literal(
      SOUP_SESSION_ERROR, SOUP_SESSION_ERROR_PARSING, "Invalid HTTP response.");
  g_assert_cmpstr(error_type_name_from_error(soup), ==, "unknown");
  g_autoptr(GError) policy = g_error_new_literal(
      WEBKIT_POLICY_ERROR, WEBKIT_POLICY_ERROR_CANNOT_SHOW_MIME_TYPE,
      "Unsupported MIME type.");
  g_assert_cmpstr(error_type_name_from_error(policy), ==, "file");
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/load-errors/tls", tls_error_test);
  g_test_add_func("/load-errors/process-termination", process_termination_test);
  g_test_add_func("/load-errors/resolver", resolver_error_test);
  g_test_add_func("/load-errors/socket", socket_error_test);
  g_test_add_func("/load-errors/non-connectivity", non_connectivity_error_test);
  g_test_add_func("/load-errors/domains", error_domain_test);
  return g_test_run();
}
