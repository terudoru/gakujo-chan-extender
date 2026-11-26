import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_transaction.dart';

class KeyringLockGateStorage extends FlutterSecureStorage {
  KeyringLockGateStorage({
    required FlutterSecureStorage inner,
    this.beforeFirstAccess,
  }) : _inner = inner,
       super(
         iOptions: inner.iOptions,
         aOptions: inner.aOptions,
         lOptions: inner.lOptions,
         webOptions: inner.webOptions,
         mOptions: inner.mOptions,
         wOptions: inner.wOptions,
       );

  final FlutterSecureStorage _inner;
  final Future<void> Function()? beforeFirstAccess;
  Future<void>? _beforeFirstAccessFuture;
  bool _locked = false;
  final _operations = StorageOperationQueue();

  void reopen() {
    _locked = false;
  }

  void _throwIfLocked() {
    if (_locked) {
      throw PlatformException(code: 'KeyringLocked', message: 'KeyringLocked');
    }
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    _throwIfLocked();
    // Startup callers can overlap; check again after the previous access so
    // cancelling one unlock prompt also blocks every queued access.
    return _operations.run(() async {
      _throwIfLocked();
      final beforeFirstAccess = this.beforeFirstAccess;
      if (beforeFirstAccess != null) {
        await (_beforeFirstAccessFuture ??= Future<void>.sync(beforeFirstAccess)
            .catchError((Object _, StackTrace _) {}));
      }
      try {
        return await operation();
      } on PlatformException catch (error) {
        if (error.code == 'KeyringLocked') {
          _locked = true;
        }
        rethrow;
      }
    });
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
  }) {
    return _guard(
      () => _inner.read(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
    );
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
  }) {
    return _guard(
      () => _inner.write(
        key: key,
        value: value,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
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
  }) {
    return _guard(
      () => _inner.delete(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
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
  }) {
    return _guard(
      () => _inner.readAll(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
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
  }) {
    return _guard(
      () => _inner.deleteAll(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
    );
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
  }) {
    return _guard(
      () => _inner.containsKey(
        key: key,
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
    );
  }

  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return _guard(
      () => _inner.checkUpgradeStatus(
        iOptions: iOptions,
        aOptions: aOptions,
        lOptions: lOptions,
        webOptions: webOptions,
        mOptions: mOptions,
        wOptions: wOptions,
      ),
    );
  }

  @override
  void registerListener({
    required String key,
    required ValueChanged<String?> listener,
  }) {
    _inner.registerListener(key: key, listener: listener);
  }

  @override
  void unregisterListener({
    required String key,
    required ValueChanged<String?> listener,
  }) {
    _inner.unregisterListener(key: key, listener: listener);
  }

  @override
  void unregisterAllListenersForKey({required String key}) {
    _inner.unregisterAllListenersForKey(key: key);
  }

  @override
  void unregisterAllListeners() {
    _inner.unregisterAllListeners();
  }

  @override
  Stream<bool>? get onCupertinoProtectedDataAvailabilityChanged =>
      _inner.onCupertinoProtectedDataAvailabilityChanged;

  @override
  Future<bool?> isCupertinoProtectedDataAvailable() =>
      _inner.isCupertinoProtectedDataAvailable();
}
