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

class GakujoActivityStore {
  GakujoActivityStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageFactory.create();

  static const _snapshotsKey = 'more_better_gakujo_activity_snapshots';
  static const _deadlinesKey = 'more_better_gakujo_deadlines';
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

  Future<String?> _readRawValue(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } on Object {
      // Cached activity data is best-effort. If secure storage is briefly
      // unavailable (e.g. a cold keychain read times out), degrade to no
      // cached data rather than throwing out of a background scan.
      return null;
    }
  }

  Future<List<GakujoActivitySnapshot>> loadSnapshots() async {
    final raw = await _readRawValue(_snapshotsKey);
    final snapshots = _decodeList(raw, GakujoActivitySnapshot.fromJson)
        .where(_isUsefulSnapshot)
        .where(_isRecentSnapshot)
        .toList();
    snapshots.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return snapshots.take(_maxSnapshots).toList();
  }

  Future<List<GakujoDeadlineEntry>> loadDeadlines() async {
    final raw = await _readRawValue(_deadlinesKey);
    final deadlines = _decodeList(raw, GakujoDeadlineEntry.fromJson)
        .where(_isUsefulDeadline)
        .where(_isActiveDeadline)
        .toList();
    deadlines.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return deadlines.take(_maxDeadlines).toList();
  }

  Future<List<GakujoFavoritePage>> loadFavorites() async {
    final raw = await _readRawValue(_favoritesKey);
    final favorites = _decodeList(raw, GakujoFavoritePage.fromJson)
        .where(_isUsefulFavorite)
        .toList();
    favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return favorites.take(_maxFavorites).toList();
  }

  Future<List<GakujoActivityChangeEntry>> loadChanges() async {
    final raw = await _readRawValue(_changesKey);
    final changes = _decodeList(raw, GakujoActivityChangeEntry.fromJson)
        .where(_isUsefulChange)
        .where(_isRecentChange)
        .toList();
    changes.sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return changes.take(_maxChanges).toList();
  }

  Future<List<GakujoCachedReportList>> loadReportLists() async {
    final raw = await _readRawValue(_reportListsKey);
    final reportLists = _decodeList(raw, GakujoCachedReportList.fromJson)
        .where(_isUsefulReportList)
        .where(_isRecentReportList)
        .toList();
    reportLists.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return reportLists.take(_maxReportLists).toList();
  }

  Future<void> compact() async {
    await Future.wait([
      _writeList(_snapshotsKey, await loadSnapshots()),
      _writeList(_deadlinesKey, await loadDeadlines()),
      _writeList(_favoritesKey, await loadFavorites()),
      _writeList(_changesKey, await loadChanges()),
      _writeList(_reportListsKey, await loadReportLists()),
    ]);
  }

  Future<GakujoActivitySnapshot> recordSnapshot({
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
    final snapshots = [...await loadSnapshots()];
    final hash = sha1.convert(utf8.encode(content)).toString();
    final existingIndex = snapshots.indexWhere(
      (snapshot) => snapshot.category == category && snapshot.url == url,
    );
    final existing = existingIndex >= 0 ? snapshots[existingIndex] : null;
    final existingHadUpdate =
        existingIndex >= 0 && snapshots[existingIndex].hasUpdate;
    final hasUpdate = existing != null && existing.contentHash != hash;
    final now = DateTime.now();
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

  Future<void> markSnapshotsSeen() async {
    final snapshots = (await loadSnapshots()).where(_isUsefulSnapshot);
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
    return _secureStorage.delete(key: _snapshotsKey);
  }

  Future<List<GakujoDeadlineEntry>> mergeDeadlines(
    List<GakujoDeadlineEntry> nextEntries,
  ) async {
    final entries = <String, GakujoDeadlineEntry>{
      for (final entry in await loadDeadlines())
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
    return _secureStorage.delete(key: _deadlinesKey);
  }

  Future<void> addFavorite(GakujoFavoritePage page) async {
    if (!_isUsefulFavorite(page)) {
      return;
    }
    final favorites = await loadFavorites();
    final filtered =
        favorites.where((favorite) => favorite.url != page.url).toList();
    await _writeList(_favoritesKey, [page, ...filtered].take(_maxFavorites));
  }

  Future<void> replaceFavorites(List<GakujoFavoritePage> favorites) {
    final compacted = favorites.where(_isUsefulFavorite).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return _writeList(
      _favoritesKey,
      compacted.take(_maxFavorites),
    );
  }

  Future<void> removeFavorite(String url) async {
    final favorites = await loadFavorites();
    await _writeList(
      _favoritesKey,
      favorites.where((favorite) => favorite.url != url).toList(),
    );
  }

  Future<void> saveReportList(GakujoCachedReportList reportList) async {
    if (!_isUsefulReportList(reportList) || !_isRecentReportList(reportList)) {
      return;
    }
    final reportLists = await loadReportLists();
    final filtered =
        reportLists.where((entry) => entry.url != reportList.url).toList();
    await _writeList(
      _reportListsKey,
      [reportList, ...filtered].take(_maxReportLists),
    );
  }

  Future<void> replaceReportLists(List<GakujoCachedReportList> reportLists) {
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
    return _secureStorage.delete(key: _reportListsKey);
  }

  Future<void> clearChanges() {
    return _secureStorage.delete(key: _changesKey);
  }

  Future<void> _addChange(GakujoActivityChangeEntry entry) async {
    if (!_isUsefulChange(entry)) {
      return;
    }
    final changes = [entry, ...await loadChanges()];
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
        return DateTime(year, month, day, hour, minute);
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
    var dueAt = DateTime(now.year, month, day, hour, minute);
    if (dueAt.add(_deadlineGracePeriod).isBefore(now) &&
        now.difference(dueAt).inDays > 180) {
      dueAt = DateTime(now.year + 1, month, day, hour, minute);
    }
    return dueAt;
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

  Future<void> _writeList(String key, Iterable<Object> values) {
    return _secureStorage.write(
      key: key,
      value: jsonEncode(
        values.map((value) => (value as dynamic).toJson()).toList(),
      ),
    );
  }
}
