// More Better Gakujo patch: only synthetic data in a per-test temporary directory.
@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_windows/src/flutter_secure_storage_windows_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const options = {'useBackwardCompatibility': 'false'};
  late Directory directory;
  late File file;
  late _FileFaults faults;
  late DpapiJsonFileMapStorage mapStorage;
  late FlutterSecureStorageWindows storage;

  FlutterSecureStorageWindows createStorage(MapStorage backing) =>
      createFlutterSecureStorageWindows(
        MethodChannelFlutterSecureStorage(),
        backing,
      );

  Future<List<File>> preservedFiles() async => [
        await for (final entity in directory.list())
          if (entity is File && entity.path.startsWith('${file.path}.corrupt-'))
            entity,
      ];

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('fss_windows_reliability_');
    file = File(path.join(directory.path, encryptedJsonFileName));
    faults = _FileFaults();
    mapStorage = DpapiJsonFileMapStorage.forTesting(
      getFilePath: () => file.path,
      fileFactory: (filePath) => _ControlledFile(File(filePath), faults),
    );
    storage = createStorage(mapStorage);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('a missing file is empty and the first write creates it', () async {
    expect(await storage.readAll(options: options), isEmpty);
    await storage.write(key: 'first', value: 'fixture-1', options: options);
    expect(await storage.readAll(options: options), {'first': 'fixture-1'});
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('clear removes primary, temporary and recovery files only', () async {
    await storage.write(key: 'existing', value: 'fixture', options: options);
    final temporary = File('${file.path}.tmp');
    final recovery = File('${file.path}.corrupt-123');
    final unrelated = File('${file.path}.corrupt-not-a-timestamp');
    await temporary.writeAsString('temporary');
    await recovery.writeAsString('recovery');
    await unrelated.writeAsString('unrelated');

    await mapStorage.clear(options);
    expect(await file.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
    expect(await recovery.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
    await mapStorage.clear(options);
  });

  test('clear reports a primary file access failure', () async {
    await storage.write(key: 'existing', value: 'fixture', options: options);
    faults.deleteError = FileSystemException('Injected failure', file.path, const OSError('access denied', 5));
    await expectLater(mapStorage.clear(options), throwsA(isA<FileSystemException>()));
    expect(await file.exists(), isTrue);
    faults.deleteError = null;
    await mapStorage.clear(options);
    expect(await file.exists(), isFalse);
  });

  test('a missing parent directory is empty and created on write', () async {
    final nested = DpapiJsonFileMapStorage.forTesting(
      getFilePath: () =>
          path.join(directory.path, 'nested', encryptedJsonFileName),
    );
    final target = createStorage(nested);
    expect(await target.readAll(options: options), isEmpty);
    await target.write(key: 'first', value: 'fixture-1', options: options);
    expect(await target.readAll(options: options), {'first': 'fixture-1'});
  });

  for (final errorCode in [5, 32, 30, null]) {
    test('read failure ($errorCode) aborts writes without losing keys',
        () async {
      await storage.write(
          key: 'existing', value: 'fixture-1', options: options);
      final previousBytes = await file.readAsBytes();
      faults.readError = FileSystemException(
        'Injected read failure',
        file.path,
        errorCode == null ? null : OSError('Injected error', errorCode),
      );
      final readFailure = throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'read_failed'),
      );

      await expectLater(storage.readAll(options: options), readFailure);
      await expectLater(
        storage.write(key: 'blocked', value: 'fixture-2', options: options),
        readFailure,
      );
      expect(await file.readAsBytes(), previousBytes);
      expect(await File('${file.path}.tmp').exists(), isFalse);
      expect(await preservedFiles(), isEmpty);

      faults.readError = null;
      await storage.write(key: 'next', value: 'fixture-3', options: options);
      expect(await storage.readAll(options: options), {
        'existing': 'fixture-1',
        'next': 'fixture-3',
      });
    });
  }

  test('an interrupted temporary write leaves the previous file intact',
      () async {
    await storage.write(key: 'existing', value: 'fixture-1', options: options);
    final previousBytes = await file.readAsBytes();
    faults.interruptWrite = true;

    await expectLater(
      storage.write(key: 'interrupted', value: 'fixture-2', options: options),
      throwsA(isA<FileSystemException>()),
    );
    expect(faults.lastFlush, isTrue);
    expect(await file.readAsBytes(), previousBytes);
    expect(await File('${file.path}.tmp').exists(), isTrue);
    expect(await storage.readAll(options: options), {'existing': 'fixture-1'});

    faults.interruptWrite = false;
    final deletesBeforeRetry = faults.temporaryDeletes;
    await storage.write(key: 'next', value: 'fixture-3', options: options);
    expect(faults.temporaryDeletes, deletesBeforeRetry + 1);
    expect(await File('${file.path}.tmp').exists(), isFalse);
    expect(await storage.readAll(options: options), {
      'existing': 'fixture-1',
      'next': 'fixture-3',
    });
  });

  test('a failed replacement leaves the previous file intact', () async {
    await storage.write(key: 'existing', value: 'fixture-1', options: options);
    final previousBytes = await file.readAsBytes();
    faults.failRename = true;

    await expectLater(
      storage.write(key: 'blocked', value: 'fixture-2', options: options),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), previousBytes);
    expect(await storage.readAll(options: options), {'existing': 'fixture-1'});

    faults.failRename = false;
    await storage.write(key: 'next', value: 'fixture-3', options: options);
    expect(await storage.readAll(options: options), {
      'existing': 'fixture-1',
      'next': 'fixture-3',
    });
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('a stale temporary file is removed before writing', () async {
    await storage.write(key: 'existing', value: 'fixture-1', options: options);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(List<int>.filled(4096, 0xAB));
    final deletesBeforeWrite = faults.temporaryDeletes;

    await storage.write(key: 'next', value: 'fixture-2', options: options);
    expect(faults.temporaryDeletes, deletesBeforeWrite + 1);
    expect(faults.lastFlush, isTrue);
    expect(await temporary.exists(), isFalse);
    expect(await storage.readAll(options: options), {
      'existing': 'fixture-1',
      'next': 'fixture-2',
    });
  });

  final malformedFiles = <String, Uint8List Function()>{
    'an empty file': () => Uint8List(0),
    'undecryptable bytes': () => Uint8List.fromList([0, 1, 2, 3, 4]),
    'invalid UTF-8': () => _encrypt(Uint8List.fromList([0xFF, 0xFE, 0])),
    'invalid JSON': () => _encrypt(utf8.encode('invalid-json-fixture')),
    'non-object JSON': () => _encrypt(utf8.encode('[1, 2, 3]')),
  };
  for (final entry in malformedFiles.entries) {
    test('${entry.key} is renamed aside before starting an empty store',
        () async {
      final originalBytes = entry.value();
      await file.writeAsBytes(originalBytes, flush: true);

      expect(await storage.readAll(options: options), isEmpty);
      expect(await file.exists(), isFalse);
      final backups = await preservedFiles();
      expect(backups, hasLength(1));
      expect(backups.single.path, matches(r'\.corrupt-\d+$'));
      expect(await backups.single.readAsBytes(), originalBytes);

      await storage.write(key: 'next', value: 'fixture-1', options: options);
      expect(await storage.readAll(options: options), {'next': 'fixture-1'});
      expect(await backups.single.readAsBytes(), originalBytes);
      expect(await preservedFiles(), hasLength(1));
    });
  }

  test('failed corruption preservation aborts a write and retains the file',
      () async {
    final originalBytes = Uint8List.fromList([0, 1, 2, 3, 4]);
    await file.writeAsBytes(originalBytes, flush: true);
    faults.failRename = true;

    await expectLater(
      storage.write(key: 'blocked', value: 'fixture-1', options: options),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), originalBytes);
    expect(await preservedFiles(), isEmpty);
    expect(await File('${file.path}.tmp').exists(), isFalse);

    faults.failRename = false;
    await storage.write(key: 'next', value: 'fixture-2', options: options);
    expect(await storage.readAll(options: options), {'next': 'fixture-2'});
    expect(await (await preservedFiles()).single.readAsBytes(), originalBytes);
  });

  test('overlapping writes preserve keys across plugin instances', () async {
    final secondStorage = createStorage(
      DpapiJsonFileMapStorage.forTesting(getFilePath: () => file.path),
    );
    await Future.wait([
      for (var i = 0; i < 10; i++)
        (i.isEven ? storage : secondStorage).write(
          key: 'key-$i',
          value: 'fixture-$i',
          options: options,
        ),
    ]);
    expect(await storage.readAll(options: options), {
      for (var i = 0; i < 10; i++) 'key-$i': 'fixture-$i',
    });
  });

  test('a second instance cannot load during an in-flight mutation', () async {
    final gate = _GatedMapStorage(mapStorage);
    final firstStorage = createStorage(gate);
    final secondStorage = createStorage(gate);
    final first =
        firstStorage.write(key: 'first', value: 'fixture-1', options: options);
    await gate.firstLoadStarted.future;
    final second = secondStorage.write(
        key: 'second', value: 'fixture-2', options: options);
    try {
      // Drain pending microtasks. An instance-local lock would enter load twice.
      await Future<void>.delayed(Duration.zero);
      expect(gate.loadCalls, 1);
    } finally {
      gate.releaseFirstLoad.complete();
      await Future.wait([first, second]);
    }
    expect(await storage.readAll(options: options), {
      'first': 'fixture-1',
      'second': 'fixture-2',
    });
  });
}

class _FileFaults {
  FileSystemException? deleteError;
  FileSystemException? readError;
  bool interruptWrite = false;
  bool failRename = false;
  bool? lastFlush;
  int temporaryDeletes = 0;
}

/// Delegates to real temporary files, with faults at the actual I/O boundary.
class _ControlledFile implements File {
  _ControlledFile(this._delegate, this._faults);

  final File _delegate;
  final _FileFaults _faults;

  @override
  String get path => _delegate.path;

  @override
  Future<bool> exists() => _delegate.exists();

  @override
  bool existsSync() => _delegate.existsSync();

  @override
  Future<Uint8List> readAsBytes() async {
    final error = _faults.readError;
    if (error != null) throw error;
    return _delegate.readAsBytes();
  }

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await _delegate.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    _faults.lastFlush = flush;
    if (_faults.interruptWrite) {
      await _delegate.writeAsBytes(bytes.take(4).toList(),
          mode: mode, flush: flush);
      throw FileSystemException('Injected interrupted write', path);
    }
    await _delegate.writeAsBytes(bytes, mode: mode, flush: flush);
    return this;
  }

  @override
  Future<File> rename(String newPath) async {
    if (_faults.failRename) {
      throw FileSystemException('Injected rename failure', path);
    }
    return _delegate.rename(newPath);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (_faults.deleteError != null) throw _faults.deleteError!;
    if (path.endsWith('.tmp')) _faults.temporaryDeletes++;
    return _delegate.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedMapStorage extends MapStorage {
  _GatedMapStorage(this._delegate);

  final MapStorage _delegate;
  final firstLoadStarted = Completer<void>();
  final releaseFirstLoad = Completer<void>();
  int loadCalls = 0;

  @override
  Future<Map<String, String>> load(Map<String, String> options) async {
    loadCalls++;
    if (loadCalls == 1) {
      firstLoadStarted.complete();
      await releaseFirstLoad.future;
    }
    return _delegate.load(options);
  }

  @override
  FutureOr<void> save(Map<String, String> data, Map<String, String> options) =>
      _delegate.save(data, options);

  @override
  FutureOr<void> clear(Map<String, String> options) => _delegate.clear(options);
}

/// Encrypts synthetic malformed payloads to reach UTF-8/JSON recovery paths.
Uint8List _encrypt(Uint8List bytes) => using((alloc) {
      final inputBytes = alloc<Uint8>(bytes.length);
      inputBytes.asTypedList(bytes.length).setAll(0, bytes);
      final input = alloc<CRYPT_INTEGER_BLOB>();
      input.ref.cbData = bytes.length;
      input.ref.pbData = inputBytes;
      final output = alloc<CRYPT_INTEGER_BLOB>();
      final Win32Result(value: succeeded) = CryptProtectData(
        input,
        null,
        null,
        null,
        0,
        output,
      );
      if (!succeeded) throw StateError('Could not encrypt test fixture');
      try {
        return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData),
        );
      } finally {
        LocalFree(HLOCAL(output.ref.pbData.cast()));
      }
    });
