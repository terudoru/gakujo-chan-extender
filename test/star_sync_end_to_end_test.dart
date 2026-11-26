import 'dart:io';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_drive_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_quota_meter.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

import 'support/fake_google_drive.dart';

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

void main() {
  test('Drive syncs stars between two devices', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final drive = FakeGoogleDrive(
        server,
        includeSpaces: false,
        awaitUploadHook: false,
      );
      const config = StarSyncConfig();
      StarSyncTransport transport(StarSyncConfig config) =>
          StarSyncGoogleDriveTransport(
            apiBase: drive.base,
            quotaMeter: StarSyncQuotaMeter(storage: _Storage()),
            accessToken: ({bool forceRefresh = false}) async => 'token',
          );

      final storageA = _Storage();
      final storageB = _Storage();
      final activityA = GakujoActivityStore(secureStorage: storageA);
      final activityB = GakujoActivityStore(secureStorage: storageB);
      final a = StarSyncEngine(
        loginId: () => 'student',
        activityStore: activityA,
        secureStorage: storageA,
        transportFactory: transport,
      );
      final b = StarSyncEngine(
        loginId: () => 'student',
        activityStore: activityB,
        secureStorage: storageB,
        transportFactory: transport,
      );
      try {
        await a.setUpWithDrive(config);
        for (final id in ['3', '4']) {
          await activityA.upsertStarredMessage(
            GakujoStarredMessage(
              keijitype: '1',
              genrecd: '2',
              seqNo: id,
              title: 'Title $id',
              starredAt: DateTime.utc(2026),
            ),
          );
        }
        await a.syncNow();
        await b.setUpWithDrive(config);
        expect(
          (await activityB.loadStarredMessages()).map((e) => e.title).toSet(),
          {'Title 3', 'Title 4'},
        );
        final deviceA =
            (jsonDecode(storageA.values[starSyncStateKey]!) as Map)['deviceId'];
        final original = drive.files.singleWhere(
          (f) => f.name == 'stars/devices/$deviceA',
        );
        final version = original.version;
        await activityA.removeStarredMessage('1|2|3');
        await a.syncNow();
        drive.files.remove(original);
        final replacement = drive.add(original.name, original.bytes)
          ..version = version;
        await b.syncNow();
        expect(drive.counts['GET /drive/v3/files/${replacement.id}'], 1);
        expect(
          (await activityB.loadStarredMessages()).map((e) => e.title).toList(),
          ['Title 4'],
        );
      } finally {
        a.dispose();
        b.dispose();
        await server.close(force: true);
      }
  });

  test('Drive re-reads a replaced keyring with the same version', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final drive = FakeGoogleDrive(
      server,
      includeSpaces: false,
      awaitUploadHook: false,
    );
    final storageA = _Storage();
    final storageB = _Storage();
    StarSyncEngine engine(_Storage storage) => StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => StarSyncGoogleDriveTransport(
        apiBase: drive.base,
        quotaMeter: StarSyncQuotaMeter(storage: _Storage()),
        accessToken: ({bool forceRefresh = false}) async => 'token',
      ),
    );
    final a = engine(storageA);
    var b = engine(storageB);
    try {
      const config = StarSyncConfig();
      await a.setUpWithDrive(config);
      await b.setUpWithDrive(config);
      final original = drive.files.singleWhere(
        (f) => f.name == 'stars/keyring.json',
      );
      final before = jsonDecode(storageB.values[starSyncStateKey]!) as Map;
      b.dispose();
      b = engine(storageB);
      await b.load();
      await a.resetRemoteWithDrive();
      final replacement = drive.files.singleWhere((f) => f.name == original.name);
      expect(replacement.id, isNot(original.id));
      expect(replacement.version, original.version);
      final reads = drive.counts['GET /drive/v3/files/${replacement.id}'] ?? 0;
      await b.syncNow();
      final after = jsonDecode(storageB.values[starSyncStateKey]!) as Map;
      final reset = jsonDecode(storageA.values[starSyncStateKey]!) as Map;
      expect(drive.counts['GET /drive/v3/files/${replacement.id}'], reads + 1);
      expect(after['keyId'], isNot(before['keyId']));
      expect(after['keyId'], reset['keyId']);
      expect(after['dataKey'], reset['dataKey']);
      expect(after['keyringEtag'], '${replacement.id}:${replacement.version}');
      expect(b.status.value.status, StarSyncStatus.ok);
    } finally {
      a.dispose();
      b.dispose();
      await server.close(force: true);
    }
  });
}
