// Live WebDAV example (create the parent collection first):
// STAR_SYNC_LIVE_WEBDAV_URL=http://127.0.0.1:8080/dav/ STAR_SYNC_LIVE_WEBDAV_USER=user STAR_SYNC_LIVE_WEBDAV_PASSWORD=password flutter test test/star_sync_live_webdav_test.dart
// The server must require Basic authentication and allow collection creation and deletion.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_webdav_transport.dart';

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

class _Device {
  _Device() : storage = _Storage() {
    activity = GakujoActivityStore(secureStorage: storage);
    engine = StarSyncEngine(activityStore: activity, secureStorage: storage);
  }

  final _Storage storage;
  late final GakujoActivityStore activity;
  late final StarSyncEngine engine;
}

class _Fixture {
  _Fixture() {
    final env = Platform.environment;
    String requiredEnv(String name) {
      final value = env[name];
      if (value == null || value.isEmpty) {
        throw StateError('$name must be set for the live WebDAV test');
      }
      return value;
    }

    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final name =
        'star-sync-live-${DateTime.now().microsecondsSinceEpoch}-$suffix';
    final base = requiredEnv('STAR_SYNC_LIVE_WEBDAV_URL')
        .replaceFirst(RegExp(r'/+$'), '');
    parent = StarSyncWebDavConfig(
      baseUrl: Uri.parse('$base/'),
      username: requiredEnv('STAR_SYNC_LIVE_WEBDAV_USER'),
      password: requiredEnv('STAR_SYNC_LIVE_WEBDAV_PASSWORD'),
    );
    collectionName = name;
    webDav = StarSyncWebDavConfig(
      baseUrl: Uri.parse('$base/$name/'),
      username: parent.username,
      password: parent.password,
    );
    config = StarSyncConfig(backend: StarSyncBackend.webDav, webDav: webDav);
    addTearDown(cleanup);
  }

  late final StarSyncWebDavConfig parent;
  late final String collectionName;
  late final StarSyncWebDavConfig webDav;
  late final StarSyncConfig config;
  final devices = <_Device>[];
  bool _created = false;

  Future<void> createCollection() async {
    final transport = StarSyncWebDavTransport(parent);
    try {
      await transport.ensureDirectory(collectionName);
      _created = true;
    } finally {
      transport.close();
    }
  }

  _Device device() {
    final result = _Device();
    devices.add(result);
    return result;
  }

  Future<void> cleanup() async {
    for (final device in devices) {
      device.engine.dispose();
    }
    if (!_created) return;
    final transport = StarSyncWebDavTransport(webDav);
    try {
      for (final entry in await transport.list('stars/devices')) {
        await transport.delete(entry.path);
      }
      await transport.delete('stars/keyring.json');
    } finally {
      transport.close();
      final client = HttpClient();
      try {
        final request = await client.openUrl('DELETE', webDav.baseUrl);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('${parent.username}:${parent.password}'))}',
        );
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode != HttpStatus.notFound) {
          checkStarSyncStatus(response.statusCode);
        }
      } finally {
        client.close(force: true);
      }
    }
  }
}

GakujoStarredMessage _message(String id, String title) => GakujoStarredMessage(
  keijitype: '1',
  genrecd: '2',
  seqNo: id,
  title: title,
  starredAt: DateTime.utc(2026),
);

Future<Set<String>> _titles(_Device device) async =>
    (await device.activity.loadStarredMessages()).map((m) => m.title).toSet();

bool _containsBytes(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

void main() {
  final skip =
      (Platform.environment['STAR_SYNC_LIVE_WEBDAV_URL']?.isNotEmpty ?? false)
      ? null
      : 'Set STAR_SYNC_LIVE_WEBDAV_URL to run live WebDAV tests';
  const timeout = Timeout(Duration(minutes: 2));
  const passphrase = 'correct horse battery staple';
  const newPassphrase = 'new correct horse battery staple';

  test(
    'syncs additions, removals, and re-stars between devices',
    () async {
      final fixture = _Fixture();
      await fixture.createCollection();
      final a = fixture.device();
      final b = fixture.device();
      await a.engine.setUp(fixture.config, passphrase);
      await a.activity.upsertStarredMessage(_message('3', 'Title 3'));
      await a.activity.upsertStarredMessage(_message('4', 'Title 4'));
      await a.engine.syncNow();
      await b.engine.setUp(fixture.config, passphrase);
      expect(await _titles(b), {'Title 3', 'Title 4'});
      await a.activity.removeStarredMessage('1|2|3');
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(await _titles(b), {'Title 4'});
      await b.activity.upsertStarredMessage(_message('3', 'Title 3'));
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(await _titles(a), {'Title 3', 'Title 4'});
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'wrong passphrase persists nothing on the joining device',
    () async {
      final fixture = _Fixture();
      await fixture.createCollection();
      final a = fixture.device();
      final b = fixture.device();
      await a.engine.setUp(fixture.config, passphrase);
      await expectLater(
        b.engine.setUp(fixture.config, 'wrong passphrase'),
        throwsA(isA<StarSyncWrongPassphraseException>()),
      );
      expect(b.storage.values, isEmpty);
      expect(await b.activity.loadStarredMessages(), isEmpty);
      expect(b.storage.values, isEmpty);
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'passphrase change preserves key ID and existing device access',
    () async {
      final fixture = _Fixture();
      await fixture.createCollection();
      final a = fixture.device();
      final b = fixture.device();
      final c = fixture.device();
      await a.engine.setUp(fixture.config, passphrase);
      await b.engine.setUp(fixture.config, passphrase);
      final transport = StarSyncWebDavTransport(fixture.webDav);
      try {
        Future<String> keyId() async {
          final object = await transport.get('stars/keyring.json');
          return StarSyncKeyring.fromJson(
            jsonDecode(utf8.decode(object!.bytes)),
          ).keyId;
        }

        final originalKeyId = await keyId();
        await a.engine.changePassphrase(passphrase, newPassphrase);
        expect(await keyId(), originalKeyId);
        await a.activity.upsertStarredMessage(
          _message('5', 'Changed passphrase'),
        );
        await a.engine.syncNow();
        await b.engine.syncNow();
        expect(b.engine.status.value.status, StarSyncStatus.ok);
        expect(await _titles(b), contains('Changed passphrase'));
        await expectLater(
          c.engine.setUp(fixture.config, passphrase),
          throwsA(isA<StarSyncWrongPassphraseException>()),
        );
        expect(c.storage.values, isEmpty);
        await c.engine.setUp(fixture.config, newPassphrase);
        expect(await _titles(c), contains('Changed passphrase'));
      } finally {
        transport.close();
      }
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'reset requires a device to rejoin with the new passphrase',
    () async {
      final fixture = _Fixture();
      await fixture.createCollection();
      final a = fixture.device();
      final b = fixture.device();
      await a.engine.setUp(fixture.config, passphrase);
      await b.engine.setUp(fixture.config, passphrase);
      await a.engine.resetRemote(newPassphrase);
      await a.activity.upsertStarredMessage(_message('6', 'After reset'));
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(b.engine.status.value.status, StarSyncStatus.needsPassphrase);
      await b.engine.rejoin(newPassphrase);
      await b.engine.syncNow();
      expect(b.engine.status.value.status, StarSyncStatus.ok);
      expect(await _titles(b), contains('After reset'));
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'device files have encrypted headers and do not expose titles',
    () async {
      final fixture = _Fixture();
      await fixture.createCollection();
      final a = fixture.device();
      final b = fixture.device();
      const titles = [
        'A private starred title',
        'Another private starred title',
      ];
      await a.engine.setUp(fixture.config, passphrase);
      await a.activity.upsertStarredMessage(_message('7', titles[0]));
      await a.activity.upsertStarredMessage(_message('8', titles[1]));
      await a.engine.syncNow();
      await b.engine.setUp(fixture.config, passphrase);
      expect(await _titles(b), titles.toSet());
      final transport = StarSyncWebDavTransport(fixture.webDav);
      try {
        final entries = await transport.list('stars/devices');
        expect(entries.length, greaterThanOrEqualTo(2));
        for (final entry in entries) {
          final object = await transport.get(entry.path);
          expect(object, isNotNull);
          final bytes = object!.bytes;
          expect(bytes.length, greaterThanOrEqualTo(4));
          expect(bytes.sublist(0, 4), ascii.encode('MBGS'));
          for (final title in titles) {
            expect(_containsBytes(bytes, utf8.encode(title)), isFalse);
          }
        }
      } finally {
        transport.close();
      }
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'wrong WebDAV password persists nothing on the device',
    () async {
      final fixture = _Fixture();
      await fixture.createCollection();
      final device = fixture.device();
      final wrongConfig = StarSyncConfig(
        backend: StarSyncBackend.webDav,
        webDav: StarSyncWebDavConfig(
          baseUrl: fixture.webDav.baseUrl,
          username: fixture.webDav.username,
          password: '${fixture.webDav.password}-wrong',
        ),
      );
      await expectLater(
        device.engine.setUp(wrongConfig, passphrase),
        throwsA(
          isA<StarSyncTransportException>().having(
            (error) => error.kind,
            'kind',
            StarSyncTransportErrorKind.auth,
          ),
        ),
      );
      expect(device.storage.values, isEmpty);
      expect(await device.activity.loadStarredMessages(), isEmpty);
      expect(device.storage.values, isEmpty);
    },
    skip: skip,
    timeout: timeout,
  );
}
