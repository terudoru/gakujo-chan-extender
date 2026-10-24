#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <cstring>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";
constexpr const wchar_t kWindowPlacementRegKey[] =
    L"Software\\Yoshida\\MoreBetterGakujo";
constexpr const wchar_t kWindowPlacementRegValue[] = L"WindowPlacement";
constexpr int kMinWindowWidth = 960;
constexpr int kMinWindowHeight = 600;
constexpr DWORD kWindowPlacementVersion = 1;

struct SavedWindowPlacement {
  DWORD version;
  UINT dpi;
  WINDOWPLACEMENT placement;
};

struct TitleStripVisibility {
  RECT strip;
  bool visible;
};

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

void SetMinimumWindowSize(HWND hwnd, MINMAXINFO* min_max_info) {
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;
  min_max_info->ptMinTrackSize.x = Scale(kMinWindowWidth, scale_factor);
  min_max_info->ptMinTrackSize.y = Scale(kMinWindowHeight, scale_factor);
}

BOOL CALLBACK CheckTitleStrip(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto* visibility = reinterpret_cast<TitleStripVisibility*>(data);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  RECT intersection = {};
  if (GetMonitorInfoW(monitor, &info)) {
    RECT strip = visibility->strip;
    // WINDOWPLACEMENT uses workspace coordinates, not screen coordinates.
    OffsetRect(&strip, info.rcWork.left - info.rcMonitor.left,
                info.rcWork.top - info.rcMonitor.top);
    if (IntersectRect(&intersection, &strip, &info.rcWork) &&
        intersection.right - intersection.left >= 100) {
      visibility->visible = true;
      return FALSE;
    }
  }
  return TRUE;
}

bool HasVisibleTitleStrip(const RECT& rect) {
  if (rect.right <= rect.left || rect.bottom <= rect.top) {
    return false;
  }
  TitleStripVisibility visibility = {rect, false};
  if (static_cast<LONGLONG>(rect.bottom) - rect.top > 32) {
    visibility.strip.bottom = rect.top + 32;
  }
  EnumDisplayMonitors(nullptr, nullptr, CheckTitleStrip,
                       reinterpret_cast<LPARAM>(&visibility));
  return visibility.visible;
}

int RestoreWindowPlacement(HWND hwnd) {
  SavedWindowPlacement saved = {};
  DWORD placement_size = sizeof(saved);
  if (RegGetValueW(HKEY_CURRENT_USER, kWindowPlacementRegKey,
                   kWindowPlacementRegValue, RRF_RT_REG_BINARY, nullptr,
                   &saved, &placement_size) != ERROR_SUCCESS) {
    return SW_SHOWNORMAL;
  }
  WINDOWPLACEMENT placement = {};
  UINT saved_dpi = 0;
  if (placement_size == sizeof(placement)) {
    // Legacy values have no DPI metadata; preserve their physical pixels.
    std::memcpy(&placement, &saved, sizeof(placement));
  } else if (placement_size == sizeof(saved) &&
             saved.version == kWindowPlacementVersion && saved.dpi > 0 &&
             saved.dpi <= static_cast<UINT>(MAXLONG)) {
    placement = saved.placement;
    saved_dpi = saved.dpi;
  } else {
    return SW_SHOWNORMAL;
  }
  if (placement.length != sizeof(placement)) {
    return SW_SHOWNORMAL;
  }

  RECT& rect = placement.rcNormalPosition;
  const LONGLONG width = static_cast<LONGLONG>(rect.right) - rect.left;
  const LONGLONG height = static_cast<LONGLONG>(rect.bottom) - rect.top;
  HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONULL);
  if (!monitor || width <= 0 || width > MAXLONG || height <= 0 ||
      height > MAXLONG) {
    return SW_SHOWNORMAL;
  }
  if (saved_dpi != 0) {
    const UINT target_dpi = FlutterDesktopGetDpiForMonitor(monitor);
    if (target_dpi == 0 || target_dpi > static_cast<UINT>(MAXLONG)) {
      return SW_SHOWNORMAL;
    }
    const int scaled_width = MulDiv(static_cast<int>(width),
                                    static_cast<int>(target_dpi),
                                    static_cast<int>(saved_dpi));
    const int scaled_height = MulDiv(static_cast<int>(height),
                                     static_cast<int>(target_dpi),
                                     static_cast<int>(saved_dpi));
    if (scaled_width <= 0 || scaled_height <= 0 ||
        static_cast<LONGLONG>(rect.left) + scaled_width > MAXLONG ||
        static_cast<LONGLONG>(rect.top) + scaled_height > MAXLONG) {
      return SW_SHOWNORMAL;
    }
    rect.right = rect.left + scaled_width;
    rect.bottom = rect.top + scaled_height;
  }
  if (!HasVisibleTitleStrip(rect)) {
    return SW_SHOWNORMAL;
  }

  if (placement.showCmd == SW_SHOWMINIMIZED || placement.showCmd == SW_MINIMIZE) {
    placement.showCmd = SW_SHOWNORMAL;
  }
  const int show_command = static_cast<int>(placement.showCmd);
  // Keep the window hidden until Flutter's first-frame callback calls Show().
  placement.showCmd = SW_HIDE;
  return SetWindowPlacement(hwnd, &placement) ? show_command : SW_SHOWNORMAL;
}

void SaveWindowPlacement(HWND hwnd) {
  SavedWindowPlacement saved = {};
  saved.version = kWindowPlacementVersion;
  saved.dpi = FlutterDesktopGetDpiForMonitor(
      MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));
  saved.placement.length = sizeof(saved.placement);
  if (saved.dpi == 0 || !GetWindowPlacement(hwnd, &saved.placement)) {
    return;
  }

  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kWindowPlacementRegKey, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  RegSetValueExW(key, kWindowPlacementRegValue, 0, REG_BINARY,
                 reinterpret_cast<const BYTE*>(&saved),
                 static_cast<DWORD>(sizeof(saved)));
  RegCloseKey(key);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);
  show_command_ = RestoreWindowPlacement(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, show_command_);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      SaveWindowPlacement(hwnd);
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }
    case WM_GETMINMAXINFO:
      SetMinimumWindowSize(
          hwnd, reinterpret_cast<MINMAXINFO*>(lparam));
      return 0;

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
