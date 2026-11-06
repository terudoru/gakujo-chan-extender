import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BundledSecureStorage extends FlutterSecureStorage {
  BundledSecureStorage({
    required this._storage,
    required this._bundleKey,
    Set<String> uncachedKeys = const {},
  }) : _uncachedKeys = Set<String>.unmodifiable(uncachedKeys);

  final FlutterSecureStorage _storage;
  final String _bundleKey;
  final Set<String> _uncachedKeys;
  Future<Map<String, String>>? _pendingRead;
  Map<String, String>? _cachedValues;
  Future<void> _pendingWrite = Future<void>.value();

  /// Drops the in-memory bundle cache so the next read hits the keychain again.
  ///
  /// Used by recovery flows: if an earlier read cached an empty/stale bundle
  /// (e.g. the keychain was transiently unavailable), clearing forces a fresh
  /// read instead of serving the poisoned cache.
  void clearCache() {
    _cachedValues = null;
    _pendingRead = null;
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
    final values = await (_uncachedKeys.contains(key)
        ? _readFreshBundle(
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          )
        : _readBundle(
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          ));
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
    final values = await _readBundle(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    if (_uncachedKeys.isNotEmpty) {
      final fresh = await _readFreshBundle(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
      for (final key in _uncachedKeys) {
        if (fresh.containsKey(key)) values[key] = fresh[key]!;
      }
    }
    return values;
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
    final values = await (_uncachedKeys.contains(key)
        ? _readFreshBundle(
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          )
        : _readBundle(
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          ));
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
    await _updateBundle(
      (values) {
        if (value == null) {
          values.remove(key);
        } else {
          values[key] = value;
        }
      },
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
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
    await _updateBundle(
      (values) {
        values.remove(key);
      },
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
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
    final operation = _pendingWrite.then((_) async {
      _pendingRead = null;
      _cachedValues = const {};
      await _storage.delete(
        key: _bundleKey,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    });
    _pendingWrite = operation.catchError((_) {});
    await operation;
  }

  Future<Map<String, String>> _readBundle({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _pendingWrite;
    final cachedValues = _cachedValues;
    if (cachedValues != null) {
      return Map<String, String>.from(cachedValues);
    }
    final pendingRead = _pendingRead;
    if (pendingRead != null) {
      return pendingRead.then(Map<String, String>.from);
    }
    final read = _readBundleUncached(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    ).then(_withoutUncachedKeys);
    _pendingRead = read;
    return read.then((values) {
      _cachedValues = Map<String, String>.from(values);
      return Map<String, String>.from(values);
    }).whenComplete(() {
      _pendingRead = null;
    });
  }

  Map<String, String> _withoutUncachedKeys(Map<String, String> values) {
    return Map<String, String>.from(values)
      ..removeWhere((key, _) => _uncachedKeys.contains(key));
  }

  Future<Map<String, String>> _readFreshBundle({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await _pendingWrite;
    return _readBundleUncached(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }

  Future<Map<String, String>> _readBundleUncached({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final raw = await _storage.read(
      key: _bundleKey,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    if (raw == null || raw.trim().isEmpty) {
      return const {};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const {};
    }

    return decoded.map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
  }

  Future<void> _writeBundle(
    Map<String, String> values, {
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final snapshot = Map<String, String>.from(values);
    final encoded = jsonEncode(snapshot);
    try {
      await _storage.write(
        key: _bundleKey,
        value: encoded,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on PlatformException catch (error) {
      if (!_isDuplicateItemError(error)) {
        rethrow;
      }
      // flutter_secure_storage's update-or-add write path can surface
      // errSecDuplicateItem (-25299) on some macOS/iOS keychains: the item
      // exists but the update query does not match it, so the add is rejected.
      // Delete the stale entry and rewrite the authoritative bundle value.
      final previousRaw = await _storage.read(
        key: _bundleKey,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
      await _storage.delete(
        key: _bundleKey,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
      try {
        await _storage.write(
          key: _bundleKey,
          value: encoded,
          iOptions: iOptions,
          aOptions: aOptions,
          lOptions: lOptions,
          webOptions: webOptions,
          mOptions: mOptions,
          wOptions: wOptions,
        );
      } catch (writeError, writeStackTrace) {
        try {
          await _storage.write(
            key: _bundleKey,
            value: previousRaw,
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          );
        } catch (_) {
          // Best effort: preserve the rewrite failure even if restore fails.
        }
        Error.throwWithStackTrace(writeError, writeStackTrace);
      }
    }
    _cachedValues = _withoutUncachedKeys(snapshot);
    _pendingRead = null;
  }

  static bool _isDuplicateItemError(PlatformException error) {
    if (error.details == -25299) {
      return true;
    }
    final description =
        '${error.code} ${error.message ?? ''} ${error.details ?? ''}'
            .toLowerCase();
    return description.contains('-25299') ||
        description.contains('already exists');
  }

  Future<void> _updateBundle(
    void Function(Map<String, String> values) update, {
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final operation = _pendingWrite.then((_) async {
      final values = await _readBundleUncached(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
      final nextValues = Map<String, String>.from(values);
      update(nextValues);
      await _writeBundle(
        nextValues,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    });
    _pendingWrite = operation.catchError((_) {});
    await operation;
  }
}
