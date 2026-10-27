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
