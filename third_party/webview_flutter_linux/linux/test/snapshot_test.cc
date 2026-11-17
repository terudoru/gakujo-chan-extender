#include "../src/webview/webview_snapshot.h"
#include "javascript_test_helpers.h"

#include <cstring>

namespace {

struct PngReader {
  const guint8 *data;
  gsize length;
  gsize offset = 0;
};

cairo_status_t read_png(void *data, unsigned char *output, unsigned int length) {
  auto *reader = static_cast<PngReader *>(data);
  if (length > reader->length - reader->offset) return CAIRO_STATUS_READ_ERROR;
  memcpy(output, reader->data + reader->offset, length);
  reader->offset += length;
  return CAIRO_STATUS_SUCCESS;
}

void physical_pixels_test() {
  cairo_surface_t *surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 64, 32);
  cairo_surface_set_device_scale(surface, 2, 2);
  cairo_t *context = cairo_create(surface);
  cairo_set_source_rgb(context, 1, 0, 0);
  cairo_paint(context);
  cairo_destroy(context);
  GError *error = nullptr;
  g_autoptr(GBytes) bytes = encode_webview_snapshot(surface, nullptr, &error);
  cairo_surface_destroy(surface);
  g_assert_no_error(error);
  g_assert_nonnull(bytes);
  gsize length = 0;
  const auto *data = static_cast<const guint8 *>(g_bytes_get_data(bytes, &length));
  PngReader reader{data, length};
  surface = cairo_image_surface_create_from_png_stream(read_png, &reader);
  g_assert_cmpint(cairo_surface_status(surface), ==, CAIRO_STATUS_SUCCESS);
  g_assert_cmpint(cairo_image_surface_get_width(surface), ==, 64);
  g_assert_cmpint(cairo_image_surface_get_height(surface), ==, 32);
  const auto *pixels =
      reinterpret_cast<const guint32 *>(cairo_image_surface_get_data(surface));
  g_assert_cmphex(pixels[0] & 0x00ffffff, ==, 0x00ff0000);
  cairo_surface_destroy(surface);
}

void cancelled_encoding_test() {
  cairo_surface_t *surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 2, 2);
  g_autoptr(GCancellable) cancellable = g_cancellable_new();
  g_cancellable_cancel(cancellable);
  GError *error = nullptr;
  g_assert_null(encode_webview_snapshot(surface, cancellable, &error));
  g_assert_error(error, G_IO_ERROR, G_IO_ERROR_CANCELLED);
  g_clear_error(&error);
  cairo_surface_destroy(surface);
}

struct SnapshotResult {
  bool done = false;
  GBytes *bytes = nullptr;
  GError *error = nullptr;
};

void snapshot_ready(GObject *object, GAsyncResult *result, gpointer data) {
  auto *snapshot = static_cast<SnapshotResult *>(data);
  snapshot->bytes = take_webview_snapshot_finish(
      WEBKIT_WEB_VIEW(object), result, &snapshot->error);
  snapshot->done = true;
}

void await_snapshot(SnapshotResult *result) {
  const gint64 deadline = g_get_monotonic_time() + 5 * G_TIME_SPAN_SECOND;
  while (!result->done && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
  g_assert_true(result->done);
}

void unavailable_test() {
  WebKitWebView *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  g_object_ref_sink(view);
  SnapshotResult result;
  take_webview_snapshot(view, 100, snapshot_ready, &result);
  await_snapshot(&result);
  g_assert_null(result.bytes);
  g_assert_error(result.error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED);
  g_clear_error(&result.error);
  g_object_unref(view);
}

void deadline_test() {
  WebKitWebView *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  g_object_ref_sink(view);
  SnapshotResult result;
  take_webview_snapshot(view, 0, snapshot_ready, &result);
  await_snapshot(&result);
  g_assert_null(result.bytes);
  g_assert_error(result.error, G_IO_ERROR, G_IO_ERROR_TIMED_OUT);
  g_clear_error(&result.error);
  g_object_unref(view);
}

void visible_snapshot_test() {
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_autoptr(WebKitWebContext) context = webkit_web_context_new_ephemeral();
  WebKitWebView *view =
      WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(context));
  gtk_window_set_default_size(GTK_WINDOW(window), 320, 180);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show_all(window);
  webview_test::load_html(
      view, "<body style='background:red'>snapshot</body>", "about:blank");
  SnapshotResult result;
  take_webview_snapshot(view, 3000, snapshot_ready, &result);
  await_snapshot(&result);
  g_assert_no_error(result.error);
  g_assert_nonnull(result.bytes);
  gsize length = 0;
  const auto *data =
      static_cast<const guint8 *>(g_bytes_get_data(result.bytes, &length));
  const guint8 signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
  g_assert_cmpuint(length, >, sizeof(signature));
  g_assert_cmpmem(data, sizeof(signature), signature, sizeof(signature));
  g_bytes_unref(result.bytes);
  gtk_widget_destroy(window);
}

} // namespace

int main(int argc, char **argv) {
  g_setenv("WEBKIT_DISABLE_DMABUF_RENDERER", "1", FALSE);
  gtk_init(&argc, &argv);
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/snapshot/physical-pixels", physical_pixels_test);
  g_test_add_func("/snapshot/cancelled-encoding", cancelled_encoding_test);
  g_test_add_func("/snapshot/unavailable", unavailable_test);
  g_test_add_func("/snapshot/deadline", deadline_test);
  g_test_add_func("/snapshot/visible", visible_snapshot_test);
  return g_test_run();
}
