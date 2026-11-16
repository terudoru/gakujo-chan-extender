#include "../src/webview/webview_context_menu.h"

#include <initializer_list>

static WebKitContextMenu *make_menu(
    std::initializer_list<WebKitContextMenuAction> actions) {
  WebKitContextMenu *menu = webkit_context_menu_new();
  for (WebKitContextMenuAction action : actions) {
    WebKitContextMenuItem *item =
        action == WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION
            ? webkit_context_menu_item_new_separator()
            : webkit_context_menu_item_new_from_stock_action(action);
    webkit_context_menu_append(menu, item);
  }
  return menu;
}

static void assert_actions(
    WebKitContextMenu *menu,
    std::initializer_list<WebKitContextMenuAction> actions) {
  g_assert_cmpuint(webkit_context_menu_get_n_items(menu), ==, actions.size());
  GList *link = webkit_context_menu_get_items(menu);
  for (WebKitContextMenuAction action : actions) {
    g_assert_nonnull(link);
    auto *item = WEBKIT_CONTEXT_MENU_ITEM(link->data);
    g_assert_cmpint(webkit_context_menu_item_get_stock_action(item), ==, action);
    g_assert_cmpint(webkit_context_menu_item_is_separator(item), ==,
                    action == WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION);
    link = link->next;
  }
  g_assert_null(link);
}

static void link_menu_test() {
  g_autoptr(WebKitContextMenu) menu = make_menu({
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_LINK_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_LINK_TO_CLIPBOARD,
  });
  remove_unmanaged_download_items(menu);
  assert_actions(menu, {
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_LINK_TO_CLIPBOARD,
  });
}

static void image_menu_test() {
  g_autoptr(WebKitContextMenu) menu = make_menu({
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_IMAGE_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_IMAGE_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_URL_TO_CLIPBOARD,
  });
  remove_unmanaged_download_items(menu);
  assert_actions(menu, {
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_IMAGE_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_URL_TO_CLIPBOARD,
  });
}

static void combined_menu_test() {
  g_autoptr(WebKitContextMenu) menu = make_menu({
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_LINK_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_LINK_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_LINK_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_IMAGE_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_IMAGE_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_URL_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_VIDEO_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_AUDIO_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
  });
  remove_unmanaged_download_items(menu);
  assert_actions(menu, {
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_LINK_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_LINK_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_IMAGE_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_IMAGE_URL_TO_CLIPBOARD,
  });
}

static void page_menu_test() {
  const auto actions = {
      WEBKIT_CONTEXT_MENU_ACTION_GO_BACK,
      WEBKIT_CONTEXT_MENU_ACTION_GO_FORWARD,
      WEBKIT_CONTEXT_MENU_ACTION_STOP,
      WEBKIT_CONTEXT_MENU_ACTION_RELOAD,
  };
  g_autoptr(WebKitContextMenu) menu = make_menu(actions);
  remove_unmanaged_download_items(menu);
  assert_actions(menu, actions);
}

static void media_menu_test() {
  g_autoptr(WebKitContextMenu) menu = make_menu({
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_VIDEO_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_VIDEO_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_VIDEO_LINK_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_AUDIO_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_AUDIO_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_AUDIO_LINK_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_INSPECT_ELEMENT,
  });
  remove_unmanaged_download_items(menu);
  assert_actions(menu, {
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_VIDEO_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_VIDEO_LINK_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_OPEN_AUDIO_IN_NEW_WINDOW,
      WEBKIT_CONTEXT_MENU_ACTION_COPY_AUDIO_LINK_TO_CLIPBOARD,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_INSPECT_ELEMENT,
  });
}

static void empty_menu_test() {
  g_autoptr(WebKitContextMenu) empty = make_menu({});
  remove_unmanaged_download_items(empty);
  assert_actions(empty, {});

  g_autoptr(WebKitContextMenu) downloads = make_menu({
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_LINK_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_IMAGE_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_VIDEO_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_DOWNLOAD_AUDIO_TO_DISK,
      WEBKIT_CONTEXT_MENU_ACTION_NO_ACTION,
  });
  remove_unmanaged_download_items(downloads);
  assert_actions(downloads, {});
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/context-menu/link", link_menu_test);
  g_test_add_func("/context-menu/image", image_menu_test);
  g_test_add_func("/context-menu/combined", combined_menu_test);
  g_test_add_func("/context-menu/page", page_menu_test);
  g_test_add_func("/context-menu/media", media_menu_test);
  g_test_add_func("/context-menu/empty", empty_menu_test);
  return g_test_run();
}
