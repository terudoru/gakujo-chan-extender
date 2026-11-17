#include "../../../../linux/runner/file_chooser_dialog.h"

static void restored_size_test() {
  GtkWidget *dialog = gtk_file_chooser_dialog_new(
      "名前を付けて保存", nullptr, GTK_FILE_CHOOSER_ACTION_SAVE,
      "キャンセル", GTK_RESPONSE_CANCEL, "保存", GTK_RESPONSE_ACCEPT, nullptr);
  const GdkRectangle workarea = {0, 0, 1280, 800};
  gtk_window_set_default_size(GTK_WINDOW(dialog), 1096, 822);
  gtk_widget_realize(dialog);
  fit_file_chooser_to_workarea(GTK_WINDOW(dialog), workarea);
  gint width, height;
  gtk_window_get_default_size(GTK_WINDOW(dialog), &width, &height);
  g_assert_cmpint(width, <=, 1152);
  g_assert_cmpint(height, <=, 720);
  // A saved size can be applied again by GTK while the chooser maps.
  gtk_window_resize(GTK_WINDOW(dialog), 2000, 1600);
  fit_file_chooser_to_workarea(GTK_WINDOW(dialog), workarea);
  gtk_window_get_default_size(GTK_WINDOW(dialog), &width, &height);
  g_assert_cmpint(width, <=, 1152);
  g_assert_cmpint(height, <=, 720);
  gtk_widget_destroy(dialog);
}

static void small_size_test() {
  GtkWidget *dialog = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(dialog), 500, 400);
  fit_file_chooser_to_workarea(GTK_WINDOW(dialog), {1280, 0, 1280, 800});
  gint width, height;
  gtk_window_get_default_size(GTK_WINDOW(dialog), &width, &height);
  g_assert_cmpint(width, ==, 500);
  g_assert_cmpint(height, ==, 400);
  gtk_widget_destroy(dialog);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/file-chooser/restored-size", restored_size_test);
  g_test_add_func("/file-chooser/keep-small-size", small_size_test);
  return g_test_run();
}
