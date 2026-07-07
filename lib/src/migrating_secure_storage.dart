import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MigratingSecureStorage extends FlutterSecureStorage {
  MigratingSecureStorage({
    required FlutterSecureStorage primary,
    required FlutterSecureStorage fallback,
    bool deleteFallbackAfterMigration = true,
  })  : _primary = primary,
        _fallback = fallback,
        _deleteFallbackAfterMigration = deleteFallbackAfterMigration;

  final FlutterSecureStorage _primary;
  final FlutterSecureStorage _fallback;
  final bool _deleteFallbackAfterMigration;
  // A cold macOS keychain read (first access after launch, possibly behind an
  // unlock prompt) can take well over a second. Keep the timeout generous
  // enough that a slow-but-successful primary read is not abandoned to the
  // legacy fallback store, which would surface as missing credentials/settings.
  static const _storageOperationTimeout = Duration(seconds: 3);

  Future<Map<String, String?>> readKeys(Iterable<String> keys) async {
    final requestedKeys = keys.toList(growable: false);
    Object? primaryError;
    StackTrace? primaryStackTrace;
    final values = <String, String?>{};

    List<MapEntry<String, String?>> primaryEntries;
    try {
      primaryEntries = await Future.wait(
        requestedKeys.map((key) async {
          String? value;
          try {
            value = await _primary.read(key: key);
          } on Object catch (error, stackTrace) {
            primaryError ??= error;
            primaryStackTrace ??= stackTrace;
          }
          return MapEntry(key, value);
        }),
      ).timeout(_storageOperationTimeout);
    } on TimeoutException catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
      primaryEntries = [
        for (final key in requestedKeys) MapEntry(key, null),
      ];
    }

    for (final entry in primaryEntries) {
      values[entry.key] = entry.value;
    }

    final missingKeys = requestedKeys
        .where((key) => values[key] == null)
        .toList(growable: false);
    if (missingKeys.isEmpty) {
      return values;
    }

    final fallbackEntries = await Future.wait(
      missingKeys.map((key) async {
        final fallbackValue = await _readFallbackKey(key: key);
        return MapEntry(key, fallbackValue);
      }),
    );

    var fallbackHit = false;
    for (final entry in fallbackEntries) {
      final fallbackValue = entry.value;
      values[entry.key] = fallbackValue;
      if (fallbackValue == null) {
        continue;
      }
      fallbackHit = true;
      if (primaryError == null) {
        await _migrateFallbackValue(key: entry.key, value: fallbackValue);
      }
    }

    final error = primaryError;
    if (error != null && !fallbackHit) {
      Error.throwWithStackTrace(error, primaryStackTrace!);
    }
    return values;
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
    Object? primaryError;
    StackTrace? primaryStackTrace;
    String? primaryValue;

    try {
      primaryValue = await _primary
          .read(
            key: key,
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          )
          .timeout(_storageOperationTimeout);
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }

    if (primaryValue != null) {
      return primaryValue;
    }

    final fallbackValue = await _readFallbackKey(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    if (primaryError != null && fallbackValue == null) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }

    if (primaryError == null && fallbackValue != null) {
      await _migrateFallbackValue(
        key: key,
        value: fallbackValue,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }

    return fallbackValue;
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
    Object? primaryError;
    StackTrace? primaryStackTrace;
    Map<String, String> primaryValues = const {};

    try {
      primaryValues = await _primary
          .readAll(
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          )
          .timeout(_storageOperationTimeout);
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }

    final fallbackValues = await _readFallbackAll(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );

    if (primaryError != null && fallbackValues.isEmpty) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }

    final values = <String, String>{
      ...fallbackValues,
      ...primaryValues,
    };

    if (primaryError == null && fallbackValues.isNotEmpty) {
      await _migrateMissingValues(
        primaryValues: primaryValues,
        fallbackValues: fallbackValues,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
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
    final value = await read(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    return value != null;
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
    await _primary.write(
      key: key,
      value: value,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    await _deleteFallbackKey(
      key: key,
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
    await _primary.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    await _deleteFallbackKey(
      key: key,
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
    await _primary.deleteAll(
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    try {
      await _fallback.deleteAll(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on Object {
      // Best effort cleanup only. The primary storage already reflects
      // the requested delete-all state.
    }
  }

  Future<Map<String, String>> _readFallbackAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    try {
      return await _fallback
          .readAll(
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          )
          .timeout(_storageOperationTimeout);
    } on Object {
      return const {};
    }
  }

  Future<String?> _readFallbackKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    try {
      return await _fallback
          .read(
            key: key,
            iOptions: iOptions,
            aOptions: aOptions,
            lOptions: lOptions,
            webOptions: webOptions,
            mOptions: mOptions,
            wOptions: wOptions,
          )
          .timeout(_storageOperationTimeout);
    } on Object {
      return null;
    }
  }

  Future<void> _migrateMissingValues({
    required Map<String, String> primaryValues,
    required Map<String, String> fallbackValues,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    for (final entry in fallbackValues.entries) {
      if (primaryValues.containsKey(entry.key)) {
        continue;
      }

      await _migrateFallbackValue(
        key: entry.key,
        value: entry.value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
  }

  Future<void> _migrateFallbackValue({
    required String key,
    required String value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    try {
      await _primary.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
      if (_deleteFallbackAfterMigration) {
        await _deleteFallbackKey(
          key: key,
          iOptions: iOptions,
          aOptions: aOptions,
          lOptions: lOptions,
          webOptions: webOptions,
          mOptions: mOptions,
          wOptions: wOptions,
        );
      }
    } on Object {
      // Keep reads usable even if a best-effort migration cannot be written.
    }
  }

  Future<void> _deleteFallbackKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    try {
      await _fallback.delete(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on Object {
      // The fallback store may not exist or may already have been cleared.
    }
  }
}
