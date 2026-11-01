import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_factory.dart';

import 'star_sync/star_sync_quota_meter.dart';
import 'star_sync/star_sync_transport.dart';

const googleDrivePendingChecksKey = 'more_better_gakujo_drive_pending_checks';

class GoogleDriveFileSaver {
  GoogleDriveFileSaver({
    required this._accessToken,
    HttpClient Function()? httpClientFactory,
    Uri? apiBase,
    Future<void> Function(Duration)? delay,
    StarSyncQuotaMeter? quotaMeter,
    FlutterSecureStorage? secureStorage,
    required this.account,
    this.gakujoAccountHash,
    this.onPendingCheck,
  }) : _client = (httpClientFactory ?? HttpClient.new)(),
       _base = apiBase ?? Uri.parse('https://www.googleapis.com'),
       _delay = delay ?? Future<void>.delayed,
       _quotaMeter = quotaMeter ?? StarSyncQuotaMeter.shared,
       _storage = secureStorage ?? SecureStorageFactory.create() {
    if (account.isEmpty) throw ArgumentError('Missing Google account');
    validateStarSyncEndpoint(_base);
  }

  final Future<String> Function({bool forceRefresh}) _accessToken;
  final HttpClient _client;
  final StarSyncQuotaMeter _quotaMeter;
  final FlutterSecureStorage _storage;
  final String account;
  final String? gakujoAccountHash;
  final void Function()? onPendingCheck;
  final Uri _base;
  final Future<void> Function(Duration) _delay;
  final Map<String, String> _folders = {};
  final Set<String> _createdFolders = {};
  final Random _random = Random.secure();
  static const _chunkSize = 8 * 1024 * 1024;
  static const _folderMime = 'application/vnd.google-apps.folder';

  static bool isAutomaticFileTooLarge(int length) =>
      300 + 50 * ((length + _chunkSize - 1) ~/ _chunkSize) >
      starSyncGoogleSoftLimit;

  /// Releases the HTTP client; the saver must not be used afterwards.
  void close() => _client.close(force: true);

  Uri _uri(String path, [Map<String, String>? query]) =>
      _base.resolve(path).replace(queryParameters: query);

  String _escape(String value) =>
      value.replaceAll('\\', r'\\').replaceAll("'", r"\'");

  Future<StarSyncHttpResponse> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> body = const [],
    bool retryNetwork = true,
    bool retryStatus = true,
  }) async {
    var refreshed = false;
    var retries = 0;
    var token = await _accessToken();
    while (true) {
      StarSyncHttpResponse response;
      final cost = method != 'GET'
          ? 50
          : uri.path.endsWith('/files')
          ? 100
          : uri.queryParameters['alt'] == 'media'
          ? 200
          : 5;
      await _quotaMeter.charge(
        cost,
        automatic: Zone.current[#driveSaveAutomatic] == true,
      );
      try {
        response = await starSyncRequest(
          _client,
          method,
          uri,
          headers: {'authorization': 'Bearer $token', ...headers},
          body: body,
        );
      } on StarSyncTransportException catch (error) {
        if (!retryNetwork ||
            error.kind != StarSyncTransportErrorKind.network ||
            retries >= 3) {
          rethrow;
        }
        await _backoff(retries++);
        continue;
      }
      if (response.statusCode == 401 && !refreshed) {
        token = await _accessToken(forceRefresh: true);
        refreshed = true;
        continue;
      }
      if (retryStatus &&
          (response.statusCode == 429 || response.statusCode >= 500) &&
          retries < 3) {
        await _backoff(retries++);
        continue;
      }
      return response;
    }
  }

  Future<void> _backoff(int retry) => _delay(
    Duration(milliseconds: (500 * (1 << retry)) + _random.nextInt(250)),
  );

  Map<String, dynamic> _json(StarSyncHttpResponse response) {
    checkStarSyncStatus(response.statusCode);
    final value = jsonDecode(utf8.decode(response.bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Drive response');
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> _list(
    String name,
    String parent, {
    bool folder = false,
  }) async {
    final q =
        "${folder ? "mimeType='$_folderMime' and " : ''}name='${_escape(name)}' and trashed=false and '${_escape(parent)}' in parents";
    final files = <Map<String, dynamic>>[];
    String? page;
    do {
      final result = _json(
        await _request(
          'GET',
          _uri('/drive/v3/files', {
            'q': q,
            'fields': 'nextPageToken,files(id,name,size,mimeType,md5Checksum,createdTime,ownedByMe,shared,appProperties)',
            'pageSize': '1000',
            'pageToken': ?page,
          }),
        ),
      );
      final entries = result['files'];
      if (entries is! List) {
        throw const FormatException('Invalid Drive file list');
      }
      files.addAll(entries.map((e) => Map<String, dynamic>.from(e as Map)));
      final next = result['nextPageToken'];
      if (next != null && next is! String) {
        throw const FormatException('Invalid page token');
      }
      page = next as String?;
    } while (page != null && page.isNotEmpty);
    return files;
  }

  Future<String> _folder(String name, String parent) async {
    final key = jsonEncode([parent, name]);
    final cached = _folders[key];
    if (cached != null) {
      final response = await _request(
        'GET',
        _uri('/drive/v3/files/${Uri.encodeComponent(cached)}', {
          'fields': 'id,ownedByMe,shared,trashed',
        }),
      );
      if (response.statusCode != 404) {
        final file = _json(response);
        if (file['id'] == cached &&
            file['ownedByMe'] == true &&
            file['shared'] == false &&
            file['trashed'] == false) {
          return cached;
        }
      }
      _folders.remove(key);
    }
    var retries = 0;
    while (true) {
      final existing = (await _list(name, parent, folder: true))
          .where((file) => file['ownedByMe'] == true && file['shared'] == false)
          .toList();
      if (existing.isNotEmpty) {
        existing.sort((a, b) {
          final time = DateTime.parse(a['createdTime'] as String)
              .compareTo(DateTime.parse(b['createdTime'] as String));
          return time != 0 ? time : _id(a).compareTo(_id(b));
        });
        return _folders[key] = _id(existing.first);
      }
      StarSyncHttpResponse response;
      try {
        response = await _request(
          'POST',
          _uri('/drive/v3/files', {'fields': 'id'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
          retryNetwork: false,
          retryStatus: false,
          body: utf8.encode(
            jsonEncode({
              'name': name,
              'mimeType': _folderMime,
              'parents': [parent],
            }),
          ),
        );
      } on StarSyncTransportException catch (error) {
        if (error.kind != StarSyncTransportErrorKind.network || retries >= 3) {
          rethrow;
        }
        await _backoff(retries++);
        continue;
      }
      if ((response.statusCode == 429 || response.statusCode >= 500) &&
          retries < 3) {
        await _backoff(retries++);
        continue;
      }
      final created = _id(_json(response));
      _createdFolders.add(created);
      return _folders[key] = created;
    }
  }

  Future<bool> _hasChildren(String folder) async {
    final result = _json(
      await _request(
        'GET',
        _uri('/drive/v3/files', {
          'q': "'${_escape(folder)}' in parents and trashed=false",
          'fields': 'files(id)',
          'pageSize': '1',
        }),
      ),
    );
    final files = result['files'];
    if (files is! List) throw const FormatException('Invalid Drive file list');
    return files.isNotEmpty;
  }

  Future<bool> _isPrivateFolder(String id) async {
    final response = await _request(
      'GET',
      _uri('/drive/v3/files/${Uri.encodeComponent(id)}', {
        'fields': 'id,ownedByMe,shared,trashed',
      }),
    );
    if (response.statusCode == 404) return false;
    final file = _json(response);
    return file['id'] == id &&
        file['ownedByMe'] == true &&
        file['shared'] == false &&
        file['trashed'] == false;
  }

  String _id(Map<String, dynamic> value) {
    final id = value['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Missing Drive id');
    }
    return id;
  }

  static Future<List<Map<String, String>>> _readPendingChecks(
    FlutterSecureStorage storage,
  ) async {
    final raw = await storage.read(key: googleDrivePendingChecksKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid pending checks');
    return decoded.map((entry) {
      if (entry is! Map ||
          (entry['id'] != null &&
              (entry['id'] is! String || (entry['id'] as String).isEmpty)) ||
          entry['root'] is! String ||
          entry['parent'] is! String ||
          entry['account'] is! String ||
          (entry['id'] == null &&
              (entry['name'] is! String ||
                  entry['size'] is! String ||
                  entry['md5'] is! String ||
                  entry['started'] is! String ||
                  entry['uploadKey'] is! String)) ||
          (entry['root'] as String).isEmpty ||
          (entry['parent'] as String).isEmpty) {
        throw const FormatException('Invalid pending check');
      }
      return Map<String, String>.from(entry);
    }).toList();
  }

  Future<List<Map<String, String>>> _pendingChecks() =>
      _readPendingChecks(_storage);

  static Future<int> pendingCheckCount({FlutterSecureStorage? storage}) async =>
      (await _readPendingChecks(storage ?? SecureStorageFactory.create()))
          .length;

  Future<void> _savePendingChecks(List<Map<String, String>> entries) =>
      entries.isEmpty
      ? _storage.delete(key: googleDrivePendingChecksKey)
      : _storage.write(
          key: googleDrivePendingChecksKey,
          value: jsonEncode(entries),
        );

  Future<bool> _verifyPending(Map<String, String> entry) async {
    final parent = entry['parent']!;
    final root = entry['root']!;
    final coursePrivate = await _isPrivateFolder(parent);
    final rootPrivate = await _isPrivateFolder(root);
    final private = coursePrivate && rootPrivate;
    final ids = <String>[];
    if (entry['id'] != null) {
      ids.add(entry['id']!);
    } else {
      final started = DateTime.parse(entry['started']!).toUtc();
      for (final file in await _list(entry['name']!, parent)) {
        final created = DateTime.tryParse(file['createdTime'] as String? ?? '');
        final properties = file['appProperties'];
        if (file['name'] == entry['name'] &&
            file['size'] == entry['size'] &&
            file['md5Checksum'] == entry['md5'] &&
            created != null &&
            !created.toUtc().isBefore(started) &&
            properties is Map &&
            properties['mbgUpload'] == entry['uploadKey']) {
          ids.add(_id(file));
        }
      }
    }
    if (entry['id'] == null && ids.isEmpty) {
      throw StateError('Pending upload not yet found');
    }
    if (private) return true;
    _folders.removeWhere((_, value) => value == parent || value == root);
    for (final id in ids) {
      final deleted = await _request(
        'DELETE',
        _uri('/drive/v3/files/${Uri.encodeComponent(id)}'),
      );
      if (deleted.statusCode != 404) checkStarSyncStatus(deleted.statusCode);
    }
    // A course folder this upload created inherits a root shared meanwhile;
    // its name is course information too. Folders that already existed may
    // hold other files and are left alone.
    if (entry['createdParent'] == '1' && !await _hasChildren(parent)) {
      final deleted = await _request(
        'DELETE',
        _uri('/drive/v3/files/${Uri.encodeComponent(parent)}'),
      );
      if (deleted.statusCode != 404) checkStarSyncStatus(deleted.statusCode);
    }
    return false;
  }

  /// Retries verification using the automatic quota budget.
  Future<void> processPendingChecks() => runZoned(() async {
    final entries = await _pendingChecks();
    Object? failure;
    StackTrace? failureStack;
    for (final entry in List<Map<String, String>>.of(entries)) {
      if (entry['account'] != account) continue;
      try {
        await _verifyPending(entry);
        final remaining = List<Map<String, String>>.of(entries)..remove(entry);
        await _savePendingChecks(remaining);
        entries.remove(entry);
      } on Object catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }, zoneValues: {#driveSaveAutomatic: true});

  Future<String> saveFile({
    required String courseName,
    required String fileName,
    required Stream<List<int>> Function() open,
    required int length,
    String? mimeType,
    bool automatic = false,
  }) => runZoned(
    () => _saveFile(
      courseName: courseName,
      fileName: fileName,
      open: open,
      length: length,
      mimeType: mimeType,
      automatic: automatic,
    ),
    zoneValues: {#driveSaveAutomatic: automatic},
  );

  Future<String> _saveFile({
    required String courseName,
    required String fileName,
    required Stream<List<int>> Function() open,
    required int length,
    String? mimeType,
    required bool automatic,
  }) async {
    if (length < 0 || fileName.isEmpty) throw ArgumentError('Invalid file');
    await processPendingChecks();
    if ((await _pendingChecks()).length >= 100) {
      throw StateError('Too many pending Drive checks');
    }
    final chunks = (length + _chunkSize - 1) ~/ _chunkSize;
    final estimate = 300 + 50 * chunks;
    if (automatic && isAutomaticFileTooLarge(length)) {
      throw const GoogleDriveSaveTooLarge();
    }
    if (automatic && !await _quotaMeter.allowsAutomatic(estimate)) {
      throw const GoogleDriveSaveSoftLimit();
    }
    final course = courseName
        .replaceAll(RegExp(r'[\\/\x00-\x1f\x7f]'), '_')
        .trim();
    final root = await _folder('More Better Gakujo', 'root');
    final parent = await _folder(course.isEmpty ? 'その他' : course, root);
    var name = fileName;
    var suffix = 2;
    String? checksum;
    while (true) {
      final existing = await _list(name, parent);
      if (existing.isNotEmpty && checksum == null) {
        checksum = (await md5.bind(open()).first).toString();
      }
      for (final file in existing) {
        if (file['shared'] == false &&
            file['name'] == name &&
            file['md5Checksum'] == checksum) {
          return _id(file);
        }
      }
      if (existing.isEmpty) break;
      final dot = fileName.lastIndexOf('.');
      final split = dot > 0 ? dot : fileName.length;
      name =
          '${fileName.substring(0, split)} (${suffix++})${fileName.substring(split)}';
    }
    checksum ??= (await md5.bind(open()).first).toString();
    final entry = <String, String>{
      'root': root,
      'parent': parent,
      if (parent != root && _createdFolders.contains(parent)) 'createdParent': '1',
      'account': account,
      'gakujoAccountHash': gakujoAccountHash ?? '',
      'name': name,
      'size': '$length',
      'md5': checksum,
      'started': DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
        isUtc: true,
      ).toIso8601String(),
      'uploadKey': List.generate(
        16,
        (_) => _random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
    };
    final entries = await _pendingChecks();
    entries.add(entry);
    await _savePendingChecks(entries);
    try {
      final response = await _request(
        'POST',
        _uri('/upload/drive/v3/files', {
          'uploadType': 'resumable',
          'fields': 'id',
        }),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'x-upload-content-length': '$length',
          'x-upload-content-type': mimeType ?? 'application/octet-stream',
        },
        body: utf8.encode(
          jsonEncode({
            'name': name,
            'parents': [parent],
            'appProperties': {'mbgUpload': entry['uploadKey']},
            'mimeType': ?mimeType,
          }),
        ),
      );
      checkStarSyncStatus(response.statusCode);
      final location = response.headers.value('location');
      if (location == null) {
        throw const FormatException('Missing upload location');
      }
      final session = _base.resolve(location);
      if (session.scheme != _base.scheme ||
          session.host != _base.host ||
          session.port != _base.port ||
          session.userInfo.isNotEmpty ||
          session.hasFragment) {
        throw const FormatException('Invalid upload location');
      }
      final id = await _upload(session, open, length);
      entry['id'] = id;
      await _savePendingChecks(entries);
      final private = await _verifyPending(entry);
      entries.remove(entry);
      await _savePendingChecks(entries);
      if (!private) throw const GoogleDriveSaveFolderShared();
      return id;
    } on GoogleDriveSaveFolderShared {
      rethrow;
    } on Object catch (error) {
      onPendingCheck?.call();
      throw GoogleDrivePendingCheckException(error);
    }
  }

  int _offset(StarSyncHttpResponse response, int total) {
    final range = response.headers.value('range');
    if (range == null) return 0;
    final match = RegExp(r'^bytes=0-(\d+)$').firstMatch(range);
    if (match == null) throw const FormatException('Invalid upload range');
    final offset = int.parse(match.group(1)!) + 1;
    if (offset > total) throw const FormatException('Invalid upload offset');
    return offset;
  }

  Future<String> _upload(
    Uri session,
    Stream<List<int>> Function() open,
    int total,
  ) async {
    final iterator = StreamIterator<List<int>>(open());
    var pending = <int>[];
    var position = 0;
    var ended = false;
    try {
      while (true) {
        while (pending.length < _chunkSize && !ended) {
          if (await iterator.moveNext()) {
            pending.addAll(iterator.current);
          } else {
            ended = true;
          }
        }
        final count = min(_chunkSize, total - position);
        if (pending.length < count ||
            (count == 0 && (pending.isNotEmpty || !ended))) {
          throw const FormatException('Stream length mismatch');
        }
        if (position + count == total && !ended) {
          if (pending.length != count) {
            throw const FormatException('Stream length mismatch');
          }
          while (await iterator.moveNext()) {
            if (iterator.current.isNotEmpty) {
              throw const FormatException('Stream length mismatch');
            }
          }
          ended = true;
        }
        final chunk = pending.sublist(0, count);
        var acknowledged = 0;
        var failures = 0;
        while (true) {
          StarSyncHttpResponse response;
          try {
            response = await _request(
              'PUT',
              session,
              headers: {
                'content-type': 'application/octet-stream',
                'content-range': total == 0
                    ? 'bytes */0'
                    : 'bytes ${position + acknowledged}-${position + count - 1}/$total',
              },
              body: chunk.sublist(acknowledged),
              retryNetwork: false,
            );
          } on StarSyncTransportException catch (error) {
            if (error.kind != StarSyncTransportErrorKind.network ||
                failures++ >= 3) {
              rethrow;
            }
            await _backoff(failures - 1);
            response = await _request(
              'PUT',
              session,
              headers: {'content-range': 'bytes */$total'},
            );
          }
          if (response.statusCode >= 200 && response.statusCode < 300) {
            if (position + count != total ||
                pending.length != count ||
                !ended) {
              throw const FormatException('Stream length mismatch');
            }
            return _id(_json(response));
          }
          if (response.statusCode != 308) {
            checkStarSyncStatus(response.statusCode);
          }
          final offset = _offset(response, total);
          if (offset < position + acknowledged || offset > position + count) {
            throw const FormatException('Unexpected upload offset');
          }
          if (offset == position + acknowledged && failures++ >= 3) {
            throw const FormatException('Upload made no progress');
          }
          acknowledged = offset - position;
          if (acknowledged == count && count > 0) break;
        }
        pending = pending.sublist(count);
        position += count;
      }
    } finally {
      await iterator.cancel();
    }
  }
}

class GoogleDriveSaveSoftLimit implements Exception {
  const GoogleDriveSaveSoftLimit();
}

class GoogleDriveSaveTooLarge implements Exception {
  const GoogleDriveSaveTooLarge();
}

class GoogleDriveSaveFolderShared implements Exception {
  const GoogleDriveSaveFolderShared();

  @override
  String toString() => '保存先のフォルダが共有されていたため、Google ドライブへの保存を取り消しました';
}

class GoogleDrivePendingCheckException implements Exception {
  const GoogleDrivePendingCheckException(this.cause);

  final Object cause;
}
