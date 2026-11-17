#include "../src/webview/webview_find.h"

#include <functional>
#include <vector>

static void wait_for(const std::function<bool()> &condition) {
  bool expired = false;
  const guint timeout = g_timeout_add_seconds(
      15,
      +[](gpointer data) -> gboolean {
        *static_cast<bool *>(data) = true;
        return G_SOURCE_REMOVE;
      },
      &expired);
  while (!condition() && !expired)
    g_main_context_iteration(nullptr, TRUE);
  if (!expired) g_source_remove(timeout);
  g_assert_false(expired);
}

static void total_matches_test() {
  struct Results {
    bool loaded = false;
    const gchar *text = "needle";
    std::vector<guint> counts;
  } results;
  g_autoptr(GtkWidget) window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_object_ref_sink(window);
  WebKitWebView *view = WEBKIT_WEB_VIEW(webkit_web_view_new());
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show_all(window);
  WebKitFindController *controller = webkit_web_view_get_find_controller(view);
  g_signal_connect(view, "load-changed", G_CALLBACK(+[](
      WebKitWebView *, WebKitLoadEvent event, gpointer data) {
    if (event == WEBKIT_LOAD_FINISHED) static_cast<Results *>(data)->loaded = true;
  }), &results);
  g_signal_connect(controller, "found-text", G_CALLBACK(+[](
      WebKitFindController *controller, guint, gpointer data) {
    recount_find_matches(controller, static_cast<Results *>(data)->text);
  }), &results);
  g_signal_connect(controller, "counted-matches", G_CALLBACK(+[](
      WebKitFindController *, guint matches, gpointer data) {
    static_cast<Results *>(data)->counts.push_back(matches);
  }), &results);
  g_signal_connect(controller, "failed-to-find-text", G_CALLBACK(+[](
      WebKitFindController *, gpointer data) {
    static_cast<Results *>(data)->counts.push_back(0);
  }), &results);
  webkit_web_view_load_html(view,
      "<p>needle needle needle needle needle needle needle</p>", nullptr);
  wait_for([&] { return results.loaded; });
  webkit_find_controller_search(controller, results.text,
      WEBKIT_FIND_OPTIONS_CASE_INSENSITIVE | WEBKIT_FIND_OPTIONS_WRAP_AROUND,
      G_MAXUINT);
  wait_for([&] { return results.counts.size() == 1; });
  g_assert_cmpuint(results.counts.back(), ==, 7);
  // Repeat far enough to wrap; selecting one match must never replace the total.
  for (size_t step = 0; step < 10; ++step) {
    webkit_find_controller_search_next(controller);
    wait_for([&] { return results.counts.size() == step + 2; });
    g_assert_cmpuint(results.counts.back(), ==, 7);
  }
  const size_t before_previous = results.counts.size();
  webkit_find_controller_search_previous(controller);
  wait_for([&] { return results.counts.size() == before_previous + 1; });
  g_assert_cmpuint(results.counts.back(), ==, 7);
  results.text = "absent";
  const size_t before_absent = results.counts.size();
  webkit_find_controller_search(controller, results.text,
      WEBKIT_FIND_OPTIONS_WRAP_AROUND, G_MAXUINT);
  wait_for([&] { return results.counts.size() == before_absent + 1; });
  g_assert_cmpuint(results.counts.back(), ==, 0);
  results.text = nullptr;
  webkit_find_controller_search_finish(controller);
  g_signal_handlers_disconnect_by_data(controller, &results);
  g_signal_handlers_disconnect_by_data(view, &results);
  gtk_widget_destroy(window);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/find/total-after-next-previous-wrap", total_matches_test);
  return g_test_run();
}
