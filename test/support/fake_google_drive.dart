import 'dart:convert';
import 'dart:io';

class FakeGoogleDriveFile {
  FakeGoogleDriveFile._(
    this.id,
    this.name,
    this.bytes,
    this.created,
    this._includeSpaces,
  );
  final String id;
  final String name;
  List<int> bytes;
  final DateTime created;
  final bool _includeSpaces;
  int version = 1;
  DateTime? modified;
  List<String> spaces = ['appDataFolder'];

  Map<String, Object> get json => {
    'id': id,
    if (_includeSpaces) 'spaces': spaces,
    'name': name,
    'createdTime': created.toUtc().toIso8601String(),
    'modifiedTime': (modified ?? created).toUtc().toIso8601String(),
    'version': '$version',
    'size': '${bytes.length}',
  };
}

class FakeGoogleDrive {
  FakeGoogleDrive(
    this.server, {
    this._includeSpaces = true,
    this._awaitUploadHook = true,
  }) {
    server.listen(_handle);
  }
  final HttpServer server;
  final bool _includeSpaces;
  // The transport fixture yields even when the upload hook is unset.
  final bool _awaitUploadHook;
  final files = <FakeGoogleDriveFile>[];
  final counts = <String, int>{};
  int serial = 0;
  int pageSize = 1000;
  int failures = 0;
  int failureStatus = 429;
  String failureBody = '{}';
  bool rejectOldToken = false;
  bool insertRace = false;
  void Function(FakeGoogleDriveFile)? beforeReadResponse;
  Future<void> Function()? afterUpload;

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');

  FakeGoogleDriveFile add(String name, List<int> bytes, {DateTime? created}) {
    final file = FakeGoogleDriveFile._(
      '${++serial}',
      name,
      bytes,
      created ?? DateTime.utc(2026),
      _includeSpaces,
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
      if (_awaitUploadHook) await afterUpload?.call();
      response.write(jsonEncode(file.json));
    } else {
      final id = request.uri.pathSegments.last;
      final matches = files.where((file) => file.id == id).toList();
      if (matches.isEmpty) {
        response.statusCode = 404;
      } else if (request.method == 'GET') {
        beforeReadResponse?.call(matches.first);
        response.add(matches.first.bytes);
      } else if (request.method == 'PATCH') {
        matches.first.bytes = body;
        matches.first.version++;
        if (_awaitUploadHook) await afterUpload?.call();
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
