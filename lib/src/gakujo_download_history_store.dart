import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'download_file_name_policy.dart';
import 'gakujo_download_request.dart';
import 'secure_storage_factory.dart';
import 'secure_storage_transaction.dart';
import 'stored_json.dart';

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
    final savedAt = DateTime.tryParse(json['savedAt']?.toString() ?? '');
    if (savedAt == null) {
      throw const FormatException('ダウンロード履歴の保存日時（savedAt）を読み取れませんでした');
    }
    return GakujoDownloadHistoryEntry(
      fileName: json['fileName']?.toString() ?? '',
      courseName: json['courseName']?.toString() ?? '',
      savedAt: savedAt,
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
    this.canRetry = true,
  });

  final String id;
  final GakujoDownloadRequest request;
  final DateTime failedAt;
  final String errorMessage;
  final bool canRetry;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'request': request.toJson(),
      'failedAt': failedAt.toIso8601String(),
      'errorMessage': errorMessage,
      'canRetry': canRetry,
    };
  }

  /// Serializes for external output without the request's POST form fields.
  Map<String, Object?> toExternalJson() {
    return {
      'id': sha256.convert(utf8.encode(id)).toString(),
      'request': request.toExternalJson(),
      'failedAt': failedAt.toIso8601String(),
      'errorMessage': '詳細は元の端末で確認してください',
      'canRetry': false,
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
      canRetry: json['canRetry'] != false,
    );
  }

  factory GakujoFailedDownloadEntry.fromExternalJson(Map<dynamic, dynamic> json) {
    final entry = GakujoFailedDownloadEntry.fromJson(json);
    return GakujoFailedDownloadEntry(
      id: entry.id,
      request: GakujoDownloadRequest(
        url: entry.request.url,
        method: entry.request.method,
        courseName: entry.request.courseName,
        fileName: entry.request.fileName,
        formFields: const {},
      ),
      failedAt: entry.failedAt,
      errorMessage: entry.errorMessage,
      canRetry: false,
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
  final _operations = StorageOperationQueue();

  BackupStorageParticipant get backupStorage => BackupStorageParticipant(
        _operations,
        _secureStorage,
        const [
          _historyKey,
          _failedDownloadsKey,
        ],
      );

  Future<List<GakujoDownloadHistoryEntry>> load() {
    return _enqueue(_load);
  }

  Future<List<GakujoDownloadHistoryEntry>> _load() => _loadEntries(
        _historyKey,
        GakujoDownloadHistoryEntry.fromJson,
        (entry) => entry.savedAt,
        _retainsHistoryEntry,
      );

  Future<List<GakujoFailedDownloadEntry>> loadFailedDownloads() {
    return _enqueue(_loadFailedDownloads);
  }

  Future<List<GakujoFailedDownloadEntry>> _loadFailedDownloads() => _loadEntries(
        _failedDownloadsKey,
        GakujoFailedDownloadEntry.fromJson,
        (entry) => entry.failedAt,
        _retainsFailedEntry,
      );

  Future<List<T>> _loadEntries<T extends Object>(
    String key,
    T Function(Map<dynamic, dynamic> json) decodeEntry,
    DateTime Function(T) timestamp,
    bool Function(T) retain,
  ) async {
    final raw = await _secureStorage.read(key: key);
    return decodeStoredJsonList(
      raw,
      decodeEntry,
      retain: retain,
      compare: (a, b) => timestamp(b).compareTo(timestamp(a)),
    );
  }

  Future<void> compact() {
    return _enqueue(_compact);
  }

  Future<void> _compact() async {
    await Future.wait([
      _load().then(_replaceHistory),
      _loadFailedDownloads().then(_writeFailedDownloads),
    ]);
  }

  Future<void> add(GakujoDownloadHistoryEntry entry) {
    return _enqueue(() => _add(entry));
  }

  Future<void> _add(GakujoDownloadHistoryEntry entry) async {
    final entries = [entry, ...await _load()];
    final compacted = entries.take(_maxEntries).toList();
    await _replaceHistory(compacted);
  }

  bool retainsBackupEntry(Object entry) => switch (entry) {
        final GakujoDownloadHistoryEntry value => _retainsHistoryEntry(value),
        final GakujoFailedDownloadEntry value => _retainsFailedEntry(value),
        _ => false,
      };

  Future<void> replaceHistory(List<GakujoDownloadHistoryEntry> entries) {
    return _enqueue(() => _replaceHistory(entries));
  }

  Future<void> _replaceHistory(List<GakujoDownloadHistoryEntry> entries) =>
      _writeEntries(
        entries,
        key: _historyKey,
        limit: _maxEntries,
        timestamp: (entry) => entry.savedAt,
        retain: _retainsHistoryEntry,
        encodeEntry: (entry) => entry.toJson(),
      );

  Future<void> clear() {
    return _enqueue(() => _secureStorage.delete(key: _historyKey));
  }

  Future<void> addFailedDownload({
    required GakujoDownloadRequest request,
    required String errorMessage,
  }) {
    return _enqueue(
      () => _addFailedDownload(
        request: request,
        errorMessage: errorMessage,
      ),
    );
  }

  Future<void> _addFailedDownload({
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
      ...(await _loadFailedDownloads()).where(
        (existing) => _failedRequestKey(existing.request) != requestKey,
      ),
    ];
    await _writeFailedDownloads(entries.take(_maxFailedEntries).toList());
  }

  Future<void> replaceFailedDownloads(
    List<GakujoFailedDownloadEntry> entries,
  ) {
    return _enqueue(() => _writeFailedDownloads(entries));
  }

  Future<void> removeFailedDownload(String id) {
    return _enqueue(() => _removeFailedDownload(id));
  }

  Future<void> _removeFailedDownload(String id) async {
    final entries = await _loadFailedDownloads();
    await _writeFailedDownloads(
      entries.where((entry) => entry.id != id).toList(),
    );
  }

  Future<void> clearFailedDownloads() {
    return _enqueue(
      () => _secureStorage.delete(key: _failedDownloadsKey),
    );
  }

  Future<void> _writeFailedDownloads(
    List<GakujoFailedDownloadEntry> entries,
  ) =>
      _writeEntries(
        entries,
        key: _failedDownloadsKey,
        limit: _maxFailedEntries,
        timestamp: (entry) => entry.failedAt,
        retain: _retainsFailedEntry,
        encodeEntry: (entry) => entry.toJson(),
      );

  Future<void> _writeEntries<T extends Object>(
    List<T> entries, {
    required String key,
    required int limit,
    required DateTime Function(T) timestamp,
    required bool Function(T) retain,
    required Map<String, Object?> Function(T) encodeEntry,
  }) {
    final compacted = entries.where(retain).toList();
    compacted.sort((a, b) => timestamp(b).compareTo(timestamp(a)));
    return _secureStorage.write(
      key: key,
      value: jsonEncode(compacted.take(limit).map(encodeEntry).toList()),
    );
  }

  bool _retainsHistoryEntry(GakujoDownloadHistoryEntry entry) =>
      entry.fileName.trim().isNotEmpty &&
      entry.savedAt.isAfter(DateTime.now().subtract(_historyRetention));

  bool _retainsFailedEntry(GakujoFailedDownloadEntry entry) =>
      entry.id.trim().isNotEmpty &&
      entry.request.url.trim().isNotEmpty &&
      entry.failedAt.isAfter(DateTime.now().subtract(_failedDownloadRetention));

  String _failedRequestKey(GakujoDownloadRequest request) {
    return jsonEncode([
      request.method.toUpperCase(),
      request.url,
      request.fileName,
      DownloadFileNamePolicy.safeFolderName(request.courseName),
      request.canonicalFormFields,
    ]);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    return _operations.run(operation);
  }
}
