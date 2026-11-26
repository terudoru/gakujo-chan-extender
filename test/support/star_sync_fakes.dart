import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class StarSyncFakeStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failStarWriteOnce = false;
  bool failStateAfterStarWrite = false;
  String? failReadKey;
  String? failWriteKey;
  String? failWriteKeyOnce;
  String? failWriteKeyAfterCommitOnce;
  String? failDeleteKey;
  void Function()? onStarRead;
  void Function(String)? onWrite;
  void Function(String, String?)? onWriteValue;
  Future<void> Function(String)? beforeWrite;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == failReadKey) throw StateError('read failed');
    if (key == 'more_better_gakujo_starred_messages') onStarRead?.call();
    return values[key];
  }

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
    onWrite?.call(key);
    onWriteValue?.call(key, value);
    if (beforeWrite != null) await beforeWrite!(key);
    if (key == failWriteKey) throw StateError('write failed');
    if (key == failWriteKeyOnce) {
      failWriteKeyOnce = null;
      throw StateError('sync write failed');
    }
    if (failStarWriteOnce && key == 'more_better_gakujo_starred_messages') {
      failStarWriteOnce = false;
      throw StateError('star write failed');
    }
    if (failStateAfterStarWrite &&
        key == 'more_better_gakujo_starred_messages') {
      failStateAfterStarWrite = false;
      failWriteKeyOnce = starSyncStateKey;
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    if (key == failWriteKeyAfterCommitOnce) {
      failWriteKeyAfterCommitOnce = null;
      throw StateError('write failed after changing storage');
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
    if (key == failDeleteKey) throw StateError('delete failed');
    values.remove(key);
  }
}

class StarSyncFakeTransport implements StarSyncTransport {
  StarSyncFakeTransport({this.yieldForMissingHooks = false});

  // Keep the engine fixtures' original async boundary even with no hook.
  final bool yieldForMissingHooks;
  String? failPutPathOnce;
  final files = <String, List<int>>{};
  int puts = 0;
  int deletes = 0;
  int lists = 0;
  int serverFailures = 0;
  final gets = <String, int>{};
  Completer<void>? getStarted;
  Completer<void>? getRelease;
  Completer<void>? listStarted;
  Completer<void>? listRelease;
  bool failDevicePutOnce = false;
  bool simulateKeyringRace = false;
  bool _racePending = false;
  List<int>? overwriteKeyring;
  bool revoked = false;
  bool authFailure = false;
  StarSyncTransportErrorKind? driveFailure;
  Completer<void>? devicePut;
  void Function(String, int)? onGet;
  Future<void> Function(String)? beforeEnsureDirectory;
  Future<void> Function(String)? afterPut;

  @override
  void close() {}

  @override
  Future<void> ensureDirectory(String path) async {
    final hook = beforeEnsureDirectory;
    if (hook != null || yieldForMissingHooks) await hook?.call(path);
  }

  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async {
    lists++;
    if (driveFailure != null) {
      throw StarSyncTransportException(
        driveFailure!,
        'Drive rejected request',
        statusCode: 403,
      );
    }
    if (authFailure) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.auth,
        'unauthorized',
        statusCode: 401,
      );
    }
    if (revoked) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.revoked,
      );
    }
    if (serverFailures > 0) {
      serverFailures--;
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.server,
        'busy',
        statusCode: 503,
      );
    }
    final started = listStarted;
    final release = listRelease;
    if (started != null && release != null) {
      listStarted = null;
      listRelease = null;
      started.complete();
      await release.future;
    }
    return [
      for (final entry in files.entries)
        if (entry.key.startsWith('$directory/'))
          StarSyncRemoteEntry(path: entry.key, etag: base64Encode(entry.value)),
    ];
  }

  @override
  Future<StarSyncRemoteObject?> get(
    String path, {
    int maxBytes = starSyncDefaultMaxBytes,
  }) async {
    final started = getStarted;
    final release = getRelease;
    if (started != null && release != null) {
      getStarted = null;
      getRelease = null;
      started.complete();
      await release.future;
    }
    gets[path] = (gets[path] ?? 0) + 1;
    onGet?.call(path, gets[path]!);
    if (simulateKeyringRace && path == 'stars/keyring.json') {
      simulateKeyringRace = false;
      _racePending = true;
      return null;
    }
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
    if (path == failPutPathOnce) {
      failPutPathOnce = null;
      throw StateError('collection upload failed');
    }
    if (failDevicePutOnce && path.startsWith('stars/devices/')) {
      failDevicePutOnce = false;
      throw StateError('device upload failed');
    }
    if (_racePending && createOnly && path == 'stars/keyring.json') {
      _racePending = false;
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.alreadyExists,
        'exists',
      );
    }
    if (createOnly && files.containsKey(path)) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.alreadyExists,
        'exists',
      );
    }
    files[path] = List.of(bytes);
    if (createOnly &&
        path == 'stars/keyring.json' &&
        overwriteKeyring != null) {
      files[path] = overwriteKeyring!;
      overwriteKeyring = null;
    }
    puts++;
    if (path.startsWith('stars/devices/')) devicePut?.complete();
    final hook = afterPut;
    if (hook != null || yieldForMissingHooks) await hook?.call(path);
  }

  @override
  Future<void> delete(String path) async {
    deletes++;
    files.remove(path);
  }
}
