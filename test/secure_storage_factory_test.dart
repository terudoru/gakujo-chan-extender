import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_factory.dart';
import 'package:test/test.dart';

void main() {
  test('create returns the same storage instance in macOS Flutter tests', () {
    final first = SecureStorageFactory.create();
    final second = SecureStorageFactory.create();

    expect(identical(first, second), isTrue);
  });

  test('create uses the v2 macOS keychain options in Flutter tests', () {
    if (!Platform.isMacOS) return;
    final storage = SecureStorageFactory.create();

    expect(storage.mOptions, isA<MacOsOptions>());
    final macosOptions = storage.mOptions as MacOsOptions;
    expect(
      macosOptions.accountName,
      'net.yoshida.morebettergakujoFlutter.secure_storage.v2',
    );
    expect(macosOptions.usesDataProtectionKeychain, isFalse);
  });

  test('resetMacosCache completes without throwing', () {
    expect(SecureStorageFactory.resetMacosCache, returnsNormally);
  });
}
