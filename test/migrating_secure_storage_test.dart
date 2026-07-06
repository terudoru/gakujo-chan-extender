import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/migrating_secure_storage.dart';

void main() {
  test('read prefers primary values', () async {
    final primary = _MemorySecureStorage({'token': 'primary'});
    final fallback = _MemorySecureStorage({'token': 'fallback'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.read(key: 'token'), 'primary');
    expect(primary.values['token'], 'primary');
    expect(fallback.values['token'], 'fallback');
  });

  test('read migrates fallback values into primary storage', () async {
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'fallback'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.read(key: 'token'), 'fallback');
    expect(primary.values['token'], 'fallback');
    expect(fallback.values.containsKey('token'), isFalse);
  });

  test('read migrates values through layered fallback stores', () async {
    final primary = _MemorySecureStorage();
    final middle = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'legacy'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: MigratingSecureStorage(
        primary: middle,
        fallback: fallback,
      ),
    );

    expect(await storage.read(key: 'token'), 'legacy');
    expect(primary.values['token'], 'legacy');
    expect(middle.values.containsKey('token'), isFalse);
    expect(fallback.values.containsKey('token'), isFalse);
  });

  test('readKeys avoids fallback stores when primary has requested keys',
      () async {
    final primary = _MemorySecureStorage({
      'login': 'student',
      'password': 'secret',
    });
    final fallback = _MemorySecureStorage({
      'login': 'old',
      'password': 'old-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'student', 'password': 'secret'});
    expect(primary.readAllCount, 0);
    expect(primary.readKeys, ['login', 'password']);
    expect(fallback.readAllCount, 0);
    expect(fallback.readKeys, isEmpty);
  });

  test('readKeys does not depend on primary readAll', () async {
    final primary = _MemorySecureStorage({
      'login': 'student',
      'password': 'secret',
    })
      ..readAllError = StateError('readAll unavailable');
    final fallback = _MemorySecureStorage({
      'login': 'old',
      'password': 'old-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'student', 'password': 'secret'});
    expect(primary.readAllCount, 0);
    expect(fallback.readAllCount, 0);
    expect(fallback.readKeys, isEmpty);
  });

  test('readKeys migrates only missing requested keys from fallback', () async {
    final primary = _MemorySecureStorage({'login': 'student'});
    final fallback = _MemorySecureStorage({
      'login': 'old',
      'password': 'legacy-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'student', 'password': 'legacy-secret'});
    expect(primary.values, {'login': 'student', 'password': 'legacy-secret'});
    expect(fallback.values, {'login': 'old'});
    expect(fallback.readKeys, ['password']);
  });

  test('readAll merges values and lets primary win', () async {
    final primary = _MemorySecureStorage({'token': 'primary'});
    final fallback = _MemorySecureStorage({
      'token': 'fallback',
      'legacy': 'migrated',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.readAll(), {
      'token': 'primary',
      'legacy': 'migrated',
    });
    expect(primary.values, {
      'token': 'primary',
      'legacy': 'migrated',
    });
    expect(fallback.values, {'token': 'fallback'});
  });

  test('primary read failure is rethrown when fallback is empty', () async {
    final primary = _MemorySecureStorage()..readError = StateError('denied');
    final fallback = _MemorySecureStorage();
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(storage.read(key: 'token'), throwsA(isA<StateError>()));
  });

  test('write stores primary value and removes stale fallback value', () async {
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'old'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    await storage.write(key: 'token', value: 'new');

    expect(primary.values['token'], 'new');
    expect(fallback.values.containsKey('token'), isFalse);
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage([Map<String, String>? initial])
      : values = Map<String, String>.from(initial ?? const {});

  final Map<String, String> values;
  Object? readError;
  Object? readAllError;
  int readAllCount = 0;
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
    final error = readError;
    if (error != null) {
      throw error;
    }
    readKeys.add(key);
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
    final error = readAllError ?? readError;
    if (error != null) {
      throw error;
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

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.clear();
  }
}
