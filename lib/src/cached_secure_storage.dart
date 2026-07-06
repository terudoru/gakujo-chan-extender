import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CachedSecureStorage extends FlutterSecureStorage {
  CachedSecureStorage(
    this._delegate, {
    bool cacheErrors = false,
  }) : _cacheErrors = cacheErrors;

  final FlutterSecureStorage _delegate;
  final bool _cacheErrors;
  Future<Map<String, String>>? _cacheFuture;
  Map<String, String>? _cache;

  void clearCache() {
    _cache = null;
    _cacheFuture = null;
  }

  Future<Map<String, String>> _snapshot() {
    final existing = _cache;
    if (existing != null) {
      return Future.value(existing);
    }
    return _cacheFuture ??= _delegate.readAll().then(
      (values) {
        _cache = Map<String, String>.from(values);
        return _cache!;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_cacheErrors) {
          _cacheFuture = null;
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

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
    final values = await _snapshot();
    return values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map<String, String>.from(await _snapshot());
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final values = await _snapshot();
    return values.containsKey(key);
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
    await _delegate.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    final cache = _cache;
    if (cache == null) {
      return;
    }
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
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
    await _delegate.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    _cache?.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _delegate.deleteAll(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    _cache = <String, String>{};
    _cacheFuture = Future.value(_cache);
  }
}
