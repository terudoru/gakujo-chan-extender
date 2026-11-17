#ifndef RUNNER_NOTIFICATION_ACTIVATION_H_
#define RUNNER_NOTIFICATION_ACTIVATION_H_

#include <gio/gio.h>

struct NotificationActivation {
  gchar* pending_url;
  gboolean ready;
};

inline bool notification_activation_target(GVariant* target,
                                            const gchar** id,
                                            const gchar** url) {
  if (target == nullptr ||
      !g_variant_is_of_type(target, G_VARIANT_TYPE("(ss)")) ||
      g_variant_get_size(target) > 32768) return false;
  g_variant_get(target, "(&s&s)", id, url);
  return g_uuid_string_is_valid(*id) && **url != '\0';
}

inline bool defer_notification_url(NotificationActivation* activation,
                                    const gchar* url) {
  if (activation->ready) return false;
  g_free(activation->pending_url);
  activation->pending_url = g_strdup(url);
  return true;
}

inline gchar* take_pending_notification_url(NotificationActivation* activation) {
  activation->ready = TRUE;
  return g_steal_pointer(&activation->pending_url);
}

#endif  // RUNNER_NOTIFICATION_ACTIVATION_H_
