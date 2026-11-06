import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceOnlySecretStorage extends FlutterSecureStorage {
  DeviceOnlySecretStorage({
    required FlutterSecureStorage inner,
    required Set<String> secretKeys,
  }) : _inner = inner,
       _secretKeys = Set.unmodifiable(secretKeys),
       _deviceOptions = _makeDeviceOptions(inner.iOptions);

  final FlutterSecureStorage _inner;
  final Set<String> _secretKeys;
  final IOSOptions _deviceOptions;
  static const physicalSuffix = '.device_only';

  static IOSOptions _makeDeviceOptions(IOSOptions options) => IOSOptions(
    accountName: options.accountName,
    groupId: options.groupId,
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: options.synchronizable,
    label: options.label,
    description: options.description,
    comment: options.comment,
    isInvisible: options.isInvisible,
    isNegative: options.isNegative,
    creationDate: options.creationDate,
    lastModifiedDate: options.lastModifiedDate,
    resultLimit: options.resultLimit,
    shouldReturnPersistentReference: options.shouldReturnPersistentReference,
    authenticationUIBehavior: options.authenticationUIBehavior,
    accessControlFlags: options.accessControlFlags,
    useSecureEnclave: options.useSecureEnclave,
  );

  String _physicalKey(String key) => '$key$physicalSuffix';

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
    if (!_secretKeys.contains(key)) {
      return _inner.read(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
    final value = await _inner.read(
      key: _physicalKey(key),
      iOptions: _deviceOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    if (value != null) return value;
    final legacy = await _inner.read(
      key: key,
      iOptions: null,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    if (legacy != null) {
      try {
        await _inner.write(
          key: _physicalKey(key),
          value: legacy,
          iOptions: _deviceOptions,
          aOptions: aOptions,
          lOptions: lOptions,
          webOptions: webOptions,
          mOptions: mOptions,
          wOptions: wOptions,
        );
        await _inner.delete(
          key: key,
          iOptions: null,
          aOptions: aOptions,
          lOptions: lOptions,
          webOptions: webOptions,
          mOptions: mOptions,
          wOptions: wOptions,
        );
      } on Object {
        // Preserve the legacy value when migration cannot complete.
      }
    }
    return legacy;
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
    if (!_secretKeys.contains(key)) {
      return _inner.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
    if (value == null) {
      return delete(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
    await _inner.write(
      key: _physicalKey(key),
      value: value,
      iOptions: _deviceOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    try {
      await _inner.delete(
        key: key,
        iOptions: null,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on Object {
      // The new value is already saved; legacy cleanup is best-effort.
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
    if (!_secretKeys.contains(key)) {
      return _inner.delete(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
    Object? firstError;
    StackTrace? firstStack;
    try {
      await _inner.delete(
        key: _physicalKey(key),
        iOptions: _deviceOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on Object catch (error, stack) {
      firstError = error;
      firstStack = stack;
    }
    try {
      await _inner.delete(
        key: key,
        iOptions: null,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on Object catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
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
    if (!_secretKeys.contains(key)) {
      return _inner.containsKey(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    }
    return await _inner.containsKey(
          key: _physicalKey(key),
          iOptions: _deviceOptions,
          aOptions: aOptions,
          lOptions: lOptions,
          webOptions: webOptions,
          mOptions: mOptions,
          wOptions: wOptions,
        ) ||
        await _inner.containsKey(
          key: key,
          iOptions: null,
          aOptions: aOptions,
          lOptions: lOptions,
          webOptions: webOptions,
          mOptions: mOptions,
          wOptions: wOptions,
        );
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
    final values = Map<String, String>.of(
      await _inner.readAll(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
    );
    final deviceValues = await _inner.readAll(
      iOptions: _deviceOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
    for (final key in _secretKeys) {
      final physicalKey = _physicalKey(key);
      values.remove(physicalKey);
      final value = deviceValues[physicalKey];
      if (value != null) values[key] = value;
    }
    return values;
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
    Object? firstError;
    StackTrace? firstStack;
    try {
      await _inner.deleteAll(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on Object catch (error, stack) {
      firstError = error;
      firstStack = stack;
    }
    try {
      await _inner.deleteAll(
        iOptions: _deviceOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      );
    } on Object catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
