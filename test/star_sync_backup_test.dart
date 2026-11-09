import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
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
  Future<StarSyncRemoteObject?> get(
    String path, {
    int maxBytes = starSyncDefaultMaxBytes,
  }) async {
    final bytes = files[path];
    if (bytes != null && bytes.length > maxBytes) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.invalidResponse,
        'Response is too large',
      );
    }
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
  test('Google accounts compare without regard to case', () {
    expect(sameGoogleAccount('User@Example.com', ' user@example.com'), isTrue);
    expect(sameGoogleAccount('a@example.com', 'b@example.com'), isFalse);
    expect(sameGoogleAccount(null, 'a@example.com'), isFalse);
    expect(sameGoogleAccount(null, null), isFalse);
  });

  const config = StarSyncConfig();
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
    await a.setUpWithDrive(config);
    await b.setUpWithDrive(config);
    await other.setUpWithDrive(config);
    final payload = List<int>.generate(5 * 1024 * 1024, (i) => i % 256);
    var builds = 0;
    final uploads = await Future.wait([
      a.uploadAutomaticBackupIfDue(() async {
        builds++;
        return payload;
      }),
      a.uploadAutomaticBackupIfDue(() async {
        builds++;
        return payload;
      }),
    ]);
    expect(uploads, [true, false]);
    expect(builds, 1);
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
    now = now.add(const Duration(days: 1));
    await expectLater(
      a.uploadAutomaticBackupIfDue(
        () async => encodePortableSyncBackup({
          'version': 2,
          'messageExcludeKeywords': 'a' * maxGakujoBackupBytes,
        }),
      ),
      throwsA(isA<GakujoBackupImportException>()),
    );
    expect(remote.files[backupPath], saved);
    remote.files[backupPath] = remote.files['stars/devices/${own.deviceId}']!;
    await expectLater(b.downloadBackup(own.deviceId), throwsFormatException);
    remote.files[backupPath] = saved;
    await b.deleteDeviceFile(own.deviceId);
    expect(await a.listBackups(), isEmpty);
    now = now.add(const Duration(days: 1));
    // A snapshot read before an account change must not upload afterwards.
    final staleAccount = a.requireAccount();
    final staleGeneration = a.accountGeneration;
    await a.runAccountChange(() async {});
    await expectLater(
      a.uploadBackup(
        [9],
        expectedAccount: staleAccount,
        expectedGeneration: staleGeneration,
      ),
      throwsA(isA<StarSyncAccountMismatchException>()),
    );
    expect(await a.listBackups(), isEmpty);
    await a.uploadBackup([1, 2, 3]);
    await a.resetRemoteWithDrive();
    expect(await a.listBackups(), isEmpty);
    expect(await a.uploadAutomaticBackupIfDue(() async => [4]), isTrue);
    a.dispose();
    b.dispose();
    other.dispose();
  });
}
