#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_NATIVE_DIALOG_KEYS_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_NATIVE_DIALOG_KEYS_H_

#include <gtk/gtk.h>

// More Better Gakujo patch: WebKit's in-view native dialogs focus child widgets.
inline bool focus_is_inside_native_child(GtkWidget *web_view) {
  GtkWidget *toplevel = gtk_widget_get_toplevel(web_view);
  if (!GTK_IS_WINDOW(toplevel)) {
    return false;
  }
  GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(toplevel));
  return focus != nullptr && focus != web_view &&
      gtk_widget_is_ancestor(focus, web_view);
}

inline void collect_native_child_focusable(GtkWidget *widget,
                                           GPtrArray *focusable) {
  if (!gtk_widget_get_mapped(widget) || !gtk_widget_is_sensitive(widget)) {
    return;
  }
  // Skip the selectable message label: like other platforms' dialogs, Tab
  // moves between the buttons (and the prompt's entry) only.
  if (gtk_widget_get_can_focus(widget) &&
      (GTK_IS_BUTTON(widget) || GTK_IS_ENTRY(widget))) {
    g_ptr_array_add(focusable, widget);
  }
  if (GTK_IS_CONTAINER(widget)) {
    GList *children = gtk_container_get_children(GTK_CONTAINER(widget));
    for (GList *link = children; link != nullptr; link = link->next) {
      collect_native_child_focusable(GTK_WIDGET(link->data), focusable);
    }
    g_list_free(children);
  }
}

inline bool cycle_focus_in_native_child(GtkWidget *web_view,
                                        GdkEventKey *event) {
  if (event == nullptr ||
      (event->keyval != GDK_KEY_Tab && event->keyval != GDK_KEY_ISO_Left_Tab &&
       event->keyval != GDK_KEY_KP_Tab) ||
      !focus_is_inside_native_child(web_view)) {
    return false;
  }

  GtkWindow *window = GTK_WINDOW(gtk_widget_get_toplevel(web_view));
  GtkWidget *dialog = gtk_window_get_focus(window);
  while (gtk_widget_get_parent(dialog) != web_view) {
    dialog = gtk_widget_get_parent(dialog);
  }
  // GTK's own traversal leaves the dialog at its last widget, so cycle
  // through the dialog's focusable widgets in tree order and wrap around.
  GPtrArray *focusable = g_ptr_array_new();
  collect_native_child_focusable(dialog, focusable);
  if (focusable->len > 0) {
    GtkWidget *focus = gtk_window_get_focus(window);
    guint index = 0;
    while (index < focusable->len &&
           g_ptr_array_index(focusable, index) != focus) {
      ++index;
    }
    const bool backward = (event->state & GDK_SHIFT_MASK) != 0 ||
        event->keyval == GDK_KEY_ISO_Left_Tab;
    guint next;
    if (index == focusable->len) {
      next = backward ? focusable->len - 1 : 0;
    } else if (backward) {
      next = index == 0 ? focusable->len - 1 : index - 1;
    } else {
      next = index + 1 == focusable->len ? 0 : index + 1;
    }
    gtk_widget_grab_focus(GTK_WIDGET(g_ptr_array_index(focusable, next)));
  }
  g_ptr_array_free(focusable, TRUE);
  return true;
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_NATIVE_DIALOG_KEYS_H_
