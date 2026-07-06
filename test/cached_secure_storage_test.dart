import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/cached_secure_storage.dart';

void main() {
  test('read caches the underlying readAll result', () async {
    final delegate = _CountingSecureStorage({
      'one': '1',
      'two': '2',
    });
    final storage = CachedSecureStorage(delegate);

    expect(await storage.read(key: 'one'), '1');
    expect(await storage.read(key: 'two'), '2');
    expect(await storage.read(key: 'missing'), isNull);
    expect(delegate.readAllCount, 1);
    expect(delegate.readCount, 0);
  });

  test('write and delete keep an initialized cache current', () async {
    final delegate = _CountingSecureStorage({'one': '1'});
    final storage = CachedSecureStorage(delegate);

    expect(await storage.read(key: 'one'), '1');
    await storage.write(key: 'two', value: '2');
    await storage.delete(key: 'one');

    expect(await storage.readAll(), {'two': '2'});
    expect(delegate.values, {'two': '2'});
    expect(delegate.readAllCount, 1);
  });

  test('failed initial read is not cached and can be retried', () async {
    final delegate = _CountingSecureStorage({'one': '1'})
      ..failNextReadAll = true;
    final storage = CachedSecureStorage(delegate);

    await expectLater(storage.read(key: 'one'), throwsStateError);
    expect(await storage.read(key: 'one'), '1');
    expect(delegate.readAllCount, 2);
  });

  test('failed initial read can be cached until explicitly cleared', () async {
    final delegate = _CountingSecureStorage({'one': '1'})
      ..failNextReadAll = true;
    final storage = CachedSecureStorage(delegate, cacheErrors: true);

    await expectLater(storage.read(key: 'one'), throwsStateError);
    await expectLater(storage.read(key: 'one'), throwsStateError);
    expect(delegate.readAllCount, 1);

    storage.clearCache();

    expect(await storage.read(key: 'one'), '1');
    expect(delegate.readAllCount, 2);
  });
}

class _CountingSecureStorage extends FlutterSecureStorage {
  _CountingSecureStorage(Map<String, String> initial)
      : values = Map<String, String>.from(initial);

  final Map<String, String> values;
  int readAllCount = 0;
  int readCount = 0;
  bool failNextReadAll = false;

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
    readCount += 1;
    return values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAllCount += 1;
    if (failNextReadAll) {
      failNextReadAll = false;
      throw StateError('keychain access denied');
    }
    return Map<String, String>.from(values);
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
