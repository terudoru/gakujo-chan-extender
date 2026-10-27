#ifndef FLUTTER_PLUGIN_FLUTTER_SECURE_STORAGE_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_SECURE_STORAGE_WINDOWS_PLUGIN_H_

#include <windows.h>

#include <optional>
#include <string>
#ifdef FSS_TESTING
#include <functional>
#include <utility>
#endif

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

namespace flutter_secure_storage_windows {

class FlutterSecureStorageWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterSecureStorageWindowsPlugin();
  virtual ~FlutterSecureStorageWindowsPlugin();

  // Disallow copy and assign.
  FlutterSecureStorageWindowsPlugin(const FlutterSecureStorageWindowsPlugin&) =
      delete;
  FlutterSecureStorageWindowsPlugin& operator=(
      const FlutterSecureStorageWindowsPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  // Public so that it can be exercised directly in native unit tests.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

#ifdef FSS_TESTING
  void SetSupportPathResolverForTesting(
      std::function<DWORD(std::wstring&)> resolver) {
    support_path_resolver_for_testing_ = std::move(resolver);
  }
  bool IsSupportPathComponentValidForTesting(std::wstring value);
#endif

 private:
#ifdef FSS_TESTING
  std::function<DWORD(std::wstring&)> support_path_resolver_for_testing_;
#endif
  std::optional<std::string> GetStringArg(const std::string& param,
                                          const flutter::EncodableMap* args);
  std::optional<std::string> GetValueKey(const flutter::EncodableMap* args);
  std::string RemoveKeyPrefix(const std::string& key);
  std::string GetErrorString(const DWORD& error_code);
  std::string NtStatusToString(const CHAR* operation, NTSTATUS status);
  DWORD GetApplicationSupportPath(std::wstring& path);
  std::wstring SanitizeDirString(std::wstring string);
  bool PathExists(const std::wstring& path);
  bool MakePath(const std::wstring& path);
  void EnsureSupportDirectory(const std::wstring& path);
  PBYTE GetEncryptionKey();
  void Write(const std::string& key, const std::string& val, const std::wstring& path);
  std::optional<std::string> Read(const std::string& key, const std::wstring& path);
  flutter::EncodableMap ReadAll(const std::wstring& path);
  void Delete(const std::string& key, const std::wstring& path);
  void DeleteAll(const std::wstring& path);
  bool ContainsKey(const std::string& key, const std::wstring& path);
};

}  // namespace flutter_secure_storage_windows

#endif  // FLUTTER_PLUGIN_FLUTTER_SECURE_STORAGE_WINDOWS_PLUGIN_H_
