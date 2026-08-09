#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>

#include <limits>
#include <map>
#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT kFirstDeadlineNotificationId = 2;
constexpr UINT kDeadlineNotificationCallbackMessage = WM_APP + 1;
UINT next_deadline_notification_id = kFirstDeadlineNotificationId;
std::map<UINT, std::string> deadline_notification_urls;

constexpr bool IsDeadlineNotificationDismissed(UINT callback_message) {
  return callback_message == NIN_BALLOONTIMEOUT ||
         callback_message == NIN_BALLOONHIDE;
}

static_assert(IsDeadlineNotificationDismissed(NIN_BALLOONTIMEOUT));
static_assert(IsDeadlineNotificationDismissed(NIN_BALLOONHIDE));
static_assert(!IsDeadlineNotificationDismissed(NIN_BALLOONSHOW));

std::optional<UINT> NextDeadlineNotificationId() {
  const UINT first_candidate = next_deadline_notification_id;
  do {
    const UINT candidate = next_deadline_notification_id;
    next_deadline_notification_id =
        candidate == (std::numeric_limits<UINT>::max)()
            ? kFirstDeadlineNotificationId
            : candidate + 1;
    if (deadline_notification_urls.find(candidate) ==
        deadline_notification_urls.end()) {
      return candidate;
    }
  } while (next_deadline_notification_id != first_candidate);

  return std::nullopt;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring(value.begin(), value.end());
  }
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), size);
  if (!wide.empty() && wide.back() == L'\0') {
    wide.pop_back();
  }
  return wide;
}

std::string StringArg(
    const flutter::EncodableMap& args,
    const char* key,
    const char* fallback) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return value->empty() ? fallback : *value;
  }
  return fallback;
}

void CopyWideString(wchar_t* destination,
                    size_t destination_count,
                    const std::wstring& value) {
  if (destination_count == 0) {
    return;
  }
  wcsncpy_s(destination, destination_count, value.c_str(), _TRUNCATE);
}

bool ShowDeadlineNotification(HWND hwnd,
                              const std::wstring& title,
                              const std::wstring& body,
                              const std::string& url) {
  const std::optional<UINT> notification_id = NextDeadlineNotificationId();
  if (!notification_id) {
    return false;
  }

  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = hwnd;
  data.uID = *notification_id;
  data.uFlags = NIF_ICON | NIF_TIP | NIF_INFO | NIF_MESSAGE;
  data.uCallbackMessage = kDeadlineNotificationCallbackMessage;
  data.hIcon = LoadIcon(nullptr, IDI_INFORMATION);
  CopyWideString(data.szTip, ARRAYSIZE(data.szTip), L"More Better Gakujo");
  CopyWideString(data.szInfoTitle, ARRAYSIZE(data.szInfoTitle), title);
  CopyWideString(data.szInfo, ARRAYSIZE(data.szInfo), body);
  data.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;

  BOOL notification_shown = Shell_NotifyIconW(NIM_MODIFY, &data);
  if (!notification_shown) {
    notification_shown = Shell_NotifyIconW(NIM_ADD, &data);
  }
  if (notification_shown) {
    deadline_notification_urls[*notification_id] = url;
  }

  return notification_shown != FALSE;
}

void DeleteDeadlineNotification(HWND hwnd, UINT notification_id) {
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = hwnd;
  data.uID = notification_id;
  Shell_NotifyIconW(NIM_DELETE, &data);
  deadline_notification_urls.erase(notification_id);
}

void DeleteAllDeadlineNotifications(HWND hwnd) {
  while (!deadline_notification_urls.empty()) {
    const UINT notification_id = deadline_notification_urls.begin()->first;
    DeleteDeadlineNotification(hwnd, notification_id);
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  auto notifications_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "net.yoshida.morebettergakujo/notifications",
          &flutter::StandardMethodCodec::GetInstance());
  notifications_channel->SetMethodCallHandler(
      [hwnd = GetHandle()](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "requestPermission") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "notifyDeadline") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          std::string title = "課題期限";
          std::string body = "提出期限を検出しました";
          std::string url;
          if (args) {
            title = StringArg(*args, "title", title.c_str());
            body = StringArg(*args, "body", body.c_str());
            url = StringArg(*args, "url", "");
          }
          const bool notification_shown =
              ShowDeadlineNotification(hwnd, Utf8ToWide(title),
                                       Utf8ToWide(body), url);
          result->Success(flutter::EncodableValue(notification_shown));
          return;
        }
        if (call.method_name() == "takePendingNotificationUrl") {
          result->Success(flutter::EncodableValue());
          return;
        }
        result->NotImplemented();
      });
  notification_channel_ = std::move(notifications_channel);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  DeleteAllDeadlineNotifications(GetHandle());
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kDeadlineNotificationCallbackMessage) {
    const UINT notification_id = static_cast<UINT>(wparam);
    const UINT callback_message = static_cast<UINT>(lparam);
    if (callback_message == NIN_BALLOONUSERCLICK) {
      const auto url = deadline_notification_urls.find(notification_id);
      if (url != deadline_notification_urls.end()) {
        ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
        if (notification_channel_) {
          notification_channel_->InvokeMethod(
              "deadlineNotificationTapped",
              std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                  {flutter::EncodableValue("url"),
                   flutter::EncodableValue(url->second)}}));
        }
      }
      DeleteDeadlineNotification(hwnd, notification_id);
      return 0;
    }
    if (IsDeadlineNotificationDismissed(callback_message)) {
      DeleteDeadlineNotification(hwnd, notification_id);
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
