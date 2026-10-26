import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bundled_secure_storage.dart';
import 'migrating_secure_storage.dart';

class SecureStorageFactory {
  const SecureStorageFactory._();

  static const _macosCurrentAccountName =
      'net.yoshida.morebettergakujoFlutter.secure_storage.v2';
  static const _macosBundleKey = 'more_better_gakujo_secure_storage_bundle_v1';
  static const _macosMigrationMarkerKey =
      'more_better_gakujo_migration_completed_v1';
  // Ad-hoc signed updates can require the user to approve Keychain access.
  static const _macosStorageOperationTimeout = Duration(minutes: 2);

  static const FlutterSecureStorage _macosStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: _macosCurrentAccountName,
      usesDataProtectionKeychain: false,
    ),
  );

  static final BundledSecureStorage _macosBundledStorage = BundledSecureStorage(
    storage: _macosStorage,
    bundleKey: _macosBundleKey,
  );

  static const FlutterSecureStorage _macosLegacyClassicStorage =
      FlutterSecureStorage(
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: false,
    ),
  );

  static final FlutterSecureStorage _macosMigratingStorage =
      MigratingSecureStorage(
    primary: _macosBundledStorage,
    fallback: MigratingSecureStorage(
      primary: _macosStorage,
      // Direct GitHub releases are ad-hoc signed. The data-protection
      // keychain requires the restricted keychain-access-groups entitlement
      // and a provisioning profile, so every unsigned-distribution fallback
      // must stay on the traditional macOS keychain.
      fallback: _macosLegacyClassicStorage,
      deleteFallbackAfterMigration: false,
      operationTimeout: _macosStorageOperationTimeout,
    ),
    deleteFallbackAfterMigration: false,
    migrationMarkerKey: _macosMigrationMarkerKey,
    operationTimeout: _macosStorageOperationTimeout,
  );

  static FlutterSecureStorage create() {
    if (Platform.isMacOS) {
      if (_isFlutterTest) {
        return _macosStorage;
      }
      return _macosMigratingStorage;
    }
    // The plugin's defaults delete every stored value (login, 2FA, settings,
    // history) when one entry cannot be decrypted, and drop old keys before a
    // cipher migration is committed. Fail the read instead; callers already
    // fall back per key and report unreadable data.
    return const FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
    );
  }

  static bool get _isFlutterTest {
    if (kReleaseMode) {
      return false;
    }
    return Platform.resolvedExecutable.contains('flutter_tester') ||
        Platform.environment['FLUTTER_TEST'] == 'true';
  }

  static void resetMacosCache() {
    // The macOS bundled storage caches the decoded bundle in memory; drop it
    // so recovery flows re-read from the keychain instead of serving a stale
    // (possibly empty) cached bundle.
    _macosBundledStorage.clearCache();
  }

  static Future<void> resetStorage() {
    if (Platform.isMacOS) {
      return resetMacosStorage();
    }
    return resetNonMacosStorage(create());
  }

  @visibleForTesting
  static Future<void> resetNonMacosStorage(FlutterSecureStorage storage) {
    return storage.deleteAll();
  }

  static Future<void> resetMacosStorage() async {
    if (!Platform.isMacOS) {
      return;
    }

    Object? primaryError;
    StackTrace? primaryStackTrace;
    resetMacosCache();

    try {
      await _macosMigratingStorage.deleteAll();
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }

    resetMacosCache();
    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }
  }
}
