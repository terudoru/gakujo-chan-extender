#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_SNAPSHOT_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_SNAPSHOT_H_

#include <webkit2/webkit2.h>

GBytes *encode_webview_snapshot(cairo_surface_t *surface,
                                GCancellable *cancellable, GError **error);
void take_webview_snapshot(WebKitWebView *view, guint timeout_ms,
                           GAsyncReadyCallback callback, gpointer user_data);
GBytes *take_webview_snapshot_finish(WebKitWebView *view, GAsyncResult *result,
                                     GError **error);

#endif // WEBVIEW_ALL_LINUX_WEBVIEW_SNAPSHOT_H_
