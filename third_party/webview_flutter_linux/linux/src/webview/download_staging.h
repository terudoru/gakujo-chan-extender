#ifndef WEBVIEW_ALL_LINUX_DOWNLOAD_STAGING_H_
#define WEBVIEW_ALL_LINUX_DOWNLOAD_STAGING_H_

#include <gio/gio.h>
#include <glib-unix.h>
#include <glib/gstdio.h>

#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>
#include <vector>

namespace download_staging {
constexpr const char *kPrefix = "webview-all-download-mbg-";

inline std::string Create(const std::string &root, GError **error) {
  gchar *path = g_strdup_printf("%s/%s%ld-XXXXXX", root.c_str(), kPrefix,
                                static_cast<long>(getpid()));
  if (!g_mkdtemp_full(path, 0700)) {
    g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno), "%s",
                g_strerror(errno));
    g_free(path);
    return {};
  }
  std::string result(path);
  g_free(path);
  return result;
}

inline bool RandomSuffix(const char *suffix) {
  if (std::strlen(suffix) != 6)
    return false;
  for (const char *c = suffix; *c; ++c) {
    if (!g_ascii_isalnum(*c))
      return false;
  }
  return true;
}

inline pid_t OwnerProcess(const char *name) {
  if (!g_str_has_prefix(name, kPrefix))
    return 0;
  const char *number = name + std::strlen(kPrefix);
  if (!g_ascii_isdigit(*number))
    return 0;
  char *end = nullptr;
  errno = 0;
  const long pid = std::strtol(number, &end, 10);
  return errno == 0 && pid > 0 && pid <= G_MAXINT && *end == '-' &&
                 RandomSuffix(end + 1)
             ? static_cast<pid_t>(pid) : 0;
}

inline bool OwnedDirectory(const struct stat &metadata, uid_t user) {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == user;
}

inline bool OlderThan(const struct stat &metadata, gint64 started) {
  const gint64 modified = static_cast<gint64>(metadata.st_mtim.tv_sec) *
                              G_USEC_PER_SEC + metadata.st_mtim.tv_nsec / 1000;
  const gint64 changed = static_cast<gint64>(metadata.st_ctim.tv_sec) *
                             G_USEC_PER_SEC + metadata.st_ctim.tv_nsec / 1000;
  return modified < started && changed < started;
}

inline void Remove(const std::string &root, const std::string &path) {
  struct stat original{};
  if (g_lstat(path.c_str(), &original) != 0 ||
      !OwnedDirectory(original, geteuid()))
    return;
  const std::string detached = Create(root, nullptr);
  if (detached.empty())
    return;
  // Detach first so a late WebKit/worker write cannot recreate the payload.
  if (g_rename(path.c_str(), detached.c_str()) != 0) {
    g_rmdir(detached.c_str());
    return;
  }
  struct stat current{};
  if (g_lstat(detached.c_str(), &current) != 0 ||
      current.st_dev != original.st_dev || current.st_ino != original.st_ino)
    return;
  GDir *directory = g_dir_open(detached.c_str(), 0, nullptr);
  if (!directory)
    return;
  while (const char *name = g_dir_read_name(directory)) {
    // unlink removes files and symlinks, never follows child directories.
    g_unlink((detached + "/" + name).c_str());
  }
  g_dir_close(directory);
  g_rmdir(detached.c_str());
}

inline void Sweep(const std::string &root, gint64 started, bool shutdown) {
  GDir *directory = g_dir_open(root.c_str(), 0, nullptr);
  if (!directory)
    return;
  std::vector<std::string> abandoned;
  while (const char *name = g_dir_read_name(directory)) {
    if (!g_str_has_prefix(name, "webview-all-download-"))
      continue;
    const std::string path = root + "/" + name;
    struct stat metadata{};
    if (g_lstat(path.c_str(), &metadata) != 0 ||
        !OwnedDirectory(metadata, geteuid()))
      continue;
    const pid_t owner = OwnerProcess(name);
    if (owner) {
      if (shutdown) {
        if (owner != getpid())
          continue;
      } else if (!OlderThan(metadata, started) || owner == getpid() ||
                 kill(owner, 0) == 0 || errno != ESRCH) {
        continue;
      }
      abandoned.push_back(path);
    } else if (!shutdown && OlderThan(metadata, started) &&
               g_str_has_prefix(name, "webview-all-download-") &&
               RandomSuffix(name + std::strlen("webview-all-download-"))) {
      // Older releases had no app/process marker; only reclaim empty folders.
      g_rmdir(path.c_str());
    }
  }
  g_dir_close(directory);
  for (const auto &path : abandoned)
    Remove(root, path);
}

class Lifecycle {
public:
  using BeforeQuit = void (*)(GApplication *);
  explicit Lifecycle(GApplication *application,
                     std::string root = g_get_tmp_dir(),
                     gint64 started = g_get_real_time(),
                     BeforeQuit before_quit = nullptr)
      : application_(G_APPLICATION(g_object_ref(application))),
        root_(std::move(root)), started_(started), before_quit_(before_quit) {
    startup_ =
        g_signal_connect(application_, "startup", G_CALLBACK(Startup), this);
    shutdown_ =
        g_signal_connect(application_, "shutdown", G_CALLBACK(Shutdown), this);
    signal_ = g_unix_signal_add(SIGTERM, Terminate, this);
  }
  ~Lifecycle() {
    g_source_remove(signal_);
    g_signal_handler_disconnect(application_, startup_);
    g_signal_handler_disconnect(application_, shutdown_);
    Sweep(root_, started_, true);
    g_object_unref(application_);
  }
  Lifecycle(const Lifecycle &) = delete;
  Lifecycle &operator=(const Lifecycle &) = delete;

private:
  static void Startup(GApplication *, gpointer value) {
    auto *self = static_cast<Lifecycle *>(value);
    Sweep(self->root_, self->started_, false);
  }
  static void Shutdown(GApplication *, gpointer value) {
    auto *self = static_cast<Lifecycle *>(value);
    Sweep(self->root_, self->started_, true);
  }
  static gboolean Terminate(gpointer value) {
    auto *self = static_cast<Lifecycle *>(value);
    g_application_quit(self->application_);
    if (self->before_quit_)
      self->before_quit_(self->application_);
    return G_SOURCE_CONTINUE;
  }
  GApplication *application_;
  std::string root_;
  gint64 started_;
  BeforeQuit before_quit_;
  gulong startup_;
  gulong shutdown_;
  guint signal_;
};
} // namespace download_staging

#endif // WEBVIEW_ALL_LINUX_DOWNLOAD_STAGING_H_
