#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>
#include <wincred.h>

#include <memory>
#include <string>
#include <variant>
#include <vector>

#include "flutter_secure_storage_windows_plugin.h"

namespace flutter_secure_storage_windows {
namespace test {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Invoke HandleMethodCall and return true on success, false on error / not-
// implemented.  Optionally captures the success value via |out|.
static bool Invoke(
    FlutterSecureStorageWindowsPlugin& plugin,
    const std::string& method,
    EncodableMap args,
    EncodableValue* out = nullptr) {
  bool succeeded = false;
  plugin.HandleMethodCall(
      MethodCall(method, std::make_unique<EncodableValue>(std::move(args))),
      std::make_unique<MethodResultFunctions<>>(
          [&succeeded, out](const EncodableValue* result) {
            succeeded = true;
            if (out && result) *out = *result;
          },
          /*on_error=*/nullptr,
          /*on_not_implemented=*/nullptr));
  return succeeded;
}

static bool Write(FlutterSecureStorageWindowsPlugin& plugin,
                  const std::string& key, const std::string& value) {
  return Invoke(plugin, "write",
                {{EncodableValue("key"), EncodableValue(key)},
                 {EncodableValue("value"), EncodableValue(value)}});
}

static std::optional<std::string> Read(FlutterSecureStorageWindowsPlugin& plugin,
                                       const std::string& key) {
  EncodableValue out;
  if (!Invoke(plugin, "read", {{EncodableValue("key"), EncodableValue(key)}},
              &out))
    return std::nullopt;
  if (std::holds_alternative<std::string>(out))
    return std::get<std::string>(out);
  return std::nullopt;  // null result == key not present
}

static bool ContainsKey(FlutterSecureStorageWindowsPlugin& plugin,
                        const std::string& key) {
  EncodableValue out;
  Invoke(plugin, "containsKey",
         {{EncodableValue("key"), EncodableValue(key)}}, &out);
  return std::holds_alternative<bool>(out) && std::get<bool>(out);
}

static bool Delete(FlutterSecureStorageWindowsPlugin& plugin,
                   const std::string& key) {
  return Invoke(plugin, "delete",
                {{EncodableValue("key"), EncodableValue(key)}});
}

static bool DeleteAll(FlutterSecureStorageWindowsPlugin& plugin) {
  return Invoke(plugin, "deleteAll", {});
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

class FlutterSecureStorageWindowsPluginTest : public ::testing::Test {
 protected:
  void SetUp() override { DeleteAll(plugin_); }
  void TearDown() override { DeleteAll(plugin_); }

  FlutterSecureStorageWindowsPlugin plugin_;
};

TEST(FlutterSecureStorageWindowsKeyValidationTest, RejectsPathComponentsBeforeStorageAccess) {
  FlutterSecureStorageWindowsPlugin plugin;
  for (const std::string& key : std::vector<std::string>{
           "../outside", "..\\outside", "folder/file", "stream:name",
           std::string("key\0suffix", 10)}) {
    EXPECT_FALSE(Invoke(plugin, "read", {{EncodableValue("key"), EncodableValue(key)}}));
    EXPECT_FALSE(Invoke(plugin, "write", {{EncodableValue("key"), EncodableValue(key)},
                                          {EncodableValue("value"), EncodableValue("synthetic")}}));
    EXPECT_FALSE(Invoke(plugin, "delete", {{EncodableValue("key"), EncodableValue(key)}}));
  }
}

TEST(FlutterSecureStorageWindowsSupportPathTest, FailureStopsAllOperations) {
  FlutterSecureStorageWindowsPlugin plugin;
  int calls = 0;
  plugin.SetSupportPathResolverForTesting([&](std::wstring&) {
    ++calls;
    return static_cast<DWORD>(ERROR_ACCESS_DENIED);
  });
  for (const auto& method : {"read", "write", "delete", "containsKey", "readAll", "deleteAll"}) {
    EXPECT_FALSE(Invoke(plugin, method,
                        {{EncodableValue("key"), EncodableValue("synthetic")},
                         {EncodableValue("value"), EncodableValue("synthetic")}}));
  }
  EXPECT_EQ(calls, 6);
}

TEST(FlutterSecureStorageWindowsSupportPathTest, ReusesTheValidatedPath) {
  wchar_t root[MAX_PATH + 1]{};
  const DWORD length = GetEnvironmentVariableW(L"FSS_TEST_ROOT", root, MAX_PATH + 1);
  ASSERT_GT(length, 0u);
  ASSERT_LE(length, MAX_PATH);
  const std::wstring file = std::wstring(root, length) + L"\\fss_native_test_path_sentinel.secure";
  HANDLE handle = CreateFileW(file.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  ASSERT_NE(handle, INVALID_HANDLE_VALUE);
  CloseHandle(handle);

  FlutterSecureStorageWindowsPlugin plugin;
  int calls = 0;
  plugin.SetSupportPathResolverForTesting([&](std::wstring& path) {
    if (++calls != 1) return static_cast<DWORD>(ERROR_ACCESS_DENIED);
    path.assign(root, length);
    return static_cast<DWORD>(ERROR_SUCCESS);
  });
  EXPECT_TRUE(ContainsKey(plugin, "path_sentinel"));
  EXPECT_EQ(calls, 1);
  EXPECT_TRUE(DeleteFileW(file.c_str()));
}

TEST(FlutterSecureStorageWindowsSupportPathTest, RejectsUnsafeMetadataComponents) {
  FlutterSecureStorageWindowsPlugin plugin;
  for (const auto* invalid : {L"", L" ", L".", L"..", L"... "}) {
    EXPECT_FALSE(plugin.IsSupportPathComponentValidForTesting(invalid));
  }
  for (const auto* valid : {L"net.yoshida", L"More Better Gakujo", L"ACME Inc."}) {
    EXPECT_TRUE(plugin.IsSupportPathComponentValidForTesting(valid));
  }
}

TEST(FlutterSecureStorageWindowsSupportPathTest, UnusableDirectoryStopsAllOperations) {
  wchar_t root[MAX_PATH + 1]{};
  const DWORD length = GetEnvironmentVariableW(L"FSS_TEST_ROOT", root, MAX_PATH + 1);
  ASSERT_GT(length, 0u);
  ASSERT_LE(length, MAX_PATH);
  const std::wstring blocker = std::wstring(root, length) + L"\\path_blocker";
  HANDLE handle = CreateFileW(blocker.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  ASSERT_NE(handle, INVALID_HANDLE_VALUE);
  CloseHandle(handle);

  FlutterSecureStorageWindowsPlugin plugin;
  plugin.SetSupportPathResolverForTesting([&](std::wstring& path) {
    path = blocker + L"\\child";
    return static_cast<DWORD>(ERROR_SUCCESS);
  });
  for (const auto& method : {"read", "write", "delete", "containsKey", "readAll", "deleteAll"}) {
    EXPECT_FALSE(Invoke(plugin, method,
                        {{EncodableValue("key"), EncodableValue("synthetic")},
                         {EncodableValue("value"), EncodableValue("synthetic")}}));
  }
  EXPECT_NE(GetFileAttributesW(blocker.c_str()), INVALID_FILE_ATTRIBUTES);
  EXPECT_TRUE(DeleteFileW(blocker.c_str()));
}

TEST(FlutterSecureStorageWindowsLegacySafetyTest, UnreadableCiphertextFailsWithoutDeletingFiles) {
  wchar_t root[MAX_PATH + 1]{};
  const DWORD length = GetEnvironmentVariableW(L"FSS_TEST_ROOT", root, MAX_PATH + 1);
  ASSERT_GT(length, 0u);
  ASSERT_LE(length, MAX_PATH);
  const std::wstring file = std::wstring(root, length) + L"\\fss_native_test_broken.secure";
  HANDLE handle = CreateFileW(file.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  ASSERT_NE(handle, INVALID_HANDLE_VALUE);
  BYTE bytes[64]{};
  DWORD written = 0;
  ASSERT_TRUE(WriteFile(handle, bytes, sizeof(bytes), &written, nullptr));
  ASSERT_EQ(written, sizeof(bytes));
  CloseHandle(handle);

  FlutterSecureStorageWindowsPlugin plugin;
  int keyReads = 0;
  plugin.SetEncryptionKeyProviderForTesting([&](bool allowCreate, const std::wstring&) -> PBYTE {
    EXPECT_FALSE(allowCreate);
    ++keyReads;
    return nullptr;
  });
  EXPECT_FALSE(Invoke(plugin, "read", {{EncodableValue("key"), EncodableValue("broken")}}));
  EXPECT_FALSE(Invoke(plugin, "readAll", {}));
  EXPECT_EQ(keyReads, 2);
  EXPECT_NE(GetFileAttributesW(file.c_str()), INVALID_FILE_ATTRIBUTES);

  plugin.SetEncryptionKeyProviderForTesting([](bool allowCreate, const std::wstring&) -> PBYTE {
    EXPECT_FALSE(allowCreate);
    return static_cast<PBYTE>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 16));
  });
  EXPECT_FALSE(Invoke(plugin, "read", {{EncodableValue("key"), EncodableValue("broken")}}));
  EXPECT_FALSE(Invoke(plugin, "readAll", {}));
  EXPECT_NE(GetFileAttributesW(file.c_str()), INVALID_FILE_ATTRIBUTES);
  EXPECT_TRUE(DeleteFileW(file.c_str()));
}

TEST(FlutterSecureStorageWindowsLegacySafetyTest, CredentialOnlyReadDoesNotCreateEncryptionKey) {
  FlutterSecureStorageWindowsPlugin plugin;
  bool keyAccessed = false;
  plugin.SetEncryptionKeyProviderForTesting([&](bool, const std::wstring&) -> PBYTE {
    keyAccessed = true;
    return nullptr;
  });
  plugin.SetLegacyReaderForTesting([](const std::string&) -> std::optional<std::string> {
    return "synthetic";
  });
  EXPECT_EQ(Read(plugin, "credential_only"), std::optional<std::string>("synthetic"));
  EXPECT_FALSE(keyAccessed);
}

TEST(FlutterSecureStorageWindowsLegacySafetyTest, EncryptedValueRoundTripsWithSyntheticKey) {
  wchar_t root[MAX_PATH + 1]{};
  const DWORD length = GetEnvironmentVariableW(L"FSS_TEST_ROOT", root, MAX_PATH + 1);
  ASSERT_GT(length, 0u);
  ASSERT_LE(length, MAX_PATH);
  const std::wstring file = std::wstring(root, length) + L"\\fss_native_test_roundtrip.secure";
  ASSERT_EQ(GetFileAttributesW(file.c_str()), INVALID_FILE_ATTRIBUTES);
  FlutterSecureStorageWindowsPlugin plugin;
  plugin.SetEncryptionKeyProviderForTesting([](bool, const std::wstring&) -> PBYTE {
    return static_cast<PBYTE>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 16));
  });
  ASSERT_TRUE(Write(plugin, "roundtrip", "synthetic value"));
  EXPECT_EQ(Read(plugin, "roundtrip"), std::optional<std::string>("synthetic value"));
  EXPECT_TRUE(DeleteFileW(file.c_str()));
}

TEST(FlutterSecureStorageWindowsLegacySafetyTest, BulkReadKeepsFullKeyAndDeleteAllPreservesOtherFiles) {
  wchar_t root[MAX_PATH + 1]{};
  const DWORD length = GetEnvironmentVariableW(L"FSS_TEST_ROOT", root, MAX_PATH + 1);
  ASSERT_GT(length, 0u);
  ASSERT_LE(length, MAX_PATH);
  const std::wstring unrelated = std::wstring(root, length) + L"\\unrelated.secure";
  HANDLE handle = CreateFileW(unrelated.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  ASSERT_NE(handle, INVALID_HANDLE_VALUE);
  CloseHandle(handle);

  FlutterSecureStorageWindowsPlugin plugin;
  plugin.SetEncryptionKeyProviderForTesting([](bool, const std::wstring&) -> PBYTE {
    return static_cast<PBYTE>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 16));
  });
  plugin.SetLegacyEnumerationForTesting([] {});
  plugin.SetLegacyDeleteAllForTesting([] {});
  ASSERT_TRUE(Write(plugin, "dot.secure.inner", "synthetic one"));
  ASSERT_TRUE(Write(plugin, "other", "synthetic two"));
  EncodableValue result;
  ASSERT_TRUE(Invoke(plugin, "readAll", {}, &result));
  const auto* entries = std::get_if<EncodableMap>(&result);
  ASSERT_NE(entries, nullptr);
  EXPECT_EQ(entries->at(EncodableValue("dot.secure.inner")), EncodableValue("synthetic one"));
  EXPECT_EQ(entries->at(EncodableValue("other")), EncodableValue("synthetic two"));
  EXPECT_TRUE(DeleteAll(plugin));
  EXPECT_NE(GetFileAttributesW(unrelated.c_str()), INVALID_FILE_ATTRIBUTES);
  EXPECT_TRUE(DeleteFileW(unrelated.c_str()));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, WriteAndReadRoundTrip) {
  ASSERT_TRUE(Write(plugin_, "key1", "value1"));
  EXPECT_EQ(Read(plugin_, "key1"), "value1");
}

TEST_F(FlutterSecureStorageWindowsPluginTest, LegacyOnlyCredentialUsesBlobSizeAndIsDeleted) {
  wchar_t target[] = L"fss_native_test_legacy_only";
  BYTE value[] = {'a', 'b', 'c'};  // Deliberately has no trailing NUL.
  CREDENTIALW credential = {};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = target;
  credential.CredentialBlobSize = sizeof(value);
  credential.CredentialBlob = value;
  credential.Persist = CRED_PERSIST_SESSION;
  ASSERT_TRUE(CredWriteW(&credential, 0));

  EXPECT_EQ(Read(plugin_, "legacy_only"), std::optional<std::string>("abc"));
  EncodableValue result;
  ASSERT_TRUE(Invoke(plugin_, "readAll", {}, &result));
  const auto* entries = std::get_if<EncodableMap>(&result);
  ASSERT_NE(entries, nullptr);
  EXPECT_EQ(entries->at(EncodableValue("legacy_only")), EncodableValue("abc"));
  ASSERT_TRUE(DeleteAll(plugin_));
  PCREDENTIALW existing = nullptr;
  EXPECT_FALSE(CredReadW(target, CRED_TYPE_GENERIC, 0, &existing));
  if (existing) CredFree(existing);
}

TEST_F(FlutterSecureStorageWindowsPluginTest, ReadMissingKeyReturnsNullopt) {
  EXPECT_EQ(Read(plugin_, "nonexistent"), std::nullopt);
}

TEST_F(FlutterSecureStorageWindowsPluginTest, OverwriteReturnsNewValue) {
  Write(plugin_, "k", "first");
  Write(plugin_, "k", "second");
  EXPECT_EQ(Read(plugin_, "k"), "second");
}

TEST_F(FlutterSecureStorageWindowsPluginTest, ContainsKeyTrueAfterWrite) {
  Write(plugin_, "k", "v");
  EXPECT_TRUE(ContainsKey(plugin_, "k"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, ContainsKeyFalseForMissing) {
  EXPECT_FALSE(ContainsKey(plugin_, "nonexistent"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, DeleteRemovesKey) {
  Write(plugin_, "k", "v");
  ASSERT_TRUE(ContainsKey(plugin_, "k"));
  Delete(plugin_, "k");
  EXPECT_FALSE(ContainsKey(plugin_, "k"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, DeleteNonexistentIsNoOp) {
  EXPECT_TRUE(Delete(plugin_, "never_written"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, DeleteAllClearsAllKeys) {
  Write(plugin_, "a", "1");
  Write(plugin_, "b", "2");
  DeleteAll(plugin_);
  EXPECT_FALSE(ContainsKey(plugin_, "a"));
  EXPECT_FALSE(ContainsKey(plugin_, "b"));
}

TEST_F(FlutterSecureStorageWindowsPluginTest, UnknownMethodReturnsNotImplemented) {
  bool not_implemented_called = false;
  plugin_.HandleMethodCall(
      MethodCall("unknownMethod",
                 std::make_unique<EncodableValue>(EncodableMap{})),
      std::make_unique<MethodResultFunctions<>>(
          /*on_success=*/nullptr,
          /*on_error=*/nullptr,
          [&not_implemented_called]() { not_implemented_called = true; }));
  EXPECT_TRUE(not_implemented_called);
}

}  // namespace test
}  // namespace flutter_secure_storage_windows
