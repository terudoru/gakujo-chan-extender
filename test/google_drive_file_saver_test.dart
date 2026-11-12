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
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

import 'support/memory_secure_storage.dart';

// No TestWidgetsFlutterBinding here: it replaces HttpClient with one that
// answers 400, which would break the loopback fake Drive server.
void main() {
  late StarSyncQuotaMeter meter;
  late MemorySecureStorage storage;
  var pendingNotices = 0;
  var sessionStatus = 200;
  var sessionReason = '';
  var sessionFailures = 0;
  var failFirstChunk = false;
  late DateTime now;
  var failCheck = false;
  var quotaOnCheck = false;
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
  var dropFinal = false;
  var finalLost = false;
  Map<String, dynamic>? uploadProperties;
  var unauthorized = false;
  var refreshes = 0;
  String? shareDuringUpload;
  late List<String> deleted;
  late Set<String> deletedFolders;
  String? chunkFailureReason;
  String? uploadName;
  String? uploadParent;
  void Function()? onRequest;

  setUp(() async {
    storage = MemorySecureStorage();
    meter = StarSyncQuotaMeter(storage: storage);
    pendingNotices = 0;
    sessionStatus = 200;
    sessionReason = '';
    sessionFailures = 0;
    failFirstChunk = false;
    now = DateTime.now();
    failCheck = false;
    quotaOnCheck = false;
    failDelete = false;
    files = [];
    queries = [];
    fields = [];
    uploads = 0;
    chunks = 0;
    received = 0;
    drop = false;
    dropFolder = false;
    dropFinal = false;
    finalLost = false;
    uploadProperties = null;
    unauthorized = false;
    refreshes = 0;
    shareDuringUpload = null;
    deleted = [];
    deletedFolders = {};
    chunkFailureReason = null;
    uploadName = null;
    uploadParent = null;
    onRequest = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    saver = GoogleDriveFileSaver(
      quotaMeter: meter,
      secureStorage: storage,
      account: 'user@example.com',
      gakujoAccountHash: 'gakujo-hash',
      onPendingCheck: () => pendingNotices++,
      clock: () => now,
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
          anyOf('id,ownedByMe,shared,trashed', 'id,mimeType,ownedByMe,shared,trashed'),
        );
        if (quotaOnCheck && uploads > 0) {
          response.statusCode = 403;
          response.write(jsonEncode({'error': {'errors': [{'reason': 'storageQuotaExceeded'}]}}));
          await response.close();
          return;
        }
        if (failCheck && uploads > 0) {
          response.statusCode = 403;
          await response.close();
          return;
        }
        final matches = files.where(
          (f) => f['id'] == request.uri.pathSegments.last,
        );
        if (matches.isEmpty || deletedFolders.contains(request.uri.pathSegments.last)) {
          response.statusCode = 404;
        } else {
          response.write(jsonEncode({'trashed': false, ...matches.single}));
        }
      } else if (request.method == 'GET') {
        final query = request.uri.queryParameters['q']!;
        queries.add(query);
        fields.add(request.uri.queryParameters['fields']);
        if (query == "mimeType='application/vnd.google-apps.folder' and trashed=false") {
          final folders = files.where((f) =>
              f['mimeType'] == 'application/vnd.google-apps.folder' &&
              f['trashed'] != true).map((f) => {
                ...f,
                'parents': [f['parent']],
              }).toList();
          final second = request.uri.queryParameters['pageToken'] == 'next';
          response.write(jsonEncode({
            'files': second ? folders.skip(2).toList() : folders.take(2).toList(),
            if (!second && folders.length > 2) 'nextPageToken': 'next',
          }));
          await response.close();
          return;
        }
        final children = RegExp(
          r"^'((?:\\.|[^'])*)' in parents and trashed=false$",
        ).firstMatch(query);
        if (children != null) {
          if (deletedFolders.contains(children[1])) {
            response.statusCode = 404;
            await response.close();
            return;
          }
          response.write(jsonEncode({
            'files': files
                .where((f) =>
                    f['parent'] == children[1] &&
                    f['trashed'] != true &&
                    !deleted.contains(f['id']))
                .toList(),
          }));
          await response.close();
          return;
        }
        final match = RegExp(
          r"name='((?:\\.|[^'])*)'.*and '((?:\\.|[^'])*)' in parents",
        ).firstMatch(query)!;
        String unescape(String s) =>
            s.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
        final name = unescape(match[1]!);
        final parent = unescape(match[2]!);
        if (deletedFolders.contains(parent)) {
          response.statusCode = 404;
          await response.close();
          return;
        }
        response.write(
          jsonEncode({
            'files': files
                .where(
                  (f) =>
                      f['name'] == name &&
                      f['parent'] == parent &&
                      !deletedFolders.contains(f['id']) &&
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
        if (sessionFailures > 0) {
          sessionFailures--;
          response.statusCode = sessionStatus;
          response.write(jsonEncode({'error': {'errors': [{'reason': sessionReason}]}}));
          await response.close();
          return;
        }
        final pending =
            jsonDecode(storage.values[googleDrivePendingChecksKey]!) as List;
        expect(pending.last['id'], isNull);
        expect(pending.last['gakujoAccountHash'], isA<String>());
        uploadName = data['name'] as String;
        uploadParent = (data['parents'] as List).single as String;
        uploadProperties = Map<String, dynamic>.from(
          data['appProperties'] as Map,
        );
        received = 0;
        response.headers.set('location', base.resolve('/session').toString());
      } else {
        final range = request.headers.value('content-range')!;
        if (range.startsWith('bytes */')) {
          if (finalLost) {
            response.statusCode = 403;
            await response.close();
            return;
          }
          response.statusCode = 308;
          if (received > 0) {
            response.headers.set('range', 'bytes=0-${received - 1}');
          }
        } else {
          chunks++;
          if (chunkFailureReason != null) {
            response.statusCode = 403;
            response.write(jsonEncode({'error': {'errors': [{'reason': chunkFailureReason}]}}));
            await response.close();
            return;
          }
          if (failFirstChunk) {
            response.statusCode = 403;
            await response.close();
            return;
          }
          if (shareDuringUpload != null) {
            files.singleWhere((f) => f['name'] == shareDuringUpload)['shared'] =
                true;
            shareDuringUpload = null;
          }
          final match = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(range)!;
          expect(int.parse(match[1]!), received);
          received += body.length;
          if (dropFinal && received == int.parse(match[3]!)) {
            dropFinal = false;
            finalLost = true;
            files.add({
              'id': 'lost-upload',
              'name': uploadName,
              'parent': uploadParent,
              'size': '$received',
              'md5Checksum': md5.convert(body).toString(),
              'createdTime': DateTime.now().toUtc().toIso8601String(),
              'appProperties': uploadProperties,
            });
            final socket = await response.detachSocket(writeHeaders: false);
            socket.destroy();
            return;
          }
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

  Map<String, dynamic> folder(String id, String name, String parent, {
    bool owned = true,
    bool shared = false,
    bool trashed = false,
  }) => {
    'id': id,
    'name': name,
    'parent': parent,
    'mimeType': 'application/vnd.google-apps.folder',
    'ownedByMe': owned,
    'shared': shared,
    'trashed': trashed,
    'createdTime': '2026-01-01T00:00:00Z',
  };

  Future<String> saveChosen(String id) => saver.saveFile(
    courseName: 'Course',
    fileName: 'file',
    folderId: id,
    length: 1,
    open: () => Stream.value([0]),
  );

  test('saves course folder under the selected folder', () async {
    files.add(folder('chosen', 'Chosen', 'root'));
    expect(await saveChosen('chosen'), 'uploaded');
    final course = files.singleWhere((f) => f['name'] == 'Course');
    expect(course['parent'], 'chosen');
    expect(uploadParent, course['id']);
    expect(queries.any((q) => q.contains('More Better Gakujo')), isFalse);
  });

  test('missing selected folder does not upload', () async {
    await expectLater(saveChosen('missing'), throwsA(isA<GoogleDriveSaveFolderMissing>()));
    expect(uploads, 0);
  });

  test('trashed selected folder does not upload', () async {
    files.add(folder('chosen', 'Chosen', 'root', trashed: true));
    await expectLater(saveChosen('chosen'), throwsA(isA<GoogleDriveSaveFolderMissing>()));
    expect(uploads, 0);
  });

  test('shared selected folder does not upload', () async {
    files.add(folder('chosen', 'Chosen', 'root', shared: true));
    await expectLater(saveChosen('chosen'), throwsA(isA<GoogleDriveSaveFolderShared>()));
    expect(uploads, 0);
  });

  test('unowned and non-folder selections do not upload', () async {
    files.add(folder('unowned', 'Other', 'root', owned: false));
    files.add({...folder('file', 'File', 'root'), 'mimeType': 'text/plain'});
    await expectLater(saveChosen('unowned'), throwsA(isA<GoogleDriveSaveFolderShared>()));
    await expectLater(saveChosen('file'), throwsA(isA<GoogleDriveSaveFolderMissing>()));
    expect(uploads, 0);
  });

  test('pending verification records the selected folder as root', () async {
    files.add(folder('chosen', 'Chosen', 'root'));
    failCheck = true;
    await expectLater(saveChosen('chosen'), throwsA(isA<GoogleDrivePendingCheckException>()));
    final pending = jsonDecode(storage.values[googleDrivePendingChecksKey]!) as List;
    expect(pending.single['root'], 'chosen');
  });

  test('lists private owned folders across pages with their paths', () async {
    files.addAll([
      folder('child', 'Math', 'parent'),
      folder('shared', 'Shared', 'root', shared: true),
      folder('other', 'Other', 'root', owned: false),
      folder('parent', 'School', 'root'),
      folder('orphan', 'Orphan', 'shared'),
    ]);
    final folders = await saver.listFolders();
    expect(folders.map((f) => f.path).toList(), ['Orphan', 'School', 'School / Math']);
    expect(queries, hasLength(2));
  });

  test('createFolder reuses an existing same-named folder', () async {
    files.add(folder('existing', 'My Folder', 'root'));
    final result = await saver.createFolder('  My Folder  ');
    expect(result.id, 'existing');
    expect(result.name, 'My Folder');
    expect(files, hasLength(1));
  });

  test('createFolder sanitizes names and rejects empty input', () async {
    final result = await saver.createFolder(' A/B\\C ');
    expect(result.name, 'A_B_C');
    expect(files.single['name'], 'A_B_C');
    await expectLater(saver.createFolder('  '), throwsArgumentError);
  });

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

  test(
    'failed post-upload verification is retried before the next upload',
    () async {
      failCheck = true;
      await expectLater(
        save('Course', 'file', 1),
        throwsA(isA<GoogleDrivePendingCheckException>()),
      );
      expect(pendingNotices, 1);
      expect(
        jsonDecode(storage.values[googleDrivePendingChecksKey]!) as List,
        hasLength(1),
      );
      await expectLater(
        save('Course', 'blocked', 1),
        throwsA(isA<Exception>()),
      );
      expect(uploads, 1);
      failCheck = false;
      expect(await save('Course', 'second', 1), 'uploaded');
      expect(uploads, 2);
      expect(storage.values[googleDrivePendingChecksKey], isNull);
      expect(deleted, isEmpty);
    },
  );

  test(
    'lost final response leaves an id-less record and later deletes the upload',
    () async {
      dropFinal = true;
      shareDuringUpload = 'Course';
      await expectLater(
        save('Course', 'file', 3),
        throwsA(isA<GoogleDrivePendingCheckException>()),
      );
      final entries =
          jsonDecode(storage.values[googleDrivePendingChecksKey]!) as List;
      expect(entries.single['id'], isNull);
      expect(entries.single['name'], 'file');
      expect(entries.single['gakujoAccountHash'], 'gakujo-hash');
      expect(entries.single['size'], '3');
      expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 1);
      await saver.processPendingChecks();
      expect(deleted, ['lost-upload', 'folder1']);
      expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
    },
  );

  test('lost final response is verified when folders remain private', () async {
    dropFinal = true;
    await expectLater(
      save('Course', 'file', 3),
      throwsA(isA<GoogleDrivePendingCheckException>()),
    );
    await saver.processPendingChecks();
    expect(deleted, isEmpty);
    expect(storage.values[googleDrivePendingChecksKey], isNull);
  });

  test(
    'an id-less entry remains pending when its upload cannot be found',
    () async {
      dropFinal = true;
      await expectLater(
        save('Course', 'file', 3),
        throwsA(isA<GoogleDrivePendingCheckException>()),
      );
      files.removeWhere((file) => file['id'] == 'lost-upload');
      await expectLater(saver.processPendingChecks(), throwsStateError);
      expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 1);
    },
  );

  test('quota error after upload keeps its id until verification succeeds', () async {
    quotaOnCheck = true;
    await expectLater(save('Course', 'file', 1),
        throwsA(isA<GoogleDrivePendingCheckException>()));
    final pending = jsonDecode(storage.values[googleDrivePendingChecksKey]!) as List;
    expect(pending.single['id'], 'uploaded');
    quotaOnCheck = false;
    await saver.processPendingChecks();
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
  });

  test('expired unfound upload removes its empty exposed created folder', () async {
    dropFinal = true;
    await expectLater(save('Course', 'lost', 3),
        throwsA(isA<GoogleDrivePendingCheckException>()));
    files.removeWhere((file) => file['id'] == 'lost-upload');
    files.singleWhere((file) => file['name'] == 'More Better Gakujo')['shared'] = true;
    now = now.add(const Duration(hours: 25));
    await saver.processPendingChecks();
    expect(deleted, contains(uploadParent));
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
  });

  test('session failure removes pending entry and permits the next save', () async {
    sessionStatus = 500;
    sessionFailures = 4;
    await expectLater(save('Course', 'first', 1),
        throwsA(isA<StarSyncTransportException>()));
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
    expect(pendingNotices, 0);
    expect(await save('Course', 'second', 1), 'uploaded');
  });

  test('non-final chunk failure removes pending entry', () async {
    failFirstChunk = true;
    await expectLater(save('Course', 'first', 8 * 1024 * 1024 + 1),
        throwsA(isA<StarSyncTransportException>()));
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
    expect(pendingNotices, 0);
    failFirstChunk = false;
    expect(await save('Course', 'second', 1), 'uploaded');
  });

  test('unfound upload does not block saves and expires after 24 hours', () async {
    dropFinal = true;
    await expectLater(save('Course', 'lost', 3),
        throwsA(isA<GoogleDrivePendingCheckException>()));
    files.removeWhere((file) => file['id'] == 'lost-upload');
    expect(await save('Course', 'second', 1), 'uploaded');
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 1);
    now = now.add(const Duration(hours: 25));
    await saver.processPendingChecks();
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
  });

  test('deleted parent does not block a save and missing entry expires', () async {
    dropFinal = true;
    await expectLater(save('Course', 'lost', 3),
        throwsA(isA<GoogleDrivePendingCheckException>()));
    deletedFolders.add(uploadParent!);
    expect(await save('Course', 'second', 1), 'uploaded');
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 1);
    now = now.add(const Duration(hours: 25));
    await saver.processPendingChecks();
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
  });

  test('known upload in deleted created parent is cleared', () async {
    failCheck = true;
    await expectLater(save('Course', 'file', 1),
        throwsA(isA<GoogleDrivePendingCheckException>()));
    failCheck = false;
    deletedFolders.add(uploadParent!);
    await saver.processPendingChecks();
    expect(deleted, ['uploaded']);
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
  });

  for (final reason in ['storageQuotaExceeded', 'domainPolicy']) {
    test('$reason on final chunk leaves no pending entry', () async {
      chunkFailureReason = reason;
      await expectLater(save('Course', 'file', 1), throwsA(
        reason == 'domainPolicy' ? isA<GoogleDriveDisabled>() : isA<GoogleDriveStorageFull>()));
      expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
      expect(pendingNotices, 0);
    });
  }

  test('session rate limit is retried', () async {
    sessionStatus = 403;
    sessionReason = 'userRateLimitExceeded';
    sessionFailures = 1;
    expect(await save('Course', 'file', 1), 'uploaded');
    expect(uploads, 2);
  });

  test('storage full removes pending entry', () async {
    sessionStatus = 403;
    sessionReason = 'storageQuotaExceeded';
    sessionFailures = 1;
    await expectLater(save('Course', 'file', 1),
        throwsA(isA<GoogleDriveStorageFull>()));
    expect(await GoogleDriveFileSaver.pendingCheckCount(storage: storage), 0);
    expect(pendingNotices, 0);
  });

  test('retry only uses the account that owns the pending entry', () async {
    failCheck = true;
    await expectLater(
      save('Course', 'file', 1),
      throwsA(isA<GoogleDrivePendingCheckException>()),
    );
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
    await expectLater(
      save('Course', 'file', 1),
      throwsA(isA<GoogleDrivePendingCheckException>()),
    );
    expect(pendingNotices, 1);
    expect(storage.values[googleDrivePendingChecksKey], isNotNull);
    failDelete = false;
    await saver.processPendingChecks();
    expect(deleted, ['uploaded', 'folder1']);
    expect(storage.values[googleDrivePendingChecksKey], isNull);
  });

  test(
    'pending retry uses automatic quota and leaves entries when exhausted',
    () async {
      failCheck = true;
      await expectLater(
        save('Course', 'file', 1),
        throwsA(isA<GoogleDrivePendingCheckException>()),
      );
      failCheck = false;
      final used = await meter.currentUsage();
      await meter.charge(starSyncGoogleSoftLimit - used, automatic: true);
      await expectLater(
        saver.processPendingChecks(),
        throwsA(isA<StarSyncQuotaExceeded>()),
      );
      expect(storage.values[googleDrivePendingChecksKey], isNotNull);
    },
  );

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
      expect(deleted, ['uploaded', 'folder1']);
      // Plus the empty check and deletion of the course folder it created.
      expect(await meter.currentUsage(), 710);
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

  test('an early failure removes a just-created course folder found shared', () async {
    await expectLater(
      saver.saveFile(
        courseName: 'Course',
        fileName: 'file',
        automatic: true,
        length: 1,
        open: () async* {
          // The root is shared after the course folder was created, and the
          // local read fails before any pending record exists.
          files.singleWhere((f) => f['name'] == 'More Better Gakujo')['shared'] =
              true;
          throw StateError('read failed');
        },
      ),
      throwsStateError,
    );
    final course = files.singleWhere((f) => f['name'] == 'Course');
    expect(deleted, [course['id']]);
    expect(storage.values[googleDrivePendingChecksKey], isNull);
  });

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
    await meter.charge(starSyncGoogleSoftLimit - 300);
    await expectLater(
      save('Course', 'file', 1),
      throwsA(isA<GoogleDriveSaveSoftLimit>()),
    );
    expect(queries, isEmpty);
    expect(uploads, 0);
    expect(await meter.currentUsage(), starSyncGoogleSoftLimit - 300);
  });

  test(
    'rejects oversized automatic saves before opening or requesting',
    () async {
      var opened = false;
      await expectLater(
        saver.saveFile(
          courseName: 'Course',
          fileName: 'large',
          length:
              ((starSyncGoogleSoftLimit - 300) ~/ 50 + 1) * 8 * 1024 * 1024,
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
  @override
  void cancelPendingSignIn() {}
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
  Future<String?> restore({String? expectedEmail}) async => email;
  @override
  Future<String> signIn({List<String> optionalScopes = const [], String? loginHint}) async => email!;
  @override
  Future<void> signOut() async {
    email = null;
  }
}
