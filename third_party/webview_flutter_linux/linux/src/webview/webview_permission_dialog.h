#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_PERMISSION_DIALOG_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_PERMISSION_DIALOG_H_

#include <webkit2/webkit2.h>

constexpr const char *kPermissionPageOrigin = "mbg-permission-page-origin";
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

struct WebViewPermissionDialog {
  WebKitPermissionRequest *request;
  bool completed = false;
};

inline void webview_permission_dialog_destroy(GtkWidget *dialog, gpointer value) {
  auto *data = static_cast<WebViewPermissionDialog *>(value);
  g_signal_handlers_disconnect_by_data(dialog, data);
  if (!data->completed) webkit_permission_request_deny(data->request);
  g_object_unref(data->request);
  delete data;
}

inline void webview_permission_dialog_response(GtkDialog *dialog, gint response,
                                               gpointer value) {
  auto *data = static_cast<WebViewPermissionDialog *>(value);
  data->completed = true;
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

inline GtkWidget *show_webview_permission_dialog(WebKitWebView *view,
                                                WebKitPermissionRequest *request,
                                                const gchar *origin,
                                                const gchar *description) {
  GtkWidget *parent = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GTK_IS_WINDOW(parent) || origin == nullptr || description == nullptr) {
    webkit_permission_request_deny(request);
    return nullptr;
  }
  // These WebKit requests expose no frame origin; name the current page and
  // never reuse its choice for a later request from a potentially different frame.
  GtkWidget *dialog = gtk_message_dialog_new(
      GTK_WINDOW(parent), GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
      GTK_BUTTONS_NONE, "%s のページで%sを求めています", origin, description);
  gtk_window_set_title(GTK_WINDOW(dialog), "サイトの権限");
  gtk_window_set_destroy_with_parent(GTK_WINDOW(dialog), TRUE);
  gtk_dialog_add_buttons(GTK_DIALOG(dialog), "許可しない", GTK_RESPONSE_REJECT,
                         "許可", GTK_RESPONSE_ACCEPT, nullptr);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_REJECT);
  auto *data = new WebViewPermissionDialog{WEBKIT_PERMISSION_REQUEST(
      g_object_ref(request))};
  g_signal_connect(dialog, "response",
                   G_CALLBACK(webview_permission_dialog_response), data);
  g_signal_connect(dialog, "destroy",
                   G_CALLBACK(webview_permission_dialog_destroy), data);
  g_signal_connect_object(view, "destroy", G_CALLBACK(gtk_widget_destroy), dialog,
                          G_CONNECT_SWAPPED);
  g_signal_connect_object(view, "load-changed",
                          G_CALLBACK(webview_permission_dialog_load_changed),
                          dialog, static_cast<GConnectFlags>(0));
  gtk_widget_show_all(dialog);
  return dialog;
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_PERMISSION_DIALOG_H_
