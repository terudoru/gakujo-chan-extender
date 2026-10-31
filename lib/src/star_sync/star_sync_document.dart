import 'dart:convert';
import 'dart:typed_data';

import '../gakujo_activity_store.dart';

const starSyncMaxTombstones = 1000;
const starSyncMaxStars = 300;

class StarSyncFormatException implements Exception {
  const StarSyncFormatException([this.message = 'Invalid star sync format']);
  final String message;
  @override
  String toString() => 'StarSyncFormatException: $message';
}

final _idPattern = RegExp(r'^[0-9]+\|[0-9]+\|[0-9]+$');
String _title(String value) => String.fromCharCodes(value.runes.take(300));

class StarSyncRecord {
  StarSyncRecord({
    required this.id,
    required String title,
    required this.starred,
    required DateTime starredAt,
    required this.clock,
    required this.deviceId,
    required DateTime updatedAt,
  }) : title = starred ? _title(title) : '',
       starredAt = starredAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  final String id;
  final String title;
  final bool starred;
  final DateTime starredAt;
  final int clock;
  final String deviceId;
  final DateTime updatedAt;

  StarSyncRecord copyWith({
    String? title,
    bool? starred,
    DateTime? starredAt,
    int? clock,
    String? deviceId,
    DateTime? updatedAt,
  }) => StarSyncRecord(
    id: id,
    title: title ?? this.title,
    starred: starred ?? this.starred,
    starredAt: starredAt ?? this.starredAt,
    clock: clock ?? this.clock,
    deviceId: deviceId ?? this.deviceId,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'starred': starred,
    'starredAt': starredAt.toIso8601String(),
    'clock': clock,
    'deviceId': deviceId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static StarSyncRecord? fromJson(Object? value, {String? id}) {
    if (value is! Map) {
      return null;
    }
    final recordId = id ?? value['id'];
    final title = value['title'];
    final starred = value['starred'];
    final clock = value['clock'];
    final deviceId = value['deviceId'];
    final starredAt = value['starredAt'];
    final updatedAt = value['updatedAt'];
    if (recordId is! String ||
        !_idPattern.hasMatch(recordId) ||
        (id != null && value.containsKey('id') && value['id'] != id) ||
        title is! String ||
        starred is! bool ||
        clock is! int ||
        clock < 0 ||
        deviceId is! String ||
        deviceId.isEmpty ||
        starredAt is! String ||
        updatedAt is! String) {
      return null;
    }
    final parsedStarred = DateTime.tryParse(starredAt);
    final parsedUpdated = DateTime.tryParse(updatedAt);
    if (parsedStarred == null || parsedUpdated == null) {
      return null;
    }
    return StarSyncRecord(
      id: recordId,
      title: title,
      starred: starred,
      starredAt: parsedStarred,
      clock: clock,
      deviceId: deviceId,
      updatedAt: parsedUpdated,
    );
  }

  static StarSyncRecord pick(StarSyncRecord a, StarSyncRecord b) {
    final comparison = _compareEdits(a, b);
    final winner = comparison >= 0 ? a : b;
    final loser = comparison >= 0 ? b : a;
    return winner.starred && winner.title.isEmpty && loser.title.isNotEmpty
        ? winner.copyWith(title: loser.title)
        : winner;
  }
}

int _compareEdits(StarSyncRecord a, StarSyncRecord b) {
  final clock = a.clock.compareTo(b.clock);
  return clock != 0 ? clock : a.deviceId.compareTo(b.deviceId);
}

class StarSyncDocument {
  StarSyncDocument({
    required this.deviceId,
    required DateTime writtenAt,
    required this.clock,
    required Map<String, StarSyncRecord> records,
    this.account,
  }) : writtenAt = writtenAt.toUtc(),
       records = Map.unmodifiable(records);
  static const int schema = 1;
  final String deviceId;
  final DateTime writtenAt;
  final int clock;
  final Map<String, StarSyncRecord> records;
  final String? account;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'deviceId': deviceId,
    'writtenAt': writtenAt.toIso8601String(),
    'clock': clock,
    if (account != null) 'account': account,
    'stars': records.map((id, record) => MapEntry(id, record.toJson())),
  };

  static StarSyncDocument fromJson(Object? value) {
    if (value is! Map ||
        value['schema'] != schema ||
        value['deviceId'] is! String ||
        (value['deviceId'] as String).isEmpty ||
        value['writtenAt'] is! String ||
        value['clock'] is! int ||
        (value['clock'] as int) < 0 ||
        value['stars'] is! Map ||
        (value['account'] != null && value['account'] is! String)) {
      throw const StarSyncFormatException();
    }
    final writtenAt = DateTime.tryParse(value['writtenAt'] as String);
    if (writtenAt == null) {
      throw const StarSyncFormatException();
    }
    final records = <String, StarSyncRecord>{};
    (value['stars'] as Map).forEach((key, entry) {
      if (key is String) {
        final record = StarSyncRecord.fromJson(entry, id: key);
        if (record != null) records[key] = record;
      }
    });
    return StarSyncDocument(
      deviceId: value['deviceId'] as String,
      writtenAt: writtenAt,
      clock: value['clock'] as int,
      records: records,
      account: value['account'] as String?,
    );
  }

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static StarSyncDocument fromBytes(List<int> bytes) {
    try {
      return fromJson(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      throw const StarSyncFormatException();
    }
  }
}

Map<String, StarSyncRecord> mergeStarSyncRecords(
  Iterable<Map<String, StarSyncRecord>> sources, {
  required DateTime now,
}) {
  final groups = <String, List<StarSyncRecord>>{};
  for (final source in sources) {
    for (final entry in source.entries) {
      (groups[entry.key] ??= []).add(entry.value);
    }
  }
  final merged = <String, StarSyncRecord>{};
  final ids = groups.keys.toList()..sort();
  for (final id in ids) {
    final candidates = groups[id]!;
    candidates.sort((a, b) {
      final edit = _compareEdits(b, a);
      if (edit != 0) return edit;
      final title = b.title.compareTo(a.title);
      if (title != 0) return title;
      if (a.starred != b.starred) return a.starred ? -1 : 1;
      final starredAt = b.starredAt.compareTo(a.starredAt);
      return starredAt != 0 ? starredAt : b.updatedAt.compareTo(a.updatedAt);
    });
    var winner = candidates.first;
    if (winner.starred && winner.title.isEmpty) {
      for (final candidate in candidates) {
        if (candidate.title.isNotEmpty) {
          winner = winner.copyWith(title: candidate.title);
          break;
        }
      }
    }
    merged[id] = winner;
  }
  final tombstones = merged.values.where((record) => !record.starred).toList()
    ..sort((a, b) {
      final clock = b.clock.compareTo(a.clock);
      if (clock != 0) return clock;
      final device = b.deviceId.compareTo(a.deviceId);
      return device != 0 ? device : b.id.compareTo(a.id);
    });
  for (final record in tombstones.skip(starSyncMaxTombstones)) {
    merged.remove(record.id);
  }
  return merged;
}

({Map<String, StarSyncRecord> state, int clock}) reconcileLocalStars({
  required List<GakujoStarredMessage> local,
  required Map<String, StarSyncRecord> state,
  Map<String, StarSyncRecord> known = const {},
  required int clock,
  required String deviceId,
  required DateTime now,
  bool bulkReplace = false,
}) {
  final result = Map<String, StarSyncRecord>.from(state);
  final localById = {
    for (final item in local)
      if (item.isValid) item.id: item,
  };
  final ids = {...state.keys, ...localById.keys}.toList()..sort();
  GakujoStarredMessage? lastKept;
  if (local.length >= starSyncMaxStars && local.isNotEmpty) {
    lastKept = local.reduce((a, b) {
      final date = b.starredAt.compareTo(a.starredAt);
      final order = date != 0 ? date : a.id.compareTo(b.id);
      return order >= 0 ? a : b;
    });
  }
  for (final id in ids) {
    final item = localById[id];
    final previous = state[id];
    if (item != null) {
      final knownRecord = known[id];
      final matchesPrevious =
          previous != null &&
          previous.starredAt.isAtSameMomentAs(item.starredAt);
      final matchesKnown =
          knownRecord != null &&
          knownRecord.starredAt.isAtSameMomentAs(item.starredAt);
      if (!matchesPrevious && !matchesKnown) {
        result[id] = StarSyncRecord(
          id: id,
          title: item.title,
          starred: true,
          starredAt: item.starredAt,
          clock: ++clock,
          deviceId: deviceId,
          updatedAt: now,
        );
      } else if (previous != null &&
          matchesPrevious &&
          previous.starred &&
          item.title.isNotEmpty &&
          item.title != previous.title) {
        result[id] = previous.copyWith(title: item.title);
      }
    } else if (previous != null &&
        previous.starred &&
        !bulkReplace &&
        (lastKept == null ||
            previous.starredAt.isAfter(lastKept.starredAt) ||
            (previous.starredAt.isAtSameMomentAs(lastKept.starredAt) &&
                previous.id.compareTo(lastKept.id) < 0))) {
      result[id] = previous.copyWith(
        starred: false,
        clock: ++clock,
        deviceId: deviceId,
        updatedAt: now,
      );
    }
  }
  return (state: result, clock: clock);
}

List<GakujoStarredMessage> applyStarSyncStateToLocal({
  required Map<String, StarSyncRecord> state,
  required List<GakujoStarredMessage> local,
}) {
  final localById = {for (final item in local) item.id: item};
  final result = <GakujoStarredMessage>[];
  for (final record in state.values.where((record) => record.starred)) {
    final parts = record.id.split('|');
    if (parts.length != 3 || !_idPattern.hasMatch(record.id)) {
      continue;
    }
    final previous = localById[record.id];
    result.add(
      GakujoStarredMessage(
        keijitype: parts[0],
        genrecd: parts[1],
        seqNo: parts[2],
        title: previous == null || previous.title.isEmpty
            ? record.title
            : previous.title,
        genre: previous?.genre ?? '',
        sender: previous?.sender ?? '',
        period: previous?.period ?? '',
        postedAt: previous?.postedAt ?? '',
        body: previous?.body ?? '',
        starredAt: record.starredAt,
      ),
    );
  }
  result.sort((a, b) {
    final date = b.starredAt.compareTo(a.starredAt);
    return date != 0 ? date : a.id.compareTo(b.id);
  });
  return result;
}
