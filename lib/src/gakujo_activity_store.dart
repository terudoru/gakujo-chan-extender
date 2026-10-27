import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'gakujo_activity_classifier.dart';
import 'gakujo_assignment.dart';
import 'gakujo_dated_activity.dart';
import 'secure_storage_factory.dart';
import 'secure_storage_transaction.dart';

class GakujoActivitySnapshot {
  const GakujoActivitySnapshot({
    required this.category,
    required this.title,
    required this.url,
    required this.contentHash,
    required this.updatedAt,
    required this.hasUpdate,
    this.contentPreview = '',
  });

  final String category;
  final String title;
  final String url;
  final String contentHash;
  final DateTime updatedAt;
  final bool hasUpdate;
  final String contentPreview;

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'title': title,
      'url': url,
      'contentHash': contentHash,
      'updatedAt': updatedAt.toIso8601String(),
      'hasUpdate': hasUpdate,
      'contentPreview': contentPreview,
    };
  }

  factory GakujoActivitySnapshot.fromJson(Map<dynamic, dynamic> json) {
    return GakujoActivitySnapshot(
      category: json['category']?.toString() ?? 'その他',
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      contentHash: json['contentHash']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      hasUpdate: json['hasUpdate'] == true,
      contentPreview: json['contentPreview']?.toString() ?? '',
    );
  }
}

class GakujoDeadlineEntry {
  const GakujoDeadlineEntry({
    required this.title,
    required this.url,
    required this.dueText,
    required this.detectedAt,
    this.kind = 'deadline',
    this.source = '',
    this.course = '',
    this.courseCode = '',
    this.assignment = '',
    this.messageText = '',
  });

  final String title;
  final String url;
  final String dueText;
  final DateTime detectedAt;
  final String kind;

  /// Category of the page the deadline was read from, such as 連絡通知.
  /// Older entries have none.
  final String source;

  /// Course and bare assignment title, when the page names them, so the
  /// same assignment found on two pages is told about once.
  final String course;
  final String courseCode;
  final String assignment;

  /// Full message row/body, before the dated preview drops non-date text.
  final String messageText;

  String get assignmentKind =>
      RegExp(r'^(\S*(?:レポート|小テスト|アンケート))\s').firstMatch(title)?.group(1) ?? '';

  bool get isDeadline => kind == 'deadline';

  /// Gakujo puts a per-visit `_flowExecutionKey` in its links; leaving it
  /// in made the same deadline look new, and notify again, on every visit.
  String get key => '$kind|${stableGakujoUrl(url)}|$title|$dueText';

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'url': url,
      'dueText': dueText,
      'detectedAt': detectedAt.toIso8601String(),
      'kind': kind,
      if (source.isNotEmpty) 'source': source,
      if (course.isNotEmpty) 'course': course,
      if (courseCode.isNotEmpty) 'courseCode': courseCode,
      if (assignment.isNotEmpty) 'assignment': assignment,
      if (messageText.isNotEmpty) 'messageText': messageText,
    };
  }

  factory GakujoDeadlineEntry.fromJson(Map<dynamic, dynamic> json) {
    return GakujoDeadlineEntry(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      dueText: json['dueText']?.toString() ?? '',
      detectedAt: DateTime.tryParse(json['detectedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      kind: json['kind']?.toString() ?? 'deadline',
      source: json['source']?.toString() ?? '',
      course: json['course']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      assignment: json['assignment']?.toString() ?? '',
      messageText: json['messageText']?.toString() ?? '',
    );
  }
}

/// [url] without Gakujo's per-visit `_flowExecutionKey` parameter.
String stableGakujoUrl(String url) {
  return url
      .replaceAll(RegExp(r'_flowExecutionKey=[^&#]*&?'), '')
      .replaceAll(RegExp(r'[?&]$'), '');
}

/// One deadline per assignment of the レポート・小テスト list, closing time in
/// Japan time, tied to the assignment so it is notified once.
List<GakujoDeadlineEntry> deadlineEntriesForAssignments(
  Iterable<GakujoAssignment> assignments, {
  required String url,
  required DateTime detectedAt,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  return [
    for (final assignment in assignments)
      if (assignment.dueInJapan case final due)
        GakujoDeadlineEntry(
          title: GakujoDatedActivity.compactText(
            '${assignment.kind} ${assignment.course} ${assignment.title}',
            maxLength: 80,
          ),
          url: url,
          dueText: '${due.year}/${two(due.month)}/${two(due.day)} '
              '${two(due.hour)}:${two(due.minute)}まで',
          detectedAt: detectedAt,
          source: 'レポート・小テスト',
          course: assignment.course,
          courseCode: assignment.courseCode,
          assignment: assignment.title,
        ),
  ];
}

/// A link that still opens later. One carrying a per-visit
/// `_flowExecutionKey` expires, so a tapped notification would land on
/// 「ページの有効期限ぎれ」; such a link is replaced by the portal tab of its
/// page [category], or the portal main page when the category is unknown.
String durableGakujoLink(String url, String category) {
  if (!url.contains('_flowExecutionKey=')) {
    return url;
  }
  final tab = switch (category) {
    'レポート・小テスト' => 'en',
    'スケジュール' => 'sch',
    '連絡通知' => 'kj',
    '成績' => 'si',
    _ => null,
  };
  return 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
      'campusportal.do?page=main${tab == null ? '' : '&tabId=$tab'}';
}

/// A link that opens a 連絡通知 again later. The list row's link only works
/// with the flow key of that visit, so point at the 連絡通知 flow instead and
/// keep the message's number.
String gakujoMessageLinkFor(String url) {
  final uri = Uri.tryParse(url);
  final seqNo = uri?.queryParameters['seqNo'];
  if (uri == null || seqNo == null || seqNo.isEmpty) {
    return url;
  }
  return uri.replace(
    queryParameters: {
      '_flowId': 'KJW0001100-flow',
      for (final name in const ['keijitype', 'genrecd'])
        name: ?uri.queryParameters[name],
      'seqNo': seqNo,
    },
  ).toString();
}

class GakujoActivityChangeEntry {
  const GakujoActivityChangeEntry({
    required this.category,
    required this.title,
    required this.url,
    required this.changedAt,
    required this.previousHash,
    required this.nextHash,
    this.previousPreview = '',
    this.nextPreview = '',
  });

  final String category;
  final String title;
  final String url;
  final DateTime changedAt;
  final String previousHash;
  final String nextHash;
  final String previousPreview;
  final String nextPreview;

  Map<String, Object?> toJson() {
    return {
      'category': category,
      'title': title,
      'url': url,
      'changedAt': changedAt.toIso8601String(),
      'previousHash': previousHash,
      'nextHash': nextHash,
      'previousPreview': previousPreview,
      'nextPreview': nextPreview,
    };
  }

  factory GakujoActivityChangeEntry.fromJson(Map<dynamic, dynamic> json) {
    return GakujoActivityChangeEntry(
      category: json['category']?.toString() ?? 'その他',
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      changedAt: DateTime.tryParse(json['changedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      previousHash: json['previousHash']?.toString() ?? '',
      nextHash: json['nextHash']?.toString() ?? '',
      previousPreview: json['previousPreview']?.toString() ?? '',
      nextPreview: json['nextPreview']?.toString() ?? '',
    );
  }
}

class GakujoCachedReportList {
  const GakujoCachedReportList({
    required this.title,
    required this.url,
    required this.capturedAt,
    required this.items,
  });

  final String title;
  final String url;
  final DateTime capturedAt;
  final List<String> items;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'url': url,
      'capturedAt': capturedAt.toIso8601String(),
      'items': items,
    };
  }

  factory GakujoCachedReportList.fromJson(Map<dynamic, dynamic> json) {
    final rawItems = json['items'];
    return GakujoCachedReportList(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      capturedAt: DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      items: rawItems is List<dynamic>
          ? rawItems.map((item) => item.toString()).toList()
          : const [],
    );
  }
}

class GakujoFavoritePage {
  const GakujoFavoritePage({
    required this.title,
    required this.url,
    required this.addedAt,
  });

  final String title;
  final String url;
  final DateTime addedAt;

  String get durableUrl => durableGakujoLink(
        gakujoMessageLinkFor(url),
        GakujoActivityClassifier.categoryFor(url: url, title: title, text: ''),
      );

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'url': durableUrl,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory GakujoFavoritePage.fromJson(Map<dynamic, dynamic> json) {
    return GakujoFavoritePage(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      addedAt: DateTime.tryParse(json['addedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class GakujoStarredMessage {
  GakujoStarredMessage({
    required this.keijitype,
    required this.genrecd,
    required this.seqNo,
    required this.title,
    this.genre = '',
    this.sender = '',
    this.period = '',
    this.postedAt = '',
    String body = '',
    required this.starredAt,
  }) : body = body.length > 4000 ? body.substring(0, 4000) : body;

  final String keijitype;
  final String genrecd;
  final String seqNo;
  final String title;
  final String genre;
  final String sender;
  final String period;
  final String postedAt;
  final String body;
  final DateTime starredAt;

  String get id => '$keijitype|$genrecd|$seqNo';

  bool get isValid => [keijitype, genrecd, seqNo]
      .every((value) => RegExp(r'^[0-9]+$').hasMatch(value));

  Map<String, Object?> toJson() => {
        'keijitype': keijitype,
        'genrecd': genrecd,
        'seqNo': seqNo,
        'title': title,
        'genre': genre,
        'sender': sender,
        'period': period,
        'postedAt': postedAt,
        'body': body,
        'starredAt': starredAt.toIso8601String(),
      };

  factory GakujoStarredMessage.fromJson(Map<dynamic, dynamic> json) {
    return GakujoStarredMessage(
      keijitype: json['keijitype']?.toString() ?? '',
      genrecd: json['genrecd']?.toString() ?? '',
      seqNo: json['seqNo']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      genre: json['genre']?.toString() ?? '',
      sender: json['sender']?.toString() ?? '',
      period: json['period']?.toString() ?? '',
      postedAt: json['postedAt']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      starredAt: DateTime.tryParse(json['starredAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _StorageReadResult<T> {
  const _StorageReadResult.success(this.value) : isSuccessful = true;

  const _StorageReadResult.failure(this.value) : isSuccessful = false;

  final T value;
  final bool isSuccessful;
}

class GakujoActivityStore {
  GakujoActivityStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageFactory.create();

  static const _snapshotsKey = 'more_better_gakujo_activity_snapshots';
  static const _deadlinesKey = 'more_better_gakujo_deadlines';
  static const _notifiedDeadlineKeysKey =
      'more_better_gakujo_notified_deadline_keys';
  static const _favoritesKey = 'more_better_gakujo_favorites';
  static const _starredMessagesKey = 'more_better_gakujo_starred_messages';
  static const _changesKey = 'more_better_gakujo_activity_changes';
  static const _reportListsKey = 'more_better_gakujo_cached_report_lists';
  static const _assignmentsKey = 'more_better_gakujo_assignments';
  static const _wholeAssignmentListKey =
      'more_better_gakujo_whole_assignment_list';
  static const _maxAssignments = 200;
  static const _assignmentRetention = Duration(days: 30);
  static const _maxSnapshots = 120;
  // 連絡通知 alone can hold hundreds of dated rows, so they get their own
  // share instead of pushing coursework deadlines out.
  static const _maxDeadlines = 80;
  static const _maxMessageDeadlines = 80;
  static const _maxNotifiedDeadlineKeys = 1000;
  static const _maxFavorites = 30;
  static const _maxStarredMessages = 300;
  static const _maxChanges = 120;
  static const _maxReportLists = 20;
  static const _snapshotRetention = Duration(days: 180);
  static const _deadlineGracePeriod = Duration(days: 7);
  static const _undatedDeadlineRetention = Duration(days: 90);
  static const _changeRetention = Duration(days: 90);
  static const _reportListRetention = Duration(days: 60);

  final FlutterSecureStorage _secureStorage;
  final _operations = StorageOperationQueue();

  BackupStorageParticipant get backupStorage => BackupStorageParticipant(
        _operations,
        _secureStorage,
        const [
          _deadlinesKey,
          _notifiedDeadlineKeysKey,
          _favoritesKey,
          _starredMessagesKey,
          _changesKey,
          _reportListsKey,
        ],
      );

  Future<_StorageReadResult<String?>> _readRawValue(String key) async {
    try {
      return _StorageReadResult.success(
        await _secureStorage.read(key: key),
      );
    } on Object {
      // Cached activity data is best-effort. If secure storage is briefly
      // unavailable (e.g. a cold keychain read times out), degrade to no
      // cached data rather than throwing out of a background scan.
      return const _StorageReadResult.failure(null);
    }
  }

  Future<List<GakujoActivitySnapshot>> loadSnapshots() {
    return _enqueue(() async => (await _readSnapshots()).value);
  }

  Future<_StorageReadResult<List<GakujoActivitySnapshot>>> _readSnapshots() {
    return _readList(
      key: _snapshotsKey,
      fromJson: GakujoActivitySnapshot.fromJson,
      retain: (snapshot) =>
          _isUsefulSnapshot(snapshot) && _isRecentSnapshot(snapshot),
      compare: (a, b) => b.updatedAt.compareTo(a.updatedAt),
      limit: _maxSnapshots,
    );
  }

  Future<List<GakujoDeadlineEntry>> loadDeadlines() {
    return _enqueue(() async => (await _readDeadlines()).value);
  }

  Future<List<GakujoDeadlineEntry>> loadDeadlinesForBackup() {
    return _enqueue(
      () => _readForBackup(_deadlinesKey, _readDeadlines),
    );
  }

  Future<_StorageReadResult<List<GakujoDeadlineEntry>>> _readDeadlines() {
    return _readList(
      key: _deadlinesKey,
      fromJson: GakujoDeadlineEntry.fromJson,
      retain: (entry) => _isUsefulDeadline(entry) && _isActiveDeadline(entry),
      compare: (a, b) => b.detectedAt.compareTo(a.detectedAt),
      limit: _maxDeadlines + _maxMessageDeadlines,
    );
  }

  /// The newest deadlines within each share, newest first.
  static List<GakujoDeadlineEntry> _capDeadlines(
    Iterable<GakujoDeadlineEntry> newestFirst,
  ) {
    final messages = <GakujoDeadlineEntry>[];
    final others = <GakujoDeadlineEntry>[];
    for (final entry in newestFirst) {
      final share = entry.source == '連絡通知' ? messages : others;
      final limit =
          entry.source == '連絡通知' ? _maxMessageDeadlines : _maxDeadlines;
      if (share.length < limit) {
        share.add(entry);
      }
    }
    return [...others, ...messages]
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  Future<Set<String>> loadNotifiedDeadlineKeys() {
    return _enqueue(() async => (await _readNotifiedDeadlineKeys()).value);
  }

  Future<Set<String>> loadNotifiedDeadlineKeysForBackup() {
    return _enqueue(
      () => _readForBackup(_notifiedDeadlineKeysKey, _readNotifiedDeadlineKeys),
    );
  }

  Future<_StorageReadResult<Set<String>>> _readNotifiedDeadlineKeys() async {
    final rawRead = await _readRawValue(_notifiedDeadlineKeysKey);
    if (!rawRead.isSuccessful) {
      return const _StorageReadResult.failure(<String>{});
    }
    final raw = rawRead.value;
    if (raw == null || raw.trim().isEmpty) {
      return const _StorageReadResult.success(<String>{});
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const _StorageReadResult.success(<String>{});
      }
      return _StorageReadResult.success(
        decoded
            .whereType<String>()
            .map((key) => key.trim())
            .where((key) => key.isNotEmpty)
            .map((key) => key.replaceFirstMapped(
                  RegExp(r'^(deadline|notice|schedule)\|([^|]*)\|'),
                  (match) => '${match[1]}|${stableGakujoUrl(match[2]!)}|',
                ))
            .toSet(),
      );
    } on Object {
      return const _StorageReadResult.success(<String>{});
    }
  }

  Future<void> addNotifiedDeadlineKeys(Iterable<String> deadlineKeys) {
    final keys = deadlineKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet();
    return _enqueue(() => _addNotifiedDeadlineKeys(keys));
  }

  Future<void> replaceNotifiedDeadlineKeys(Iterable<String> deadlineKeys) {
    final keys = deadlineKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();
    return _enqueue(() => _writeNotifiedDeadlineKeys(keys));
  }

  Future<void> _addNotifiedDeadlineKeys(Set<String> deadlineKeys) async {
    if (deadlineKeys.isEmpty) {
      return;
    }
    final notifiedRead = await _readNotifiedDeadlineKeys();
    if (!notifiedRead.isSuccessful) {
      return;
    }
    await _writeNotifiedDeadlineKeys([
      ...notifiedRead.value.where((key) => !deadlineKeys.contains(key)),
      ...deadlineKeys,
    ]);
  }

  /// Keeps the newest keys, oldest first. They are not tied to the stored
  /// deadlines: a deadline pushed out of storage and found again on the next
  /// visit must still count as notified, or it is notified once more.
  Future<void> _writeNotifiedDeadlineKeys(List<String> oldestFirst) {
    final kept = oldestFirst.length > _maxNotifiedDeadlineKeys
        ? oldestFirst.sublist(oldestFirst.length - _maxNotifiedDeadlineKeys)
        : oldestFirst;
    return _secureStorage.write(
      key: _notifiedDeadlineKeysKey,
      value: jsonEncode(kept),
    );
  }

  Future<List<GakujoFavoritePage>> loadFavorites() {
    return _enqueue(() async => (await _readFavorites()).value);
  }

  Future<List<GakujoStarredMessage>> loadStarredMessages() {
    return _enqueue(() async => (await _readStarredMessages()).value);
  }

  Future<List<GakujoStarredMessage>> loadStarredMessagesForBackup() {
    return _enqueue(
      () => _readForBackup(_starredMessagesKey, _readStarredMessages),
    );
  }

  Future<_StorageReadResult<List<GakujoStarredMessage>>>
      _readStarredMessages() {
    return _readList(
      key: _starredMessagesKey,
      fromJson: GakujoStarredMessage.fromJson,
      retain: (entry) => entry.isValid,
      compare: (a, b) => b.starredAt.compareTo(a.starredAt),
      limit: _maxStarredMessages,
    );
  }

  /// Returns whether the message is starred after this atomic toggle.
  Future<bool> toggleStarredMessage(GakujoStarredMessage message) {
    return _enqueue(() async {
      if (!message.isValid) {
        throw ArgumentError('Invalid message identity');
      }
      final entries = await _readForBackup(
        _starredMessagesKey,
        _readStarredMessages,
      );
      final exists = entries.any((entry) => entry.id == message.id);
      await _replaceStarredMessages([
        if (!exists) message,
        ...entries.where((entry) => entry.id != message.id),
      ]);
      return !exists;
    });
  }

  Future<void> upsertStarredMessage(GakujoStarredMessage message) {
    return _enqueue(() async {
      if (!message.isValid) return;
      final entries = await _readForBackup(
        _starredMessagesKey,
        _readStarredMessages,
      );
      await _replaceStarredMessages([
        message,
        ...entries.where((entry) => entry.id != message.id),
      ]);
    });
  }

  /// A detail visit enriches an existing star without moving it to the top
  /// or recreating one that the student has just removed.
  Future<void> refreshStarredMessage(GakujoStarredMessage detail) {
    return _enqueue(() async {
      final entries = await _readForBackup(
        _starredMessagesKey,
        _readStarredMessages,
      );
      if (!entries.any((entry) => entry.id == detail.id)) return;
      await _replaceStarredMessages([
        for (final entry in entries)
          if (entry.id == detail.id)
            GakujoStarredMessage(
              keijitype: entry.keijitype,
              genrecd: entry.genrecd,
              seqNo: entry.seqNo,
              title: detail.title,
              genre: detail.genre.isEmpty ? entry.genre : detail.genre,
              sender: detail.sender,
              period: detail.period,
              postedAt:
                  detail.postedAt.isEmpty ? entry.postedAt : detail.postedAt,
              body: detail.body,
              starredAt: entry.starredAt,
            )
          else
            entry,
      ]);
    });
  }

  Future<void> removeStarredMessage(String id) {
    return _enqueue(() async {
      final entries = await _readForBackup(
        _starredMessagesKey,
        _readStarredMessages,
      );
      await _replaceStarredMessages(
        entries.where((entry) => entry.id != id).toList(),
      );
    });
  }

  Future<void> replaceStarredMessages(List<GakujoStarredMessage> entries) {
    return _enqueue(() => _replaceStarredMessages(entries));
  }

  Future<void> _replaceStarredMessages(List<GakujoStarredMessage> entries) {
    final byId = <String, GakujoStarredMessage>{};
    final sorted = entries.where((entry) => entry.isValid).toList()
      ..sort((a, b) => b.starredAt.compareTo(a.starredAt));
    for (final entry in sorted) {
      byId.putIfAbsent(entry.id, () => entry);
    }
    return _writeList(
        _starredMessagesKey, byId.values.take(_maxStarredMessages));
  }

  Future<List<GakujoFavoritePage>> loadFavoritesForBackup() {
    return _enqueue(
      () => _readForBackup(_favoritesKey, _readFavorites),
    );
  }

  Future<_StorageReadResult<List<GakujoFavoritePage>>> _readFavorites() {
    return _readList(
      key: _favoritesKey,
      fromJson: GakujoFavoritePage.fromJson,
      retain: _isUsefulFavorite,
      compare: (a, b) => b.addedAt.compareTo(a.addedAt),
      limit: _maxFavorites,
    );
  }

  Future<List<GakujoActivityChangeEntry>> loadChanges() {
    return _enqueue(() async => (await _readChanges()).value);
  }

  Future<List<GakujoActivityChangeEntry>> loadChangesForBackup() {
    return _enqueue(
      () => _readForBackup(_changesKey, _readChanges),
    );
  }

  Future<_StorageReadResult<List<GakujoActivityChangeEntry>>> _readChanges() {
    return _readList(
      key: _changesKey,
      fromJson: GakujoActivityChangeEntry.fromJson,
      retain: (change) => _isUsefulChange(change) && _isRecentChange(change),
      compare: (a, b) => b.changedAt.compareTo(a.changedAt),
      limit: _maxChanges,
    );
  }

  Future<List<GakujoCachedReportList>> loadReportLists() {
    return _enqueue(() async => (await _readReportLists()).value);
  }

  Future<List<GakujoCachedReportList>> loadReportListsForBackup() {
    return _enqueue(
      () => _readForBackup(_reportListsKey, _readReportLists),
    );
  }

  Future<_StorageReadResult<List<GakujoCachedReportList>>> _readReportLists() {
    return _readList(
      key: _reportListsKey,
      fromJson: GakujoCachedReportList.fromJson,
      retain: (reportList) =>
          _isUsefulReportList(reportList) && _isRecentReportList(reportList),
      compare: (a, b) => b.capturedAt.compareTo(a.capturedAt),
      limit: _maxReportLists,
    );
  }

  Future<void> compact() {
    return _enqueue(_compact);
  }

  Future<void> _compact() async {
    await _compactList(_snapshotsKey, _readSnapshots);
    await _compactList(_deadlinesKey, _readDeadlines);
    await _compactNotifiedDeadlineKeys();
    await _compactList(_favoritesKey, _readFavorites);
    await _compactList(_starredMessagesKey, _readStarredMessages);
    await _compactList(_changesKey, _readChanges);
    await _compactList(_reportListsKey, _readReportLists);
    await _compactList(_assignmentsKey, _readAssignments);
  }

  Future<void> _compactNotifiedDeadlineKeys() async {
    final notifiedRead = await _readNotifiedDeadlineKeys();
    if (!notifiedRead.isSuccessful) {
      return;
    }
    await _writeNotifiedDeadlineKeys(notifiedRead.value.toList());
  }

  Future<GakujoActivitySnapshot> recordSnapshot({
    required String category,
    required String title,
    required String url,
    required String content,
  }) {
    return _enqueue(
      () => _recordSnapshot(
        category: category,
        title: title,
        url: url,
        content: content,
      ),
    );
  }

  Future<GakujoActivitySnapshot> _recordSnapshot({
    required String category,
    required String title,
    required String url,
    required String content,
  }) async {
    final preview = _contentPreview(content);
    if (url.trim().isEmpty || content.trim().isEmpty) {
      return GakujoActivitySnapshot(
        category: category,
        title: title,
        url: url,
        contentHash: '',
        updatedAt: DateTime.now(),
        hasUpdate: false,
        contentPreview: preview,
      );
    }
    final hash = sha1.convert(utf8.encode(content)).toString();
    final now = DateTime.now();
    final snapshotRead = await _readSnapshots();
    if (!snapshotRead.isSuccessful) {
      return GakujoActivitySnapshot(
        category: category,
        title: title,
        url: url,
        contentHash: hash,
        updatedAt: now,
        hasUpdate: false,
        contentPreview: preview,
      );
    }
    final snapshots = [...snapshotRead.value];
    final existingIndex = snapshots.indexWhere(
      (snapshot) => snapshot.category == category && snapshot.url == url,
    );
    final existing = existingIndex >= 0 ? snapshots[existingIndex] : null;
    final existingHadUpdate =
        existingIndex >= 0 && snapshots[existingIndex].hasUpdate;
    final hasUpdate = existing != null && existing.contentHash != hash;
    if (existing != null && existing.contentHash != hash) {
      await _addChange(
        GakujoActivityChangeEntry(
          category: category,
          title: title,
          url: durableGakujoLink(gakujoMessageLinkFor(url), category),
          changedAt: now,
          previousHash: existing.contentHash,
          nextHash: hash,
          previousPreview: existing.contentPreview,
          nextPreview: preview,
        ),
      );
    }
    final snapshot = GakujoActivitySnapshot(
      category: category,
      title: title,
      url: url,
      contentHash: hash,
      updatedAt: now,
      hasUpdate: hasUpdate || existingHadUpdate,
      contentPreview: preview,
    );
    if (existingIndex >= 0) {
      snapshots[existingIndex] = snapshot;
    } else {
      snapshots.add(snapshot);
    }
    snapshots.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _writeList(_snapshotsKey, snapshots.take(_maxSnapshots));
    return snapshot;
  }

  Future<void> markSnapshotsSeen() {
    return _enqueue(_markSnapshotsSeen);
  }

  Future<void> _markSnapshotsSeen() async {
    final snapshotRead = await _readSnapshots();
    if (!snapshotRead.isSuccessful) {
      return;
    }
    final snapshots = snapshotRead.value.where(_isUsefulSnapshot);
    await _writeList(
      _snapshotsKey,
      snapshots
          .map(
            (snapshot) => GakujoActivitySnapshot(
              category: snapshot.category,
              title: snapshot.title,
              url: snapshot.url,
              contentHash: snapshot.contentHash,
              updatedAt: snapshot.updatedAt,
              hasUpdate: false,
              contentPreview: snapshot.contentPreview,
            ),
          )
          .toList(),
    );
  }

  Future<void> clearSnapshots() {
    return _enqueue(
      () => _secureStorage.delete(key: _snapshotsKey),
    );
  }

  Future<List<GakujoDeadlineEntry>> mergeDeadlines(
    List<GakujoDeadlineEntry> nextEntries, {
    List<String>? unreadMessageUrls,
  }) {
    return _enqueue(() => _mergeDeadlines(nextEntries, unreadMessageUrls));
  }

  static String? _messageSeqNo(String url) {
    final seqNo = Uri.tryParse(url)?.queryParameters['seqNo']?.trim();
    return seqNo == null || seqNo.isEmpty ? null : seqNo;
  }

  Future<List<GakujoDeadlineEntry>> _mergeDeadlines(
    List<GakujoDeadlineEntry> nextEntries,
    List<String>? unreadMessageUrls,
  ) async {
    final deadlineRead = await _readDeadlines();
    if (!deadlineRead.isSuccessful) {
      return const [];
    }
    // Null means the unread fetch was skipped or failed. A fetch at the
    // 60-row cap cannot prove that an absent cached message has been read,
    // and an empty one may be an error page parsed as an empty list.
    final unread = unreadMessageUrls != null &&
            unreadMessageUrls.isNotEmpty &&
            unreadMessageUrls.length < 60
        ? {
            for (final url in unreadMessageUrls)
              ?_messageSeqNo(url),
          }
        : null;
    final entries = <String, GakujoDeadlineEntry>{
      for (final entry in deadlineRead.value)
        if (_isUsefulDeadline(entry)) entry.key: entry,
    };
    if (unread != null && unread.isNotEmpty) {
      // A message read on the web keeps its dates but is not announced later.
      // Only entries that name their message can be proven read.
      final notifiedRead = await _readNotifiedDeadlineKeys();
      if (notifiedRead.isSuccessful) {
        final alreadyNotified = notifiedRead.value.toSet();
        await _addNotifiedDeadlineKeys({
          for (final entry in entries.values)
            if (entry.source == '連絡通知' && !alreadyNotified.contains(entry.key))
              if (_messageSeqNo(entry.url) case final seqNo?)
                if (!unread.contains(seqNo)) entry.key,
        });
      }
    }
    final newEntries = <GakujoDeadlineEntry>[];
    for (final entry
        in nextEntries.where(_isUsefulDeadline).where(_isActiveDeadline)) {
      if (!entries.containsKey(entry.key)) {
        newEntries.add(entry);
      }
      entries[entry.key] = entry;
    }
    final sorted = entries.values.toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    await _writeList(_deadlinesKey, _capDeadlines(sorted));
    return newEntries;
  }

  /// Uses the same retention rules as the replacement writers, before import.
  bool retainsBackupEntry(Object entry) => switch (entry) {
        final GakujoDeadlineEntry value =>
          _isUsefulDeadline(value) && _isActiveDeadline(value),
        final GakujoFavoritePage value => _isUsefulFavorite(value),
        final GakujoStarredMessage value => value.isValid,
        final GakujoActivityChangeEntry value =>
          _isUsefulChange(value) && _isRecentChange(value),
        final GakujoCachedReportList value =>
          _isUsefulReportList(value) && _isRecentReportList(value),
        _ => false,
      };

  Future<void> replaceDeadlines(List<GakujoDeadlineEntry> entries) {
    return _enqueue(() => _replaceDeadlines(entries));
  }

  Future<void> _replaceDeadlines(List<GakujoDeadlineEntry> entries) {
    final compacted = entries
        .where(_isUsefulDeadline)
        .where(_isActiveDeadline)
        .toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return _writeList(
      _deadlinesKey,
      _capDeadlines(compacted),
    );
  }

  Future<void> clearDeadlines() {
    return _enqueue(
      () => _secureStorage.delete(key: _deadlinesKey),
    );
  }

  /// Assignments from the レポート・小テスト list, newest closing time first.
  Future<List<GakujoAssignment>> loadAssignments() {
    return _enqueue(() async => (await _readAssignments()).value);
  }

  /// Null means the store could not be read, rather than a confirmed empty list.
  Future<List<GakujoAssignment>?> loadAssignmentsIfAvailable() {
    return _enqueue(() async {
      final result = await _readAssignments();
      return result.isSuccessful ? result.value : null;
    });
  }

  Future<bool> assignmentsAreWholeList() {
    return _enqueue(() async =>
        (await _readRawValue(_wholeAssignmentListKey)).value == 'true');
  }

  Future<_StorageReadResult<List<GakujoAssignment>>> _readAssignments() {
    return _readList(
      key: _assignmentsKey,
      fromJson: (json) => GakujoAssignment.fromJson(json) ?? _droppedAssignment,
      retain: (assignment) =>
          !identical(assignment, _droppedAssignment) &&
          assignment.dueAt.isAfter(
            DateTime.now().subtract(_assignmentRetention),
          ),
      compare: (a, b) => b.dueAt.compareTo(a.dueAt),
      limit: _maxAssignments,
    );
  }

  /// Replaces stored assignments with the ones just read from the list. The
  /// list may be paged, so assignments not on this page are kept, unless
  /// [isWholeList]: then one still open but no longer listed was withdrawn
  /// and is dropped, so it is not reminded of.
  Future<void> mergeAssignments(
    Iterable<GakujoAssignment> assignments, {
    bool isWholeList = false,
  }) {
    final next = assignments.toList();
    // An empty whole list still drops the assignments no longer open.
    if (next.isEmpty && !isWholeList) {
      return Future<void>.value();
    }
    return _enqueue(() async {
      final read = await _readAssignments();
      if (!read.isSuccessful) {
        return;
      }
      final listed = {for (final assignment in next) assignment.id};
      final now = DateTime.now();
      final byId = <String, GakujoAssignment>{
        for (final assignment in read.value)
          if (!isWholeList ||
              listed.contains(assignment.id) ||
              !assignment.dueAt.isAfter(now))
            assignment.id: assignment,
        for (final assignment in next) assignment.id: assignment,
      };
      final sorted = byId.values.toList()
        ..sort((a, b) => b.dueAt.compareTo(a.dueAt));
      if (isWholeList) {
        final deadlines = await _readDeadlines();
        if (!deadlines.isSuccessful) {
          return;
        }
        GakujoAssignment? match(
          GakujoDeadlineEntry entry,
          Iterable<GakujoAssignment> assignments,
        ) =>
            findAssignment(
              assignments,
              title: entry.assignment,
              course: entry.course,
              courseCode: entry.courseCode,
              kind: entry.assignmentKind,
            );
        // Only a whole list proves a removal. Unrelated schedule entries
        // and messages must survive, even if they name no assignment.
        bool keepDeadline(GakujoDeadlineEntry entry) {
          final tiedToList = entry.source == 'レポート・小テスト' ||
              (entry.source == 'スケジュール' && match(entry, read.value) != null);
          return !tiedToList || match(entry, sorted) != null;
        }

        await _writeList(_deadlinesKey, deadlines.value.where(keepDeadline));
      }
      await _writeList(_assignmentsKey, sorted.take(_maxAssignments));
      await _secureStorage.write(
        key: _wholeAssignmentListKey,
        value: isWholeList.toString(),
      );
    });
  }

  Future<void> addFavorite(GakujoFavoritePage page) {
    return _enqueue(() => _addFavorite(page));
  }

  Future<void> _addFavorite(GakujoFavoritePage page) async {
    if (!_isUsefulFavorite(page)) {
      return;
    }
    final favoriteRead = await _readFavorites();
    if (!favoriteRead.isSuccessful) {
      throw StateError('Failed to read favorites');
    }
    final favorites = favoriteRead.value;
    final filtered = favorites
        .where((favorite) => favorite.durableUrl != page.durableUrl)
        .toList();
    await _writeList(_favoritesKey, [page, ...filtered].take(_maxFavorites));
  }

  Future<void> replaceFavorites(List<GakujoFavoritePage> favorites) {
    return _enqueue(() => _replaceFavorites(favorites));
  }

  Future<void> _replaceFavorites(List<GakujoFavoritePage> favorites) {
    final compacted = favorites.where(_isUsefulFavorite).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return _writeList(
      _favoritesKey,
      compacted.take(_maxFavorites),
    );
  }

  Future<void> removeFavorite(String url) {
    return _enqueue(() => _removeFavorite(url));
  }

  Future<void> _removeFavorite(String url) async {
    final favoriteRead = await _readFavorites();
    if (!favoriteRead.isSuccessful) {
      return;
    }
    final favorites = favoriteRead.value;
    await _writeList(
      _favoritesKey,
      favorites.where((favorite) => favorite.url != url).toList(),
    );
  }

  Future<void> saveReportList(GakujoCachedReportList reportList) {
    return _enqueue(() => _saveReportList(reportList));
  }

  Future<void> _saveReportList(GakujoCachedReportList reportList) async {
    if (!_isUsefulReportList(reportList) || !_isRecentReportList(reportList)) {
      return;
    }
    final reportListRead = await _readReportLists();
    if (!reportListRead.isSuccessful) {
      return;
    }
    final reportLists = reportListRead.value;
    final filtered =
        reportLists.where((entry) => entry.url != reportList.url).toList();
    await _writeList(
      _reportListsKey,
      [reportList, ...filtered].take(_maxReportLists),
    );
  }

  Future<void> replaceReportLists(List<GakujoCachedReportList> reportLists) {
    return _enqueue(() => _replaceReportLists(reportLists));
  }

  Future<void> _replaceReportLists(
    List<GakujoCachedReportList> reportLists,
  ) {
    final compacted = reportLists
        .where(_isUsefulReportList)
        .where(_isRecentReportList)
        .toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return _writeList(
      _reportListsKey,
      compacted.take(_maxReportLists),
    );
  }

  Future<void> replaceChanges(List<GakujoActivityChangeEntry> changes) {
    return _enqueue(() => _replaceChanges(changes));
  }

  Future<void> _replaceChanges(List<GakujoActivityChangeEntry> changes) {
    final compacted = changes
        .where(_isUsefulChange)
        .where(_isRecentChange)
        .toList()
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return _writeList(
      _changesKey,
      compacted.take(_maxChanges),
    );
  }

  Future<void> clearReportLists() {
    return _enqueue(() async {
      await _secureStorage.delete(key: _reportListsKey);
      // Assignments are read from the same list.
      await _secureStorage.delete(key: _assignmentsKey);
      await _secureStorage.delete(key: _wholeAssignmentListKey);
    });
  }

  Future<void> clearChanges() {
    return _enqueue(
      () => _secureStorage.delete(key: _changesKey),
    );
  }

  Future<void> _addChange(GakujoActivityChangeEntry entry) async {
    if (!_isUsefulChange(entry)) {
      return;
    }
    final changeRead = await _readChanges();
    if (!changeRead.isSuccessful) {
      return;
    }
    final changes = [entry, ...changeRead.value];
    await _writeList(
      _changesKey,
      changes.where(_isRecentChange).take(_maxChanges),
    );
  }

  bool _isUsefulSnapshot(GakujoActivitySnapshot snapshot) {
    return snapshot.url.trim().isNotEmpty &&
        snapshot.title.trim().isNotEmpty &&
        snapshot.contentHash.trim().isNotEmpty &&
        !_isGenericNoiseSnapshot(snapshot) &&
        snapshot.contentPreview.trim().toLowerCase() != 'now loading...';
  }

  bool _isGenericNoiseSnapshot(GakujoActivitySnapshot snapshot) {
    final title = snapshot.title.trim();
    final category = snapshot.category.trim();
    final preview = snapshot.contentPreview.trim();
    final url = snapshot.url.toLowerCase();
    final isGenericTitle = title == 'Gakujo' ||
        title == 'CampusSquare for WEB [CampusSquare]' ||
        title.startsWith('CampusSquare for WEB');
    if (!isGenericTitle) {
      return false;
    }

    final isGenericCategory = category == 'Gakujo' || category == 'スケジュール';
    final looksLikePortalChrome = preview.contains('前回ログイン日時') ||
        preview.contains('レポート・小テスト') ||
        preview.contains('出欠管理') ||
        preview.contains('新着情報') ||
        preview.contains('MYスケジュール');
    final isMainPortalUrl = url.contains('campusportal.do') &&
        !url.contains('tabid=') &&
        !url.contains('report') &&
        !url.contains('keiji') &&
        !url.contains('schedule');
    return isGenericCategory && (looksLikePortalChrome || isMainPortalUrl);
  }

  bool _isUsefulDeadline(GakujoDeadlineEntry entry) {
    const supportedKinds = {'deadline', 'notice', 'schedule'};
    final title = entry.title.trim();
    return entry.source != '成績' &&
        title != '☆' &&
        title != '★' &&
        entry.url.trim().isNotEmpty &&
        entry.dueText.trim().isNotEmpty &&
        supportedKinds.contains(entry.kind) &&
        !GakujoDatedActivity.isScheduleCalendarRow(entry.dueText);
  }

  bool _isUsefulFavorite(GakujoFavoritePage page) {
    return page.url.trim().isNotEmpty && page.title.trim().isNotEmpty;
  }

  bool _isUsefulReportList(GakujoCachedReportList reportList) {
    return reportList.url.trim().isNotEmpty &&
        reportList.title.trim().isNotEmpty &&
        reportList.items.any((item) => item.trim().isNotEmpty);
  }

  bool _isUsefulChange(GakujoActivityChangeEntry change) {
    return change.url.trim().isNotEmpty &&
        change.title.trim().isNotEmpty &&
        change.previousHash.trim().isNotEmpty &&
        change.nextHash.trim().isNotEmpty;
  }

  bool _isRecentSnapshot(GakujoActivitySnapshot snapshot) {
    return snapshot.updatedAt
        .isAfter(DateTime.now().subtract(_snapshotRetention));
  }

  /// Whether the date in [entry] has already passed. Deadlines are kept for
  /// a while afterwards, but telling about one then is no help.
  bool isDeadlinePassed(GakujoDeadlineEntry entry, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final dueAt = _deadlineDueAt(entry.dueText, detectedAt: entry.detectedAt);
    return dueAt != null && !dueAt.isAfter(current);
  }

  bool _isActiveDeadline(GakujoDeadlineEntry entry) {
    final now = DateTime.now();
    final dueAt = _deadlineDueAt(entry.dueText, detectedAt: entry.detectedAt);
    if (dueAt == null) {
      return entry.detectedAt.isAfter(now.subtract(_undatedDeadlineRetention));
    }
    return dueAt.add(_deadlineGracePeriod).isAfter(now);
  }

  bool _isRecentReportList(GakujoCachedReportList reportList) {
    return reportList.capturedAt
        .isAfter(DateTime.now().subtract(_reportListRetention));
  }

  bool _isRecentChange(GakujoActivityChangeEntry change) {
    return change.changedAt.isAfter(DateTime.now().subtract(_changeRetention));
  }

  DateTime? _deadlineDueAt(String text, {required DateTime detectedAt}) {
    DateTime? deadlineDateTime(
      int year,
      int month,
      int day,
      int hour,
      int minute,
    ) {
      if (hour == 24) {
        if (minute != 0) {
          return null;
        }
        return _strictDateTime(year, month, day, 0, 0)
            ?.add(const Duration(days: 1));
      }
      return _strictDateTime(year, month, day, hour, minute);
    }

    final normalized = GakujoDatedActivity.normalizeDateText(text)
        .replaceAllMapped(RegExp(r'令和([0-9]{1,2})年'), (match) {
          final reiwaYear = int.tryParse(match.group(1) ?? '');
          if (reiwaYear == null) {
            return match.group(0) ?? '';
          }
          return '${2018 + reiwaYear}年';
        })
        .replaceAll(RegExp(r'[（(][月火水木金土日][）)]'), ' ')
        .replaceAll('～', ' ')
        .replaceAll('〜', ' ')
        .replaceAll('年', '/')
        .replaceAll('月', '/')
        .replaceAll('日', ' ')
        .replaceAll('時', ':')
        .replaceAll('分', '')
        .replaceAll('-', '/');
    final fullDate = RegExp(
      r'((?:20)?[0-9]{2})[/.]([0-9]{1,2})[/.]([0-9]{1,2})(?![0-9]|\.[0-9])(?:\s*([0-9]{1,2}):([0-9]{2}))?',
    );
    final monthAndDayPattern = RegExp(
      r'(^|[^0-9.])([0-9]{1,2})[/.]([0-9]{1,2})(?![0-9]|\.[0-9])(?:\s*([0-9]{1,2}):([0-9]{2}))?',
    );
    final fullDateMatches = fullDate.allMatches(normalized).toList();
    if (fullDateMatches.isNotEmpty) {
      final fullDate = fullDateMatches.last;
      final rawYear = int.tryParse(fullDate.group(1) ?? '');
      final month = int.tryParse(fullDate.group(2) ?? '');
      final day = int.tryParse(fullDate.group(3) ?? '');
      if (rawYear != null && month != null && day != null) {
        final year = rawYear < 100 ? rawYear + 2000 : rawYear;
        final hour = int.tryParse(fullDate.group(4) ?? '') ?? 23;
        final minute = int.tryParse(fullDate.group(5) ?? '') ?? 59;
        final fullDateDueAt = deadlineDateTime(
          year,
          month,
          day,
          hour,
          minute,
        );
        if (fullDateDueAt != null) {
          final trailingMonthAndDayMatches =
              monthAndDayPattern.allMatches(normalized, fullDate.end).toList();
          if (trailingMonthAndDayMatches.isNotEmpty) {
            final trailingMonthAndDay = trailingMonthAndDayMatches.last;
            final trailingMonth = int.tryParse(
              trailingMonthAndDay.group(2) ?? '',
            );
            final trailingDay = int.tryParse(
              trailingMonthAndDay.group(3) ?? '',
            );
            if (trailingMonth != null && trailingDay != null) {
              final trailingHour =
                  int.tryParse(trailingMonthAndDay.group(4) ?? '') ?? 23;
              final trailingMinute =
                  int.tryParse(trailingMonthAndDay.group(5) ?? '') ?? 59;
              final sameYearDueAt = deadlineDateTime(
                year,
                trailingMonth,
                trailingDay,
                trailingHour,
                trailingMinute,
              );
              if (sameYearDueAt != null) {
                if (sameYearDueAt.isBefore(fullDateDueAt)) {
                  return deadlineDateTime(
                        year + 1,
                        trailingMonth,
                        trailingDay,
                        trailingHour,
                        trailingMinute,
                      ) ??
                      fullDateDueAt;
                }
                return sameYearDueAt;
              }
            }
          }
          return fullDateDueAt;
        }
      }
    }

    final monthAndDayMatches =
        monthAndDayPattern.allMatches(normalized).toList();
    if (monthAndDayMatches.isEmpty) {
      return null;
    }
    final monthAndDay = monthAndDayMatches.last;
    final month = int.tryParse(monthAndDay.group(2) ?? '');
    final day = int.tryParse(monthAndDay.group(3) ?? '');
    if (month == null || day == null) {
      return null;
    }
    final hour = int.tryParse(monthAndDay.group(4) ?? '') ?? 23;
    final minute = int.tryParse(monthAndDay.group(5) ?? '') ?? 59;
    final detectedYear = japanWallClock(detectedAt).year;
    DateTime? dueAt;
    for (final year in [detectedYear - 1, detectedYear, detectedYear + 1]) {
      final candidate = deadlineDateTime(year, month, day, hour, minute);
      if (candidate != null &&
          (dueAt == null ||
              candidate.difference(detectedAt).abs() <
                  dueAt.difference(detectedAt).abs())) {
        dueAt = candidate;
      }
    }
    return dueAt;
  }

  DateTime? _strictDateTime(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    final parsed = DateTime.utc(year, month, day, hour, minute);
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day ||
        parsed.hour != hour ||
        parsed.minute != minute) {
      return null;
    }
    // Gakujo's date text is always Japan time, regardless of the device zone.
    return parsed.subtract(const Duration(hours: 9));
  }

  String _contentPreview(String content) {
    final lines = content
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty && !_isBoilerplateLine(line))
        .take(8)
        .toList();
    final preview = lines.join('\n');
    if (preview.length <= 420) {
      return preview;
    }
    return '${preview.substring(0, 420)}...';
  }

  bool _isBoilerplateLine(String line) {
    const exact = {
      '[image]',
      'スマホ版',
      'English',
      'カスタマイズ',
      'ログアウト',
      'HOME',
      '連絡通知',
      'スケジュール',
      '休講補講',
      'シラバス',
      '履修',
      '成績',
      'ダウンロード',
      'リンク',
      '各種情報',
      'NBAS',
    };
    if (exact.contains(line)) {
      return true;
    }
    return line.startsWith('Copyright') ||
        line.startsWith('残り約') ||
        RegExp(r'^[0-9]{4}年[0-9]{1,2}月$').hasMatch(line) ||
        RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)(\s|$)').hasMatch(line);
  }

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<dynamic, dynamic>) fromJson,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const [];
      }
      final entries = <T>[];
      for (final item in decoded.whereType<Map<dynamic, dynamic>>()) {
        try {
          entries.add(fromJson(item));
        } on Object {
          // Ignore malformed legacy entries so one bad item does not hide all data.
        }
      }
      return entries;
    } on Object {
      return const [];
    }
  }

  Future<_StorageReadResult<List<T>>> _readList<T extends Object>({
    required String key,
    required T Function(Map<dynamic, dynamic>) fromJson,
    required bool Function(T) retain,
    required int Function(T, T) compare,
    required int limit,
  }) async {
    final rawRead = await _readRawValue(key);
    if (!rawRead.isSuccessful) {
      return _StorageReadResult.failure(<T>[]);
    }
    final values = _decodeList(rawRead.value, fromJson).where(retain).toList()
      ..sort(compare);
    return _StorageReadResult.success(values.take(limit).toList());
  }

  Future<T> _readForBackup<T>(
    String key,
    Future<_StorageReadResult<T>> Function() read,
  ) async {
    final result = await read();
    if (!result.isSuccessful) {
      throw StateError('Failed to read $key for backup');
    }
    return result.value;
  }

  Future<void> _compactList<T extends Object>(
    String key,
    Future<_StorageReadResult<List<T>>> Function() read,
  ) async {
    final result = await read();
    if (!result.isSuccessful) {
      return;
    }
    await _writeList(key, result.value);
  }

  Future<void> _writeList(String key, Iterable<Object> values) {
    return _secureStorage.write(
      key: key,
      value: jsonEncode(
        values.map((value) => (value as dynamic).toJson()).toList(),
      ),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    return _operations.run(operation);
  }
}

final _droppedAssignment = GakujoAssignment(
  kind: '',
  title: '',
  status: '',
  course: '',
  dueAt: DateTime.fromMillisecondsSinceEpoch(0),
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);
