import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'base32.dart';
import 'secure_storage_factory.dart';

const protectedSecretsKey = 'more_better_gakujo_protected_secrets_v1';
const secretProtectionStateKey = 'more_better_gakujo_secret_protection_v1';
const loginRecordKey = 'more_better_gakujo_login_credentials_v2';
const loginIdKey = 'more_better_gakujo_login_id';
const loginPasswordKey = 'more_better_gakujo_login_password';
const twoFactorSecretKey = 'more_better_gakujo_2fa_secret';
const loginTombstone = '{"version":1,"cleared":true}';

bool isAuthenticationCancellation(Object error) {
  if (error is! PlatformException) return false;
  final detail = '${error.code} ${error.message} ${error.details}'.toLowerCase();
  return detail.contains('authentication error [5]') ||
      detail.contains('authentication error [10]') ||
      detail.contains('authentication error [13]') ||
      detail.contains('-128') || detail.contains('user cancel');
}

FlutterSecureStorage createProtectedSecretStorage() {
  if (Platform.isIOS) {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
        accessControlFlags: [AccessControlFlag.userPresence],
      ),
    );
  }
  return const FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: true,
      resetOnError: false,
      migrateWithBackup: true,
      storageNamespace: 'more_better_gakujo_protected',
      biometricPromptTitle: '本人確認',
      biometricPromptSubtitle: '保存した学情のログイン情報を使います',
      biometricPromptNegativeButton: 'キャンセル',
    ),
  );
}

class ProtectedSecrets {
  const ProtectedSecrets({this.loginCredentials, this.twoFactorSecret});
  final String? loginCredentials;
  final String? twoFactorSecret;
  Map<String, Object> toJson() => {
    'version': 1,
    'loginCredentials': ?loginCredentials,
    'twoFactorSecret': ?twoFactorSecret,
  };
  static ProtectedSecrets decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['version'] != 1 ||
        (value['loginCredentials'] != null &&
            value['loginCredentials'] is! String) ||
        (value['twoFactorSecret'] != null &&
            value['twoFactorSecret'] is! String)) {
      throw const FormatException('Invalid protected secrets');
    }
    return ProtectedSecrets(
      loginCredentials: value['loginCredentials'] as String?,
      twoFactorSecret: value['twoFactorSecret'] as String?,
    );
  }
}

class ProtectedSecretsVault {
  ProtectedSecretsVault({
    FlutterSecureStorage? storage,
    DateTime Function()? clock,
  }) : _storage = storage ?? createProtectedSecretStorage(),
       _clock = clock ?? DateTime.now;
  final FlutterSecureStorage _storage;
  final DateTime Function() _clock;
  ProtectedSecrets? _cache;
  DateTime? _expires;
  Timer? _timer;
  Future<void> _pending = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void clearCache() {
    _timer?.cancel();
    _timer = null;
    _cache = null;
    _expires = null;
  }

  void _remember(ProtectedSecrets value) {
    clearCache();
    _cache = value;
    _expires = _clock().add(const Duration(seconds: 90));
    _timer = Timer(const Duration(seconds: 90), clearCache);
  }

  Future<ProtectedSecrets?> read() => _enqueue(_read);

  Future<ProtectedSecrets?> _read() async {
    if (_cache != null && _clock().isBefore(_expires!)) return _cache;
    clearCache();
    final raw = await _storage.read(key: protectedSecretsKey);
    if (raw == null) return null;
    final ProtectedSecrets value;
    try {
      value = ProtectedSecrets.decode(raw);
    } on FormatException {
      throw const ProtectedSecretsUnreadable();
    }
    _remember(value);
    return value;
  }

  Future<void> write(ProtectedSecrets value) => _enqueue(() => _write(value));

  Future<void> _write(ProtectedSecrets value) async {
    await _storage.write(
      key: protectedSecretsKey,
      value: jsonEncode(value.toJson()),
    );
    _remember(value);
  }

  /// The callbacks must not call vault methods; they run inside the vault
  /// queue, so [onCommitted] sees updates in the order they were committed.
  Future<ProtectedSecrets> update(
    ProtectedSecrets Function(ProtectedSecrets current) change, {
    Future<void> Function(ProtectedSecrets committed)? onCommitted,
    bool replaceUnreadable = false,
  }) => _enqueue(() async {
    ProtectedSecrets current;
    try {
      current = await _read() ?? const ProtectedSecrets();
    } on ProtectedSecretsUnreadable {
      if (!replaceUnreadable) rethrow;
      current = const ProtectedSecrets();
    }
    final value = change(current);
    await _write(value);
    if (onCommitted != null) await onCommitted(value);
    return value;
  });

  Future<void> delete() => _enqueue(() async {
    clearCache();
    await _storage.delete(key: protectedSecretsKey);
  });
}

class SecretProtectionInfo {
  const SecretProtectionInfo({
    this.enabled = false,
    this.loginId,
    this.hasTwoFactorSecret = false,
  });
  final bool enabled;
  final String? loginId;
  final bool hasTwoFactorSecret;
}

class SecretProtectionState {
  SecretProtectionState({
    FlutterSecureStorage? storage,
    ProtectedSecretsVault? vault,
    bool? supported,
  }) : storage = storage ?? SecureStorageFactory.create(),
       vault = vault ?? ProtectedSecretsVault(),
       supported = supported ?? (Platform.isAndroid || Platform.isIOS);
  final FlutterSecureStorage storage;
  final ProtectedSecretsVault vault;

  /// Only Android and iOS offer the setting. Elsewhere the state is never
  /// read, so settings loads keep their existing storage access pattern.
  final bool supported;
  Future<SecretProtectionInfo> read() async {
    if (!supported) return const SecretProtectionInfo();
    final raw = await storage.read(key: secretProtectionStateKey);
    if (raw == null) return const SecretProtectionInfo();
    try {
      final v = jsonDecode(raw);
      if (v is! Map ||
          v['version'] != 1 ||
          v['enabled'] is! bool ||
          (v['loginId'] != null && v['loginId'] is! String) ||
          v['hasTwoFactorSecret'] is! bool) {
        return const SecretProtectionInfo();
      }
      return SecretProtectionInfo(
        enabled: v['enabled'] as bool,
        loginId: v['loginId'] as String?,
        hasTwoFactorSecret: v['hasTwoFactorSecret'] as bool,
      );
    } on FormatException {
      return const SecretProtectionInfo();
    }
  }

  Future<void> write(SecretProtectionInfo value) => storage.write(
    key: secretProtectionStateKey,
    value: jsonEncode({
      'version': 1,
      'enabled': value.enabled,
      if (value.loginId != null) 'loginId': value.loginId,
      'hasTwoFactorSecret': value.hasTwoFactorSecret,
    }),
  );

  /// Changes the vault and rewrites the public state from the committed
  /// value inside the same queued operation, so concurrent login and 2FA
  /// updates cannot leave stale metadata behind.
  Future<ProtectedSecrets> updateSecrets(
    ProtectedSecrets Function(ProtectedSecrets current) change, {
    bool replaceUnreadable = false,
  }) => vault.update(
    change,
    replaceUnreadable: replaceUnreadable,
    onCommitted: (value) => write(
      SecretProtectionInfo(
        enabled: true,
        loginId: loginIdFromRecord(value.loginCredentials),
        hasTwoFactorSecret: value.twoFactorSecret != null,
      ),
    ),
  );
  Future<void> cleanupNormalSecrets() async {
    for (final action in <Future<void> Function()>[
      () => storage.write(key: loginRecordKey, value: loginTombstone),
      () => storage.delete(key: loginIdKey),
      () => storage.delete(key: loginPasswordKey),
      () => storage.delete(key: twoFactorSecretKey),
    ]) {
      try {
        await action();
      } on Object {
        /* Retry on next startup. */
      }
    }
  }
}

// Uses the same v2 validation rules as the settings store.
String? loginIdFromRecord(String? raw) {
  if (raw == null) return null;
  try {
    final v = jsonDecode(raw);
    if (v is! Map ||
        v['version'] != 1 ||
        v['cleared'] == true ||
        v['loginId'] is! String ||
        v['password'] is! String) {
      return null;
    }
    final id = (v['loginId'] as String).trim();
    return id.isEmpty || (v['password'] as String).isEmpty ? null : id;
  } on FormatException {
    return null;
  }
}

class ProtectedSecretsUnreadable implements Exception {
  const ProtectedSecretsUnreadable();
}

class SecretProtectionController {
  SecretProtectionController(this.state);
  final SecretProtectionState state;
  Future<void> enable() async {
    final storage = state.storage;
    var record = await storage.read(key: loginRecordKey);
    if (record == null) {
      final id = (await storage.read(key: loginIdKey))?.trim() ?? '';
      final password = await storage.read(key: loginPasswordKey) ?? '';
      if (id.isNotEmpty && password.isNotEmpty) {
        record = jsonEncode({
          'version': 1,
          'loginId': id,
          'password': password,
        });
      }
    }
    if (loginIdFromRecord(record) == null) record = null;
    final rawSecret = await storage.read(key: twoFactorSecretKey);
    final secret = rawSecret == null ? null : Base32.normalize(rawSecret);
    if (secret != null && !Base32.isValid(secret)) {
      throw const FormatException('Invalid Base32 secret');
    }
    final value = ProtectedSecrets(
      loginCredentials: record,
      twoFactorSecret: secret,
    );
    await state.vault.write(value);
    state.vault.clearCache();
    final verified = await state.vault.read();
    if (verified == null ||
        jsonEncode(verified.toJson()) != jsonEncode(value.toJson())) {
      throw StateError('Vault verification failed');
    }
    await state.write(
      SecretProtectionInfo(
        enabled: true,
        loginId: loginIdFromRecord(record),
        hasTwoFactorSecret: secret != null,
      ),
    );
    await state.cleanupNormalSecrets();
  }

  Future<void> disable() async {
    ProtectedSecrets value;
    try {
      value = await state.vault.read() ?? const ProtectedSecrets();
    } on Object catch (error) {
      if (isAuthenticationCancellation(error)) rethrow;
      throw const ProtectedSecretsUnreadable();
    }
    await state.storage.write(
      key: loginRecordKey,
      value: value.loginCredentials ?? loginTombstone,
    );
    if (value.twoFactorSecret == null) {
      await state.storage.delete(key: twoFactorSecretKey);
    } else {
      await state.storage.write(
        key: twoFactorSecretKey,
        value: value.twoFactorSecret,
      );
    }
    await state.write(const SecretProtectionInfo());
    await state.vault.delete();
  }

  Future<void> disableAndDiscard() async {
    await state.vault.delete();
    await state.storage.write(key: loginRecordKey, value: loginTombstone);
    await state.storage.delete(key: loginIdKey);
    await state.storage.delete(key: loginPasswordKey);
    await state.storage.delete(key: twoFactorSecretKey);
    await state.write(const SecretProtectionInfo());
  }
}
