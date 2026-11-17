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
  g_autoptr(GHashTable) decisions =
      g_hash_table_ref(webview_permission_decisions(view));
  GtkWidget *dialog = show_webview_permission_dialog(
      view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
      kPermissionMicrophone);
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
  const bool remembered = response == GTK_RESPONSE_ACCEPT || response == GTK_RESPONSE_REJECT;
  g_assert_cmpint(webview_permission_decision(
      decisions, "https://example.edu", kPermissionMicrophone), ==,
      remembered ? (response == GTK_RESPONSE_ACCEPT ? 1 : 0) : -1);
  if (remembered) {
    g_assert_null(show_webview_permission_dialog(
        view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
        kPermissionMicrophone));
    g_assert_cmpuint(request->allowed, ==, response == GTK_RESPONSE_ACCEPT ? 2 : 0);
    g_assert_cmpuint(request->denied, ==, response == GTK_RESPONSE_ACCEPT ? 0 : 2);
  }
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

static void session_scope_test() {
  auto *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  g_object_ref_sink(view);
  GHashTable *decisions = webview_permission_decisions(view);
  remember_webview_permission(decisions, "https://example.edu",
      kPermissionCamera | kPermissionMicrophone, true);
  g_assert_cmpint(webview_permission_decision(
      decisions, "https://example.edu", kPermissionCamera), ==, 1);
  g_assert_cmpint(webview_permission_decision(
      decisions, "https://example.edu", kPermissionMicrophone), ==, 1);
  g_assert_cmpint(webview_permission_decision(
      decisions, "https://example.edu", kPermissionGeolocation), ==, -1);
  g_assert_cmpint(webview_permission_decision(
      decisions, "https://other.edu", kPermissionCamera), ==, -1);
  remember_webview_permission(decisions, "https://example.edu",
      kPermissionMicrophone, false);
  g_assert_cmpint(webview_permission_decision(decisions, "https://example.edu",
      kPermissionCamera | kPermissionMicrophone), ==, 0);
  gtk_widget_destroy(GTK_WIDGET(view));
  g_object_unref(view);
  view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  g_object_ref_sink(view);
  g_assert_cmpint(webview_permission_decision(webview_permission_decisions(view),
      "https://example.edu", kPermissionCamera), ==, -1);
  gtk_widget_destroy(GTK_WIDGET(view));
  g_object_unref(view);
}

static void obscured_test(gconstpointer value) {
  const bool already_open = GPOINTER_TO_INT(value);
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  auto *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  auto *request = static_cast<TestPermissionRequest *>(
      g_object_new(test_permission_request_get_type(), nullptr));
  if (already_open) {
    g_assert_nonnull(show_webview_permission_dialog(
        view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
        kPermissionGeolocation));
  }
  set_webview_permission_obscured(view, true);
  if (!already_open) {
    g_assert_null(show_webview_permission_dialog(
        view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
        kPermissionGeolocation));
  }
  g_assert_cmpuint(request->denied, ==, 1);
  g_assert_cmpint(webview_permission_decision(webview_permission_decisions(view),
      "https://example.edu", kPermissionGeolocation), ==, -1);
  set_webview_permission_obscured(view, false);
  GtkWidget *dialog = show_webview_permission_dialog(
      view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
      kPermissionGeolocation);
  g_assert_nonnull(dialog);
  gtk_dialog_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
  g_assert_cmpuint(request->allowed, ==, 1);
  gtk_widget_destroy(window);
  g_object_unref(request);
}

static void obscured_keeps_choice_test() {
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  auto *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  GHashTable *decisions = webview_permission_decisions(view);
  remember_webview_permission(decisions, "https://example.edu",
                              kPermissionGeolocation, true);
  auto *request = static_cast<TestPermissionRequest *>(
      g_object_new(test_permission_request_get_type(), nullptr));
  set_webview_permission_obscured(view, true);
  g_assert_null(show_webview_permission_dialog(
      view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
      kPermissionGeolocation));
  g_assert_cmpuint(request->denied, ==, 1);
  g_assert_cmpint(webview_permission_decision(
      decisions, "https://example.edu", kPermissionGeolocation), ==, 1);
  set_webview_permission_obscured(view, false);
  g_assert_null(show_webview_permission_dialog(
      view, WEBKIT_PERMISSION_REQUEST(request), "https://example.edu",
      kPermissionGeolocation));
  g_assert_cmpuint(request->allowed, ==, 1);
  gtk_widget_destroy(window);
  g_object_unref(request);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/permission/descriptions", descriptions_test);
  g_test_add_func("/permission/origin", origin_test);
  g_test_add_func("/permission/unknown", unknown_request_test);
  g_test_add_func("/permission/session-scope", session_scope_test);
  g_test_add_func("/permission/obscured-keeps-choice", obscured_keeps_choice_test);
  g_test_add_data_func("/permission/obscured", GINT_TO_POINTER(FALSE), obscured_test);
  g_test_add_data_func("/permission/obscure-open-dialog", GINT_TO_POINTER(TRUE),
                       obscured_test);
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
