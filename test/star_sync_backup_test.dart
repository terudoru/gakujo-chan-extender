import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

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

class _Transport implements StarSyncTransport {
  final files = <String, List<int>>{};

  @override
  void close() {}

  @override
  Future<void> ensureDirectory(String path) async {}

  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async => [
    for (final path in files.keys)
      if (path.startsWith('$directory/')) StarSyncRemoteEntry(path: path),
  ];

  @override
  Future<StarSyncRemoteObject?> get(String path) async {
    final bytes = files[path];
    return bytes == null ? null : StarSyncRemoteObject(bytes: bytes);
  }

  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    bool createOnly = false,
  }) async {
    if (createOnly && files.containsKey(path)) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.alreadyExists,
        'exists',
      );
    }
    files[path] = List.of(bytes);
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }
}

void main() {
  const config = StarSyncConfig(backend: StarSyncBackend.googleDrive);
  test('backups round trip across devices, enforce account and kind', () async {
    final remote = _Transport();
    var now = DateTime.utc(2026, 1, 1);
    StarSyncEngine make(String account) {
      final storage = _Storage();
      return StarSyncEngine(
        loginId: () => account,
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        googleDriveTransport: () => remote,
        now: () => now,
      );
    }

    final a = make('first');
    final b = make('first');
    final other = make('other');
    await a.setUpWithPairing(config);
    final code = await a.pairingCode();
    await b.joinWithPairingCode(config, code);
    await other.joinWithPairingCode(config, code);
    expect(a.shouldUploadAutomaticBackup(now), isTrue);
    final payload = List<int>.generate(5 * 1024 * 1024, (i) => i % 256);
    await a.uploadBackup(payload);
    expect(a.shouldUploadAutomaticBackup(now), isFalse);
    expect(
      a.shouldUploadAutomaticBackup(now.add(const Duration(hours: 24))),
      isTrue,
    );
    final own = (await a.listBackups()).single;
    expect(own.isThisDevice, isTrue);
    final listed = (await b.listBackups()).single;
    expect(listed.isThisDevice, isFalse);
    expect(listed.deviceId, own.deviceId);
    expect(await b.downloadBackup(own.deviceId), payload);
    await expectLater(
      other.downloadBackup(own.deviceId),
      throwsFormatException,
    );

    final backupPath = 'backups/${own.deviceId}';
    final saved = remote.files[backupPath]!;
    remote.files[backupPath] = remote.files['stars/devices/${own.deviceId}']!;
    await expectLater(b.downloadBackup(own.deviceId), throwsFormatException);
    remote.files[backupPath] = saved;
    await b.deleteDeviceFile(own.deviceId);
    expect(await a.listBackups(), isEmpty);
    now = now.add(const Duration(days: 1));
    await a.uploadBackup([1, 2, 3]);
    await a.resetRemoteWithPairing();
    expect(await a.listBackups(), isEmpty);
    expect(a.shouldUploadAutomaticBackup(now), isTrue);
    a.dispose();
    b.dispose();
    other.dispose();
  });
}
