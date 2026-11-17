#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_NAVIGATION_POLICY_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_NAVIGATION_POLICY_H_

#include <webkit2/webkit2.h>

#include <cstring>

inline gboolean navigation_target_is_main_frame(WebKitPolicyDecisionType type,
                                                const gchar *frame_name) {
  if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return FALSE;
  }
  return frame_name == nullptr || *frame_name == '\0' ||
         strcmp(frame_name, "_self") == 0 || strcmp(frame_name, "_top") == 0 ||
         strcmp(frame_name, "_parent") == 0;
}

inline gboolean navigation_is_main_frame(
    WebKitNavigationPolicyDecision *decision, WebKitPolicyDecisionType type) {
  if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return FALSE;
  }
#if WEBKIT_CHECK_VERSION(2, 40, 0)
  WebKitNavigationAction *action =
      webkit_navigation_policy_decision_get_navigation_action(decision);
#endif
#if WEBKIT_CHECK_VERSION(2, 56, 0)
  WebKitFrameInfo *frame = webkit_navigation_action_get_target_frame_info(action);
  if (frame != nullptr) {
    return webkit_frame_info_is_main_frame(frame);
  }
#endif
  // Before 2.56 the target name does not identify the destination frame.
  // WebKit 2.54 retargets named and unnamed iframe loads (even target="frame")
  // to _self, so this fallback cannot identify real subframe navigations.
  // Only new-window actions reliably report false; the app's exact PDF viewer
  // URL exception permits its preview iframe on these older versions.
#if WEBKIT_CHECK_VERSION(2, 40, 0)
  const gchar *frame_name = webkit_navigation_action_get_frame_name(action);
#else
  const gchar *frame_name =
      webkit_navigation_policy_decision_get_frame_name(decision);
#endif
  return navigation_target_is_main_frame(type, frame_name);
}

#endif // WEBVIEW_ALL_LINUX_WEBVIEW_NAVIGATION_POLICY_H_
