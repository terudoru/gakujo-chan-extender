import 'dart:async';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const options = <String, String>{};

  test('an existing primary value does not delete an unread legacy value',
      () async {
    final primary = _MemoryMap({'key': 'primary'});
    final legacy = _MemoryLegacy({'key': 'different legacy'});
    final storage = createFlutterSecureStorageWindows(legacy, primary);

    expect(await storage.read(key: 'key', options: options), 'primary');
    expect(legacy.values, {'key': 'different legacy'});
    expect(legacy.deleted, isEmpty);
  });

  test('legacy read failure does not save or delete anything', () async {
    final primary = _MemoryMap({});
    final legacy = _MemoryLegacy({'key': 'legacy'})..failReads = true;
    final storage = createFlutterSecureStorageWindows(legacy, primary);

    await expectLater(
        storage.read(key: 'key', options: options), throwsStateError);
    await expectLater(storage.readAll(options: options), throwsStateError);
    expect(primary.saves, 0);
    expect(legacy.values, {'key': 'legacy'});
    expect(legacy.deleted, isEmpty);
  });

  test('bulk migration retains conflicting legacy values', () async {
    final primary = _MemoryMap({'conflict': 'primary', 'same': 'same'});
    final legacy = _MemoryLegacy({
      'conflict': 'different legacy',
      'same': 'same',
      'new': 'recovered',
    });
    final storage = createFlutterSecureStorageWindows(legacy, primary);

    expect(await storage.readAll(options: options), {
      'conflict': 'primary',
      'same': 'same',
      'new': 'recovered',
    });
    expect(primary.values['new'], 'recovered');
    expect(legacy.values, {'conflict': 'different legacy'});
    expect(legacy.deleted, unorderedEquals(['same', 'new']));
  });

  test('failed primary save preserves all legacy values', () async {
    final primary = _MemoryMap({})..failSaves = true;
    final legacy = _MemoryLegacy({'one': 'first', 'two': 'second'});
    final storage = createFlutterSecureStorageWindows(legacy, primary);

    await expectLater(storage.readAll(options: options), throwsStateError);
    expect(legacy.values, {'one': 'first', 'two': 'second'});
    expect(legacy.deleted, isEmpty);
  });
}

class _MemoryMap extends MapStorage {
  _MemoryMap(this.values);
  Map<String, String> values;
  bool failSaves = false;
  int saves = 0;

  @override
  FutureOr<Map<String, String>> load(Map<String, String> options) =>
      Map.of(values);

  @override
  FutureOr<void> save(Map<String, String> data, Map<String, String> options) {
    if (failSaves) throw StateError('injected save failure');
    values = Map.of(data);
    saves++;
  }

  @override
  Future<void> clear(Map<String, String> options) async {
    values.clear();
  }
}

class _MemoryLegacy extends FlutterSecureStoragePlatform {
  _MemoryLegacy(this.values);
  final Map<String, String> values;
  final List<String> deleted = [];
  bool failReads = false;

  @override
  Future<String?> read(
      {required String key, required Map<String, String> options}) async {
    if (failReads) throw StateError('injected read failure');
    return values[key];
  }

  @override
  Future<Map<String, String>> readAll(
      {required Map<String, String> options}) async {
    if (failReads) throw StateError('injected read failure');
    return Map.of(values);
  }

  @override
  Future<void> delete(
      {required String key, required Map<String, String> options}) async {
    deleted.add(key);
    values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      values.clear();

  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      values.containsKey(key);

  @override
  Future<void> write(
          {required String key,
          required String value,
          required Map<String, String> options}) async =>
      values[key] = value;
}
