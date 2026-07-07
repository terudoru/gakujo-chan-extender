import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/bundled_secure_storage.dart';

void main() {
  test('stores multiple logical keys in one physical secure-storage item',
      () async {
    final backing = _MemorySecureStorage();
    final storage = BundledSecureStorage(
      storage: backing,
      bundleKey: 'bundle',
    );

    await storage.write(key: 'login', value: 'student');
    await storage.write(key: 'password', value: 'secret');

    expect(await storage.read(key: 'login'), 'student');
    expect(await storage.read(key: 'password'), 'secret');
    expect(backing.values.keys, ['bundle']);
  });

  test('keeps concurrent writes from overwriting each other', () async {
    final backing = _MemorySecureStorage();
    final storage = BundledSecureStorage(
      storage: backing,
      bundleKey: 'bundle',
    );

    await Future.wait([
      storage.write(key: 'login', value: 'student'),
      storage.write(key: 'password', value: 'secret'),
      storage.write(key: '2fa', value: 'BASE32'),
    ]);

    expect(await storage.readAll(), {
      'login': 'student',
      'password': 'secret',
      '2fa': 'BASE32',
    });
    expect(backing.readKeys.where((key) => key == 'bundle').length, 3);
  });

  test('delete updates only the requested logical key', () async {
    final backing = _MemorySecureStorage();
    final storage = BundledSecureStorage(
      storage: backing,
      bundleKey: 'bundle',
    );

    await storage.write(key: 'login', value: 'student');
    await storage.write(key: 'password', value: 'secret');
    await storage.delete(key: 'login');

    expect(await storage.readAll(), {'password': 'secret'});
    expect(await storage.containsKey(key: 'login'), isFalse);
    expect(await storage.containsKey(key: 'password'), isTrue);
  });

  test('concurrent pending reads return independent map snapshots', () async {
    final backing = _DelayedReadSecureStorage('{"login":"student"}');
    final storage = BundledSecureStorage(
      storage: backing,
      bundleKey: 'bundle',
    );

    final firstRead = storage.readAll();
    final secondRead = storage.readAll();
    backing.completeRead();

    final first = await firstRead;
    final second = await secondRead;
    first['login'] = 'changed';

    expect(second, {'login': 'student'});
    expect(await storage.readAll(), {'login': 'student'});
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage([Map<String, String>? initial])
      : values = Map<String, String>.from(initial ?? const {});

  final Map<String, String> values;
  final List<String> readKeys = [];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readKeys.add(key);
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class _DelayedReadSecureStorage extends FlutterSecureStorage {
  _DelayedReadSecureStorage(this.value);

  final String value;
  final _readCompleter = Completer<void>();

  void completeRead() {
    _readCompleter.complete();
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _readCompleter.future;
    return value;
  }
}
