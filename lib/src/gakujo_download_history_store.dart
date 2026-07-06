import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'gakujo_download_request.dart';
import 'secure_storage_factory.dart';

class GakujoDownloadHistoryEntry {
  const GakujoDownloadHistoryEntry({
    required this.fileName,
    required this.courseName,
    required this.savedAt,
    this.location,
  });

  final String fileName;
  final String courseName;
  final DateTime savedAt;
  final String? location;

  String get displayCourseName =>
      courseName.trim().isEmpty ? '未分類' : courseName.trim();

  Map<String, Object?> toJson() {
    return {
      'fileName': fileName,
      'courseName': courseName,
      'savedAt': savedAt.toIso8601String(),
      'location': location,
    };
  }

  factory GakujoDownloadHistoryEntry.fromJson(Map<dynamic, dynamic> json) {
    final location = json['location']?.toString().trim();
    return GakujoDownloadHistoryEntry(
      fileName: json['fileName']?.toString() ?? '',
      courseName: json['courseName']?.toString() ?? '',
      savedAt: DateTime.tryParse(json['savedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      location: location == null || location.isEmpty ? null : location,
    );
  }
}

class GakujoFailedDownloadEntry {
  const GakujoFailedDownloadEntry({
    required this.id,
    required this.request,
    required this.failedAt,
    required this.errorMessage,
  });

  final String id;
  final GakujoDownloadRequest request;
  final DateTime failedAt;
  final String errorMessage;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'request': request.toJson(),
      'failedAt': failedAt.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }

  factory GakujoFailedDownloadEntry.fromJson(Map<dynamic, dynamic> json) {
    final rawRequest = json['request'];
    return GakujoFailedDownloadEntry(
      id: json['id']?.toString() ?? '',
      request: rawRequest is Map
          ? GakujoDownloadRequest.fromJsonMap(rawRequest)
          : const GakujoDownloadRequest(
              url: '',
              method: 'GET',
              courseName: '',
              fileName: '',
              formFields: {},
            ),
      failedAt: DateTime.tryParse(json['failedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      errorMessage: json['errorMessage']?.toString() ?? '',
    );
  }
}

class GakujoDownloadHistoryStore {
  GakujoDownloadHistoryStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageFactory.create();

  static const _historyKey = 'more_better_gakujo_download_history';
  static const _failedDownloadsKey = 'more_better_gakujo_failed_downloads';
  static const _maxEntries = 100;
  static const _maxFailedEntries = 30;
  static const _historyRetention = Duration(days: 180);
  static const _failedDownloadRetention = Duration(days: 30);

  final FlutterSecureStorage _secureStorage;

  Future<List<GakujoDownloadHistoryEntry>> load() async {
    final raw = await _secureStorage.read(key: _historyKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const [];
      }
      final entries = <GakujoDownloadHistoryEntry>[];
      for (final item in decoded.whereType<Map<dynamic, dynamic>>()) {
        try {
          final entry = GakujoDownloadHistoryEntry.fromJson(item);
          if (entry.fileName.trim().isNotEmpty && _isRecentHistory(entry)) {
            entries.add(entry);
          }
        } on Object {
          // Ignore malformed legacy entries so one bad item does not hide all data.
        }
      }
      entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return entries;
    } on Object {
      return const [];
    }
  }

  Future<List<GakujoFailedDownloadEntry>> loadFailedDownloads() async {
    final raw = await _secureStorage.read(key: _failedDownloadsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const [];
      }
      final entries = <GakujoFailedDownloadEntry>[];
      for (final item in decoded.whereType<Map<dynamic, dynamic>>()) {
        try {
          final entry = GakujoFailedDownloadEntry.fromJson(item);
          if (entry.id.trim().isNotEmpty &&
              entry.request.url.trim().isNotEmpty &&
              _isRecentFailedDownload(entry)) {
            entries.add(entry);
          }
        } on Object {
          // Ignore malformed legacy entries so one bad item does not hide all data.
        }
      }
      entries.sort((a, b) => b.failedAt.compareTo(a.failedAt));
      return entries;
    } on Object {
      return const [];
    }
  }

  Future<void> compact() async {
    await Future.wait([
      replaceHistory(await load()),
      replaceFailedDownloads(await loadFailedDownloads()),
    ]);
  }

  Future<void> add(GakujoDownloadHistoryEntry entry) async {
    final entries = [entry, ...await load()];
    final compacted = entries.take(_maxEntries).toList();
    await replaceHistory(compacted);
  }

  Future<void> replaceHistory(List<GakujoDownloadHistoryEntry> entries) {
    final compacted = entries
        .where(
          (entry) =>
              entry.fileName.trim().isNotEmpty && _isRecentHistory(entry),
        )
        .toList();
    compacted.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final limited = compacted.take(_maxEntries).toList();
    return _secureStorage.write(
      key: _historyKey,
      value: jsonEncode(
        limited.map((entry) => entry.toJson()).toList(),
      ),
    );
  }

  Future<void> clear() {
    return _secureStorage.delete(key: _historyKey);
  }

  Future<void> addFailedDownload({
    required GakujoDownloadRequest request,
    required String errorMessage,
  }) async {
    final now = DateTime.now();
    final id =
        '${now.microsecondsSinceEpoch}:${request.url}:${request.fileName}';
    final entry = GakujoFailedDownloadEntry(
      id: id,
      request: request,
      failedAt: now,
      errorMessage: errorMessage,
    );
    final requestKey = _failedRequestKey(request);
    final entries = [
      entry,
      ...(await loadFailedDownloads()).where(
        (existing) => _failedRequestKey(existing.request) != requestKey,
      ),
    ];
    await _writeFailedDownloads(entries.take(_maxFailedEntries).toList());
  }

  Future<void> replaceFailedDownloads(
    List<GakujoFailedDownloadEntry> entries,
  ) {
    return _writeFailedDownloads(entries);
  }

  Future<void> removeFailedDownload(String id) async {
    final entries = await loadFailedDownloads();
    await _writeFailedDownloads(
      entries.where((entry) => entry.id != id).toList(),
    );
  }

  Future<void> clearFailedDownloads() {
    return _secureStorage.delete(key: _failedDownloadsKey);
  }

  Future<void> _writeFailedDownloads(
    List<GakujoFailedDownloadEntry> entries,
  ) {
    final compacted = entries
        .where(
          (entry) =>
              entry.id.trim().isNotEmpty &&
              entry.request.url.trim().isNotEmpty &&
              _isRecentFailedDownload(entry),
        )
        .toList();
    compacted.sort((a, b) => b.failedAt.compareTo(a.failedAt));
    final limited = compacted.take(_maxFailedEntries).toList();
    return _secureStorage.write(
      key: _failedDownloadsKey,
      value: jsonEncode(limited.map((entry) => entry.toJson()).toList()),
    );
  }

  bool _isRecentHistory(GakujoDownloadHistoryEntry entry) {
    return entry.savedAt.isAfter(DateTime.now().subtract(_historyRetention));
  }

  bool _isRecentFailedDownload(GakujoFailedDownloadEntry entry) {
    return entry.failedAt
        .isAfter(DateTime.now().subtract(_failedDownloadRetention));
  }

  String _failedRequestKey(GakujoDownloadRequest request) {
    final fields = request.formFields.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final encodedFields = fields
        .map((entry) => '${entry.key}\u{1f}=${entry.value}')
        .join('\u{1e}');
    return [
      request.method.toUpperCase(),
      request.url,
      request.fileName,
      request.courseName,
      encodedFields,
    ].join('\u{1d}');
  }
}
