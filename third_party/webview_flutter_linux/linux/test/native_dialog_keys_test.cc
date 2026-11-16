// Run under xvfb-run: these tests exercise GTK focus and window key bindings.
#include "../src/webview/webview_native_dialog_keys.h"

static void native_child_focus_test() {
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *web_view = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *button = gtk_button_new_with_label("OK");
  GtkWidget *outside = gtk_button_new_with_label("Outside");
  gtk_widget_set_can_focus(web_view, TRUE);
  // A detached widget has no toplevel GtkWindow.
  g_assert_false(focus_is_inside_native_child(web_view));
  gtk_container_add(GTK_CONTAINER(window), outer);
  gtk_container_add(GTK_CONTAINER(outer), web_view);
  gtk_container_add(GTK_CONTAINER(web_view), button);
  gtk_container_add(GTK_CONTAINER(outer), outside);
  gtk_widget_show_all(window);

  gtk_widget_grab_focus(button);
  g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == button);
  g_assert_true(focus_is_inside_native_child(web_view));

  gtk_widget_grab_focus(web_view);
  g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == web_view);
  g_assert_false(focus_is_inside_native_child(web_view));

  gtk_widget_grab_focus(outside);
  g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == outside);
  g_assert_false(focus_is_inside_native_child(web_view));

  gtk_window_set_focus(GTK_WINDOW(window), nullptr);
  g_assert_null(gtk_window_get_focus(GTK_WINDOW(window)));
  g_assert_false(focus_is_inside_native_child(web_view));
  gtk_widget_destroy(window);
}

static void clicked_cb(GtkButton *, gpointer user_data) {
  ++*static_cast<guint *>(user_data);
}

static void tab_cycles_native_child_test() {
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *web_view = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *dialog = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *ok = gtk_button_new_with_label("OK");
  GtkWidget *cancel = gtk_button_new_with_label("Cancel");
  GtkWidget *outside = gtk_button_new_with_label("Outside");
  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  event.keyval = GDK_KEY_Tab;
  g_assert_false(cycle_focus_in_native_child(web_view, &event));
  gtk_widget_set_can_focus(web_view, TRUE);
  gtk_container_add(GTK_CONTAINER(window), outer);
  gtk_container_add(GTK_CONTAINER(outer), web_view);
  gtk_container_add(GTK_CONTAINER(web_view), dialog);
  // WebKit's message label is selectable and focusable; Tab must skip it.
  GtkWidget *message = gtk_label_new("q");
  gtk_label_set_selectable(GTK_LABEL(message), TRUE);
  gtk_container_add(GTK_CONTAINER(dialog), message);
  gtk_container_add(GTK_CONTAINER(dialog), ok);
  gtk_container_add(GTK_CONTAINER(dialog), cancel);
  gtk_container_add(GTK_CONTAINER(outer), outside);
  gtk_widget_show_all(window);
  gtk_window_present(GTK_WINDOW(window));
  gtk_test_widget_wait_for_draw(window);

  const guint tab_keys[] = {GDK_KEY_Tab, GDK_KEY_ISO_Left_Tab, GDK_KEY_KP_Tab};
  for (guint keyval : tab_keys) {
    event.keyval = keyval;
    // ISO_Left_Tab is the keyval produced by Shift+Tab.
    event.state = keyval == GDK_KEY_ISO_Left_Tab ? GDK_SHIFT_MASK : 0;
    gtk_widget_grab_focus(ok);
    g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == ok);
    g_assert_true(cycle_focus_in_native_child(web_view, &event));
    g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == cancel);
    g_assert_true(cycle_focus_in_native_child(web_view, &event));
    g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == ok);

    event.state = GDK_SHIFT_MASK;
    gtk_widget_grab_focus(cancel);
    g_assert_true(cycle_focus_in_native_child(web_view, &event));
    g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == ok);
    g_assert_true(cycle_focus_in_native_child(web_view, &event));
    g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == cancel);
  }

  event.keyval = GDK_KEY_Return;
  g_assert_false(cycle_focus_in_native_child(web_view, &event));
  g_assert_false(cycle_focus_in_native_child(web_view, nullptr));
  g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == cancel);

  event.keyval = GDK_KEY_Tab;
  event.state = 0;
  gtk_widget_grab_focus(web_view);
  g_assert_false(cycle_focus_in_native_child(web_view, &event));
  g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == web_view);
  gtk_widget_grab_focus(outside);
  g_assert_false(cycle_focus_in_native_child(web_view, &event));
  g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == outside);
  gtk_window_set_focus(GTK_WINDOW(window), nullptr);
  g_assert_false(cycle_focus_in_native_child(web_view, &event));
  g_assert_null(gtk_window_get_focus(GTK_WINDOW(window)));
  gtk_widget_destroy(window);
}

static void return_activates_default_test() {
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  GtkWidget *button = gtk_button_new_with_label("OK");
  gtk_container_add(GTK_CONTAINER(window), box);
  gtk_container_add(GTK_CONTAINER(box), button);
  gtk_widget_set_can_focus(box, TRUE);
  gtk_widget_set_can_default(button, TRUE);
  gtk_window_set_default(GTK_WINDOW(window), button);
  guint clicks = 0;
  g_signal_connect(button, "clicked", G_CALLBACK(clicked_cb), &clicks);
  gtk_widget_show_all(window);
  // Focus a non-button so Return must activate the window's default button.
  gtk_widget_grab_focus(box);
  g_assert_true(gtk_window_get_focus(GTK_WINDOW(window)) == box);
  g_assert_true(gtk_window_get_default_widget(GTK_WINDOW(window)) == button);

  GdkEventKey event = {};
  event.type = GDK_KEY_PRESS;
  event.window = gtk_widget_get_window(window);
  event.send_event = TRUE;
  event.time = GDK_CURRENT_TIME;
  event.keyval = GDK_KEY_Return;
  // GTK matches bindings using the hardware keycode and keyboard group.
  GdkKeymap *keymap = gdk_keymap_get_for_display(gtk_widget_get_display(window));
  GdkKeymapKey *keys = nullptr;
  gint n_keys = 0;
  g_assert_true(gdk_keymap_get_entries_for_keyval(
      keymap, event.keyval, &keys, &n_keys));
  g_assert_cmpint(n_keys, >, 0);
  event.hardware_keycode = keys[0].keycode;
  event.group = keys[0].group;
  g_free(keys);
  g_assert_cmpuint(clicks, ==, 0);
  g_assert_true(gtk_bindings_activate_event(G_OBJECT(window), &event));

  // GtkButton activation emits clicked after its keyboard animation finishes.
  const gint64 deadline = g_get_monotonic_time() + 5 * G_TIME_SPAN_SECOND;
  while (clicks == 0 && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
  g_assert_cmpuint(clicks, ==, 1);
  gtk_widget_destroy(window);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/native-dialog/child-focus", native_child_focus_test);
  g_test_add_func("/native-dialog/tab-cycles-native-child",
                  tab_cycles_native_child_test);
  g_test_add_func("/native-dialog/return-activates-default",
                  return_activates_default_test);
  return g_test_run();
}
