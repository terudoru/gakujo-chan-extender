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

class _File {
  _File(this.id, this.name, this.bytes, this.created);
  final String id;
  final String name;
  List<int> bytes;
  final DateTime created;
  int version = 1;

  Map<String, Object> get json => {
    'id': id,
    'name': name,
    'createdTime': created.toUtc().toIso8601String(),
    'modifiedTime': created.toUtc().toIso8601String(),
    'version': '$version',
    'size': '${bytes.length}',
  };
}

class _FakeDrive {
  _FakeDrive(this.server) {
    server.listen(_handle);
  }
  final HttpServer server;
  final files = <_File>[];
  final counts = <String, int>{};
  int serial = 0;
  int pageSize = 1000;
  int failures = 0;
  int failureStatus = 429;
  String failureBody = '{}';
  bool rejectOldToken = false;
  bool insertRace = false;

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');

  _File add(String name, List<int> bytes, {DateTime? created}) {
    final file = _File(
      '${++serial}',
      name,
      bytes,
      created ?? DateTime.utc(2026),
    );
    files.add(file);
    return file;
  }

  Future<void> _handle(HttpRequest request) async {
    final key = '${request.method} ${request.uri.path}';
    counts[key] = (counts[key] ?? 0) + 1;
    final body = await request.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    final response = request.response;
    if (rejectOldToken &&
        request.headers.value('authorization') == 'Bearer old') {
      response.statusCode = 401;
    } else if (failures > 0) {
      failures--;
      response.statusCode = failureStatus;
      response.write(failureBody);
    } else if (request.method == 'GET' &&
        request.uri.path == '/drive/v3/files') {
      final offset =
          int.tryParse(request.uri.queryParameters['pageToken'] ?? '') ?? 0;
      final end = (offset + pageSize).clamp(0, files.length).toInt();
      response.write(
        jsonEncode({
          'files': files.sublist(offset, end).map((f) => f.json).toList(),
          if (end < files.length) 'nextPageToken': '$end',
        }),
      );
    } else if (request.method == 'POST' &&
        request.uri.path == '/upload/drive/v3/files') {
      final contentType = request.headers.contentType!;
      final boundary = contentType.parameters['boundary']!;
      final parts = latin1.decode(body).split('--$boundary');
      final metadata = jsonDecode(
        utf8.decode(latin1.encode(parts[1].split('\r\n\r\n')[1].trim())),
      ) as Map<String, dynamic>;
      if ((metadata['parents'] as List).single != 'appDataFolder') {
        throw StateError('Wrong parent');
      }
      final payload = parts[2].split('\r\n\r\n')[1];
      final file = add(
        metadata['name'] as String,
        latin1.encode(payload.substring(0, payload.length - 2)),
      );
      if (insertRace) {
        insertRace = false;
        add(file.name, [99], created: DateTime.utc(2020));
      }
      response.write(jsonEncode(file.json));
    } else {
      final id = request.uri.pathSegments.last;
      final matches = files.where((file) => file.id == id).toList();
      if (matches.isEmpty) {
        response.statusCode = 404;
      } else if (request.method == 'GET') {
        response.add(matches.first.bytes);
      } else if (request.method == 'PATCH') {
        matches.first.bytes = body;
        matches.first.version++;
        response.write(jsonEncode(matches.first.json));
      } else if (request.method == 'DELETE') {
        files.remove(matches.first);
        response.statusCode = 204;
      } else {
        response.statusCode = 400;
      }
    }
    await response.close();
  }
}

void main() {
  test('Drive syncs stars between two devices', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final drive = _FakeDrive(server);
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
        await activityA.removeStarredMessage('1|2|3');
        await a.syncNow();
        await b.syncNow();
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
}
