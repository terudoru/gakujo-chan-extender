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

class StarSyncStatusSnapshot {
  const StarSyncStatusSnapshot({
    this.enabled = false,
    this.status = StarSyncStatus.disabled,
    this.lastSyncAt,
    this.lastError,
    this.syncing = false,
  });
  final bool enabled;
  final StarSyncStatus status;
  final DateTime? lastSyncAt;
  final String? lastError;
  final bool syncing;
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
    this.clock = 0,
    Map<String, StarSyncRecord>? records,
    Map<String, dynamic>? remoteCache,
    this.lastUploadedHash,
    this.lastSyncAt,
    this.lastError,
    this.status = StarSyncStatus.ok,
    this.pendingBulkReplace = false,
  }) : records = records ?? {},
       remoteCache = remoteCache ?? {};
  final String deviceId;
  String dataKey;
  String keyId;
  int clock;
  Map<String, StarSyncRecord> records;
  Map<String, dynamic> remoteCache;
  String? lastUploadedHash;
  DateTime? lastSyncAt;
  String? lastError;
  StarSyncStatus status;
  bool pendingBulkReplace;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'dataKey': dataKey,
    'keyId': keyId,
    'clock': clock,
    'records': records.map((key, value) => MapEntry(key, value.toJson())),
    'remoteCache': remoteCache,
    'lastUploadedHash': lastUploadedHash,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastError': lastError,
    'status': status.name,
    'pendingBulkReplace': pendingBulkReplace,
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
      clock: json['clock'] as int,
      records: records,
      remoteCache: Map<String, dynamic>.from(json['remoteCache'] as Map),
      lastUploadedHash: json['lastUploadedHash'] as String?,
      lastSyncAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
      lastError: json['lastError'] as String?,
      status: StarSyncStatus.values.byName(json['status'] as String),
      pendingBulkReplace: json['pendingBulkReplace'] as bool? ?? false,
    );
  }
}

class StarSyncEngine {
  StarSyncEngine({
    required this.activityStore,
    FlutterSecureStorage? secureStorage,
    StarSyncTransport Function(StarSyncConfig)? transportFactory,
    DateTime Function()? now,
    this.loginId,
    this.onLocalStarsChanged,
    this.kdfParams = const StarSyncKdfParams(),
  }) : _storage = secureStorage ?? SecureStorageFactory.create(),
       _transportFactory = transportFactory ?? _defaultTransport,
       _now = now ?? DateTime.now;

  final GakujoActivityStore activityStore;
  final FlutterSecureStorage _storage;
  final StarSyncTransport Function(StarSyncConfig) _transportFactory;
  final DateTime Function() _now;
  final String? Function()? loginId;
  final void Function()? onLocalStarsChanged;
  final StarSyncKdfParams kdfParams;
  final StorageOperationQueue _queue = StorageOperationQueue();
  final ValueNotifier<StarSyncStatusSnapshot> _status = ValueNotifier(
    const StarSyncStatusSnapshot(),
  );
  ValueListenable<StarSyncStatusSnapshot> get status => _status;
  StarSyncConfig? _config;
  StarSyncState? _state;
  Future<StarSyncResult>? _running;
  bool _followUp = false;
  Timer? _timer;

  static StarSyncTransport _defaultTransport(StarSyncConfig config) =>
      switch (config.backend) {
        StarSyncBackend.webDav => StarSyncWebDavTransport(config.webDav!),
        StarSyncBackend.s3 => StarSyncS3Transport(config.s3!),
      };

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
      final parsedState = StarSyncState.fromJson(
        jsonDecode(state) as Map<String, dynamic>,
      );
      final transport = _transportFactory(parsedConfig);
      transport.close();
      _config = parsedConfig;
      _state = parsedState;
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
    );
  }

  Future<void> _saveState() => _storage.write(
    key: starSyncStateKey,
    value: jsonEncode(_state!.toJson()),
  );
  Future<void> _saveConfig() => _storage.write(
    key: starSyncConfigKey,
    value: jsonEncode(_config!.toJson()),
  );

  Future<void> setUp(StarSyncConfig config, String passphrase) async {
    final transport = _transportFactory(config);
    try {
      await transport.ensureDirectory(_deviceDirectory);
      var remote = await transport.get(_keyringPath);
      if (remote == null) {
        final memory = kdfParams.memoryKiB;
        final iterations = kdfParams.iterations;
        final parallelism = kdfParams.parallelism;
        final data = utf8.encode(
          await _createKeyringJson(passphrase, memory, iterations, parallelism),
        );
        try {
          await transport.put(_keyringPath, data, createOnly: true);
          remote = StarSyncRemoteObject(bytes: data);
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
        _config = config;
        _state = StarSyncState(
          deviceId: deviceId,
          dataKey: base64Encode(keyBytes),
          keyId: keyring.keyId,
        );
        await _saveState();
        await _saveConfig();
        _publish();
      });
    } finally {
      transport.close();
    }
    await syncNow();
  }

  Future<StarSyncResult> syncNow() {
    if (_running != null) {
      _followUp = true;
      return _running!;
    }
    final run = _runAndFollowUp();
    _running = run;
    return run.whenComplete(() {
      _running = null;
    });
  }

  Future<StarSyncResult> _runAndFollowUp() async {
    var result = const StarSyncResult();
    var changed = false;
    do {
      _followUp = false;
      result = await _queue.run(_sync);
      changed = changed || result.localChanged;
    } while (_followUp);
    return StarSyncResult(
      localChanged: changed,
      skippedFiles: result.skippedFiles,
      devices: result.devices,
    );
  }

  Future<StarSyncResult> _sync() async {
    final config = _config;
    final state = _state;
    if (config == null || state == null) {
      return const StarSyncResult();
    }
    _publish(syncing: true);
    final transport = _transportFactory(config);
    try {
      final keyObject = await transport.get(_keyringPath);
      if (keyObject == null) {
        throw StateError('missing keyring');
      }
      final keyring = StarSyncKeyring.fromJson(
        jsonDecode(utf8.decode(keyObject.bytes)),
      );
      if (keyring.keyId != state.keyId) {
        state.status = StarSyncStatus.needsPassphrase;
        await _saveState();
        return const StarSyncResult();
      }
      final id = loginId?.call()?.trim();
      final account = id == null || id.isEmpty
          ? null
          : base64UrlEncode(
              sha256.convert(utf8.encode('mbg-star-account:$id')).bytes,
            );
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
        if (account != null &&
            document.account != null &&
            account != document.account) {
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
        account: account,
      );
      final semantic = document.toJson()..remove('writtenAt');
      final hash = sha256.convert(utf8.encode(jsonEncode(semantic))).toString();
      final ownPath = '$_deviceDirectory/${state.deviceId}';
      if (state.lastUploadedHash != hash ||
          !entries.any((entry) => entry.path == ownPath)) {
        final encrypted = await encryptStarSyncFile(
          dataKey: starSyncKeyFromBytes(base64Decode(state.dataKey)),
          keyId: state.keyId,
          deviceId: state.deviceId,
          plaintext: document.toBytes(),
        );
        await transport.put(ownPath, encrypted);
        state.lastUploadedHash = hash;
      }
      state.status = StarSyncStatus.ok;
      state.lastError = null;
      state.lastSyncAt = now;
      await _saveState();
      return StarSyncResult(
        localChanged: changed,
        skippedFiles: skipped,
        devices: entries.length,
      );
    } on Object catch (error) {
      state.status = StarSyncStatus.error;
      state.lastError = _errorMessage(error);
      await _saveState();
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
    bool Function()? shouldSync,
    void Function(StarSyncResult)? onResult,
  }) {
    if (_config == null) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (shouldSync != null && !shouldSync()) return;
      unawaited(
        syncNow()
            .then<void>((result) {
              onResult?.call(result);
            })
            .catchError((Object _) {}),
      );
    });
  }

  void dispose() => _timer?.cancel();

  Future<void> withBulkReplace(Future<void> Function() replace) =>
      _queue.runExclusive(() async {
        await markBulkReplace();
        await replace();
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
        final transport = _transportFactory(_config!);
        try {
          final keyring = await _readKeyring(transport);
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
      final transport = _transportFactory(_config!);
      try {
        final keyring = await _readKeyring(transport);
        final bytes = await _unwrap(keyring, passphrase);
        _state!
          ..dataKey = base64Encode(bytes)
          ..keyId = keyring.keyId
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
      final transport = _transportFactory(_config!);
      try {
        for (final entry in await transport.list(_deviceDirectory)) {
          await transport.delete(entry.path);
        }
        await transport.delete(_keyringPath);
        final memory = kdfParams.memoryKiB;
        final iterations = kdfParams.iterations;
        final parallelism = kdfParams.parallelism;
        final created = await _createKeyringJson(
          newPassphrase,
          memory,
          iterations,
          parallelism,
        );
        final keyBytes = await _unwrapKeyBytes(created, newPassphrase);
        await transport.put(
          _keyringPath,
          utf8.encode(created),
          createOnly: true,
        );
        _state!
          ..dataKey = base64Encode(keyBytes)
          ..keyId = StarSyncKeyring.fromJson(jsonDecode(created)).keyId
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
