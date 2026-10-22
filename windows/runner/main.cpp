#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <roapi.h>
#include <shobjidl.h>

#include <memory>
#include <string>
#include <utility>

#include "app_identity.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

void RegisterUrlProtocol() {
  std::wstring exe_path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(
      nullptr, exe_path.data(), static_cast<DWORD>(exe_path.size()));
  if (length == 0 || length >= exe_path.size()) {
    return;
  }
  exe_path.resize(length);

  constexpr wchar_t key_path[] = L"Software\\Classes\\morebettergakujo";
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key_path, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  constexpr wchar_t description[] = L"URL:More Better Gakujo";
  constexpr wchar_t empty[] = L"";
  RegSetValueExW(key, nullptr, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(description),
                 static_cast<DWORD>(sizeof(description)));
  RegSetValueExW(key, L"URL Protocol", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(empty),
                 static_cast<DWORD>(sizeof(empty)));
  RegCloseKey(key);

  const std::wstring command_key =
      std::wstring(key_path) + L"\\shell\\open\\command";
  if (RegCreateKeyExW(HKEY_CURRENT_USER, command_key.c_str(), 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  const std::wstring command = L"\"" + exe_path + L"\" \"%1\"";
  RegSetValueExW(key, nullptr, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(command.c_str()),
                 static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
}

bool ActivateExistingInstance(const std::string& url) {
  HWND window = nullptr;
  // The owning process may still be creating its window.
  for (int attempt = 0; attempt < 100; ++attempt) {
    window = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"More Better Gakujo");
    if (window) {
      break;
    }
    Sleep(50);
  }
  if (!window) {
    return false;
  }

  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  AllowSetForegroundWindow(process_id);
  ShowWindowAsync(window, SW_RESTORE);
  SetForegroundWindow(window);
  if (url.empty()) {
    return true;
  }

  COPYDATASTRUCT data = {};
  data.dwData = kDeadlineNotificationCopyDataId;
  data.cbData = static_cast<DWORD>(url.size());
  data.lpData = const_cast<char*>(url.data());
  DWORD_PTR result = 0;
  return SendMessageTimeoutW(window, WM_COPYDATA, 0,
                             reinterpret_cast<LPARAM>(&data),
                             SMTO_ABORTIFHUNG | SMTO_BLOCK, 5000, &result) != 0 &&
         result != FALSE;
}

void RegisterAppIdentity() {
  SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);

  const std::wstring key_path =
      std::wstring(L"Software\\Classes\\AppUserModelId\\") + kAppUserModelId;
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key_path.c_str(), 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }

  constexpr wchar_t display_name[] = L"More Better Gakujo";
  RegSetValueExW(key, L"DisplayName", 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(display_name),
                 static_cast<DWORD>(sizeof(display_name)));

  std::wstring exe_path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(
      nullptr, exe_path.data(), static_cast<DWORD>(exe_path.size()));
  std::wstring icon_path;
  if (length > 0 && length < exe_path.size()) {
    exe_path.resize(length);
    const size_t separator = exe_path.find_last_of(L"\\/");
    if (separator != std::wstring::npos) {
      icon_path = exe_path.substr(0, separator + 1) + L"app_icon.png";
    }
  }
  const DWORD attributes = icon_path.empty()
                               ? INVALID_FILE_ATTRIBUTES
                               : GetFileAttributesW(icon_path.c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES &&
      (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
    RegSetValueExW(key, L"IconUri", 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(icon_path.c_str()),
                   static_cast<DWORD>((icon_path.size() + 1) * sizeof(wchar_t)));
  } else {
    RegDeleteValueW(key, L"IconUri");
  }
  RegCloseKey(key);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  RegisterAppIdentity();
  RegisterUrlProtocol();
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  std::string pending_notification_url;
  for (const auto& argument : command_line_arguments) {
    pending_notification_url = DeadlineNotificationUrlFromArgument(argument);
    if (!pending_notification_url.empty()) {
      break;
    }
  }

  HANDLE mutex =
      CreateMutexW(nullptr, TRUE, L"Local\\Yoshida.MoreBetterGakujo.Instance");
  const DWORD mutex_error = GetLastError();
  const std::unique_ptr<void, decltype(&::CloseHandle)> instance_mutex(
      mutex, &::CloseHandle);
  if (!instance_mutex) {
    return EXIT_FAILURE;
  }
  if (mutex_error == ERROR_ALREADY_EXISTS) {
    const DWORD wait_result = WaitForSingleObject(instance_mutex.get(), 0);
    if (wait_result != WAIT_OBJECT_0 && wait_result != WAIT_ABANDONED) {
      return ActivateExistingInstance(pending_notification_url) ? EXIT_SUCCESS
                                                              : EXIT_FAILURE;
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const HRESULT winrt_result = ::RoInitialize(RO_INIT_SINGLETHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, std::move(pending_notification_url));
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"More Better Gakujo", origin, size)) {
    window.Destroy();
    if (SUCCEEDED(winrt_result)) {
      ::RoUninitialize();
    }
    ::CoUninitialize();
    ReleaseMutex(instance_mutex.get());
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  window.Destroy();
  if (SUCCEEDED(winrt_result)) {
    ::RoUninitialize();
  }
  ::CoUninitialize();
  ReleaseMutex(instance_mutex.get());
  return EXIT_SUCCESS;
}
