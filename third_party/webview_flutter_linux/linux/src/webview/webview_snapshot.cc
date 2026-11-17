#include "webview/webview_snapshot.h"

namespace {

struct PngWriter {
  GByteArray *bytes;
  GCancellable *cancellable;
};

cairo_status_t write_png(void *data, const unsigned char *bytes,
                          unsigned int length) {
  auto *writer = static_cast<PngWriter *>(data);
  if (writer->cancellable != nullptr &&
      g_cancellable_is_cancelled(writer->cancellable)) {
    return CAIRO_STATUS_WRITE_ERROR;
  }
  g_byte_array_append(writer->bytes, bytes, length);
  return CAIRO_STATUS_SUCCESS;
}

struct SnapshotRequest {
  GCancellable *cancellable;
  guint timeout_id = 0;
  bool completed = false;
};

void destroy_snapshot_request(gpointer data) {
  auto *request = static_cast<SnapshotRequest *>(data);
  g_clear_object(&request->cancellable);
  delete request;
}

void complete_snapshot(GTask *task, GBytes *bytes, GError *error) {
  auto *request = static_cast<SnapshotRequest *>(g_task_get_task_data(task));
  if (request->completed) {
    g_clear_pointer(&bytes, g_bytes_unref);
    g_clear_error(&error);
    return;
  }
  request->completed = true;
  if (request->timeout_id != 0) {
    g_source_remove(request->timeout_id);
    request->timeout_id = 0;
  }
  if (error != nullptr) {
    g_task_return_error(task, error);
  } else {
    g_task_return_pointer(task, bytes,
                          reinterpret_cast<GDestroyNotify>(g_bytes_unref));
  }
}

gboolean snapshot_timed_out(gpointer data) {
  GTask *task = G_TASK(data);
  auto *request = static_cast<SnapshotRequest *>(g_task_get_task_data(task));
  request->timeout_id = 0;
  complete_snapshot(task, nullptr,
                    g_error_new_literal(G_IO_ERROR, G_IO_ERROR_TIMED_OUT,
                                        "Snapshot timed out."));
  g_cancellable_cancel(request->cancellable);
  return G_SOURCE_REMOVE;
}

void encode_snapshot(GTask *task, gpointer, gpointer data,
                      GCancellable *cancellable) {
  GError *error = nullptr;
  GBytes *bytes = encode_webview_snapshot(
      static_cast<cairo_surface_t *>(data), cancellable, &error);
  if (error != nullptr) {
    g_task_return_error(task, error);
  } else {
    g_task_return_pointer(task, bytes,
                          reinterpret_cast<GDestroyNotify>(g_bytes_unref));
  }
}

void snapshot_encoded(GObject *, GAsyncResult *result, gpointer data) {
  GTask *task = G_TASK(data);
  GError *error = nullptr;
  auto *bytes =
      static_cast<GBytes *>(g_task_propagate_pointer(G_TASK(result), &error));
  complete_snapshot(task, bytes, error);
  g_object_unref(task);
}

#if WEBKIT_CHECK_VERSION(2, 2, 0)
void snapshot_finished(GObject *object, GAsyncResult *result, gpointer data) {
  GTask *task = G_TASK(data);
  auto *request = static_cast<SnapshotRequest *>(g_task_get_task_data(task));
  GError *error = nullptr;
  cairo_surface_t *surface = webkit_web_view_get_snapshot_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (surface == nullptr || request->completed) {
    if (surface != nullptr) cairo_surface_destroy(surface);
    complete_snapshot(task, nullptr, error);
    g_object_unref(task);
    return;
  }
  // PNG compression must not block GTK from hiding the native view on timeout.
  GTask *encoding =
      g_task_new(nullptr, request->cancellable, snapshot_encoded, task);
  g_task_set_task_data(encoding, surface,
                       reinterpret_cast<GDestroyNotify>(cairo_surface_destroy));
  g_task_run_in_thread(encoding, encode_snapshot);
  g_object_unref(encoding);
}
#endif

} // namespace

GBytes *encode_webview_snapshot(cairo_surface_t *surface,
                                GCancellable *cancellable, GError **error) {
  if (cancellable != nullptr &&
      g_cancellable_set_error_if_cancelled(cancellable, error)) {
    return nullptr;
  }
  g_autoptr(GByteArray) bytes = g_byte_array_new();
  PngWriter writer{bytes, cancellable};
  const cairo_status_t status =
      cairo_surface_write_to_png_stream(surface, write_png, &writer);
  if (cancellable != nullptr &&
      g_cancellable_set_error_if_cancelled(cancellable, error)) {
    return nullptr;
  }
  if (status != CAIRO_STATUS_SUCCESS) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                         cairo_status_to_string(status));
    return nullptr;
  }
  // Keep the surface's physical pixels; Flutter fits them to the logical view.
  return g_byte_array_free_to_bytes(g_steal_pointer(&bytes));
}

void take_webview_snapshot(WebKitWebView *view, guint timeout_ms,
                           GAsyncReadyCallback callback, gpointer user_data) {
  GTask *task = g_task_new(view, nullptr, callback, user_data);
  auto *request = new SnapshotRequest{g_cancellable_new()};
  g_task_set_task_data(task, request, destroy_snapshot_request);
  if (timeout_ms == 0) {
    complete_snapshot(task, nullptr,
                      g_error_new_literal(G_IO_ERROR, G_IO_ERROR_TIMED_OUT,
                                          "Snapshot timed out."));
    g_object_unref(task);
    return;
  }
#if WEBKIT_CHECK_VERSION(2, 2, 0)
  if (gtk_widget_get_mapped(GTK_WIDGET(view))) {
    request->timeout_id = g_timeout_add_full(
        G_PRIORITY_DEFAULT, timeout_ms, snapshot_timed_out, g_object_ref(task),
        g_object_unref);
    webkit_web_view_get_snapshot(
        view, WEBKIT_SNAPSHOT_REGION_VISIBLE, WEBKIT_SNAPSHOT_OPTIONS_NONE,
        request->cancellable, snapshot_finished, task);
    return;
  }
#endif
  complete_snapshot(task, nullptr,
                    g_error_new_literal(G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                                        "Snapshot unavailable."));
  g_object_unref(task);
}

GBytes *take_webview_snapshot_finish(WebKitWebView *view, GAsyncResult *result,
                                     GError **error) {
  g_return_val_if_fail(g_task_is_valid(result, view), nullptr);
  return static_cast<GBytes *>(g_task_propagate_pointer(G_TASK(result), error));
}
