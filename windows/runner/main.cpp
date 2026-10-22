#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <roapi.h>
#include <shobjidl.h>

#include "app_identity.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

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

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const HRESULT winrt_result = ::RoInitialize(RO_INIT_SINGLETHREADED);
  RegisterAppIdentity();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"More Better Gakujo", origin, size)) {
    window.Destroy();
    if (SUCCEEDED(winrt_result)) {
      ::RoUninitialize();
    }
    ::CoUninitialize();
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
  return EXIT_SUCCESS;
}
