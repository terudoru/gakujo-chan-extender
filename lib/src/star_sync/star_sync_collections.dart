import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'star_sync_document.dart';

abstract class StarSyncCollection {
  bool get preferRemoteOnFirstSync => false;
  String get name;
  bool get growOnly;
  Future<Map<String, Object?>?> readLocal();

  /// Applies only if local data still equals basedOn in canonical JSON.
  /// Returns false on a concurrent edit; the engine retries on a later sync.
  Future<bool> applyLocal(
    Map<String, Object?> entries, {
    required Map<String, Object?> basedOn,
  });
  Map<String, Object?> clearSnapshot(
    Map<String, Object?> current,
    Map<String, Object?> snapshot,
  ) => {
    for (final entry in current.entries)
      if (!snapshot.containsKey(entry.key) ||
          starSyncCanonicalJson(entry.value) !=
              starSyncCanonicalJson(snapshot[entry.key]))
        entry.key: entry.value,
  };

  Map<String, Object?> restoreSnapshot(Map<String, Object?> live) => live;

  int? get maxLive;
  Comparable Function(Object? value)? get order;
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String starSyncCanonicalJson(Object? value) => jsonEncode(_canonical(value));
String starSyncValueHash(Object? value) =>
    sha256.convert(utf8.encode(starSyncCanonicalJson(value))).toString();

class StarSyncCollectionRecord {
  const StarSyncCollectionRecord({
    required this.key,
    required this.value,
    required this.deleted,
    required this.clock,
    required this.deviceId,
    required this.valueHash,
  });

  final String key;
  final Object? value;
  final bool deleted;
  final int clock;
  final String deviceId;
  final String valueHash;

  Map<String, Object?> toJson() => {
    'key': key,
    'value': value,
    'deleted': deleted,
    'clock': clock,
    'deviceId': deviceId,
    'valueHash': valueHash,
  };

  static StarSyncCollectionRecord fromJson(Object? json, String key) {
    if (json is! Map ||
        json['key'] != key ||
        json['deleted'] is! bool ||
        json['clock'] is! int ||
        (json['clock'] as int) < 0 ||
        json['deviceId'] is! String ||
        (json['deviceId'] as String).isEmpty ||
        json['valueHash'] is! String ||
        !json.containsKey('value') ||
        (json['deleted'] == true && json['value'] != null)) {
      throw const StarSyncFormatException();
    }
    final value = json['value'];
    if (starSyncValueHash(value) != json['valueHash']) {
      throw const StarSyncFormatException();
    }
    return StarSyncCollectionRecord(
      key: key,
      value: value,
      deleted: json['deleted'] as bool,
      clock: json['clock'] as int,
      deviceId: json['deviceId'] as String,
      valueHash: json['valueHash'] as String,
    );
  }
}

class StarSyncCollectionDocument {
  const StarSyncCollectionDocument({
    required this.collection,
    required this.deviceId,
    required this.account,
    required this.clock,
    required this.records,
  });

  final String collection;
  final String deviceId;
  final String? account;
  final int clock;
  final Map<String, StarSyncCollectionRecord> records;

  Map<String, Object?> toJson() => {
    'schema': 1,
    'collection': collection,
    'deviceId': deviceId,
    'account': account,
    'clock': clock,
    'records': records.map((key, value) => MapEntry(key, value.toJson())),
  };

  static StarSyncCollectionDocument fromJson(Object? json) {
    if (json is! Map ||
        json['schema'] != 1 ||
        json['collection'] is! String ||
        json['deviceId'] is! String ||
        (json['deviceId'] as String).isEmpty ||
        (json['account'] != null && json['account'] is! String) ||
        json['clock'] is! int ||
        (json['clock'] as int) < 0 ||
        json['records'] is! Map) {
      throw const StarSyncFormatException();
    }
    final records = <String, StarSyncCollectionRecord>{};
    for (final entry in (json['records'] as Map).entries) {
      if (entry.key is! String) throw const StarSyncFormatException();
      final key = entry.key as String;
      records[key] = StarSyncCollectionRecord.fromJson(entry.value, key);
    }
    return StarSyncCollectionDocument(
      collection: json['collection'] as String,
      deviceId: json['deviceId'] as String,
      account: json['account'] as String?,
      clock: json['clock'] as int,
      records: records,
    );
  }
}

Map<String, StarSyncCollectionRecord> mergeStarSyncCollectionRecords(
  Iterable<Map<String, StarSyncCollectionRecord>> sources,
) {
  final result = <String, StarSyncCollectionRecord>{};
  for (final source in sources) {
    for (final record in source.values) {
      final old = result[record.key];
      if (old == null ||
          record.clock > old.clock ||
          (record.clock == old.clock &&
              record.deviceId.compareTo(old.deviceId) > 0)) {
        result[record.key] = record;
      }
    }
  }
  final tombstones = result.values.where((record) => record.deleted).toList()
    ..sort((a, b) {
      final clock = b.clock.compareTo(a.clock);
      if (clock != 0) return clock;
      final device = b.deviceId.compareTo(a.deviceId);
      return device != 0 ? device : b.key.compareTo(a.key);
    });
  for (final record in tombstones.skip(starSyncMaxTombstones)) {
    result.remove(record.key);
  }
  final keys = result.keys.toList()..sort();
  return {for (final key in keys) key: result[key]!};
}
