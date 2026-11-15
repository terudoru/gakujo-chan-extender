#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  gboolean window_shown;
  gint normal_window_width;
  gint normal_window_height;
  gint normal_window_x;
  gint normal_window_y;
  gboolean normal_window_position_valid;
  GdkWindowState window_state;
  gboolean window_state_saved;
  FlMethodChannel* notification_channel;
  FlMethodChannel* window_channel;
  GPtrArray* pending_window_calls;
  GDBusConnection* notification_connection;
  GHashTable* notification_urls;
  guint notification_action_subscription;
  guint notification_closed_subscription;
  gboolean notifications_shutdown;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Unique, so a second launch only raises the running window (like Windows).
// GLib 2.74 renamed the flag; Ubuntu 22.04 ships 2.72.
#if GLIB_CHECK_VERSION(2, 74, 0)
static const GApplicationFlags kApplicationFlags = G_APPLICATION_DEFAULT_FLAGS;
#else
static const GApplicationFlags kApplicationFlags = G_APPLICATION_FLAGS_NONE;
#endif

static const char* kNotificationBusName = "org.freedesktop.Notifications";
static const char* kNotificationObjectPath = "/org/freedesktop/Notifications";

struct NotificationRequest {
  MyApplication* application;
  FlMethodCall* method_call;
};

static gchar* get_bundle_icon_path() {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable == nullptr) {
    return nullptr;
  }
  g_autofree gchar* directory = g_path_get_dirname(executable);
  g_autofree gchar* path =
      g_build_filename(directory, "data", "app_icon.png", nullptr);
  return g_file_test(path, G_FILE_TEST_IS_REGULAR) ? g_steal_pointer(&path)
                                                : nullptr;
}

static const char* notification_string_arg(FlMethodCall* method_call,
                                           const char* key,
                                           const char* fallback) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return fallback;
  }
  const char* text = fl_value_get_string(value);
  return *text == '\0' ? fallback : text;
}

static void close_notification(GDBusConnection* connection, guint32 id) {
  g_dbus_connection_call(
      connection, kNotificationBusName, kNotificationObjectPath,
      kNotificationBusName, "CloseNotification", g_variant_new("(u)", id),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr, nullptr);
}

static void notification_signal_cb(GDBusConnection* connection,
                                   const gchar* sender_name,
                                   const gchar* object_path,
                                   const gchar* interface_name,
                                   const gchar* signal_name,
                                   GVariant* parameters,
                                   gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->notifications_shutdown) {
    return;
  }
  guint32 id;
  if (g_strcmp0(signal_name, "NotificationClosed") == 0) {
    if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(uu)"))) {
      return;
    }
    guint32 reason;
    g_variant_get(parameters, "(uu)", &id, &reason);
    g_hash_table_remove(self->notification_urls, GUINT_TO_POINTER(id));
    return;
  }
  if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(us)"))) {
    return;
  }
  const gchar* action;
  g_variant_get(parameters, "(u&s)", &id, &action);
  const char* url = static_cast<const char*>(
      g_hash_table_lookup(self->notification_urls, GUINT_TO_POINTER(id)));
  if (g_strcmp0(action, "default") != 0 || url == nullptr) {
    return;
  }
  if (self->window != nullptr) {
    gtk_window_deiconify(self->window);
    gtk_window_present(self->window);
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "url", fl_value_new_string(url));
    fl_method_channel_invoke_method(self->notification_channel,
                                   "deadlineNotificationTapped", args,
                                   nullptr, nullptr, nullptr);
  }
  close_notification(connection, id);
  g_hash_table_remove(self->notification_urls, GUINT_TO_POINTER(id));
}

static void notification_request_complete(NotificationRequest* request,
                                          gboolean shown) {
  g_autoptr(FlValue) result = fl_value_new_bool(shown);
  fl_method_call_respond_success(request->method_call, result, nullptr);
  g_object_unref(request->method_call);
  g_application_release(G_APPLICATION(request->application));
  g_object_unref(request->application);
  g_free(request);
}

static void notify_deadline_cb(GObject* object,
                               GAsyncResult* result,
                               gpointer user_data) {
  NotificationRequest* request = static_cast<NotificationRequest*>(user_data);
  MyApplication* self = request->application;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
  if (reply == nullptr) {
    notification_request_complete(request, FALSE);
    return;
  }
  guint32 id;
  g_variant_get(reply, "(u)", &id);
  gboolean shown = id != 0 && !self->notifications_shutdown &&
                   self->window != nullptr;
  if (shown) {
    g_hash_table_insert(
        self->notification_urls, GUINT_TO_POINTER(id),
        g_strdup(notification_string_arg(request->method_call, "url", "")));
  } else if (id != 0) {
    close_notification(G_DBUS_CONNECTION(object), id);
  }
  notification_request_complete(request, shown);
}

static void notify_deadline(NotificationRequest* request) {
  MyApplication* self = request->application;
  const char* title =
      notification_string_arg(request->method_call, "title", "課題期限");
  const char* body = notification_string_arg(
      request->method_call, "body", "提出期限を検出しました");
  g_autofree gchar* escaped_body = g_markup_escape_text(body, -1);
  const gchar* app_icon = "";
  g_autofree gchar* icon_uri = nullptr;
  if (gtk_icon_theme_has_icon(gtk_icon_theme_get_default(), APPLICATION_ID)) {
    app_icon = APPLICATION_ID;
  } else {
    g_autofree gchar* icon_path = get_bundle_icon_path();
    if (icon_path != nullptr) {
      icon_uri = g_filename_to_uri(icon_path, nullptr, nullptr);
      if (icon_uri != nullptr) {
        app_icon = icon_uri;
      }
    }
  }
  const gchar* actions[] = {"default", "開く", nullptr};
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&hints, "{sv}", "desktop-entry",
                       g_variant_new_string(APPLICATION_ID));
  g_variant_builder_add(&hints, "{sv}", "urgency", g_variant_new_byte(1));
  g_dbus_connection_call(
      self->notification_connection, kNotificationBusName,
      kNotificationObjectPath, kNotificationBusName, "Notify",
      g_variant_new("(susss@as@a{sv}i)", "More Better Gakujo", 0,
                    app_icon, title, escaped_body,
                    g_variant_new_strv(actions, -1),
                    g_variant_builder_end(&hints), -1),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
      notify_deadline_cb, request);
}

static void notification_bus_cb(GObject* object,
                                GAsyncResult* result,
                                gpointer user_data) {
  NotificationRequest* request = static_cast<NotificationRequest*>(user_data);
  MyApplication* self = request->application;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  if (connection == nullptr || self->notifications_shutdown) {
    notification_request_complete(request, FALSE);
    return;
  }
  if (self->notification_connection == nullptr) {
    self->notification_connection = g_steal_pointer(&connection);
    self->notification_action_subscription =
        g_dbus_connection_signal_subscribe(
            self->notification_connection, kNotificationBusName,
            kNotificationBusName, "ActionInvoked", kNotificationObjectPath,
            nullptr, G_DBUS_SIGNAL_FLAGS_NONE, notification_signal_cb, self,
            nullptr);
    self->notification_closed_subscription =
        g_dbus_connection_signal_subscribe(
            self->notification_connection, kNotificationBusName,
            kNotificationBusName, "NotificationClosed", kNotificationObjectPath,
            nullptr, G_DBUS_SIGNAL_FLAGS_NONE, notification_signal_cb, self,
            nullptr);
  }
  notify_deadline(request);
}

static void notification_method_call_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "requestPermission") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    fl_method_call_respond_success(method_call, result, nullptr);
  } else if (g_strcmp0(method, "takePendingNotificationUrl") == 0) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "notifyDeadline") == 0) {
    if (self->notifications_shutdown) {
      g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
      fl_method_call_respond_success(method_call, result, nullptr);
      return;
    }
    NotificationRequest* request = g_new0(NotificationRequest, 1);
    request->application = MY_APPLICATION(g_object_ref(self));
    request->method_call = FL_METHOD_CALL(g_object_ref(method_call));
    // Wait for the notification ID before shutdown so it can be closed too.
    g_application_hold(G_APPLICATION(self));
    if (self->notification_connection != nullptr) {
      notify_deadline(request);
    } else {
      g_bus_get(G_BUS_TYPE_SESSION, nullptr, notification_bus_cb, request);
    }
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

static void shutdown_notifications(MyApplication* self) {
  self->notifications_shutdown = TRUE;
  if (self->notification_connection != nullptr) {
    GHashTableIter iter;
    gpointer id;
    g_hash_table_iter_init(&iter, self->notification_urls);
    while (g_hash_table_iter_next(&iter, &id, nullptr)) {
      close_notification(self->notification_connection, GPOINTER_TO_UINT(id));
    }
    // The process exits right after shutdown; send the queued closes first.
    g_dbus_connection_flush_sync(self->notification_connection, nullptr,
                                 nullptr);
    g_dbus_connection_signal_unsubscribe(
        self->notification_connection, self->notification_action_subscription);
    g_dbus_connection_signal_unsubscribe(
        self->notification_connection, self->notification_closed_subscription);
    g_clear_object(&self->notification_connection);
  }
  g_clear_pointer(&self->notification_urls, g_hash_table_unref);
}

static void secret_service_status_complete(FlMethodCall* method_call,
                                           const char* status) {
  g_autoptr(FlValue) result = fl_value_new_string(status);
  fl_method_call_respond_success(method_call, result, nullptr);
  g_object_unref(method_call);
}

static void secret_service_activatable_cb(GObject* object,
                                          GAsyncResult* result,
                                          gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
  if (reply == nullptr) {
    secret_service_status_complete(method_call, "unknown");
    return;
  }
  g_auto(GStrv) names = nullptr;
  g_variant_get(reply, "(^as)", &names);
  for (guint i = 0; names[i] != nullptr; i++) {
    if (g_strcmp0(names[i], "org.freedesktop.secrets") == 0) {
      secret_service_status_complete(method_call, "activatable");
      return;
    }
  }
  secret_service_status_complete(method_call, "missing");
}

static void secret_service_owner_cb(GObject* object,
                                    GAsyncResult* result,
                                    gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(object), result, &error);
  if (reply == nullptr) {
    secret_service_status_complete(method_call, "unknown");
    return;
  }
  gboolean has_owner;
  g_variant_get(reply, "(b)", &has_owner);
  if (has_owner) {
    secret_service_status_complete(method_call, "running");
    return;
  }
  g_dbus_connection_call(
      G_DBUS_CONNECTION(object), "org.freedesktop.DBus",
      "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListActivatableNames",
      nullptr, G_VARIANT_TYPE("(as)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr,
      secret_service_activatable_cb, method_call);
}

static void secret_service_bus_cb(GObject* object,
                                  GAsyncResult* result,
                                  gpointer user_data) {
  FlMethodCall* method_call = FL_METHOD_CALL(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_finish(result, &error);
  if (connection == nullptr) {
    secret_service_status_complete(method_call, "unknown");
    return;
  }
  g_dbus_connection_call(
      connection, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner",
      g_variant_new("(s)", "org.freedesktop.secrets"), G_VARIANT_TYPE("(b)"),
      G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, secret_service_owner_cb, method_call);
}

static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "secretServiceStatus") == 0) {
    g_bus_get(G_BUS_TYPE_SESSION, nullptr, secret_service_bus_cb,
              g_object_ref(method_call));
  } else if (g_strcmp0(method, "waitUntilShown") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  } else if (self->window_shown) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    fl_method_call_respond_success(method_call, result, nullptr);
  } else {
    g_ptr_array_add(self->pending_window_calls, g_object_ref(method_call));
  }
}

static void complete_window_calls(MyApplication* self, gboolean shown) {
  g_autoptr(FlValue) result = fl_value_new_bool(shown);
  for (guint i = 0; i < self->pending_window_calls->len; i++) {
    FlMethodCall* method_call =
        FL_METHOD_CALL(g_ptr_array_index(self->pending_window_calls, i));
    fl_method_call_respond_success(method_call, result, nullptr);
  }
  g_ptr_array_set_size(self->pending_window_calls, 0);
}

static void restore_window_state(GtkWindow* window, MyApplication* self) {
  gint width;
  gint height;
  gtk_window_get_default_size(window, &width, &height);
  self->window_state = static_cast<GdkWindowState>(0);
  self->window_state_saved = FALSE;
  self->normal_window_position_valid = FALSE;

  g_autofree gchar* path = g_build_filename(
      g_get_user_config_dir(), APPLICATION_ID, "window-state.ini", nullptr);
  g_autoptr(GKeyFile) state = g_key_file_new();
  if (g_key_file_load_from_file(state, path, G_KEY_FILE_NONE, nullptr)) {
    g_autoptr(GError) error = nullptr;
    gint saved_width = g_key_file_get_integer(state, "window", "width", &error);
    gint saved_height = 0;
    if (error == nullptr) {
      saved_height = g_key_file_get_integer(state, "window", "height", &error);
    }
    if (error == nullptr && saved_width >= 960 && saved_height >= 600 &&
        saved_width <= 16384 && saved_height <= 16384) {
      width = saved_width;
      height = saved_height;
      if (g_key_file_get_boolean(state, "window", "maximized", nullptr)) {
        self->window_state = GDK_WINDOW_STATE_MAXIMIZED;
      }
    }
  }

  GdkGeometry hints = {};
  hints.min_width = 960;
  hints.min_height = 600;
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = nullptr;
  if (display != nullptr) {
    monitor = gdk_display_get_primary_monitor(display);
    if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
      monitor = gdk_display_get_monitor(display, 0);
    }
  }
  if (monitor != nullptr) {
    GdkRectangle workarea;
    gdk_monitor_get_workarea(monitor, &workarea);
    if (workarea.width > 0 && workarea.height > 0) {
      width = MIN(width, workarea.width);
      height = MIN(height, workarea.height);
      hints.min_width = MIN(hints.min_width, workarea.width);
      hints.min_height = MIN(hints.min_height, workarea.height);
    }
  }
  self->normal_window_width = width;
  self->normal_window_height = height;
  gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE);
  gtk_window_set_default_size(window, width, height);
#ifdef GDK_WINDOWING_X11
  if (display != nullptr && GDK_IS_X11_DISPLAY(display)) {
    g_autoptr(GError) error = nullptr;
    gint x = g_key_file_get_integer(state, "window", "x", &error);
    gint y = 0;
    if (error == nullptr) {
      y = g_key_file_get_integer(state, "window", "y", &error);
    }
    if (error == nullptr) {
      for (gint i = 0; i < gdk_display_get_n_monitors(display); i++) {
        GdkRectangle workarea;
        gdk_monitor_get_workarea(gdk_display_get_monitor(display, i), &workarea);
        // Use wide arithmetic for coordinates read from the state file.
        if (workarea.width > 0 && workarea.height > 0 &&
            static_cast<gint64>(x) + width > workarea.x &&
            static_cast<gint64>(workarea.x) + workarea.width > x &&
            static_cast<gint64>(y) + MIN(32, height) > workarea.y &&
            static_cast<gint64>(workarea.y) + workarea.height > y) {
          self->normal_window_x = x;
          self->normal_window_y = y;
          self->normal_window_position_valid = TRUE;
          gtk_window_move(window, x, y);
          break;
        }
      }
    }
  }
#endif
  if (self->window_state & GDK_WINDOW_STATE_MAXIMIZED) {
    gtk_window_maximize(window);
  }
}

static void save_window_state(MyApplication* self) {
  // Both delete-event and destroy can run for the same close.
  if (self->window_state_saved) {
    return;
  }
  self->window_state_saved = TRUE;

  g_autofree gchar* dir =
      g_build_filename(g_get_user_config_dir(), APPLICATION_ID, nullptr);
  if (g_mkdir_with_parents(dir, 0700) != 0) {
    return;
  }
  g_autofree gchar* path = g_build_filename(dir, "window-state.ini", nullptr);
  g_autoptr(GKeyFile) state = g_key_file_new();
  g_key_file_set_integer(state, "window", "width", self->normal_window_width);
  g_key_file_set_integer(state, "window", "height", self->normal_window_height);
  if (self->normal_window_position_valid) {
    g_key_file_set_integer(state, "window", "x", self->normal_window_x);
    g_key_file_set_integer(state, "window", "y", self->normal_window_y);
  }
  g_key_file_set_boolean(state, "window", "maximized",
                         (self->window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0);
  g_key_file_save_to_file(state, path, nullptr);
}

static void window_size_allocate_cb(GtkWidget* window,
                                    GtkAllocation* allocation,
                                    MyApplication* self) {
  if (!(self->window_state & (GDK_WINDOW_STATE_MAXIMIZED |
                             GDK_WINDOW_STATE_FULLSCREEN |
                             GDK_WINDOW_STATE_ICONIFIED))) {
    gtk_window_get_size(GTK_WINDOW(window), &self->normal_window_width,
                        &self->normal_window_height);
  }
}

static gboolean window_configure_cb(GtkWidget* window,
                                    GdkEventConfigure* event,
                                    MyApplication* self) {
  if (!(self->window_state & (GDK_WINDOW_STATE_MAXIMIZED |
                             GDK_WINDOW_STATE_FULLSCREEN |
                             GDK_WINDOW_STATE_ICONIFIED))) {
    gtk_window_get_position(GTK_WINDOW(window), &self->normal_window_x,
                            &self->normal_window_y);
    self->normal_window_position_valid = TRUE;
  }
  return FALSE;
}

static gboolean window_state_cb(GtkWidget* window,
                                GdkEventWindowState* event,
                                MyApplication* self) {
  self->window_state = event->new_window_state;
  return FALSE;
}

static gboolean window_delete_cb(GtkWidget* window,
                                 GdkEvent* event,
                                 MyApplication* self) {
  save_window_state(self);
  return FALSE;
}

static void window_destroy_cb(GtkWidget* window, MyApplication* self) {
  save_window_state(self);
  self->window = nullptr;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  // Let GTK map and paint the window before a waiting keyring access can
  // block the main loop with its unlock prompt.
  g_timeout_add_full(
      G_PRIORITY_DEFAULT, 200,
      [](gpointer user_data) -> gboolean {
        MyApplication* self = MY_APPLICATION(user_data);
        self->window_shown = TRUE;
        if (self->pending_window_calls != nullptr) {
          complete_window_calls(self, TRUE);
        }
        return G_SOURCE_REMOVE;
      },
      g_object_ref(self), g_object_unref);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_deiconify(self->window);
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  if (gtk_icon_theme_has_icon(gtk_icon_theme_get_default(), APPLICATION_ID)) {
    gtk_window_set_icon_name(window, APPLICATION_ID);
    gtk_window_set_default_icon_name(APPLICATION_ID);
  } else {
    g_autofree gchar* icon_path = get_bundle_icon_path();
    if (icon_path != nullptr) {
      g_autoptr(GError) error = nullptr;
      gtk_window_set_icon_from_file(window, icon_path, &error);
      g_clear_error(&error);
      gtk_window_set_default_icon_from_file(icon_path, &error);
    }
  }
  self->window = window;
  self->window_shown = FALSE;
  g_signal_connect_object(window, "destroy", G_CALLBACK(window_destroy_cb),
                          self, static_cast<GConnectFlags>(0));
  g_signal_connect_object(window, "size-allocate",
                          G_CALLBACK(window_size_allocate_cb), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(window, "window-state-event",
                          G_CALLBACK(window_state_cb), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(window, "configure-event",
                          G_CALLBACK(window_configure_cb), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(window, "delete-event", G_CALLBACK(window_delete_cb),
                          self, static_cast<GConnectFlags>(0));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "More Better Gakujo");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "More Better Gakujo");
  }

  gtk_window_set_default_size(window, 1280, 800);
  restore_window_state(window, self);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  g_autoptr(FlStandardMethodCodec) notification_codec =
      fl_standard_method_codec_new();
  g_clear_object(&self->notification_channel);
  self->notification_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "net.yoshida.morebettergakujo/notifications",
      FL_METHOD_CODEC(notification_codec));
  fl_method_channel_set_method_call_handler(
      self->notification_channel, notification_method_call_cb, self, nullptr);
  g_clear_object(&self->window_channel);
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "net.yoshida.morebettergakujo/window",
      FL_METHOD_CODEC(notification_codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_cb, self, nullptr);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  shutdown_notifications(MY_APPLICATION(application));

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  shutdown_notifications(self);
  if (self->pending_window_calls != nullptr) {
    complete_window_calls(self, FALSE);
    g_clear_pointer(&self->pending_window_calls, g_ptr_array_unref);
  }
  if (self->window_channel != nullptr) {
    fl_method_channel_set_method_call_handler(
        self->window_channel, nullptr, nullptr, nullptr);
    g_clear_object(&self->window_channel);
  }
  if (self->notification_channel != nullptr) {
    fl_method_channel_set_method_call_handler(
        self->notification_channel, nullptr, nullptr, nullptr);
    g_clear_object(&self->notification_channel);
  }
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_window_calls = g_ptr_array_new_with_free_func(g_object_unref);
  self->notification_urls =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr, g_free);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     kApplicationFlags, nullptr));
}
