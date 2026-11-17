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
  switch (error->code) {
  case WEBKIT_NETWORK_ERROR_CANCELLED:
    return "unknown";
  case WEBKIT_NETWORK_ERROR_FILE_DOES_NOT_EXIST:
    return "fileNotFound";
  case WEBKIT_NETWORK_ERROR_UNKNOWN_PROTOCOL:
    return "unsupportedScheme";
  case WEBKIT_NETWORK_ERROR_FAILED:
    return "connect";
  case WEBKIT_POLICY_ERROR_CANNOT_SHOW_URI:
    return "unsupportedScheme";
  case WEBKIT_POLICY_ERROR_CANNOT_SHOW_MIME_TYPE:
    return "file";
  case WEBKIT_DOWNLOAD_ERROR_NETWORK:
    return "connect";
  default:
    return "unknown";
  }
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
