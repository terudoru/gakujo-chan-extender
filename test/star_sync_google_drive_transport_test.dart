import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_drive_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

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
      response.write(jsonEncode({'id': file.id}));
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
        response.write('{}');
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
  late _FakeDrive drive;
  late StarSyncGoogleDriveTransport transport;

  setUp(() async {
    drive = _FakeDrive(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    transport = StarSyncGoogleDriveTransport(
      apiBase: drive.base,
      accessToken: ({bool forceRefresh = false}) async => 'token',
      delay: (_) async {},
    );
  });

  tearDown(() async {
    transport.close();
    await drive.server.close(force: true);
  });

  test('create, update, get and delete', () async {
    await transport.ensureDirectory('stars/devices');
    await transport.put('stars/devices/a', [0, 255, 1]);
    expect((await transport.get('stars/devices/a'))!.bytes, [0, 255, 1]);
    await transport.put('stars/devices/a', [2, 3]);
    expect((await transport.get('stars/devices/a'))!.bytes, [2, 3]);
    expect((await transport.get('stars/devices/a'))!.etag, '2');
    await transport.delete('stars/devices/a');
    expect(await transport.get('stars/devices/a'), isNull);
    await transport.delete('stars/devices/a');
    expect(drive.counts['POST /upload/drive/v3/files'], 1);
    expect(drive.counts['PATCH /upload/drive/v3/files/1'], 1);
  });

  test(
    'paginates, filters direct children and chooses oldest duplicate',
    () async {
      drive.pageSize = 2;
      drive.add('stars/devices/a', [1], created: DateTime.utc(2025));
      drive.add('stars/devices/a', [2], created: DateTime.utc(2024));
      drive.add('stars/devices/b', [3]);
      drive.add('stars/devices/sub/c', [4]);
      drive.add('stars/devices2/x', [5]);
      final entries = await transport.list('stars/devices');
      expect(entries.map((e) => e.path).toSet(), {
        'stars/devices/a',
        'stars/devices/b',
      });
      expect((await transport.get('stars/devices/a'))!.bytes, [2]);
      expect(drive.counts['GET /drive/v3/files'], 3);
      await transport.delete('stars/devices/a');
      expect(drive.files.where((f) => f.name == 'stars/devices/a'), isEmpty);
    },
  );

  test('createOnly rejects an existing file without uploading', () async {
    drive.add('stars/keyring.json', [1]);
    await expectLater(
      transport.put('stars/keyring.json', [2], createOnly: true),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.alreadyExists,
        ),
      ),
    );
    expect(drive.counts['POST /upload/drive/v3/files'], isNull);
  });

  test('createOnly removes its own file after a duplicate race', () async {
    drive.insertRace = true;
    await expectLater(
      transport.put('stars/keyring.json', [2], createOnly: true),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.alreadyExists,
        ),
      ),
    );
    expect(drive.files.single.bytes, [99]);
    expect(drive.counts['DELETE /drive/v3/files/1'], 1);
  });

  test('refreshes the token once after 401', () async {
    transport.close();
    drive.rejectOldToken = true;
    var refreshes = 0;
    transport = StarSyncGoogleDriveTransport(
      apiBase: drive.base,
      accessToken: ({bool forceRefresh = false}) async {
        if (forceRefresh) refreshes++;
        return forceRefresh ? 'fresh' : 'old';
      },
    );
    expect(await transport.list('stars'), isEmpty);
    expect(refreshes, 1);
    expect(drive.counts['GET /drive/v3/files'], 2);
  });

  test('retries 429 with exponential delays', () async {
    transport.close();
    drive.failures = 3;
    final delays = <Duration>[];
    transport = StarSyncGoogleDriveTransport(
      apiBase: drive.base,
      accessToken: ({bool forceRefresh = false}) async => 'token',
      delay: (duration) async => delays.add(duration),
    );
    expect(await transport.list('stars'), isEmpty);
    expect(delays, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
  });

  test('plain 403 is an auth error', () async {
    drive.failures = 1;
    drive.failureStatus = 403;
    await expectLater(
      transport.list('stars'),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.auth,
        ),
      ),
    );
    expect(drive.counts['GET /drive/v3/files'], 1);
  });

  test('rate-limited 403 exhausts retries as a server error', () async {
    drive.failures = 4;
    drive.failureStatus = 403;
    drive.failureBody = jsonEncode({
      'error': {
        'errors': [
          {'reason': 'userRateLimitExceeded'},
        ],
      },
    });
    await expectLater(
      transport.list('stars'),
      throwsA(
        isA<StarSyncTransportException>().having(
          (e) => e.kind,
          'kind',
          StarSyncTransportErrorKind.server,
        ),
      ),
    );
    expect(drive.counts['GET /drive/v3/files'], 4);
  });
}
