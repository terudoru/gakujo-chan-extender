import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../secure_storage_factory.dart';
import '../secure_storage_transaction.dart';

const starSyncGoogleQuotaKey = 'more_better_gakujo_google_quota';
const starSyncGoogleSoftLimit = 15000;
const starSyncGoogleHardLimit = 25000;
const starSyncGoogleQuotaMessage =
    '本日の Google ドライブの利用量の上限に達しました。明日になると再開します';

class StarSyncQuotaExceeded implements Exception {
  const StarSyncQuotaExceeded();

  @override
  String toString() => starSyncGoogleQuotaMessage;
}

class StarSyncQuotaMeter {
  StarSyncQuotaMeter({FlutterSecureStorage? storage, DateTime Function()? now})
    : _storage = storage ?? SecureStorageFactory.create(),
      _now = now ?? DateTime.now;

  static final shared = StarSyncQuotaMeter();
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final StorageOperationQueue _queue = StorageOperationQueue();
  final ValueNotifier<int> usage = ValueNotifier(0);
  String? _date;
  int _used = 0;
  bool _loaded = false;
  bool _saveNoticeShown = false;

  String _day() {
    final now = _now().toLocal();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> _load() async {
    if (!_loaded) {
      final raw = await _storage.read(key: starSyncGoogleQuotaKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map || data['date'] is! String ||
            data['units'] is! int || (data['units'] as int) < 0) {
          throw const FormatException('Invalid Google Drive quota');
        }
        _date = data['date'] as String;
        _used = data['units'] as int;
        _saveNoticeShown = data['saveNoticeShown'] == true;
      }
      _loaded = true;
    }
    final today = _day();
    if (_date != today) {
      _date = today;
      _used = 0;
      _saveNoticeShown = false;
    }
    usage.value = _used;
  }

  Future<int> currentUsage() => _queue.run(() async {
    await _load();
    return _used;
  });

  Future<bool> allowsAutomatic(int estimate) => _queue.run(() async {
    await _load();
    return _used + estimate <= starSyncGoogleSoftLimit;
  });

  Future<bool> claimSaveNotice() => _queue.run(() async {
    await _load();
    if (_saveNoticeShown) return false;
    await _storage.write(
      key: starSyncGoogleQuotaKey,
      value: jsonEncode({
        'date': _date,
        'units': _used,
        'saveNoticeShown': true,
      }),
    );
    _saveNoticeShown = true;
    return true;
  });

  Future<void> charge(int units) => _queue.run(() async {
    if (units <= 0) throw ArgumentError.value(units, 'units');
    await _load();
    if (_used + units > starSyncGoogleHardLimit) {
      throw const StarSyncQuotaExceeded();
    }
    final next = _used + units;
    await _storage.write(
      key: starSyncGoogleQuotaKey,
      value: jsonEncode({
        'date': _date,
        'units': next,
        'saveNoticeShown': _saveNoticeShown,
      }),
    );
    _used = next;
    usage.value = next;
  });
}
