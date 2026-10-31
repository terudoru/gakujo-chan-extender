import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../gakujo_activity_store.dart';
import '../secure_storage_factory.dart';
import '../secure_storage_transaction.dart';
import 'star_sync_config.dart';
import 'star_sync_crypto.dart';
import 'star_sync_document.dart';
import 'star_sync_google_auth.dart';
import 'star_sync_s3_transport.dart';
import 'star_sync_transport.dart';
import 'star_sync_webdav_transport.dart';

const starSyncConfigKey = 'more_better_gakujo_star_sync_config';
const starSyncStateKey = 'more_better_gakujo_star_sync_state';
const _keyringPath = 'stars/keyring.json';
const _deviceDirectory = 'stars/devices';

Future<String> _createKeyringJson(
  String passphrase,
  int memory,
  int iterations,
  int parallelism,
) => Isolate.run(() async {
  final created = await createStarSyncKeyring(
    passphrase,
    params: StarSyncKdfParams(
      memoryKiB: memory,
      iterations: iterations,
      parallelism: parallelism,
    ),
  );
  return jsonEncode(created.keyring.toJson());
});

Future<List<int>> _unwrapKeyBytes(String encoded, String passphrase) =>
    Isolate.run(() async {
      final keyring = StarSyncKeyring.fromJson(jsonDecode(encoded));
      return starSyncKeyBytes(await unwrapStarSyncKeyring(keyring, passphrase));
    });

Future<String> _rewrapKeyringJson(
  String encoded,
  List<int> bytes,
  String passphrase,
) => Isolate.run(() async {
  final keyring = StarSyncKeyring.fromJson(jsonDecode(encoded));
  final result = await rewrapStarSyncKeyring(
    starSyncKeyFromBytes(bytes),
    keyring,
    passphrase,
  );
  return jsonEncode(result.toJson());
});

enum StarSyncTrigger { localChange, startup, resume, manual }

enum StarSyncPairingSetup { created, needsPairingCode }

class StarSyncAccountRequiredException implements Exception {
  const StarSyncAccountRequiredException();
}

class StarSyncAccountMismatchException implements Exception {
  const StarSyncAccountMismatchException();
}

class StarSyncSetupRaceException extends StateError {
  StarSyncSetupRaceException() : super('Keyring changed during reset');
}

class _AccountChanged implements Exception {
  const _AccountChanged();
}

class StarSyncPairingMismatchException implements Exception {
  const StarSyncPairingMismatchException();
}

class StarSyncStatusSnapshot {
  const StarSyncStatusSnapshot({
    this.enabled = false,
    this.status = StarSyncStatus.disabled,
    this.lastSyncAt,
    this.lastError,
    this.syncing = false,
    this.cooldownUntil,
  });
  final bool enabled;
  final StarSyncStatus status;
  final DateTime? lastSyncAt;
  final String? lastError;
  final bool syncing;
  final DateTime? cooldownUntil;
}

class StarSyncResult {
  const StarSyncResult({
    this.localChanged = false,
    this.skippedFiles = 0,
    this.devices = 0,
  });
  final bool localChanged;
  final int skippedFiles;
  final int devices;
}

class StarSyncDeviceInfo {
  const StarSyncDeviceInfo({
    required this.deviceId,
    this.lastModified,
    required this.isThisDevice,
  });
  final String deviceId;
  final DateTime? lastModified;
  final bool isThisDevice;
}

class StarSyncState {
  StarSyncState({
    required this.deviceId,
    required this.dataKey,
    required this.keyId,
    this.boundAccount,
    this.clock = 0,
    Map<String, StarSyncRecord>? records,
    Map<String, dynamic>? remoteCache,
    Map<String, DateTime>? retiredKeyIds,
    this.lastUploadedHash,
    this.lastSyncAt,
    this.lastError,
    this.status = StarSyncStatus.ok,
    this.pendingBulkReplace = false,
    List<String>? pendingLocalClearIds,
    this.keyringEtag,
    this.pendingLocalChange = false,
    this.localReviewRequired = false,
    this.cooldownUntil,
    this.serverFailures = 0,
    this.backgroundDate,
    this.backgroundCount = 0,
  }) : records = records ?? {},
       remoteCache = remoteCache ?? {},
       retiredKeyIds = retiredKeyIds ?? {},
       pendingLocalClearIds = pendingLocalClearIds ?? [];
  final String deviceId;
  String dataKey;
  String keyId;
  final String? boundAccount;
  int clock;
  Map<String, StarSyncRecord> records;
  Map<String, dynamic> remoteCache;
  Map<String, DateTime> retiredKeyIds;
  String? lastUploadedHash;
  DateTime? lastSyncAt;
  String? lastError;
  StarSyncStatus status;
  bool pendingBulkReplace;
  List<String> pendingLocalClearIds;
  String? keyringEtag;
  bool pendingLocalChange;
  bool localReviewRequired;
  DateTime? cooldownUntil;
  int serverFailures;
  String? backgroundDate;
  int backgroundCount;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'dataKey': dataKey,
    'keyId': keyId,
    'boundAccount': boundAccount,
    'clock': clock,
    'records': records.map((key, value) => MapEntry(key, value.toJson())),
    'remoteCache': remoteCache,
    'retiredKeyIds': retiredKeyIds.map(
      (key, value) => MapEntry(key, value.toIso8601String()),
    ),
    'lastUploadedHash': lastUploadedHash,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastError': lastError,
    'status': status.name,
    'pendingBulkReplace': pendingBulkReplace,
    'pendingLocalClearIds': pendingLocalClearIds,
    'keyringEtag': keyringEtag,
    'pendingLocalChange': pendingLocalChange,
    'localReviewRequired': localReviewRequired,
    'cooldownUntil': cooldownUntil?.toIso8601String(),
    'serverFailures': serverFailures,
    'backgroundDate': backgroundDate,
    'backgroundCount': backgroundCount,
  };

  factory StarSyncState.fromJson(Map<String, dynamic> json) {
    final records = <String, StarSyncRecord>{};
    (json['records'] as Map<String, dynamic>).forEach((key, value) {
      final record = StarSyncRecord.fromJson(value, id: key);
      if (record != null) records[key] = record;
    });
    return StarSyncState(
      deviceId: json['deviceId'] as String,
      dataKey: json['dataKey'] as String,
      keyId: json['keyId'] as String,
      boundAccount: json['boundAccount'] as String?,
      clock: json['clock'] as int,
      records: records,
      remoteCache: Map<String, dynamic>.from(json['remoteCache'] as Map),
      retiredKeyIds: {
        for (final entry in (json['retiredKeyIds'] as Map? ?? {}).entries)
          if (entry.key is String &&
              entry.value is String &&
              DateTime.tryParse(entry.value as String) != null)
            entry.key as String: DateTime.parse(entry.value as String),
      },
      lastUploadedHash: json['lastUploadedHash'] as String?,
      lastSyncAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
      lastError: json['lastError'] as String?,
      status: StarSyncStatus.values.byName(json['status'] as String),
      pendingBulkReplace: json['pendingBulkReplace'] as bool? ?? false,
      pendingLocalClearIds: (json['pendingLocalClearIds'] as List? ?? [])
          .cast<String>()
          .toList(),
      keyringEtag: json['keyringEtag'] as String?,
      pendingLocalChange: json['pendingLocalChange'] as bool? ?? false,
      localReviewRequired:
          json['localReviewRequired'] as bool? ??
          (json['status'] == 'accountMismatch'),
      cooldownUntil: DateTime.tryParse(json['cooldownUntil'] as String? ?? ''),
      serverFailures: json['serverFailures'] as int? ?? 0,
      backgroundDate: json['backgroundDate'] as String?,
      backgroundCount: json['backgroundCount'] as int? ?? 0,
    );
  }
}

class StarSyncEngine {
  StarSyncEngine({
    required this.activityStore,
    FlutterSecureStorage? secureStorage,
    StarSyncTransport Function(StarSyncConfig)? transportFactory,
    StarSyncTransport Function()? googleDriveTransport,
    DateTime Function()? now,
    Random? random,
    Future<void> Function(Duration)? delay,
    Timer Function(Duration, void Function())? timerFactory,
    this.loginId,
    this.canSync,
    this.onLocalStarsChanged,
    this.kdfParams = const StarSyncKdfParams(),
  }) : _storage = secureStorage ?? SecureStorageFactory.create(),
       _transportFactory =
           transportFactory ??
           ((config) => _defaultTransport(config, googleDriveTransport)),
       _now = now ?? DateTime.now,
       _random = random ?? Random(),
       _delay = delay ?? Future<void>.delayed,
       _timerFactory = timerFactory ?? Timer.new;

  final GakujoActivityStore activityStore;
  final FlutterSecureStorage _storage;
  final StarSyncTransport Function(StarSyncConfig) _transportFactory;
  final DateTime Function() _now;
  final Random _random;
  final Future<void> Function(Duration) _delay;
  final Timer Function(Duration, void Function()) _timerFactory;
  Completer<void>? _backgroundWake;
  final String? Function()? loginId;
  final bool Function()? canSync;
  final void Function()? onLocalStarsChanged;
  final StarSyncKdfParams kdfParams;
  final StorageOperationQueue _queue = StorageOperationQueue();
  final ValueNotifier<StarSyncStatusSnapshot> _status = ValueNotifier(
    const StarSyncStatusSnapshot(),
  );
  ValueListenable<StarSyncStatusSnapshot> get status => _status;
  StarSyncConfig? _config;
  StarSyncConfig? get config => _config;
  StarSyncState? _state;
  Future<StarSyncResult>? _running;
  bool _followUp = false;
  StarSyncTrigger _followUpTrigger = StarSyncTrigger.localChange;
  bool _wakeForLocal = false;
  Timer? _timer;
  Timer? _cooldownTimer;
  bool _disposed = false;
  int _accountGeneration = 0;
  int get accountGeneration => _accountGeneration;

  static StarSyncTransport _defaultTransport(
    StarSyncConfig config,
    StarSyncTransport Function()? googleDriveTransport,
  ) => switch (config.backend) {
    StarSyncBackend.webDav => StarSyncWebDavTransport(config.webDav!),
    StarSyncBackend.s3 => StarSyncS3Transport(config.s3!),
    StarSyncBackend.googleDrive =>
      googleDriveTransport?.call() ??
          (throw StateError('Google Drive transport is not configured')),
  };

  Future<T> runAccountChange<T>(Future<T> Function() change) =>
      _queue.runExclusive(() async {
        _accountGeneration++;
        try {
          return await change();
        } finally {
          final state = _state;
          final account = _currentAccount();
          if (_config != null &&
              state != null &&
              (account == null || account != state.boundAccount)) {
            state.localReviewRequired = true;
            await _saveState();
          }
        }
      });

  Future<void> resetInMemory() => _queue.run(() async {
    pauseTimers();
    _config = null;
    _state = null;
    _publish();
  });

  Future<void> load() => _queue.run(() async {
    final config = await _storage.read(key: starSyncConfigKey);
    final state = await _storage.read(key: starSyncStateKey);
    try {
      if (config == null && state == null) {
        return;
      }
      if (config == null || state == null) {
        throw const FormatException();
      }
      final parsedConfig = StarSyncConfig.fromJson(
        jsonDecode(config) as Map<String, dynamic>,
      );
      final stateJson = jsonDecode(state) as Map<String, dynamic>;
      final parsedState = StarSyncState.fromJson(stateJson);
      _config = parsedConfig;
      _state = parsedState;
      try {
        if (stateJson['pendingLocalClear'] == true &&
            !stateJson.containsKey('pendingLocalClearIds')) {
          parsedState.pendingLocalClearIds =
              (await activityStore.loadStarredMessages())
                  .map((star) => star.id)
                  .toList();
          await _saveState();
        }
        if (!await _accountMatches(parsedState)) return;
        await _finishPendingLocalClear();
      } on Object {
        return;
      }
      if (parsedConfig.backend != StarSyncBackend.googleDrive) {
        final transport = _transportFactory(parsedConfig);
        transport.close();
      }
      _scheduleCooldown(parsedState);
      _publish();
    } catch (_) {
      _config = null;
      _state = null;
      await _storage.delete(key: starSyncConfigKey);
      await _storage.delete(key: starSyncStateKey);
      _status.value = const StarSyncStatusSnapshot(
        lastError: '同期設定を読み込めませんでした',
      );
    }
  });

  void _publish({bool syncing = false}) {
    final state = _state;
    _status.value = StarSyncStatusSnapshot(
      enabled: _config != null && state != null,
      status: state?.status ?? StarSyncStatus.disabled,
      lastSyncAt: state?.lastSyncAt,
      lastError: state?.lastError,
      syncing: syncing,
      cooldownUntil: state?.cooldownUntil,
    );
  }

  Future<void> _saveState() => _storage.write(
    key: starSyncStateKey,
    value: jsonEncode(_state!.toJson()),
  );

  Future<void> _finishPendingLocalClear() async {
    final state = _state!;
    if (state.pendingLocalClearIds.isEmpty) return;
    final pendingIds = state.pendingLocalClearIds;
    try {
      final ids = pendingIds.toSet();
      await activityStore.transformStarredMessages<void>(
        (current) async => (
          next: current.where((star) => !ids.contains(star.id)).toList(),
          result: null,
        ),
      );
      state.pendingLocalClearIds = [];
      if (state.lastError == '端末内のスターを消去できませんでした') {
        state.status = StarSyncStatus.ok;
        state.lastError = null;
      }
      await _saveState();
      _publish();
    } on Object {
      state.pendingLocalClearIds = pendingIds;
      state.status = StarSyncStatus.error;
      state.lastError = '端末内のスターを消去できませんでした';
      try {
        await _saveState();
      } on Object {
        // The persisted pending IDs remain set if saving fails.
      }
      _publish();
      rethrow;
    }
  }

  Future<void> _install(
    StarSyncConfig config,
    StarSyncState state, {
    required List<String> pendingLocalClearIds,
  }) async {
    state.pendingLocalClearIds = pendingLocalClearIds;
    try {
      await _storage.write(
        key: starSyncStateKey,
        value: jsonEncode(state.toJson()),
      );
      await _storage.write(
        key: starSyncConfigKey,
        value: jsonEncode(config.toJson()),
      );
    } on Object {
      for (final key in [starSyncStateKey, starSyncConfigKey]) {
        try {
          await _storage.delete(key: key);
        } on Object {
          // Cleanup is best effort; preserve the original write error.
        }
      }
      _publish();
      rethrow;
    }
    _config = config;
    _state = state;
    _publish();
    await _finishPendingLocalClear();
  }

  String? _currentAccount() {
    final id = loginId?.call()?.trim();
    if (id == null || id.isEmpty) return null;
    return base64UrlEncode(
      sha256.convert(utf8.encode('mbg-star-account:$id')).bytes,
    );
  }

  String requireAccount() =>
      _currentAccount() ?? (throw const StarSyncAccountRequiredException());

  Future<bool> _accountMatches(StarSyncState state) async {
    final current = _currentAccount();
    if (current != null && state.boundAccount == current) return true;
    state.status = StarSyncStatus.accountMismatch;
    state.localReviewRequired = true;
    await _saveState();
    _publish();
    return false;
  }

  Future<void> _requireBoundAccount() async {
    final state = _state;
    if (_config == null || state == null) throw StateError('Sync is disabled');
    if (!await _accountMatches(state)) {
      throw const StarSyncAccountMismatchException();
    }
  }

  Future<int> localStarCount() async =>
      (await activityStore.loadStarredMessages()).length;

  /// Read the retired key before an explicit reset removes remote data.
  Future<String?> _deleteRemoteData(StarSyncTransport transport) async {
    String? retiredKeyId;
    try {
      final keyring = await transport.get(_keyringPath);
      if (keyring != null) {
        retiredKeyId = StarSyncKeyring.fromJson(
          jsonDecode(utf8.decode(keyring.bytes)),
        ).keyId;
      }
    } on Object {
      // An explicit reset must also recover from an unreadable keyring.
    }
    for (final entry in await transport.list(_deviceDirectory)) {
      await transport.delete(entry.path);
    }
    await transport.delete(_keyringPath);
    return retiredKeyId;
  }

  String _setupAccount(String? expectedAccount, int? expectedGeneration) {
    final account = _currentAccount();
    if ((expectedAccount != null && account != expectedAccount) ||
        (expectedGeneration != null &&
            accountGeneration != expectedGeneration)) {
      throw const StarSyncAccountMismatchException();
    }
    return account ?? (throw const StarSyncAccountRequiredException());
  }

  Future<void> setUp(
    StarSyncConfig config,
    String passphrase, {
    bool resetExisting = false,
    bool clearLocalStars = false,
    String? expectedAccount,
    int? expectedGeneration,
  }) async {
    final account = _setupAccount(expectedAccount, expectedGeneration);
    final clearIds = clearLocalStars
        ? (await activityStore.loadStarredMessages())
              .map((star) => star.id)
              .toList()
        : <String>[];
    final transport = _transportFactory(config);
    try {
      await transport.ensureDirectory(_deviceDirectory);
      final retiredKeyId = resetExisting
          ? await _deleteRemoteData(transport)
          : null;
      var remote = await transport.get(_keyringPath);
      if (remote == null) {
        final memory = kdfParams.memoryKiB;
        final iterations = kdfParams.iterations;
        final parallelism = kdfParams.parallelism;
        final data = utf8.encode(
          await _createKeyringJson(passphrase, memory, iterations, parallelism),
        );
        try {
          _setupAccount(account, expectedGeneration);
          await transport.put(_keyringPath, data, createOnly: true);
          remote = await transport.get(_keyringPath);
        } on StarSyncTransportException catch (error) {
          if (error.kind != StarSyncTransportErrorKind.alreadyExists) {
            rethrow;
          }
          remote = await transport.get(_keyringPath);
        }
      }
      if (remote == null) {
        throw StateError('Keyring missing');
      }
      final bytes = remote.bytes;
      final keyBytes = await _unwrapKeyBytes(utf8.decode(bytes), passphrase);
      final keyring = StarSyncKeyring.fromJson(jsonDecode(utf8.decode(bytes)));
      final random = Random.secure();
      final deviceId = base64UrlEncode(
        List<int>.generate(16, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      await _queue.run(() async {
        if (_currentAccount() != account ||
            (expectedGeneration != null &&
                accountGeneration != expectedGeneration)) {
          throw const StarSyncAccountMismatchException();
        }
        await _install(
          config,
          StarSyncState(
            deviceId: deviceId,
            dataKey: base64Encode(keyBytes),
            keyId: keyring.keyId,
            boundAccount: account,
            retiredKeyIds: {?retiredKeyId: _now()},
          ),
          pendingLocalClearIds: clearIds,
        );
      });
    } finally {
      transport.close();
    }
    await _syncAfterSetup();
  }

  Future<void> _syncAfterSetup() async {
    try {
      await syncNow();
    } on Object {
      // The configuration is already saved and sync records its own error.
    }
  }

  Future<void> _installPairing(
    StarSyncConfig config,
    String keyId,
    List<int> keyBytes,
    String account, {
    required List<String> pendingLocalClearIds,
    int? expectedGeneration,
    String? retiredKeyId,
  }) => _queue.run(() async {
    if (_currentAccount() != account ||
        (expectedGeneration != null &&
            accountGeneration != expectedGeneration)) {
      throw const StarSyncAccountMismatchException();
    }
    final random = Random.secure();
    final deviceId = base64UrlEncode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    await _install(
      config,
      StarSyncState(
        deviceId: deviceId,
        dataKey: base64Encode(keyBytes),
        keyId: keyId,
        boundAccount: account,
        retiredKeyIds: {?retiredKeyId: _now()},
      ),
      pendingLocalClearIds: pendingLocalClearIds,
    );
  });

  Future<StarSyncPairingSetup> setUpWithPairing(
    StarSyncConfig config, {
    bool resetExisting = false,
    bool clearLocalStars = false,
    String? expectedAccount,
    int? expectedGeneration,
  }) async {
    final account = _setupAccount(expectedAccount, expectedGeneration);
    final clearIds = clearLocalStars
        ? (await activityStore.loadStarredMessages())
              .map((star) => star.id)
              .toList()
        : <String>[];
    final transport = _transportFactory(config);
    try {
      await transport.ensureDirectory(_deviceDirectory);
      final retiredKeyId = resetExisting
          ? await _deleteRemoteData(transport)
          : null;
      if (await transport.get(_keyringPath) != null) {
        if (resetExisting) throw StarSyncSetupRaceException();
        return StarSyncPairingSetup.needsPairingCode;
      }
      _setupAccount(account, expectedGeneration);
      final created = createStarSyncPairingKeyring();
      try {
        await transport.put(
          _keyringPath,
          utf8.encode(jsonEncode(created.keyring.toJson())),
          createOnly: true,
        );
      } on StarSyncTransportException catch (error) {
        if (error.kind != StarSyncTransportErrorKind.alreadyExists) rethrow;
        if (resetExisting) throw StarSyncSetupRaceException();
        return StarSyncPairingSetup.needsPairingCode;
      }
      final stored = await _readKeyring(transport);
      if (stored.keyId != created.keyring.keyId) {
        if (resetExisting) throw StarSyncSetupRaceException();
        return StarSyncPairingSetup.needsPairingCode;
      }
      await _installPairing(
        config,
        created.keyring.keyId,
        created.dataKey,
        account,
        pendingLocalClearIds: clearIds,
        expectedGeneration: expectedGeneration,
        retiredKeyId: retiredKeyId,
      );
    } finally {
      transport.close();
    }
    await _syncAfterSetup();
    return StarSyncPairingSetup.created;
  }

  Future<void> _verifyPairing(
    StarSyncTransport transport,
    StarSyncKeyring keyring,
    ({String keyId, List<int> dataKey}) code,
  ) async {
    if (code.keyId != keyring.keyId) {
      throw const StarSyncPairingMismatchException();
    }
    final entries = await transport.list(_deviceDirectory);
    for (final entry in entries) {
      StarSyncRemoteObject? object;
      try {
        object = await transport.get(entry.path);
      } on Object {
        continue;
      }
      if (object == null) continue;
      try {
        await decryptStarSyncFile(
          dataKey: starSyncKeyFromBytes(code.dataKey),
          keyId: code.keyId,
          bytes: object.bytes,
          expectedDeviceId: entry.path.split('/').last,
        );
        return;
      } on StarSyncDecryptException {
        continue;
      } on StarSyncFormatException {
        continue;
      }
    }
    if (entries.isNotEmpty) throw const StarSyncPairingMismatchException();
  }

  Future<void> joinWithPairingCode(
    StarSyncConfig config,
    String code, {
    bool clearLocalStars = false,
    String? expectedAccount,
    int? expectedGeneration,
  }) async {
    final account = _setupAccount(expectedAccount, expectedGeneration);
    final clearIds = clearLocalStars
        ? (await activityStore.loadStarredMessages())
              .map((star) => star.id)
              .toList()
        : <String>[];
    final decoded = decodeStarSyncPairingCode(code);
    final transport = _transportFactory(config);
    try {
      final keyring = await _readKeyring(transport);
      await _verifyPairing(transport, keyring, decoded);
      await _installPairing(
        config,
        decoded.keyId,
        decoded.dataKey,
        account,
        pendingLocalClearIds: clearIds,
        expectedGeneration: expectedGeneration,
      );
    } finally {
      transport.close();
    }
    await _syncAfterSetup();
  }

  Future<String> pairingCode() => _queue.run(() async {
    final state = _state;
    if (_config == null || state == null) throw StateError('Sync is disabled');
    await _requireBoundAccount();
    return encodeStarSyncPairingCode(state.keyId, base64Decode(state.dataKey));
  });

  Future<void> rejoinWithPairingCode(String code) async {
    await _queue.run(() async {
      final config = _config;
      final state = _state;
      if (config == null || state == null) throw StateError('Sync is disabled');
      await _requireBoundAccount();
      final decoded = decodeStarSyncPairingCode(code);
      final transport = _transportFactory(config);
      try {
        final keyring = await _readKeyring(transport);
        await _verifyPairing(transport, keyring, decoded);
        state
          ..dataKey = base64Encode(decoded.dataKey)
          ..keyId = decoded.keyId
          ..keyringEtag = null
          ..remoteCache = {}
          ..lastUploadedHash = null
          ..status = StarSyncStatus.ok;
        await _saveState();
      } finally {
        transport.close();
      }
    });
    await syncNow();
  }

  Future<String> resetRemoteWithPairing() async {
    final code = await _queue.run(() async {
      final config = _config;
      final state = _state;
      if (config == null || state == null) throw StateError('Sync is disabled');
      await _requireBoundAccount();
      final transport = _transportFactory(config);
      try {
        final retiredKeyId = await _deleteRemoteData(transport);
        if (retiredKeyId != null) state.retiredKeyIds[retiredKeyId] = _now();
        final created = createStarSyncPairingKeyring();
        await transport.put(
          _keyringPath,
          utf8.encode(jsonEncode(created.keyring.toJson())),
          createOnly: true,
        );
        final stored = await _readKeyring(transport);
        if (stored.keyId != created.keyring.keyId) {
          throw StarSyncSetupRaceException();
        }
        state
          ..dataKey = base64Encode(created.dataKey)
          ..keyId = created.keyring.keyId
          ..keyringEtag = null
          ..remoteCache = {}
          ..lastUploadedHash = null
          ..status = StarSyncStatus.ok;
        await _saveState();
        return encodeStarSyncPairingCode(
          created.keyring.keyId,
          created.dataKey,
        );
      } finally {
        transport.close();
      }
    });
    await syncNow();
    return code;
  }

  Future<void> resumeKeepingLocal() =>
      _resumeAfterAccountReturn(discardLocal: false);

  Future<void> resumeDiscardingLocal() =>
      _resumeAfterAccountReturn(discardLocal: true);

  Future<void> _resumeAfterAccountReturn({required bool discardLocal}) async {
    final resumed = await _queue.run(() async {
      final state = _state;
      if (_config == null || state == null || !state.localReviewRequired) {
        return false;
      }
      if (!await _accountMatches(state)) return false;
      if (discardLocal) {
        final changed = await activityStore.transformStarredMessages<bool>((
          current,
        ) async {
          if (_currentAccount() != state.boundAccount) {
            throw const _AccountChanged();
          }
          final next = applyStarSyncStateToLocal(
            state: state.records,
            local: current.where((item) {
              final record = state.records[item.id];
              return record != null && record.title == item.title;
            }).toList(),
          );
          return (
            next: next,
            result:
                jsonEncode(current.map((e) => e.toJson()).toList()) !=
                jsonEncode(next.map((e) => e.toJson()).toList()),
          );
        });
        if (changed) onLocalStarsChanged?.call();
        state.pendingBulkReplace = false;
      }
      state.localReviewRequired = false;
      state.status = StarSyncStatus.ok;
      await _saveState();
      _publish();
      return true;
    });
    if (resumed) await syncNow();
  }

  Future<StarSyncResult> syncNow({
    StarSyncTrigger trigger = StarSyncTrigger.manual,
  }) async {
    if (_running != null) {
      if (trigger == StarSyncTrigger.localChange && _backgroundWake != null) {
        _wakeForLocal = true;
        _backgroundWake!.complete();
        _backgroundWake = null;
      } else if (trigger == StarSyncTrigger.localChange ||
          trigger == StarSyncTrigger.manual) {
        _followUp = true;
        if (trigger == StarSyncTrigger.manual ||
            _followUpTrigger != StarSyncTrigger.manual) {
          _followUpTrigger = trigger;
        }
      }
      return _running!;
    }
    final run = _runAndFollowUp(trigger);
    _running = run;
    try {
      return await run;
    } finally {
      _running = null;
    }
  }

  Future<StarSyncResult> _runAndFollowUp(StarSyncTrigger trigger) async {
    var result = const StarSyncResult();
    var changed = false;
    do {
      _followUp = false;
      try {
        result = await _triggerSync(trigger);
      } on Object {
        if (_followUp && _followUpTrigger == StarSyncTrigger.localChange) {
          await _queue.run(() async {
            if (_state != null) {
              _state!.pendingLocalChange = true;
              await _saveState();
              _scheduleCooldown(_state!);
            }
          });
        }
        rethrow;
      }
      changed = changed || result.localChanged;
      trigger = _followUpTrigger;
      _followUpTrigger = StarSyncTrigger.localChange;
    } while (_followUp);
    return StarSyncResult(
      localChanged: changed,
      skippedFiles: result.skippedFiles,
      devices: result.devices,
    );
  }

  Future<StarSyncResult> _triggerSync(StarSyncTrigger trigger) async {
    final config = _config;
    final state = _state;
    if (_disposed || config == null || state == null) {
      return const StarSyncResult();
    }
    await _queue.run(() async {
      if (!_disposed &&
          identical(_config, config) &&
          identical(_state, state) &&
          await _accountMatches(state)) {
        await _finishPendingLocalClear();
      }
    });
    if ((trigger == StarSyncTrigger.startup ||
            trigger == StarSyncTrigger.resume) &&
        canSync?.call() == false) {
      return const StarSyncResult();
    }
    final now = _now();
    final background =
        trigger == StarSyncTrigger.startup || trigger == StarSyncTrigger.resume;
    final inCooldown =
        state.cooldownUntil != null && now.isBefore(state.cooldownUntil!);
    if (background &&
        !inCooldown &&
        !state.pendingLocalChange &&
        _currentAccount() != null &&
        _currentAccount() == state.boundAccount &&
        !state.localReviewRequired &&
        state.status != StarSyncStatus.accountMismatch) {
      final date = '${now.year}-${now.month}-${now.day}';
      final count = state.backgroundDate == date ? state.backgroundCount : 0;
      if ((state.lastSyncAt != null &&
              now.difference(state.lastSyncAt!) < const Duration(minutes: 2)) ||
          count >= 120) {
        return const StarSyncResult();
      }
      final wake = Completer<void>();
      _backgroundWake = wake;
      await Future.any([
        _delay(Duration(milliseconds: _random.nextInt(20001))),
        wake.future,
      ]);
      if (identical(_backgroundWake, wake)) _backgroundWake = null;
      if (_wakeForLocal) {
        _wakeForLocal = false;
        trigger = StarSyncTrigger.localChange;
      }
    }
    return _queue.run(() async {
      if (_disposed ||
          !identical(_config, config) ||
          !identical(_state, state)) {
        return const StarSyncResult();
      }
      if (!await _accountMatches(state)) return const StarSyncResult();
      await _finishPendingLocalClear();
      if (trigger != StarSyncTrigger.manual && canSync?.call() == false) {
        if (trigger == StarSyncTrigger.localChange) {
          state.pendingLocalChange = true;
          await _saveState();
        }
        return const StarSyncResult();
      }
      if (state.localReviewRequired) {
        state.status = StarSyncStatus.accountReturned;
        await _saveState();
        _publish();
        return const StarSyncResult();
      }
      final current = _now();
      if (trigger != StarSyncTrigger.manual &&
          state.cooldownUntil != null &&
          current.isBefore(state.cooldownUntil!)) {
        if (trigger == StarSyncTrigger.localChange) {
          state.pendingLocalChange = true;
          await _saveState();
          _scheduleCooldown(state);
        }
        return const StarSyncResult();
      }
      if (background && trigger != StarSyncTrigger.localChange) {
        final date = '${current.year}-${current.month}-${current.day}';
        if (state.backgroundDate != date) {
          state.backgroundDate = date;
          state.backgroundCount = 0;
        }
        state.backgroundCount++;
      }
      if (trigger == StarSyncTrigger.localChange) {
        state.pendingLocalChange = true;
        await _saveState();
      }
      _cooldownTimer?.cancel();
      return _sync();
    });
  }

  void _scheduleCooldown(StarSyncState state) {
    _cooldownTimer?.cancel();
    final until = state.cooldownUntil;
    if (until == null || !state.pendingLocalChange) return;
    final remaining = until.difference(_now());
    final delay =
        (remaining.isNegative ? Duration.zero : remaining) +
        Duration(milliseconds: _random.nextInt(5001));
    _cooldownTimer = _timerFactory(delay, () {
      if (canSync?.call() == false) return;
      unawaited(
        syncNow(trigger: StarSyncTrigger.localChange)
            .catchError((Object _) => const StarSyncResult()),
      );
    });
  }

  Future<StarSyncResult> _sync() async {
    final config = _config;
    final state = _state;
    if (config == null || state == null) {
      return const StarSyncResult();
    }
    if (!await _accountMatches(state)) return const StarSyncResult();
    _publish(syncing: true);
    final transport = _transportFactory(config);
    try {
      final keyEntries = await transport.list('stars');
      final matches = keyEntries.where((entry) => entry.path == _keyringPath);
      if (matches.isEmpty) throw StateError('missing keyring');
      final etag = matches.first.etag;
      if (etag == null || etag.isEmpty || etag != state.keyringEtag) {
        final keyObject = await transport.get(_keyringPath);
        if (keyObject == null) throw StateError('missing keyring');
        final keyring = StarSyncKeyring.fromJson(
          jsonDecode(utf8.decode(keyObject.bytes)),
        );
        if (keyring.keyId != state.keyId) {
          state.status = keyring.mode == 'pairing'
              ? StarSyncStatus.needsPairingCode
              : StarSyncStatus.needsPassphrase;
          state.keyringEtag = null;
          await _saveState();
          return const StarSyncResult();
        }
        state.keyringEtag = etag;
      }
      state.retiredKeyIds.removeWhere(
        (_, retiredAt) =>
            _now().difference(retiredAt) > const Duration(days: 7),
      );
      await _saveState();
      final entries = await transport.list(_deviceDirectory);
      final caches = <String, dynamic>{};
      final documents = <StarSyncDocument>[];
      var skipped = 0;
      for (final entry in entries) {
        final deviceId = entry.path.split('/').last;
        if (deviceId == state.deviceId) {
          continue;
        }
        final previous = state.remoteCache[deviceId] as Map<String, dynamic>?;
        StarSyncDocument? document;
        final unchanged =
            state.retiredKeyIds.isEmpty &&
            previous != null &&
            ((entry.etag != null && entry.etag == previous['etag']) ||
                (entry.etag == null &&
                    entry.lastModified != null &&
                    entry.size != null &&
                    entry.lastModified!.toIso8601String() ==
                        previous['lastModified'] &&
                    entry.size == previous['size']));
        if (unchanged) {
          document = StarSyncDocument.fromJson(previous['document']);
        } else {
          try {
            final object = await transport.get(entry.path);
            if (object == null) {
              continue;
            }
            final fileKeyId = starSyncFileKeyId(object.bytes);
            if (fileKeyId != null && fileKeyId != state.keyId) {
              if (state.retiredKeyIds.containsKey(fileKeyId)) {
                final latest = await transport.get(entry.path);
                if (latest != null &&
                    starSyncFileKeyId(latest.bytes) == fileKeyId) {
                  await transport.delete(entry.path);
                }
              }
              continue;
            }
            final plain = await decryptStarSyncFile(
              dataKey: starSyncKeyFromBytes(base64Decode(state.dataKey)),
              keyId: state.keyId,
              bytes: object.bytes,
              expectedDeviceId: deviceId,
            );
            document = StarSyncDocument.fromBytes(plain);
            if (document.deviceId != deviceId) {
              throw const StarSyncFormatException();
            }
          } on StarSyncDecryptException {
            skipped++;
          } on StarSyncFormatException {
            skipped++;
          }
          if (document == null && previous != null) {
            document = StarSyncDocument.fromJson(previous['document']);
            caches[deviceId] = previous;
          }
        }
        if (document == null) {
          continue;
        }
        if (document.account != state.boundAccount) {
          caches.remove(deviceId);
          skipped++;
          continue;
        }
        documents.add(document);
        if (!caches.containsKey(deviceId)) {
          caches[deviceId] = {
            'etag': entry.etag,
            'lastModified': entry.lastModified?.toIso8601String(),
            'size': entry.size,
            'document': document.toJson(),
          };
        }
      }
      var clock = state.clock;
      if (!await _accountMatches(state)) return const StarSyncResult();
      for (final document in documents) {
        clock = max(clock, document.clock);
        for (final record in document.records.values) {
          clock = max(clock, record.clock);
        }
      }
      final now = _now().toUtc();
      late Map<String, StarSyncRecord> mergedRecords;
      final changed = await activityStore.transformStarredMessages<bool>((
        current,
      ) async {
        if (_currentAccount() != state.boundAccount) {
          throw const _AccountChanged();
        }
        final reconciled = reconcileLocalStars(
          local: current,
          state: state.records,
          clock: clock,
          deviceId: state.deviceId,
          now: now,
          bulkReplace: state.pendingBulkReplace,
        );
        mergedRecords = mergeStarSyncRecords([
          reconciled.state,
          ...documents.map((e) => e.records),
        ], now: now);
        clock = reconciled.clock;
        final live =
            mergedRecords.values.where((record) => record.starred).toList()
              ..sort((a, b) {
                final date = b.starredAt.compareTo(a.starredAt);
                return date != 0 ? date : a.id.compareTo(b.id);
              });
        for (final record in live.skip(starSyncMaxStars)) {
          mergedRecords[record.id] = record.copyWith(
            starred: false,
            clock: ++clock,
            deviceId: state.deviceId,
            updatedAt: now,
          );
        }
        mergedRecords = mergeStarSyncRecords([mergedRecords], now: now);
        final next = applyStarSyncStateToLocal(
          state: mergedRecords,
          local: current,
        );
        return (
          next: next,
          result:
              jsonEncode(current.map((e) => e.toJson()).toList()) !=
              jsonEncode(next.map((e) => e.toJson()).toList()),
        );
      });
      for (final record in mergedRecords.values) {
        clock = max(clock, record.clock);
      }
      state.records = mergedRecords;
      state.clock = clock;
      if (changed) onLocalStarsChanged?.call();
      state.remoteCache = caches;
      state.pendingBulkReplace = false;
      await _saveState();
      final document = StarSyncDocument(
        deviceId: state.deviceId,
        writtenAt: now,
        clock: clock,
        records: state.records,
        account: state.boundAccount,
      );
      final semantic = document.toJson()..remove('writtenAt');
      final hash = sha256.convert(utf8.encode(jsonEncode(semantic))).toString();
      final ownPath = '$_deviceDirectory/${state.deviceId}';
      if (!await _accountMatches(state)) return const StarSyncResult();
      if (state.lastUploadedHash != hash ||
          !entries.any((entry) => entry.path == ownPath)) {
        final encrypted = await encryptStarSyncFile(
          dataKey: starSyncKeyFromBytes(base64Decode(state.dataKey)),
          keyId: state.keyId,
          deviceId: state.deviceId,
          plaintext: document.toBytes(),
        );
        if (!await _accountMatches(state)) return const StarSyncResult();
        await transport.put(ownPath, encrypted);
        state.lastUploadedHash = hash;
      }
      state.status = StarSyncStatus.ok;
      state.lastError = skipped == 0 ? null : '一部の端末のデータを読めませんでした（$skipped台）';
      state.lastSyncAt = _now().toUtc();
      state.pendingLocalChange = false;
      state.serverFailures = 0;
      state.cooldownUntil = null;
      await _saveState();
      return StarSyncResult(
        localChanged: changed,
        skippedFiles: skipped,
        devices: entries.length,
      );
    } on _AccountChanged {
      await _accountMatches(state);
      return const StarSyncResult();
    } on StarSyncGoogleAuthException catch (error) {
      if (error.kind == StarSyncGoogleAuthErrorKind.notSignedIn ||
          error.kind == StarSyncGoogleAuthErrorKind.revoked) {
        state.status = StarSyncStatus.needsGoogleSignIn;
        state.lastError = 'Google へのログインが必要です';
        state.cooldownUntil = null;
        await _saveState();
        return const StarSyncResult();
      }
      state.status = StarSyncStatus.error;
      state.lastError = 'Google に接続できませんでした';
      await _saveState();
      rethrow;
    } on Object catch (error) {
      if (config.backend == StarSyncBackend.googleDrive &&
          error is StarSyncTransportException &&
          error.kind == StarSyncTransportErrorKind.auth) {
        state.status = StarSyncStatus.needsGoogleSignIn;
        state.lastError = 'Google へのログインが必要です';
        state.cooldownUntil = null;
        await _saveState();
        return const StarSyncResult();
      }
      if (error is StarSyncTransportException &&
          error.kind == StarSyncTransportErrorKind.server) {
        state.serverFailures++;
        final minutes = min(60, 1 << min(state.serverFailures - 1, 6));
        state.cooldownUntil = _now().add(Duration(minutes: minutes));
      }
      state.status = StarSyncStatus.error;
      state.lastError = _errorMessage(error);
      await _saveState();
      _scheduleCooldown(state);
      rethrow;
    } finally {
      transport.close();
      _publish();
    }
  }

  String _errorMessage(Object error) {
    if (error is StateError && error.message == 'missing keyring') {
      return '同期データが見つかりません';
    }
    if (error is StarSyncTransportException) {
      return switch (error.kind) {
        StarSyncTransportErrorKind.auth => '認証に失敗しました',
        StarSyncTransportErrorKind.tls => '証明書を確認できませんでした',
        StarSyncTransportErrorKind.server =>
          'サーバーエラー (HTTP ${error.statusCode})',
        _ => '接続できませんでした',
      };
    }
    return '同期できませんでした';
  }

  void scheduleSync({
    Duration delay = const Duration(seconds: 5),
    StarSyncTrigger trigger = StarSyncTrigger.localChange,
    bool Function()? shouldSync,
    void Function(StarSyncResult)? onResult,
  }) {
    if (_config == null) {
      return;
    }
    _timer?.cancel();
    if (trigger == StarSyncTrigger.localChange && _backgroundWake != null) {
      delay = Duration.zero;
    }
    if (trigger == StarSyncTrigger.localChange) {
      unawaited(
        _queue
            .run(() async {
              if (_state != null) {
                _state!.pendingLocalChange = true;
                await _saveState();
              }
            })
            .catchError((Object _) {}),
      );
    }
    _timer = _timerFactory(delay, () {
      if (canSync?.call() == false || (shouldSync != null && !shouldSync())) {
        return;
      }
      unawaited(
        syncNow(trigger: trigger)
            .then<void>((result) {
              onResult?.call(result);
            })
            .catchError((Object _) {}),
      );
    });
  }

  void pauseTimers() {
    _timer?.cancel();
    _cooldownTimer?.cancel();
    final wake = _backgroundWake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _backgroundWake = null;
  }

  void dispose() {
    _disposed = true;
    pauseTimers();
  }

  Future<void> withBulkReplace(Future<void> Function() replace) =>
      _queue.runExclusive(() async {
        final state = _state;
        final previous = state?.pendingBulkReplace;
        await markBulkReplace();
        try {
          await replace();
        } on Object {
          if (state != null && identical(_state, state)) {
            state.pendingBulkReplace = previous!;
            await _saveState();
          }
          rethrow;
        }
      });

  Future<void> markBulkReplace() => _queue.run(() async {
    if (_state == null) {
      return;
    }
    _state!.pendingBulkReplace = true;
    await _saveState();
  });

  Future<StarSyncKeyring> _readKeyring(StarSyncTransport transport) async {
    final object = await transport.get(_keyringPath);
    if (object == null) {
      throw StateError('missing keyring');
    }
    return StarSyncKeyring.fromJson(jsonDecode(utf8.decode(object.bytes)));
  }

  Future<List<int>> _unwrap(StarSyncKeyring keyring, String passphrase) =>
      _unwrapKeyBytes(jsonEncode(keyring.toJson()), passphrase);

  Future<void> changePassphrase(String current, String next) =>
      _queue.run(() async {
        await _requireBoundAccount();
        final transport = _transportFactory(_config!);
        try {
          final keyring = await _readKeyring(transport);
          if (keyring.mode == 'pairing') throw StateError('Pairing keyring');
          final bytes = await _unwrap(keyring, current);
          final encoded = jsonEncode(keyring.toJson());
          final wrapped = utf8.encode(
            await _rewrapKeyringJson(encoded, bytes, next),
          );
          await transport.put(_keyringPath, wrapped);
        } finally {
          transport.close();
        }
      });

  Future<void> rejoin(String passphrase) async {
    await _queue.run(() async {
      await _requireBoundAccount();
      final transport = _transportFactory(_config!);
      try {
        final keyring = await _readKeyring(transport);
        final bytes = await _unwrap(keyring, passphrase);
        _state!
          ..dataKey = base64Encode(bytes)
          ..keyId = keyring.keyId
          ..keyringEtag = null
          ..remoteCache = {}
          ..lastUploadedHash = null
          ..status = StarSyncStatus.ok;
        await _saveState();
      } finally {
        transport.close();
      }
    });
    await syncNow();
  }

  Future<void> resetRemote(String newPassphrase) async {
    await _queue.run(() async {
      await _requireBoundAccount();
      final transport = _transportFactory(_config!);
      try {
        final retiredKeyId = await _deleteRemoteData(transport);
        if (retiredKeyId != null) _state!.retiredKeyIds[retiredKeyId] = _now();
        final memory = kdfParams.memoryKiB;
        final iterations = kdfParams.iterations;
        final parallelism = kdfParams.parallelism;
        final created = await _createKeyringJson(
          newPassphrase,
          memory,
          iterations,
          parallelism,
        );
        await transport.put(
          _keyringPath,
          utf8.encode(created),
          createOnly: true,
        );
        final stored = await transport.get(_keyringPath);
        if (stored == null) throw StateError('missing keyring');
        final encoded = utf8.decode(stored.bytes);
        final keyBytes = await _unwrapKeyBytes(encoded, newPassphrase);
        _state!
          ..dataKey = base64Encode(keyBytes)
          ..keyId = StarSyncKeyring.fromJson(jsonDecode(encoded)).keyId
          ..keyringEtag = null
          ..remoteCache = {}
          ..lastUploadedHash = null
          ..status = StarSyncStatus.ok;
        await _saveState();
      } finally {
        transport.close();
      }
    });
    await syncNow();
  }

  Future<List<StarSyncDeviceInfo>> listDevices() => _queue.run(() async {
    await _requireBoundAccount();
    final transport = _transportFactory(_config!);
    try {
      final entries = await transport.list(_deviceDirectory);
      return entries.map((entry) {
        final id = entry.path.split('/').last;
        return StarSyncDeviceInfo(
          deviceId: id,
          lastModified: entry.lastModified,
          isThisDevice: id == _state!.deviceId,
        );
      }).toList();
    } finally {
      transport.close();
    }
  });

  Future<void> deleteDeviceFile(String deviceId) => _queue.run(() async {
    await _requireBoundAccount();
    validateStarSyncPath(deviceId);
    if (deviceId.contains('/') || deviceId == _state!.deviceId) {
      throw ArgumentError('Invalid device');
    }
    final transport = _transportFactory(_config!);
    try {
      await transport.delete('$_deviceDirectory/$deviceId');
    } finally {
      transport.close();
    }
  });

  Future<void> disable({bool deleteOwnRemoteFile = false}) =>
      _queue.run(() async {
        _timer?.cancel();
        _cooldownTimer?.cancel();
        final wake = _backgroundWake;
        if (wake != null && !wake.isCompleted) wake.complete();
        _backgroundWake = null;
        if (deleteOwnRemoteFile && _config != null && _state != null) {
          final transport = _transportFactory(_config!);
          try {
            await transport.delete('$_deviceDirectory/${_state!.deviceId}');
          } finally {
            transport.close();
          }
        }
        await _storage.delete(key: starSyncConfigKey);
        await _storage.delete(key: starSyncStateKey);
        _config = null;
        _state = null;
        _publish();
      });
}
