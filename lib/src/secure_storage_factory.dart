import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageFactory {
  const SecureStorageFactory._();

  static FlutterSecureStorage create() {
    if (Platform.isMacOS) {
      return const FlutterSecureStorage(
        mOptions: MacOsOptions(
          usesDataProtectionKeychain: false,
        ),
      );
    }
    return const FlutterSecureStorage();
  }
}
