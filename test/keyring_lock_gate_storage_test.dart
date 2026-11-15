import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/keyring_lock_gate_storage.dart';

const _operations = [
  'read',
  'write',
  'delete',
  'readAll',
  'deleteAll',
  'containsKey',
  'checkUpgradeStatus',
];

Future<dynamic> _call(FlutterSecureStorage storage, String operation) {
  return switch (operation) {
    'read' => storage.read(key: 'token'),
    'write' => storage.write(key: 'token', value: 'value'),
    'delete' => storage.delete(key: 'token'),
    'readAll' => storage.readAll(),
    'deleteAll' => storage.deleteAll(),
    'containsKey' => storage.containsKey(key: 'token'),
    'checkUpgradeStatus' => storage.checkUpgradeStatus(),
    _ => throw ArgumentError.value(operation),
  };
}

void main() {
  final lockedError = isA<PlatformException>()
      .having((error) => error.code, 'code', 'KeyringLocked')
      .having((error) => error.message, 'message', 'KeyringLocked');

  test('accesses wait for beforeFirstAccess and run in order', () async {
    final ready = Completer<void>();
    final release = Completer<void>();
    final inner = _FakeSecureStorage()..pending = release.future;
    final storage = KeyringLockGateStorage(
      inner: inner,
      beforeFirstAccess: () => ready.future,
    );
    final results = [
      for (final operation in _operations) _call(storage, operation),
    ];

    await Future<void>.delayed(Duration.zero);
    expect(inner.calls, isEmpty);
    ready.complete();
    await Future<void>.delayed(Duration.zero);
    expect(inner.calls, ['read']);
    release.complete();
    await Future.wait(results);
    expect(inner.calls, _operations);
  });

  test(
    'beforeFirstAccess is called only once, including after reopen',
    () async {
      var calls = 0;
      final inner = _FakeSecureStorage();
      final storage = KeyringLockGateStorage(
        inner: inner,
        beforeFirstAccess: () async {
          calls++;
        },
      );

      await Future.wait([
        for (final operation in _operations) _call(storage, operation),
      ]);
      storage.reopen();
      expect(await storage.read(key: 'token'), 'value');
      expect(calls, 1);
      expect(inner.calls, [..._operations, 'read']);
    },
  );

  test('a throwing beforeFirstAccess does not block access', () async {
    var calls = 0;
    final inner = _FakeSecureStorage();
    final storage = KeyringLockGateStorage(
      inner: inner,
      beforeFirstAccess: () {
        calls++;
        throw StateError('Window unavailable');
      },
    );

    expect(await storage.read(key: 'token'), 'value');
    await storage.write(key: 'token', value: 'value');
    expect(calls, 1);
    expect(inner.calls, ['read', 'write']);
  });

  for (final operation in _operations) {
    test(
      '$operation closes the gate on KeyringLocked until reopened',
      () async {
        final error = PlatformException(
          code: 'KeyringLocked',
          message: 'Unlock cancelled',
        );
        final inner = _FakeSecureStorage()..error = error;
        final storage = KeyringLockGateStorage(inner: inner);

        await expectLater(_call(storage, operation), throwsA(same(error)));
        expect(inner.calls, [operation]);

        inner.error = null;
        for (final blocked in _operations) {
          await expectLater(_call(storage, blocked), throwsA(lockedError));
        }
        expect(inner.calls, [operation]);

        storage.reopen();
        await _call(storage, operation);
        expect(inner.calls, [operation, operation]);
      },
    );
  }

  test('other PlatformException codes leave the gate open', () async {
    final error = PlatformException(code: 'StorageUnavailable');
    final inner = _FakeSecureStorage()..error = error;
    final storage = KeyringLockGateStorage(inner: inner);

    for (final operation in _operations) {
      await expectLater(_call(storage, operation), throwsA(same(error)));
    }
    expect(inner.calls, _operations);

    inner.error = null;
    expect(await storage.read(key: 'token'), 'value');
    expect(inner.calls.length, _operations.length + 1);
  });

  test('overlapping accesses show only one unlock attempt', () async {
    final release = Completer<void>();
    final inner = _FakeSecureStorage()
      ..pending = release.future
      ..error = PlatformException(
        code: 'KeyringLocked',
        message: 'KeyringLocked',
      );
    final storage = KeyringLockGateStorage(inner: inner);
    final results = [
      for (final operation in _operations)
        expectLater(_call(storage, operation), throwsA(lockedError)),
    ];

    await Future<void>.delayed(Duration.zero);
    expect(inner.calls, ['read']);
    release.complete();
    await Future.wait(results);
    expect(inner.calls, ['read']);
  });

  test('another KeyringLocked after reopening closes the gate again', () async {
    final error = PlatformException(code: 'KeyringLocked');
    final inner = _FakeSecureStorage()..error = error;
    final storage = KeyringLockGateStorage(inner: inner);

    await expectLater(storage.read(key: 'token'), throwsA(same(error)));
    storage.reopen();
    await expectLater(
      storage.write(key: 'token', value: 'value'),
      throwsA(same(error)),
    );
    await expectLater(storage.delete(key: 'token'), throwsA(lockedError));
    expect(inner.calls, ['read', 'write']);
  });

  test(
    'successful calls preserve inner results and keep the gate open',
    () async {
      final inner = _FakeSecureStorage();
      final storage = KeyringLockGateStorage(inner: inner);

      expect(await storage.read(key: 'token'), 'value');
      await storage.write(key: 'token', value: null);
      await storage.delete(key: 'token');
      expect(await storage.readAll(), {'token': 'value'});
      await storage.deleteAll();
      expect(await storage.containsKey(key: 'token'), isTrue);
      expect(
        await storage.checkUpgradeStatus(),
        SecureStorageUpgradeStatus.unsupported,
      );
      expect(inner.calls, _operations);
    },
  );
}

class _FakeSecureStorage extends FlutterSecureStorage {
  final calls = <String>[];
  PlatformException? error;
  Future<void>? pending;

  Future<void> _beforeAccess(String operation) async {
    calls.add(operation);
    final wait = pending;
    if (wait != null) await wait;
    final failure = error;
    if (failure != null) throw failure;
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
    await _beforeAccess('read');
    return 'value';
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
  }) => _beforeAccess('write');

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _beforeAccess('delete');

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _beforeAccess('readAll');
    return {'token': 'value'};
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _beforeAccess('deleteAll');

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _beforeAccess('containsKey');
    return true;
  }

  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _beforeAccess('checkUpgradeStatus');
    return SecureStorageUpgradeStatus.unsupported;
  }
}
