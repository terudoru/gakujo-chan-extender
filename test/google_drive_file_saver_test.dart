import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/google_drive_file_saver.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late GoogleDriveFileSaver saver;
  late List<Map<String, dynamic>> files;
  late List<String> queries;
  var uploads = 0;
  var chunks = 0;
  var received = 0;
  var drop = false;
  var unauthorized = false;
  var refreshes = 0;
  String? uploadName;

  setUp(() async {
    files = [];
    queries = [];
    uploads = 0;
    chunks = 0;
    received = 0;
    drop = false;
    unauthorized = false;
    refreshes = 0;
    uploadName = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    saver = GoogleDriveFileSaver(
      apiBase: base,
      delay: (_) async {},
      accessToken: ({bool forceRefresh = false}) async {
        if (forceRefresh) refreshes++;
        return forceRefresh ? 'refreshed' : 'token';
      },
    );
    server.listen((request) async {
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (unauthorized &&
          request.headers.value('authorization') != 'Bearer refreshed') {
        unauthorized = false;
        response.statusCode = 401;
      } else if (request.method == 'GET') {
        final query = request.uri.queryParameters['q']!;
        queries.add(query);
        final match = RegExp(
          r"name='((?:\\.|[^'])*)'.*and '((?:\\.|[^'])*)' in parents",
        ).firstMatch(query)!;
        String unescape(String s) =>
            s.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
        final name = unescape(match[1]!);
        final parent = unescape(match[2]!);
        response.write(
          jsonEncode({
            'files': files
                .where(
                  (f) =>
                      f['name'] == name &&
                      f['parent'] == parent &&
                      (!query.startsWith('mimeType=') ||
                          f['mimeType'] ==
                              'application/vnd.google-apps.folder'),
                )
                .toList(),
          }),
        );
      } else if (request.uri.path == '/drive/v3/files') {
        final data = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        final id = 'folder${files.length}';
        files.add({
          'id': id,
          'name': data['name'],
          'parent': data['parents'][0],
          'mimeType': data['mimeType'],
        });
        response.write(jsonEncode({'id': id}));
      } else if (request.uri.path == '/upload/drive/v3/files') {
        final data = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        uploads++;
        uploadName = data['name'] as String;
        received = 0;
        response.headers.set('location', base.resolve('/session').toString());
      } else {
        final range = request.headers.value('content-range')!;
        if (range.startsWith('bytes */')) {
          response.statusCode = 308;
          if (received > 0) {
            response.headers.set('range', 'bytes=0-${received - 1}');
          }
        } else {
          chunks++;
          final match = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(range)!;
          expect(int.parse(match[1]!), received);
          received += body.length;
          if (drop) {
            drop = false;
            final socket = await response.detachSocket(writeHeaders: false);
            socket.destroy();
            return;
          }
          if (received == int.parse(match[3]!)) {
            response.write(jsonEncode({'id': 'uploaded'}));
          } else {
            response.statusCode = 308;
            response.headers.set('range', 'bytes=0-${received - 1}');
          }
        }
      }
      await response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  Future<String> save(String course, String name, int length) => saver.saveFile(
    courseName: course,
    fileName: name,
    length: length,
    open: () async* {
      var remaining = length;
      while (remaining > 0) {
        final size = remaining > 65536 ? 65536 : remaining;
        yield Uint8List(size);
        remaining -= size;
      }
    },
  );

  test('folders reused, same size skipped, collision gets suffix', () async {
    expect(await save('Course', 'file.pdf', 3), 'uploaded');
    files.add({
      'id': 'existing',
      'name': 'file.pdf',
      'parent': 'folder1',
      'size': '3',
    });
    expect(await save('Course', 'file.pdf', 3), 'existing');
    expect(await save('Course', 'file.pdf', 4), 'uploaded');
    expect(uploadName, 'file (2).pdf');
    expect(files.where((f) => f['mimeType'] != null).length, 2);
    expect(uploads, 2);
  });

  test('20 MiB upload uses three chunks', () async {
    expect(await save('Course', 'large', 20 * 1024 * 1024), 'uploaded');
    expect(chunks, 3);
  });

  test('resumes after a dropped chunk', () async {
    drop = true;
    expect(await save('Course', 'large', 20 * 1024 * 1024), 'uploaded');
    expect(received, 20 * 1024 * 1024);
    expect(chunks, 3);
  });

  test('refreshes once on 401 and escapes course names', () async {
    unauthorized = true;
    expect(await save("Teacher's \\ course", 'file', 1), 'uploaded');
    expect(refreshes, 1);
    expect(queries.any((q) => q.contains(r"Teacher\'s")), isTrue);
  });
}
