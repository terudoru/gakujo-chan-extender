#include "my_application.h"
#include "webview/download_staging.h"

static void cancel_native_dialogs(GApplication*) {
  GList* windows = gtk_window_list_toplevels();
  for (GList* item = windows; item != nullptr; item = item->next)
    g_object_ref(item->data);
  for (GList* item = windows; item != nullptr; item = item->next) {
    if (GTK_IS_DIALOG(item->data))
      gtk_dialog_response(GTK_DIALOG(item->data), GTK_RESPONSE_CANCEL);
  }
  g_list_free_full(windows, g_object_unref);
}

int main(int argc, char** argv) {
  const gint64 started = g_get_real_time();
  // DMA-BUF can leave WebKit blank on virtio-gpu VMs; use its software fallback.
  g_setenv("WEBKIT_DISABLE_DMABUF_RENDERER", "1", FALSE);
  g_autoptr(MyApplication) app = my_application_new();
  download_staging::Lifecycle staging(G_APPLICATION(app), g_get_tmp_dir(),
                                      started, cancel_native_dialogs);
  return g_application_run(G_APPLICATION(app), argc, argv);
}
