#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_PERMISSION_DIALOG_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_PERMISSION_DIALOG_H_

#include <webkit2/webkit2.h>

constexpr const char *kPermissionPageOrigin = "mbg-permission-page-origin";
constexpr const char *kPermissionDecisions = "mbg-permission-decisions";
constexpr const char *kPermissionObscured = "mbg-permission-obscured";
constexpr const char *kPermissionDialogView = "mbg-permission-dialog-view";
enum WebViewPermissionResource {
  kPermissionCamera = 1,
  kPermissionMicrophone = 2,
  kPermissionGeolocation = 4,
  kPermissionNotifications = 8,
};

inline guint webview_permission_resources(WebKitPermissionRequest *request) {
  if (WEBKIT_IS_GEOLOCATION_PERMISSION_REQUEST(request))
    return kPermissionGeolocation;
  if (WEBKIT_IS_NOTIFICATION_PERMISSION_REQUEST(request))
    return kPermissionNotifications;
  if (!WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request)) return 0;
  auto *media = WEBKIT_USER_MEDIA_PERMISSION_REQUEST(request);
  if (webkit_user_media_permission_is_for_display_device(media)) return 0;
  guint resources = 0;
  if (webkit_user_media_permission_is_for_video_device(media))
    resources |= kPermissionCamera;
  if (webkit_user_media_permission_is_for_audio_device(media))
    resources |= kPermissionMicrophone;
  return resources;
}

inline const gchar *webview_permission_description(guint resources) {
  switch (resources) {
  case kPermissionCamera: return "カメラの使用";
  case kPermissionMicrophone: return "マイクの使用";
  case kPermissionCamera | kPermissionMicrophone: return "カメラとマイクの使用";
  case kPermissionGeolocation: return "位置情報の取得";
  case kPermissionNotifications: return "通知の表示";
  default: return nullptr;
  }
}

inline gchar *webview_permission_page_origin(const gchar *uri) {
  if (uri == nullptr) return nullptr;
  WebKitSecurityOrigin *origin = webkit_security_origin_new_for_uri(uri);
  const gchar *protocol = webkit_security_origin_get_protocol(origin);
  const gchar *host = webkit_security_origin_get_host(origin);
  gchar *result = nullptr;
  if ((g_strcmp0(protocol, "https") == 0 || g_strcmp0(protocol, "http") == 0) &&
      host != nullptr && *host != '\0')
    result = webkit_security_origin_to_string(origin);
  webkit_security_origin_unref(origin);
  return result;
}

inline GHashTable *webview_permission_decisions(WebKitWebView *view) {
  auto *decisions = static_cast<GHashTable *>(
      g_object_get_data(G_OBJECT(view), kPermissionDecisions));
  if (decisions == nullptr) {
    decisions = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
    g_object_set_data_full(G_OBJECT(view), kPermissionDecisions, decisions,
        [](gpointer value) { g_hash_table_unref(static_cast<GHashTable *>(value)); });
  }
  return decisions;
}

inline gint webview_permission_decision(GHashTable *decisions,
                                        const gchar *origin, guint resources) {
  if (webview_permission_description(resources) == nullptr) return -1;
  bool allowed = true;
  for (guint kind = kPermissionCamera; kind <= kPermissionNotifications; kind <<= 1) {
    if (!(resources & kind)) continue;
    g_autofree gchar *key = g_strdup_printf("%s\n%u", origin, kind);
    const gint value = GPOINTER_TO_INT(g_hash_table_lookup(decisions, key));
    if (value == 1) return 0;
    if (value == 0) allowed = false;
  }
  return allowed ? 1 : -1;
}

inline void remember_webview_permission(GHashTable *decisions, const gchar *origin,
                                        guint resources, bool allowed) {
  for (guint kind = kPermissionCamera; kind <= kPermissionNotifications; kind <<= 1) {
    if (resources & kind)
      g_hash_table_replace(decisions, g_strdup_printf("%s\n%u", origin, kind),
                            GINT_TO_POINTER(allowed ? 2 : 1));
  }
}

inline bool webview_permission_obscured(WebKitWebView *view) {
  return g_object_get_data(G_OBJECT(view), kPermissionObscured) != nullptr;
}

struct WebViewPermissionDialog {
  WebKitPermissionRequest *request;
  GHashTable *decisions;
  gchar *origin;
  guint resources;
  bool completed = false;
  guint timeout = 0;
};

inline void webview_permission_dialog_destroy(GtkWidget *dialog, gpointer value) {
  auto *data = static_cast<WebViewPermissionDialog *>(value);
  g_signal_handlers_disconnect_by_data(dialog, data);
  g_object_set_data(G_OBJECT(dialog), kPermissionDialogView, nullptr);
  g_object_set_data(G_OBJECT(dialog), "mbg-permission-dialog-data", nullptr);
  if (data->timeout) g_source_remove(data->timeout);
  if (!data->completed) webkit_permission_request_deny(data->request);
  g_object_unref(data->request);
  g_hash_table_unref(data->decisions);
  g_free(data->origin);
  delete data;
}

inline void webview_permission_dialog_response(GtkDialog *dialog, gint response,
                                               gpointer value) {
  auto *data = static_cast<WebViewPermissionDialog *>(value);
  data->completed = true;
  if (response == GTK_RESPONSE_ACCEPT || response == GTK_RESPONSE_REJECT) {
    remember_webview_permission(data->decisions, data->origin, data->resources,
                                response == GTK_RESPONSE_ACCEPT);
  }
  if (response == GTK_RESPONSE_ACCEPT)
    webkit_permission_request_allow(data->request);
  else
    webkit_permission_request_deny(data->request);
  gtk_widget_destroy(GTK_WIDGET(dialog));
}

inline void webview_permission_dialog_load_changed(WebKitWebView *,
                                                   WebKitLoadEvent event,
                                                   GtkWidget *dialog) {
  if (event == WEBKIT_LOAD_STARTED) gtk_widget_destroy(dialog);
}

inline gboolean webview_permission_dialog_timeout(gpointer value) {
  auto *dialog = GTK_WIDGET(value);
  auto *data = static_cast<WebViewPermissionDialog *>(
      g_object_get_data(G_OBJECT(dialog), "mbg-permission-dialog-data"));
  data->timeout = 0;
  gtk_widget_destroy(dialog);
  return G_SOURCE_REMOVE;
}

inline void set_webview_permission_obscured(WebKitWebView *view, bool obscured) {
  g_object_set_data(G_OBJECT(view), kPermissionObscured,
                    GINT_TO_POINTER(obscured));
  GList *windows = gtk_window_list_toplevels();
  for (GList *item = windows; item != nullptr; item = item->next)
    g_object_ref(item->data);
  for (GList *item = windows; item != nullptr; item = item->next) {
    auto *dialog = GTK_WIDGET(item->data);
    if (g_object_get_data(G_OBJECT(dialog), kPermissionDialogView) != view)
      continue;
    if (obscured) {
      gtk_widget_hide(dialog);
    } else {
      auto *data = static_cast<WebViewPermissionDialog *>(
          g_object_get_data(G_OBJECT(dialog), "mbg-permission-dialog-data"));
      const gint decision = webview_permission_decision(
          data->decisions, data->origin, data->resources);
      if (decision >= 0)
        gtk_dialog_response(GTK_DIALOG(dialog),
                            decision ? GTK_RESPONSE_ACCEPT : GTK_RESPONSE_REJECT);
      else
        gtk_widget_show_all(dialog);
    }
  }
  g_list_free_full(windows, g_object_unref);
}

inline GtkWidget *show_webview_permission_dialog(WebKitWebView *view,
                                                WebKitPermissionRequest *request,
                                                const gchar *origin,
                                                guint resources) {
  const gchar *description = webview_permission_description(resources);
  GtkWidget *parent = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GTK_IS_WINDOW(parent) || origin == nullptr || description == nullptr) {
    webkit_permission_request_deny(request);
    return nullptr;
  }
  GHashTable *decisions = webview_permission_decisions(view);
  const gint decision = webview_permission_decision(decisions, origin, resources);
  if (decision >= 0 && !webview_permission_obscured(view)) {
    if (decision) webkit_permission_request_allow(request);
    else webkit_permission_request_deny(request);
    return nullptr;
  }
  // WebKit exposes no frame origin here; scope session choices to the page origin.
  GtkWidget *dialog = gtk_message_dialog_new(
      GTK_WINDOW(parent), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
      GTK_BUTTONS_NONE, "%s のページで%sを求めています", origin, description);
  gtk_window_set_title(GTK_WINDOW(dialog), "サイトの権限");
  gtk_window_set_destroy_with_parent(GTK_WINDOW(dialog), TRUE);
  gtk_dialog_add_buttons(GTK_DIALOG(dialog), "許可しない", GTK_RESPONSE_REJECT,
                         "許可", GTK_RESPONSE_ACCEPT, nullptr);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_REJECT);
  auto *data = new WebViewPermissionDialog{
      WEBKIT_PERMISSION_REQUEST(g_object_ref(request)), g_hash_table_ref(decisions),
      g_strdup(origin), resources};
  g_object_set_data(G_OBJECT(dialog), kPermissionDialogView, view);
  g_object_set_data(G_OBJECT(dialog), "mbg-permission-dialog-data", data);
  // WebKitGTK 4.1 has no permission cancellation signal. Bound the hold
  // even if the page stays covered; navigation/destruction also deny it.
  data->timeout = g_timeout_add_seconds(
      120, webview_permission_dialog_timeout, dialog);
  g_signal_connect(dialog, "response",
                   G_CALLBACK(webview_permission_dialog_response), data);
  g_signal_connect(dialog, "destroy",
                   G_CALLBACK(webview_permission_dialog_destroy), data);
  g_signal_connect_object(view, "destroy", G_CALLBACK(gtk_widget_destroy), dialog,
                          G_CONNECT_SWAPPED);
  g_signal_connect_object(view, "load-changed",
                          G_CALLBACK(webview_permission_dialog_load_changed),
                          dialog, static_cast<GConnectFlags>(0));
  if (!webview_permission_obscured(view)) gtk_widget_show_all(dialog);
  return dialog;
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_PERMISSION_DIALOG_H_
