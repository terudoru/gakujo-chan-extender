import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'gakujo_dated_activity.dart';
import 'secure_storage_factory.dart';

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
  });

  final String title;
  final String url;
  final String dueText;
  final DateTime detectedAt;
  final String kind;

  bool get isDeadline => kind == 'deadline';

  String get key => '$kind|$url|$title|$dueText';

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'url': url,
      'dueText': dueText,
      'detectedAt': detectedAt.toIso8601String(),
      'kind': kind,
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
    );
  }
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

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'url': url,
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
  static const _changesKey = 'more_better_gakujo_activity_changes';
  static const _reportListsKey = 'more_better_gakujo_cached_report_lists';
  static const _maxSnapshots = 120;
  static const _maxDeadlines = 80;
  static const _maxFavorites = 30;
  static const _maxChanges = 120;
  static const _maxReportLists = 20;
  static const _snapshotRetention = Duration(days: 180);
  static const _deadlineGracePeriod = Duration(days: 7);
  static const _undatedDeadlineRetention = Duration(days: 90);
  static const _changeRetention = Duration(days: 90);
  static const _reportListRetention = Duration(days: 60);

  final FlutterSecureStorage _secureStorage;
  Future<void> _pendingOperation = Future<void>.value();

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

  Future<List<GakujoActivitySnapshot>> loadSnapshots() async {
    await _pendingOperation;
    return (await _readSnapshots()).value;
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

  Future<List<GakujoDeadlineEntry>> loadDeadlines() async {
    await _pendingOperation;
    return (await _readDeadlines()).value;
  }

  Future<_StorageReadResult<List<GakujoDeadlineEntry>>> _readDeadlines() {
    return _readList(
      key: _deadlinesKey,
      fromJson: GakujoDeadlineEntry.fromJson,
      retain: (entry) => _isUsefulDeadline(entry) && _isActiveDeadline(entry),
      compare: (a, b) => b.detectedAt.compareTo(a.detectedAt),
      limit: _maxDeadlines,
    );
  }

  Future<Set<String>> loadNotifiedDeadlineKeys() async {
    await _pendingOperation;
    return (await _readNotifiedDeadlineKeys()).value;
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

  Future<void> _addNotifiedDeadlineKeys(Set<String> deadlineKeys) async {
    if (deadlineKeys.isEmpty) {
      return;
    }
    final notifiedRead = await _readNotifiedDeadlineKeys();
    if (!notifiedRead.isSuccessful) {
      return;
    }
    await _writeStringSet(
      _notifiedDeadlineKeysKey,
      {...notifiedRead.value, ...deadlineKeys},
    );
  }

  Future<List<GakujoFavoritePage>> loadFavorites() async {
    await _pendingOperation;
    return (await _readFavorites()).value;
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

  Future<List<GakujoActivityChangeEntry>> loadChanges() async {
    await _pendingOperation;
    return (await _readChanges()).value;
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

  Future<List<GakujoCachedReportList>> loadReportLists() async {
    await _pendingOperation;
    return (await _readReportLists()).value;
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
    await _compactList(_changesKey, _readChanges);
    await _compactList(_reportListsKey, _readReportLists);
  }

  Future<void> _compactNotifiedDeadlineKeys() async {
    final deadlineRead = await _readDeadlines();
    final notifiedRead = await _readNotifiedDeadlineKeys();
    if (!deadlineRead.isSuccessful || !notifiedRead.isSuccessful) {
      return;
    }
    final activeDeadlineKeys = deadlineRead.value
        .where((entry) => entry.isDeadline)
        .map((entry) => entry.key)
        .toSet();
    await _writeStringSet(
      _notifiedDeadlineKeysKey,
      notifiedRead.value.intersection(activeDeadlineKeys),
    );
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
          url: url,
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
    List<GakujoDeadlineEntry> nextEntries,
  ) {
    return _enqueue(() => _mergeDeadlines(nextEntries));
  }

  Future<List<GakujoDeadlineEntry>> _mergeDeadlines(
    List<GakujoDeadlineEntry> nextEntries,
  ) async {
    final deadlineRead = await _readDeadlines();
    if (!deadlineRead.isSuccessful) {
      return const [];
    }
    final entries = <String, GakujoDeadlineEntry>{
      for (final entry in deadlineRead.value)
        if (_isUsefulDeadline(entry)) entry.key: entry,
    };
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
    await _writeList(_deadlinesKey, sorted.take(_maxDeadlines).toList());
    return newEntries;
  }

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
      compacted.take(_maxDeadlines),
    );
  }

  Future<void> clearDeadlines() {
    return _enqueue(
      () => _secureStorage.delete(key: _deadlinesKey),
    );
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
      return;
    }
    final favorites = favoriteRead.value;
    final filtered =
        favorites.where((favorite) => favorite.url != page.url).toList();
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
    return _enqueue(
      () => _secureStorage.delete(key: _reportListsKey),
    );
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
    return entry.url.trim().isNotEmpty &&
        entry.dueText.trim().isNotEmpty &&
        supportedKinds.contains(entry.kind);
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

  bool _isActiveDeadline(GakujoDeadlineEntry entry) {
    final now = DateTime.now();
    final dueAt = _deadlineDueAt(entry.dueText, now: now);
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

  DateTime? _deadlineDueAt(String text, {required DateTime now}) {
    final normalized = GakujoDatedActivity.normalizeDateText(text)
        .replaceAllMapped(RegExp(r'令和([0-9]{1,2})年'), (match) {
          final reiwaYear = int.tryParse(match.group(1) ?? '');
          if (reiwaYear == null) {
            return match.group(0) ?? '';
          }
          return '${2018 + reiwaYear}年';
        })
        .replaceAll(RegExp(r'[（(][月火水木金土日][）)]'), '')
        .replaceAll('～', '/')
        .replaceAll('〜', '/')
        .replaceAll('年', '/')
        .replaceAll('月', '/')
        .replaceAll('日', '')
        .replaceAll('時', ':')
        .replaceAll('分', '')
        .replaceAll('-', '/');
    final fullDate = RegExp(
      r'((?:20)?[0-9]{2})/([0-9]{1,2})/([0-9]{1,2})(?:\s*([0-9]{1,2}):([0-9]{2}))?',
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
        return _strictDateTime(year, month, day, hour, minute);
      }
    }

    final monthAndDayPattern = RegExp(
      r'(^|[^0-9])([0-9]{1,2})/([0-9]{1,2})(?:\s*([0-9]{1,2}):([0-9]{2}))?',
    );
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
    var dueAt = _strictDateTime(now.year, month, day, hour, minute);
    if (dueAt == null) {
      return null;
    }
    if (dueAt.add(_deadlineGracePeriod).isBefore(now) &&
        now.difference(dueAt).inDays > 180) {
      dueAt = _strictDateTime(now.year + 1, month, day, hour, minute);
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
    final parsed = DateTime(year, month, day, hour, minute);
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day ||
        parsed.hour != hour ||
        parsed.minute != minute) {
      return null;
    }
    return parsed;
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

  Future<void> _writeStringSet(String key, Set<String> values) {
    final sorted = values.toList()..sort();
    return _secureStorage.write(
      key: key,
      value: jsonEncode(sorted),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _pendingOperation.then((_) => operation());
    _pendingOperation = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }
}
