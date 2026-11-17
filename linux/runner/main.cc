#include "my_application.h"

int main(int argc, char** argv) {
  // DMA-BUF can leave WebKit blank on virtio-gpu VMs; use its software fallback.
  g_setenv("WEBKIT_DISABLE_DMABUF_RENDERER", "1", FALSE);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
