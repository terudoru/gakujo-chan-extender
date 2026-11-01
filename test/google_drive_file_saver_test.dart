import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_quota_meter.dart';
import 'package:morebettergakujo_flutter/src/google_drive_file_saver.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';

import 'support/memory_secure_storage.dart';

// No TestWidgetsFlutterBinding here: it replaces HttpClient with one that
// answers 400, which would break the loopback fake Drive server.
void main() {
  late StarSyncQuotaMeter meter;
  late MemorySecureStorage storage;
  var pendingNotices = 0;
  var failCheck = false;
  var failDelete = false;
  late HttpServer server;
  late Uri base;
  late GoogleDriveFileSaver saver;
  late List<Map<String, dynamic>> files;
  late List<String> queries;
  late List<String?> fields;
  var uploads = 0;
  var chunks = 0;
  var received = 0;
  var drop = false;
  var dropFolder = false;
  var unauthorized = false;
  var refreshes = 0;
  String? shareDuringUpload;
  late List<String> deleted;
  String? uploadName;
  String? uploadParent;
  void Function()? onRequest;

  setUp(() async {
    storage = MemorySecureStorage();
    meter = StarSyncQuotaMeter(storage: storage);
    pendingNotices = 0;
    failCheck = false;
    failDelete = false;
    files = [];
    queries = [];
    fields = [];
    uploads = 0;
    chunks = 0;
    received = 0;
    drop = false;
    dropFolder = false;
    unauthorized = false;
    refreshes = 0;
    shareDuringUpload = null;
    deleted = [];
    uploadName = null;
    uploadParent = null;
    onRequest = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    saver = GoogleDriveFileSaver(
      quotaMeter: meter,
      secureStorage: storage,
      account: 'user@example.com',
      onPendingCheck: () => pendingNotices++,
      apiBase: base,
      delay: (_) async {},
      accessToken: ({bool forceRefresh = false}) async {
        if (forceRefresh) refreshes++;
        return forceRefresh ? 'refreshed' : 'token';
      },
    );
    server.listen((request) async {
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      onRequest?.call();
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (unauthorized &&
          request.headers.value('authorization') != 'Bearer refreshed') {
        unauthorized = false;
        response.statusCode = 401;
      } else if (request.method == 'GET' &&
          request.uri.path != '/drive/v3/files') {
        expect(
          request.uri.queryParameters['fields'],
          'id,ownedByMe,shared,trashed',
        );
        if (failCheck && uploads > 0) {
          response.statusCode = 403;
          await response.close();
          return;
        }
        final matches = files.where(
          (f) => f['id'] == request.uri.pathSegments.last,
        );
        if (matches.isEmpty) {
          response.statusCode = 404;
        } else {
          response.write(jsonEncode({'trashed': false, ...matches.single}));
        }
      } else if (request.method == 'GET') {
        final query = request.uri.queryParameters['q']!;
        queries.add(query);
        fields.add(request.uri.queryParameters['fields']);
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
                      f['trashed'] != true &&
                      (!query.startsWith('mimeType=') ||
                          f['mimeType'] ==
                              'application/vnd.google-apps.folder'),
                )
                .toList(),
          }),
        );
      } else if (request.method == 'DELETE') {
        if (failDelete) {
          response.statusCode = 403;
          await response.close();
          return;
        }
        deleted.add(request.uri.pathSegments.last);
        response.statusCode = 204;
      } else if (request.uri.path == '/drive/v3/files') {
        final data = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        final id = 'folder${files.length}';
        files.add({
          'id': id,
          'name': data['name'],
          'parent': data['parents'][0],
          'mimeType': data['mimeType'],
          'createdTime': '2026-01-01T00:00:00Z',
          'ownedByMe': true,
          'shared': false,
        });
        if (dropFolder) {
          dropFolder = false;
          final socket = await response.detachSocket(writeHeaders: false);
          socket.destroy();
          return;
        }
        response.write(jsonEncode({'id': id}));
      } else if (request.uri.path == '/upload/drive/v3/files') {
        final data = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
        uploads++;
        uploadName = data['name'] as String;
        uploadParent = (data['parents'] as List).single as String;
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
          if (shareDuringUpload != null) {
            files.singleWhere((f) => f['name'] == shareDuringUpload)['shared'] =
                true;
            shareDuringUpload = null;
          }
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
    automatic: true,
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

  test(
    'matching checksum skipped, same size different content gets suffix',
    () async {
      expect(await save('Course', 'file.pdf', 3), 'uploaded');
      files.add({
        'id': 'existing',
        'name': 'file.pdf',
        'parent': 'folder1',
        'size': '3',
        'md5Checksum': md5.convert([0, 0, 0]).toString(),
        'shared': false,
      });
      expect(await save('Course', 'file.pdf', 3), 'existing');
      files.last['md5Checksum'] = md5.convert([1, 2, 3]).toString();
      expect(await save('Course', 'file.pdf', 3), 'uploaded');
      expect(uploadName, 'file (2).pdf');
      expect(await save('Course', 'file.pdf', 4), 'uploaded');
      expect(uploadName, 'file (2).pdf');
      expect(files.where((f) => f['mimeType'] != null).length, 2);
      expect(uploads, 3);
    },
  );

  test('ignores shared and unowned folders at both levels', () async {
    const folderMime = 'application/vnd.google-apps.folder';
    files.addAll([
      {
        'id': 'shared-root',
        'name': 'More Better Gakujo',
        'parent': 'root',
        'mimeType': folderMime,
        'createdTime': '2020-01-01T00:00:00Z',
        'ownedByMe': true,
        'shared': true,
      },
      {
        'id': 'unowned-root',
        'name': 'More Better Gakujo',
        'parent': 'root',
        'mimeType': folderMime,
        'createdTime': '2020-01-01T00:00:00Z',
        'ownedByMe': false,
        'shared': false,
      },
      {
        'id': 'shared-course',
        'name': 'Course',
        'parent': 'folder4',
        'mimeType': folderMime,
        'createdTime': '2020-01-01T00:00:00Z',
        'ownedByMe': true,
        'shared': true,
      },
      {
        'id': 'unowned-course',
        'name': 'Course',
        'parent': 'folder4',
        'mimeType': folderMime,
        'createdTime': '2020-01-01T00:00:00Z',
        'ownedByMe': false,
        'shared': false,
      },
    ]);
    expect(await save('Course', 'file', 1), 'uploaded');
    expect(files[4]['parent'], 'root');
    expect(files[5]['parent'], files[4]['id']);
    expect(uploadParent, files[5]['id']);
    expect(
      fields.every(
        (f) => f != null && f.contains('ownedByMe') && f.contains('shared'),
      ),
      isTrue,
    );
  });

  test('replaces cached folders that become shared', () async {
    await save('Course', 'first', 1);
    final oldRoot = files.singleWhere((f) => f['name'] == 'More Better Gakujo');
    oldRoot['shared'] = true;
    await save('Course', 'second', 1);
    final newRoot = files.lastWhere((f) => f['name'] == 'More Better Gakujo');
    expect(newRoot['id'], isNot(oldRoot['id']));
    final oldCourse = files.lastWhere((f) => f['name'] == 'Course');
    expect(oldCourse['parent'], newRoot['id']);
    oldCourse['shared'] = true;
    await save('Course', 'third', 1);
    expect(uploadParent, isNot(oldCourse['id']));
    expect(files.last['parent'], newRoot['id']);
  });

  test('replaces a cached trashed folder', () async {
    await save('Course', 'first', 1);
    final oldCourse = files.singleWhere((f) => f['name'] == 'Course');
    oldCourse['trashed'] = true;
    await save('Course', 'second', 1);
    expect(uploadParent, isNot(oldCourse['id']));
    expect(files.last['name'], 'Course');
  });

  test('failed post-upload verification is retried before the next upload', () async {
    failCheck = true;
    await expectLater(save('Course', 'file', 1), throwsA(isA<GoogleDrivePendingCheckException>()));
    expect(pendingNotices, 1);
    expect(jsonDecode(storage.values[googleDrivePendingChecksKey]!) as List, hasLength(1));
    await expectLater(save('Course', 'blocked', 1), throwsA(isA<Exception>()));
    expect(uploads, 1);
    failCheck = false;
    expect(await save('Course', 'second', 1), 'uploaded');
    expect(uploads, 2);
    expect(storage.values[googleDrivePendingChecksKey], isNull);
    expect(deleted, isEmpty);
  });

  test('retry only uses the account that owns the pending entry', () async {
    failCheck = true;
    await expectLater(save('Course', 'file', 1), throwsA(isA<GoogleDrivePendingCheckException>()));
    failCheck = false;
    final other = GoogleDriveFileSaver(
      quotaMeter: meter,
      secureStorage: storage,
      account: 'other@example.com',
      apiBase: base,
      accessToken: ({bool forceRefresh = false}) async => 'token',
    );
    await other.processPendingChecks();
    expect(storage.values[googleDrivePendingChecksKey], isNotNull);
    other.close();
    await saver.processPendingChecks();
    expect(storage.values[googleDrivePendingChecksKey], isNull);
  });

  test('failed deletion remains pending until a later retry', () async {
    shareDuringUpload = 'Course';
    failDelete = true;
    await expectLater(save('Course', 'file', 1), throwsA(isA<GoogleDrivePendingCheckException>()));
    expect(pendingNotices, 1);
    expect(storage.values[googleDrivePendingChecksKey], isNotNull);
    failDelete = false;
    await saver.processPendingChecks();
    expect(deleted, ['uploaded']);
    expect(storage.values[googleDrivePendingChecksKey], isNull);
  });

  test('pending retry uses automatic quota and leaves entries when exhausted', () async {
    failCheck = true;
    await expectLater(save('Course', 'file', 1), throwsA(isA<GoogleDrivePendingCheckException>()));
    failCheck = false;
    final used = await meter.currentUsage();
    await meter.charge(starSyncGoogleSoftLimit - used, automatic: true);
    await expectLater(saver.processPendingChecks(), throwsA(isA<StarSyncQuotaExceeded>()));
    expect(storage.values[googleDrivePendingChecksKey], isNotNull);
  });

  for (final folder in ['Course', 'More Better Gakujo']) {
    test('deletes upload when $folder becomes shared during upload', () async {
      shareDuringUpload = folder;
      await expectLater(
        save('Course', 'file', 1),
        throwsA(
          isA<GoogleDriveSaveFolderShared>().having(
            (error) => error.toString(),
            'message',
            '保存先のフォルダが共有されていたため、Google ドライブへの保存を取り消しました',
          ),
        ),
      );
      expect(deleted, ['uploaded']);
      expect(await meter.currentUsage(), 560);
      await save('Course', 'another', 1);
      final shared = files.singleWhere(
        (f) => f['name'] == folder && f['shared'] == true,
      );
      expect(uploadParent, isNot(shared['id']));
      if (folder == 'More Better Gakujo') {
        expect(files.last['parent'], isNot(shared['id']));
      }
    });
  }

  test('replaces a cached folder that is missing or no longer owned', () async {
    await save('Course', 'first', 1);
    final oldRoot = files.singleWhere((f) => f['name'] == 'More Better Gakujo');
    oldRoot['ownedByMe'] = false;
    await save('Course', 'second', 1);
    final oldCourse = files.lastWhere((f) => f['name'] == 'Course');
    expect(oldCourse['parent'], isNot(oldRoot['id']));
    final oldCourseId = oldCourse['id'];
    oldCourse['id'] = 'missing';
    oldCourse['trashed'] = true;
    await save('Course', 'third', 1);
    expect(uploadParent, isNot(oldCourseId));
  });

  test('charges five units for each cached folder check', () async {
    await save('Course', 'first', 1);
    final before = await meter.currentUsage();
    await save('Course', 'second', 1);
    expect(await meter.currentUsage() - before, 220);
  });

  test('does not deduplicate a shared file', () async {
    await save('Course', 'first', 3);
    files.add({
      'id': 'shared-file',
      'name': 'file.pdf',
      'parent': uploadParent,
      'md5Checksum': md5.convert([0, 0, 0]).toString(),
      'shared': true,
    });
    expect(await save('Course', 'file.pdf', 3), 'uploaded');
    expect(uploadName, 'file (2).pdf');
    expect(uploads, 2);
  });

  test('closing a running saver prevents subsequent requests', () async {
    onRequest = () {
      onRequest = null;
      saver.close();
    };
    await expectLater(save('Course', 'file', 1), throwsA(anything));
    expect(uploads, 0);
    expect(chunks, 0);
  });

  test('account change during a job prevents further requests', () async {
    final auth = _FakeGoogleAuth();
    final email = auth.currentEmail!;
    saver = GoogleDriveFileSaver(
      quotaMeter: meter,
      secureStorage: storage,
      account: 'user@example.com',
      onPendingCheck: () => pendingNotices++,
      apiBase: base,
      accessToken: ({bool forceRefresh = false}) =>
          googleDriveTokenForAccount(auth, email, forceRefresh: forceRefresh),
    );
    onRequest = () {
      auth.email = 'other@example.test';
      onRequest = null;
    };
    await expectLater(
      save('Course', 'file', 1),
      throwsA(isA<GoogleDriveAccountChanged>()),
    );
    expect(queries, hasLength(1));
    expect(uploads, 0);
    expect(chunks, 0);
  });

  test('account change while obtaining a token aborts the request', () async {
    final auth = _FakeGoogleAuth();
    auth.pendingToken = Completer<String>();
    final token = googleDriveTokenForAccount(auth, auth.currentEmail!);
    auth.email = 'other@example.test';
    auth.pendingToken!.complete('token');
    await expectLater(token, throwsA(isA<GoogleDriveAccountChanged>()));
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

  test('finds the folder when its creation response is lost', () async {
    dropFolder = true;
    expect(await save('Course', 'file', 1), 'uploaded');
    final roots = files.where((f) => f['name'] == 'More Better Gakujo');
    expect(roots, hasLength(1));
    final course = files.singleWhere((f) => f['name'] == 'Course');
    expect(course['parent'], roots.single['id']);
    expect(uploadParent, course['id']);
  });

  test('chooses oldest duplicate folder, breaking ties by id', () async {
    for (final id in ['z', 'b', 'a']) {
      files.add({
        'id': id,
        'name': 'More Better Gakujo',
        'parent': 'root',
        'mimeType': 'application/vnd.google-apps.folder',
        'ownedByMe': true,
        'shared': false,
        'createdTime': id == 'z'
            ? '2026-02-01T00:00:00Z'
            : '2026-01-01T00:00:00Z',
      });
    }
    expect(await save('Course', 'file', 1), 'uploaded');
    expect(files.singleWhere((f) => f['name'] == 'Course')['parent'], 'a');
    saver = GoogleDriveFileSaver(
      quotaMeter: meter,
      secureStorage: storage,
      account: 'user@example.com',
      onPendingCheck: () => pendingNotices++,
      apiBase: base,
      delay: (_) async {},
      accessToken: ({bool forceRefresh = false}) async => 'token',
    );
    expect(await save('Course', 'another', 1), 'uploaded');
    expect(files.where((f) => f['name'] == 'Course'), hasLength(1));
    expect(uploadParent, files.singleWhere((f) => f['name'] == 'Course')['id']);
  });

  test('skips an upload before any requests at the soft limit', () async {
    await meter.charge(14700);
    await expectLater(
      save('Course', 'file', 1),
      throwsA(isA<GoogleDriveSaveSoftLimit>()),
    );
    expect(queries, isEmpty);
    expect(uploads, 0);
    expect(await meter.currentUsage(), 14700);
  });

  test(
    'rejects oversized automatic saves before opening or requesting',
    () async {
      var opened = false;
      await expectLater(
        saver.saveFile(
          courseName: 'Course',
          fileName: 'large',
          length: 295 * 8 * 1024 * 1024,
          automatic: true,
          open: () {
            opened = true;
            return const Stream<List<int>>.empty();
          },
        ),
        throwsA(isA<GoogleDriveSaveTooLarge>()),
      );
      expect(opened, isFalse);
      expect(queries, isEmpty);
      expect(await meter.currentUsage(), 0);
    },
  );

  test('counts lists, folder creation and each upload request', () async {
    await save('Course', 'file', 8 * 1024 * 1024 + 1);
    expect(chunks, 2);
    expect(await meter.currentUsage(), 560);
  });

  test('charges the repeated request after a token refresh', () async {
    unauthorized = true;
    await save('Course', 'file', 1);
    expect(refreshes, 1);
    expect(await meter.currentUsage(), 610);
  });

  test('refreshes once on 401 and escapes course names', () async {
    unauthorized = true;
    expect(await save("Teacher's \\ course", 'file', 1), 'uploaded');
    expect(refreshes, 1);
    expect(queries.any((q) => q.contains(r"Teacher\'s")), isTrue);
  });
}

class _FakeGoogleAuth implements StarSyncGoogleAuth {
  String? email = 'first@example.test';
  Completer<String>? pendingToken;

  @override
  String? get currentEmail => email;
  @override
  Future<String> accessToken({bool forceRefresh = false}) async =>
      pendingToken == null ? 'token' : await pendingToken!.future;
  @override
  Future<bool> hasScope(String scope) async => true;
  @override
  Future<void> requestScopes(List<String> scopes) async {}
  @override
  Future<String?> restore() async => email;
  @override
  Future<String> signIn() async => email!;
  @override
  Future<void> signOut() async {
    email = null;
  }
}
