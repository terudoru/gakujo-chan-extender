import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../secure_storage_factory.dart';

class DriveDownloadPreference {
  DriveDownloadPreference({FlutterSecureStorage? storage})
    : _storage = storage ?? SecureStorageFactory.create();

  static const key = 'drive_downloads_preference';
  final FlutterSecureStorage _storage;
  bool enabled = false;
  String? boundAccount;
  String? boundGoogleEmail;
  String? folderId;
  String? folderName;
  String? folderEmail;

  Future<void> load(File legacyFile) async {
    final raw = await _storage.read(key: key);
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      enabled = data['enabled'] == true;
      boundAccount = data['boundAccount'] as String?;
      boundGoogleEmail = data['boundGoogleEmail'] as String?;
      folderId = data['folderId'] as String?;
      folderName = data['folderName'] as String?;
      folderEmail = data['folderEmail'] as String?;
    } else if (await legacyFile.exists()) {
      // The old toggle has no account identity, so it cannot be trusted on.
      final legacyEnabled = await legacyFile.readAsString() == 'true';
      await save(legacyEnabled, null);
    }
    if (await legacyFile.exists()) await legacyFile.delete();
  }

  Future<void> save(bool value, String? account, [String? googleEmail]) async {
    await _storage.write(
      key: key,
      value: jsonEncode({
        'enabled': value,
        'boundAccount': account,
        'boundGoogleEmail': googleEmail,
        'folderId': folderId,
        'folderName': folderName,
        'folderEmail': folderEmail,
      }),
    );
    enabled = value;
    boundAccount = account;
    boundGoogleEmail = googleEmail;
  }

  Future<void> saveFolder(String? id, String? name, String? email) async {
    await _storage.write(
      key: key,
      value: jsonEncode({
        'enabled': enabled,
        'boundAccount': boundAccount,
        'boundGoogleEmail': boundGoogleEmail,
        'folderId': id,
        'folderName': id == null ? null : name,
        'folderEmail': id == null ? null : email,
      }),
    );
    folderId = id;
    folderName = id == null ? null : name;
    folderEmail = id == null ? null : email;
  }

  String? folderIdFor(String? email) =>
      email != null && folderEmail == email ? folderId : null;

  String? folderNameFor(String? email) =>
      email != null && folderEmail == email ? folderName : null;

  Future<void> clear() async {
    await _storage.delete(key: key);
    enabled = false;
    boundAccount = null;
    boundGoogleEmail = null;
    folderId = null;
    folderName = null;
    folderEmail = null;
  }

  bool matches(String? account, [String? googleEmail]) =>
      enabled &&
      account != null &&
      account == boundAccount &&
      googleEmail != null &&
      googleEmail == boundGoogleEmail;

  bool matchesUpload(
    String? account,
    String? googleEmail,
    String? originAccount,
    String? originGoogleEmail,
  ) =>
      matches(account, googleEmail) &&
      matches(originAccount, originGoogleEmail);
}

class DriveDownloadQueue {
  final _jobs = Queue<Future<void> Function()>();
  bool _running = false;
  int _generation = 0;

  int get generation => _generation;
  bool isCurrent(int generation) => generation == _generation;

  void cancel() {
    _generation++;
    _jobs.clear();
  }

  void add(Future<void> Function(int) job) {
    final generation = _generation;
    _jobs.add(() => job(generation));
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_jobs.isNotEmpty) {
        await _jobs.removeFirst()();
      }
    } finally {
      _running = false;
    }
  }
}
