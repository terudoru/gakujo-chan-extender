import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/device_only_secret_storage.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_factory.dart';
import 'package:test/test.dart';

const secret = 'secret';
const physical = '$secret${DeviceOnlySecretStorage.physicalSuffix}';
const normal = KeychainAccessibility.unlocked;
const device = KeychainAccessibility.unlocked_this_device;

void main() {
  late _Storage inner;
  late DeviceOnlySecretStorage storage;
  setUp(() {
    inner = _Storage();
    storage = DeviceOnlySecretStorage(inner: inner, secretKeys: {secret});
  });

  test('non-secret values keep their normal name and accessibility', () async {
    await storage.write(key: 'setting', value: 'value');
    expect(await storage.read(key: 'setting'), 'value');
    expect(inner.values, {(normal, 'setting'): 'value'});
  });

  test('write replaces legacy secret with device-only physical key', () async {
    inner.values[(normal, secret)] = 'old';
    await storage.write(key: secret, value: 'new');
    expect(inner.values, {(device, physical): 'new'});
  });

  test('read migrates a legacy secret', () async {
    inner.values[(normal, secret)] = 'old';
    expect(await storage.read(key: secret), 'old');
    expect(inner.values, {(device, physical): 'old'});
  });

  test('failed legacy deletion does not hide a new value', () async {
    inner.values[(normal, secret)] = 'old';
    inner.failDeleteKey = secret;
    await storage.write(key: secret, value: 'new');
    expect(await storage.read(key: secret), 'new');
    expect(inner.values[(normal, secret)], 'old');
  });

  test('delete removes both copies and containsKey becomes false', () async {
    inner.values.addAll({(normal, secret): 'old', (device, physical): 'new'});
    expect(await storage.containsKey(key: secret), isTrue);
    await storage.delete(key: secret);
    expect(await storage.containsKey(key: secret), isFalse);
    expect(inner.values, isEmpty);
  });

  test(
    'readAll hides physical names and prefers the device-only value',
    () async {
      inner.values.addAll({
        (normal, secret): 'old',
        (device, physical): 'new',
        (normal, 'setting'): 'value',
      });
      expect(await storage.readAll(), {secret: 'new', 'setting': 'value'});
    },
  );

  test('reset deletes both accessibility groups', () async {
    inner.values.addAll({
      (normal, 'setting'): 'value',
      (device, physical): 'new',
    });
    await SecureStorageFactory.resetNonMacosStorage(storage);
    expect(inner.values, isEmpty);
  });

  test(
    'delete attempts legacy cleanup even if physical deletion fails',
    () async {
      inner.values.addAll({(normal, secret): 'old', (device, physical): 'new'});
      inner.failDeleteKey = physical;
      await expectLater(storage.delete(key: secret), throwsStateError);
      expect(inner.values.containsKey((normal, secret)), isFalse);
    },
  );

  test('migration write failure preserves the legacy secret', () async {
    inner.values[(normal, secret)] = 'old';
    inner.failWrite = true;
    expect(await storage.read(key: secret), 'old');
    expect(inner.values, {(normal, secret): 'old'});
  });
}

class _Storage extends FlutterSecureStorage {
  final values = <(KeychainAccessibility, String), String>{};
  String? failDeleteKey;
  bool failWrite = false;

  KeychainAccessibility _accessibility(AppleOptions? options) =>
      options?.accessibility ?? KeychainAccessibility.unlocked;

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
    return values[(_accessibility(iOptions), key)];
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
    if (failWrite) throw StateError('write failed');
    if (value == null) {
      values.remove((_accessibility(iOptions), key));
    } else {
      values[(_accessibility(iOptions), key)] = value;
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
    if (key == failDeleteKey) throw StateError('delete failed');
    // The Darwin plugin deletes the named key across accessibility levels.
    values.removeWhere((entry, _) => entry.$2 == key);
  }

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
    return values.containsKey((_accessibility(iOptions), key));
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
    return {
      for (final entry in values.entries)
        if (entry.key.$1 == _accessibility(iOptions)) entry.key.$2: entry.value,
    };
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
    values.removeWhere((entry, _) => entry.$1 == _accessibility(iOptions));
  }
}
