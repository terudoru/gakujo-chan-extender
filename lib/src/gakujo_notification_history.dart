import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_storage_factory.dart';
import 'secure_storage_transaction.dart';

class GakujoNotificationHistoryEntry {
  const GakujoNotificationHistoryEntry({
    required this.title,
    required this.body,
    required this.postedAt,
    this.url,
  });

  final String title;
  final String body;
  final DateTime postedAt;
  final String? url;

  Map<String, Object?> toJson() => {
    'title': title,
    'body': body,
    'postedAtMillis': postedAt.millisecondsSinceEpoch,
    if (url != null) 'url': url,
  };

  static GakujoNotificationHistoryEntry? fromJson(Object? value) {
    if (value
        case {
          'title': final String title,
          'body': final String body,
          'postedAtMillis': final int millis,
        }
        when millis > 0 && millis <= 8640000000000000) {
      final url = (value as Map)['url'];
      return GakujoNotificationHistoryEntry(
        title: title,
        body: body,
        postedAt: DateTime.fromMillisecondsSinceEpoch(millis),
        url: url is String ? url : null,
      );
    }
    return null;
  }

  static List<GakujoNotificationHistoryEntry> newestFirst(Iterable rows) =>
      [for (final row in rows) ?fromJson(row)]
        ..sort((a, b) => b.postedAt.compareTo(a.postedAt));
}

/// Desktop notifications are posted while Flutter is running. Mobile and
/// macOS keep their own native history so a background delivery can be saved.
class GakujoNotificationHistoryStore {
  GakujoNotificationHistoryStore({FlutterSecureStorage? storage})
    : _storage = storage ?? SecureStorageFactory.create();

  static final _operations = StorageOperationQueue();
  static int _generation = 0;
  static const _key = 'more_better_gakujo_notification_history';
  final FlutterSecureStorage _storage;

  int get generation => _generation;

  Future<List> _read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? [] : jsonDecode(raw) as List;
  }

  Future<List<GakujoNotificationHistoryEntry>> load(String account) =>
      _operations.run(
        () async => GakujoNotificationHistoryEntry.newestFirst(
          (await _read()).where(
            (row) => row is Map && row['account'] == account,
          ),
        ),
      );

  Future<void> record(
    String account,
    GakujoNotificationHistoryEntry entry, {
    required int generation,
  }) =>
      _operations.run(() async {
        if (generation != _generation) return;
        final rows = await _read();
        await _storage.write(
          key: _key,
          value: jsonEncode([
            {'account': account, ...entry.toJson()},
            ...rows.take(199),
          ]),
        );
      });

  Future<void> clear() {
    _generation++;
    return _operations.run(() => _storage.delete(key: _key));
  }
}
