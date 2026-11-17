#include "../src/webview/webview_permission_dialog.h"

typedef struct {
  GObject parent_instance;
  guint allowed;
  guint denied;
} TestPermissionRequest;

typedef struct { GObjectClass parent_class; } TestPermissionRequestClass;

static void permission_iface_init(WebKitPermissionRequestIface *iface) {
  iface->allow = [](WebKitPermissionRequest *request) {
    ++reinterpret_cast<TestPermissionRequest *>(request)->allowed;
  };
  iface->deny = [](WebKitPermissionRequest *request) {
    ++reinterpret_cast<TestPermissionRequest *>(request)->denied;
  };
}

G_DEFINE_TYPE_WITH_CODE(TestPermissionRequest, test_permission_request,
    G_TYPE_OBJECT, G_IMPLEMENT_INTERFACE(WEBKIT_TYPE_PERMISSION_REQUEST,
                                         permission_iface_init))

static void test_permission_request_class_init(TestPermissionRequestClass *) {}
static void test_permission_request_init(TestPermissionRequest *) {}

static void descriptions_test() {
  g_assert_cmpstr(webview_permission_description(kPermissionCamera), ==,
                  "カメラの使用");
  g_assert_cmpstr(webview_permission_description(kPermissionMicrophone), ==,
                  "マイクの使用");
  g_assert_cmpstr(webview_permission_description(
      kPermissionCamera | kPermissionMicrophone), ==, "カメラとマイクの使用");
  g_assert_cmpstr(webview_permission_description(kPermissionGeolocation), ==,
                  "位置情報の取得");
  g_assert_cmpstr(webview_permission_description(kPermissionNotifications), ==,
                  "通知の表示");
  g_assert_null(webview_permission_description(0));
  g_assert_null(webview_permission_description(16));
}

static void origin_test() {
  g_autofree gchar *origin = webview_permission_page_origin(
      "https://user:secret@example.edu:8443/path?token=value#fragment");
  g_assert_cmpstr(origin, ==, "https://example.edu:8443");
  g_assert_null(webview_permission_page_origin(nullptr));
  g_assert_null(webview_permission_page_origin("about:blank"));
  g_assert_null(webview_permission_page_origin("file:///tmp/page.html"));
}

static void response_test(gconstpointer value) {
  const int response = GPOINTER_TO_INT(value);
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  auto *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  auto *request = static_cast<TestPermissionRequest *>(
      g_object_new(test_permission_request_get_type(), nullptr));
  GtkWidget *dialog = show_webview_permission_dialog(
      view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
      "マイクの使用");
  g_assert_nonnull(dialog);
  g_assert_true(gtk_window_get_modal(GTK_WINDOW(dialog)));
  g_assert_true(gtk_window_get_transient_for(GTK_WINDOW(dialog)) ==
                GTK_WINDOW(window));
  if (response == GTK_RESPONSE_NONE)
    g_signal_emit_by_name(view, "load-changed", WEBKIT_LOAD_STARTED);
  else if (response == GTK_RESPONSE_DELETE_EVENT)
    gtk_widget_destroy(window);
  else
    gtk_dialog_response(GTK_DIALOG(dialog), response);
  g_assert_cmpuint(request->allowed, ==, response == GTK_RESPONSE_ACCEPT ? 1 : 0);
  g_assert_cmpuint(request->denied, ==, response == GTK_RESPONSE_ACCEPT ? 0 : 1);
  if (response != GTK_RESPONSE_DELETE_EVENT) gtk_widget_destroy(window);
  g_object_unref(request);
}

static void unknown_request_test() {
  auto *request = static_cast<TestPermissionRequest *>(
      g_object_new(test_permission_request_get_type(), nullptr));
  g_assert_cmpuint(webview_permission_resources(
      WEBKIT_PERMISSION_REQUEST(request)), ==, 0);
  g_object_unref(request);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/permission/descriptions", descriptions_test);
  g_test_add_func("/permission/origin", origin_test);
  g_test_add_func("/permission/unknown", unknown_request_test);
  g_test_add_data_func("/permission/allow", GINT_TO_POINTER(GTK_RESPONSE_ACCEPT),
                       response_test);
  g_test_add_data_func("/permission/deny", GINT_TO_POINTER(GTK_RESPONSE_REJECT),
                       response_test);
  g_test_add_data_func("/permission/navigate", GINT_TO_POINTER(GTK_RESPONSE_NONE),
                       response_test);
  g_test_add_data_func("/permission/close", GINT_TO_POINTER(GTK_RESPONSE_DELETE_EVENT),
                       response_test);
  return g_test_run();
}
