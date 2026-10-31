import 'dart:convert';
import 'dart:typed_data';

import '../gakujo_activity_store.dart';

const starSyncTombstoneRetention = Duration(days: 180);
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
  }) : title = _title(title),
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
    return winner.title.isEmpty && loser.title.isNotEmpty
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
  }) : writtenAt = writtenAt.toUtc(),
       records = Map.unmodifiable(records);
  static const int schema = 1;
  final String deviceId;
  final DateTime writtenAt;
  final int clock;
  final Map<String, StarSyncRecord> records;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'deviceId': deviceId,
    'writtenAt': writtenAt.toIso8601String(),
    'clock': clock,
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
        value['stars'] is! Map) {
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
      return edit != 0 ? edit : b.title.compareTo(a.title);
    });
    var winner = candidates.first;
    if (winner.title.isEmpty) {
      for (final candidate in candidates) {
        if (candidate.title.isNotEmpty) {
          winner = winner.copyWith(title: candidate.title);
          break;
        }
      }
    }
    if (winner.starred ||
        !winner.updatedAt.isBefore(now.subtract(starSyncTombstoneRetention))) {
      merged[id] = winner;
    }
  }
  final live = merged.values.where((record) => record.starred).toList()
    ..sort((a, b) {
      final date = b.starredAt.compareTo(a.starredAt);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
  for (final record in live.skip(starSyncMaxStars)) {
    merged.remove(record.id);
  }
  return merged;
}

({Map<String, StarSyncRecord> state, int clock}) reconcileLocalStars({
  required List<GakujoStarredMessage> local,
  required Map<String, StarSyncRecord> state,
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
  DateTime? oldest;
  if (local.length >= starSyncMaxStars && local.isNotEmpty) {
    oldest = local
        .map((item) => item.starredAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }
  for (final id in ids) {
    final item = localById[id];
    final previous = state[id];
    if (item != null) {
      if (previous == null ||
          !previous.starred ||
          !previous.starredAt.isAtSameMomentAs(item.starredAt)) {
        result[id] = StarSyncRecord(
          id: id,
          title: item.title,
          starred: true,
          starredAt: item.starredAt,
          clock: ++clock,
          deviceId: deviceId,
          updatedAt: now,
        );
      } else if (item.title.isNotEmpty && item.title != previous.title) {
        result[id] = previous.copyWith(title: item.title);
      }
    } else if (previous != null &&
        previous.starred &&
        !bulkReplace &&
        (oldest == null || previous.starredAt.isAfter(oldest))) {
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
