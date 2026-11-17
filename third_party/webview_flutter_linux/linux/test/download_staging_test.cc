#include "../src/webview/download_staging.h"

#include <sys/wait.h>
#include <utime.h>

namespace {
class Fixture {
public:
  Fixture() {
    gchar *path = g_dir_make_tmp("mbg-staging-test-XXXXXX", nullptr);
    g_assert_nonnull(path);
    root = path;
    g_free(path);
  }
  ~Fixture() {
    for (auto path = paths.rbegin(); path != paths.rend(); ++path) {
      g_unlink(path->c_str());
      g_rmdir(path->c_str());
    }
    g_rmdir(root.c_str());
  }
  std::string Directory(const std::string &name) {
    const std::string path = root + "/" + name;
    g_assert_cmpint(g_mkdir(path.c_str(), 0700), ==, 0);
    paths.push_back(path);
    return path;
  }
  void File(const std::string &path) {
    g_assert_true(g_file_set_contents(path.c_str(), "partial", -1, nullptr));
    paths.push_back(path);
  }
  std::string root;
  std::vector<std::string> paths;
};

pid_t DeadProcess() {
  const pid_t child = fork();
  g_assert_cmpint(child, >=, 0);
  if (child == 0)
    _exit(0);
  int status = 0;
  while (waitpid(child, &status, 0) < 0)
    g_assert_cmpint(errno, ==, EINTR);
  return child;
}

std::string Name(pid_t pid, const char *suffix) {
  return std::string(download_staging::kPrefix) + std::to_string(pid) + "-" +
         suffix;
}

void TestOwnedNames() {
  g_assert_cmpint(download_staging::OwnerProcess(
                     "webview-all-download-mbg-12-Ab12cd"), ==, 12);
  for (const char *name : {"webview-all-download-test-Ab12cd",
                           "webview-all-download-mbg-0-Ab12cd",
                           "webview-all-download-mbg-12-Ab12cd-extra",
                           "webview-all-download-mbg-12-../../"})
    g_assert_cmpint(download_staging::OwnerProcess(name), ==, 0);
  struct stat metadata{};
  metadata.st_mode = S_IFDIR | 0700;
  metadata.st_uid = geteuid();
  g_assert_true(download_staging::OwnedDirectory(metadata, geteuid()));
  g_assert_false(download_staging::OwnedDirectory(metadata, geteuid() + 1));
  metadata.st_mode = S_IFLNK | 0700;
  g_assert_false(download_staging::OwnedDirectory(metadata, geteuid()));
  metadata.st_mtim = {10, 0};
  metadata.st_ctim = {10, 0};
  g_assert_true(download_staging::OlderThan(metadata, 11 * G_USEC_PER_SEC));
  g_assert_false(download_staging::OlderThan(metadata, 10 * G_USEC_PER_SEC));
  metadata.st_ctim.tv_sec = 12;
  g_assert_false(download_staging::OlderThan(metadata, 11 * G_USEC_PER_SEC));
}

void TestStartupSweep() {
  Fixture fixture;
  const pid_t dead = DeadProcess();
  const std::string stale = fixture.Directory(Name(dead, "Ab12cd"));
  fixture.File(stale + "/payload");
  fixture.File(stale + "/payload.wkdownload");
  const std::string legacy = fixture.Directory("webview-all-download-Ab12cd");
  const std::string nonempty = fixture.Directory("webview-all-download-Bb12cd");
  fixture.File(nonempty + "/payload");
  const std::string live = fixture.Directory(Name(getpid(), "Ab12cd"));
  fixture.File(live + "/payload");
  int alive[2];
  g_assert_cmpint(pipe(alive), ==, 0);
  const pid_t other_process = fork();
  g_assert_cmpint(other_process, >=, 0);
  if (other_process == 0) {
    close(alive[1]);
    char byte;
    read(alive[0], &byte, 1);
    _exit(0);
  }
  close(alive[0]);
  const std::string other_live =
      fixture.Directory(Name(other_process, "Db12cd"));
  fixture.File(other_live + "/payload");
  const std::string unrelated =
      fixture.Directory("webview-all-download-test-Ab12cd");
  const std::string target = fixture.Directory("target");
  fixture.File(target + "/payload");
  const std::string symbolic = fixture.root + "/" + Name(dead, "Bb12cd");
  g_assert_cmpint(symlink(target.c_str(), symbolic.c_str()), ==, 0);
  fixture.paths.push_back(symbolic);
  g_usleep(1000);
  const gint64 started = g_get_real_time();
  g_usleep(1000);
  const std::string recent = fixture.Directory(Name(dead, "Cb12cd"));
  fixture.File(recent + "/payload");
  // Filesystem timestamps may be coarser than the realtime clock.
  const time_t future = static_cast<time_t>(started / G_USEC_PER_SEC + 1);
  struct utimbuf newer{future, future};
  g_assert_cmpint(g_utime(recent.c_str(), &newer), ==, 0);

  download_staging::Sweep(fixture.root, started, false);
  g_assert_false(g_file_test(stale.c_str(), G_FILE_TEST_EXISTS));
  g_assert_false(g_file_test(legacy.c_str(), G_FILE_TEST_EXISTS));
  for (const auto &path : {nonempty, live, other_live, unrelated, target, recent}) {
    g_test_message("Preserving %s", path.c_str());
    g_assert_true(g_file_test(path.c_str(), G_FILE_TEST_IS_DIR));
  }
  g_assert_true(g_file_test(symbolic.c_str(), G_FILE_TEST_IS_SYMLINK));
  g_assert_true(g_file_test((target + "/payload").c_str(), G_FILE_TEST_EXISTS));
  close(alive[1]);
  int status = 0;
  g_assert_cmpint(waitpid(other_process, &status, 0), ==, other_process);
}

void TestShutdownSweep() {
  Fixture fixture;
  GError *error = nullptr;
  const std::string stage = download_staging::Create(fixture.root, &error);
  g_assert_no_error(error);
  g_assert_false(stage.empty());
  fixture.paths.push_back(stage);
  fixture.File(stage + "/payload");
  const std::string other = fixture.Directory(Name(DeadProcess(), "Ab12cd"));
  fixture.File(other + "/payload");
  download_staging::Sweep(fixture.root, g_get_real_time(), true);
  g_assert_false(g_file_test(stage.c_str(), G_FILE_TEST_EXISTS));
  g_assert_true(g_file_test((other + "/payload").c_str(), G_FILE_TEST_EXISTS));
  download_staging::Sweep(fixture.root, g_get_real_time(), true);
}

void RunApplication(bool signal) {
  Fixture fixture;
  struct State {
    GApplication *application;
    Fixture *fixture;
    std::string stage;
    bool signal;
  } state{g_application_new(nullptr, G_APPLICATION_NON_UNIQUE), &fixture, {}, signal};
  {
    download_staging::Lifecycle lifecycle(state.application, fixture.root);
    g_signal_connect(
        state.application, "activate",
        G_CALLBACK(+[](GApplication *app, gpointer value) {
          auto *state = static_cast<State *>(value);
          g_application_hold(app);
          state->stage = download_staging::Create(state->fixture->root, nullptr);
          g_assert_false(state->stage.empty());
          state->fixture->File(state->stage + "/payload");
          g_idle_add(+[](gpointer value) -> gboolean {
            auto *state = static_cast<State *>(value);
            if (state->signal)
              g_assert_cmpint(kill(getpid(), SIGTERM), ==, 0);
            else
              g_application_quit(state->application);
            return G_SOURCE_REMOVE;
          }, value);
        }), &state);
    g_assert_cmpint(g_application_run(state.application, 0, nullptr), ==, 0);
    g_application_release(state.application);
    // Check the shutdown signal, before Lifecycle's fallback destructor cleanup.
    g_assert_false(g_file_test(state.stage.c_str(), G_FILE_TEST_EXISTS));
    GDir *directory = g_dir_open(fixture.root.c_str(), 0, nullptr);
    g_assert_nonnull(directory);
    g_assert_null(g_dir_read_name(directory));
    g_dir_close(directory);
  }
  g_object_unref(state.application);
}

void TestApplicationShutdown() { RunApplication(false); }

void TestSigterm() {
  if (g_test_subprocess()) {
    RunApplication(true);
    return;
  }
  g_test_trap_subprocess(nullptr, 5 * G_USEC_PER_SEC, G_TEST_SUBPROCESS_DEFAULT);
  g_test_trap_assert_passed();
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/staging/owned-names", TestOwnedNames);
  g_test_add_func("/staging/startup-sweep", TestStartupSweep);
  g_test_add_func("/staging/shutdown-sweep", TestShutdownSweep);
  g_test_add_func("/staging/application-shutdown", TestApplicationShutdown);
  g_test_add_func("/staging/sigterm", TestSigterm);
  return g_test_run();
}
