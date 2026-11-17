#ifndef RUNNER_FILE_CHOOSER_DIALOG_H_
#define RUNNER_FILE_CHOOSER_DIALOG_H_

#include <gtk/gtk.h>

inline void fit_file_chooser_to_workarea(GtkWindow* dialog,
                                        const GdkRectangle& workarea) {
  if (workarea.width <= 0 || workarea.height <= 0) return;
  GdkGeometry hints = {};
  hints.max_width = MAX(1, workarea.width * 9 / 10);
  hints.max_height = MAX(1, workarea.height * 9 / 10);
  gtk_window_set_geometry_hints(dialog, nullptr, &hints, GDK_HINT_MAX_SIZE);
  gint width, height;
  gtk_window_get_size(dialog, &width, &height);
  width = CLAMP(width, 1, hints.max_width);
  height = CLAMP(height, 1, hints.max_height);
  gtk_window_set_default_size(dialog, width, height);
  gtk_window_resize(dialog, width, height);
}

inline void fit_file_chooser_to_parent_monitor(GtkWidget* dialog,
                                               gpointer parent) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(parent));
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(parent));
  GdkMonitor* monitor = window != nullptr
      ? gdk_display_get_monitor_at_window(display, window)
      : gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) monitor = gdk_display_get_monitor(display, 0);
  if (monitor == nullptr) return;
  GdkRectangle workarea;
  gdk_monitor_get_workarea(monitor, &workarea);
  fit_file_chooser_to_workarea(GTK_WINDOW(dialog), workarea);
}

#endif  // RUNNER_FILE_CHOOSER_DIALOG_H_
