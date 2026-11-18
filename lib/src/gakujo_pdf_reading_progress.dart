import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stores page numbers by document digest on this device.
class GakujoPdfReadingProgress {
  GakujoPdfReadingProgress({this._directory});

  static const _fileName = 'pdf_reading_progress.json';
  static const _maxEntries = 128;
  static const _maxBytes = 16 * 1024;
  // Match the PDF viewer's page limit.
  static const maxPage = 2000;
  static final _digest = RegExp(r'^[0-9a-f]{64}$');
  static final _temporaryFileName = RegExp(
    r'^pdf_reading_progress\.json\.[0-9]+\.[0-9]+\.tmp$',
  );

  final Directory? _directory;
  Future<void> _tail = Future<void>.value();

  Future<int?> read(String key) {
    if (!_validKey(key)) return Future<int?>.value();
    return _enqueue(() async => (await _read(await _file()))[key]);
  }

  Future<void> save(String key, int page) {
    if (!_validKey(key) || !_validPage(page)) return Future<void>.value();
    return _enqueue(() async {
      final file = await _file();
      final pages = await _read(file);
      if (pages.isNotEmpty && pages.keys.last == key && pages[key] == page) {
        return;
      }
      pages
        ..remove(key)
        ..[key] = page;
      _trim(pages);
      await _write(file, pages);
    });
  }

  Future<void> clear() {
    return _enqueue(() async {
      final file = await _file();
      if (!await file.parent.exists()) return;
      await for (final entry in file.parent.list(followLinks: false)) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            (name == _fileName || _temporaryFileName.hasMatch(name))) {
          await entry.delete();
        }
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static bool _validKey(String key) =>
      key.length == 64 && _digest.hasMatch(key);

  static bool _validPage(int page) => page > 0 && page <= maxPage;

  static void _trim(Map<String, int> pages) {
    while (pages.length > _maxEntries) {
      pages.remove(pages.keys.first);
    }
  }

  Future<Map<String, int>> _read(File file) async {
    final pages = <String, int>{};
    if (!await file.exists()) return pages;

    final input = await file.open();
    try {
      final bytes = await input.read(_maxBytes + 1);
      if (bytes.length > _maxBytes) return pages;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final page = entry.value;
          if (_validKey(entry.key) && page is int && _validPage(page)) {
            pages[entry.key] = page;
          }
        }
        _trim(pages);
      }
    } on FormatException {
      // Older or invalid data should not prevent a fresh save.
    } finally {
      await input.close();
    }
    return pages;
  }

  Future<void> _write(File file, Map<String, int> pages) async {
    await file.parent.create(recursive: true);
    final temporaryFile = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporaryFile.writeAsString(jsonEncode(pages), flush: true);
      await temporaryFile.rename(file.path);
    } finally {
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
      } on FileSystemException {
        // Keep a write or rename error visible to the caller.
      }
    }
  }

  Future<File> _file() async {
    final directory = _directory ?? await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
