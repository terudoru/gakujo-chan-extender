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

  static const FlutterSecureStorage _macosLegacyDefaultStorage =
      FlutterSecureStorage();

  static final FlutterSecureStorage _macosMigratingStorage =
      MigratingSecureStorage(
    primary: _macosBundledStorage,
    fallback: MigratingSecureStorage(
      primary: _macosStorage,
      fallback: MigratingSecureStorage(
        primary: _macosLegacyClassicStorage,
        fallback: _macosLegacyDefaultStorage,
        deleteFallbackAfterMigration: false,
      ),
      deleteFallbackAfterMigration: false,
    ),
    deleteFallbackAfterMigration: false,
  );

  static FlutterSecureStorage create() {
    if (Platform.isMacOS) {
      if (_isFlutterTest) {
        return _macosStorage;
      }
      return _macosMigratingStorage;
    }
    return const FlutterSecureStorage();
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
