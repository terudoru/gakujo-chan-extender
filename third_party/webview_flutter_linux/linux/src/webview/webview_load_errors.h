#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_LOAD_ERRORS_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_LOAD_ERRORS_H_

#include <webkit2/webkit2.h>

inline const gchar *error_type_name_from_error(GError *error) {
  if (error == nullptr) {
    return "unknown";
  }
  if (error->domain == G_TLS_ERROR) {
    return "failedSslHandshake";
  }
  // libsoup 3 preserves GLib's DNS and socket error domains.
  if (error->domain == G_RESOLVER_ERROR) {
    switch (error->code) {
    case G_RESOLVER_ERROR_NOT_FOUND:
    case G_RESOLVER_ERROR_TEMPORARY_FAILURE:
    case G_RESOLVER_ERROR_INTERNAL:
      return "hostLookup";
    default:
      return "unknown";
    }
  }
  if (error->domain == G_IO_ERROR) {
    switch (error->code) {
    case G_IO_ERROR_HOST_NOT_FOUND:
      return "hostLookup";
    case G_IO_ERROR_TIMED_OUT:
      return "timeout";
    case G_IO_ERROR_CONNECTION_REFUSED:
    case G_IO_ERROR_HOST_UNREACHABLE:
    case G_IO_ERROR_NETWORK_UNREACHABLE:
    case G_IO_ERROR_CONNECTION_CLOSED:
    case G_IO_ERROR_NOT_CONNECTED:
    case G_IO_ERROR_PROXY_FAILED:
      return "connect";
    default:
      return "unknown";
    }
  }
  if (error->domain == WEBKIT_NETWORK_ERROR) {
    switch (error->code) {
    case WEBKIT_NETWORK_ERROR_FILE_DOES_NOT_EXIST:
      return "fileNotFound";
    case WEBKIT_NETWORK_ERROR_UNKNOWN_PROTOCOL:
      return "unsupportedScheme";
    case WEBKIT_NETWORK_ERROR_FAILED:
      return "connect";
    case -1001: // WebKit's Soup backend also uses NSURLErrorTimedOut.
      return "timeout";
    default:
      return "unknown";
    }
  }
  if (error->domain == WEBKIT_POLICY_ERROR) {
    switch (error->code) {
    case WEBKIT_POLICY_ERROR_CANNOT_SHOW_URI:
      return "unsupportedScheme";
    case WEBKIT_POLICY_ERROR_CANNOT_SHOW_MIME_TYPE:
      return "file";
    default:
      return "unknown";
    }
  }
  if (g_error_matches(error, WEBKIT_DOWNLOAD_ERROR,
                      WEBKIT_DOWNLOAD_ERROR_NETWORK)) return "connect";
  return "unknown";
}

inline bool should_suppress_connectivity_error_page(GError *error,
                                                    bool event_listening) {
  if (!event_listening) return false;
  const gchar *type = error_type_name_from_error(error);
  return g_str_equal(type, "connect") || g_str_equal(type, "hostLookup") ||
         g_str_equal(type, "timeout");
}

inline const gchar *web_process_termination_description(
    WebKitWebProcessTerminationReason reason) {
  if (reason == WEBKIT_WEB_PROCESS_TERMINATED_BY_API) {
    return nullptr;
  }
  return reason == WEBKIT_WEB_PROCESS_EXCEEDED_MEMORY_LIMIT
             ? "WebKit content process exceeded its memory limit."
             : "WebKit content process terminated unexpectedly.";
}

#endif // WEBVIEW_ALL_LINUX_WEBVIEW_LOAD_ERRORS_H_
