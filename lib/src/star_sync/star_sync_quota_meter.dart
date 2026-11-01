import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../secure_storage_factory.dart';
import '../secure_storage_transaction.dart';

const starSyncGoogleQuotaKey = 'more_better_gakujo_google_quota';
const starSyncGoogleSoftLimit = 15000;
const starSyncGoogleHardLimit = 25000;
const starSyncGoogleQuotaMessage =
    '直近24時間の Google ドライブの利用量が上限に達しました。時間をおくと再開します';

class StarSyncQuotaExceeded implements Exception {
  const StarSyncQuotaExceeded();

  @override
  String toString() => starSyncGoogleQuotaMessage;
}

/// Counts Google Drive API quota units over a rolling 24 hours in hourly
/// buckets. A rolling window bounds every fixed 24-hour period, including
/// Google's own accounting day, which a local calendar day would not.
class StarSyncQuotaMeter {
  StarSyncQuotaMeter({FlutterSecureStorage? storage, DateTime Function()? now})
    : _storage = storage ?? SecureStorageFactory.create(),
      _now = now ?? DateTime.now;

  static final shared = StarSyncQuotaMeter();
  static const _window = Duration(hours: 24);
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final StorageOperationQueue _queue = StorageOperationQueue();
  final ValueNotifier<int> usage = ValueNotifier(0);
  // Hour start (UTC, ms since epoch) -> units charged in that hour.
  final Map<int, int> _buckets = {};
  int? _saveNoticeAt;
  bool _loaded = false;

  int _hour(DateTime time) {
    final utc = time.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
    ).millisecondsSinceEpoch;
  }

  // Buckets that can still overlap the last 24 hours (one extra hour, so the
  // hourly rounding never undercounts).
  int get _oldestCounted => _hour(_now()) - _window.inMilliseconds;

  int get _used => _buckets.entries
      .where((entry) => entry.key >= _oldestCounted)
      .fold(0, (sum, entry) => sum + entry.value);

  Future<void> _load() async {
    if (!_loaded) {
      final raw = await _storage.read(key: starSyncGoogleQuotaKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        final buckets = data is Map ? data['buckets'] : null;
        if (buckets is Map) {
          for (final entry in buckets.entries) {
            final hour = int.tryParse('${entry.key}');
            final units = entry.value;
            if (hour == null || units is! int || units < 0) {
              throw const FormatException('Invalid Google Drive quota');
            }
            _buckets[hour] = units;
          }
          final notice = data['saveNoticeAt'];
          _saveNoticeAt = notice is int ? notice : null;
        }
        // An older day-based record is ignored; the rolling window starts
        // empty, which can only make the next 24 hours slightly generous
        // once.
      }
      _loaded = true;
    }
    _buckets.removeWhere((hour, _) => hour < _oldestCounted);
    usage.value = _used;
  }

  Future<void> _save() => _storage.write(
    key: starSyncGoogleQuotaKey,
    value: jsonEncode({
      'buckets': {
        for (final entry in _buckets.entries) '${entry.key}': entry.value,
      },
      'saveNoticeAt': ?_saveNoticeAt,
    }),
  );

  Future<int> currentUsage() => _queue.run(() async {
    await _load();
    return _used;
  });

  Future<bool> allowsAutomatic(int estimate) => _queue.run(() async {
    await _load();
    return _used + estimate <= starSyncGoogleSoftLimit;
  });

  /// How long until automatic work of [estimate] units fits under the soft
  /// limit again, as old hourly buckets leave the window.
  Future<Duration> timeUntilAutomaticAllowed(int estimate) =>
      _queue.run(() async {
        await _load();
        var used = _used;
        if (used + estimate <= starSyncGoogleSoftLimit) return Duration.zero;
        final now = _now().toUtc().millisecondsSinceEpoch;
        final hours =
            _buckets.keys.where((hour) => hour >= _oldestCounted).toList()
              ..sort();
        for (final hour in hours) {
          used -= _buckets[hour]!;
          if (used + estimate <= starSyncGoogleSoftLimit) {
            // This bucket stops counting once its hour is outside the window.
            final expires =
                hour +
                _window.inMilliseconds +
                const Duration(hours: 1).inMilliseconds;
            return Duration(milliseconds: (expires - now).clamp(0, 1 << 31));
          }
        }
        return _window;
      });

  /// True at most once per 24 hours, for the "save skipped" notice.
  Future<bool> claimSaveNotice() => _queue.run(() async {
    await _load();
    final now = _now().toUtc().millisecondsSinceEpoch;
    final last = _saveNoticeAt;
    if (last != null && now - last < _window.inMilliseconds) return false;
    _saveNoticeAt = now;
    await _save();
    return true;
  });

  Future<void> charge(int units) => _queue.run(() async {
    if (units <= 0) throw ArgumentError.value(units, 'units');
    await _load();
    if (_used + units > starSyncGoogleHardLimit) {
      throw const StarSyncQuotaExceeded();
    }
    final hour = _hour(_now());
    _buckets[hour] = (_buckets[hour] ?? 0) + units;
    await _save();
    usage.value = _used;
  });
}
