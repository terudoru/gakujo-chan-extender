import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// An extension on `Map<String, String>` to add support for specific
/// configuration options related to backward compatibility.
@visibleForTesting
extension OptionsExtension on Map<String, String> {
  /// Checks whether the `useBackwardCompatibility` flag is enabled in the map.
  ///
  /// Returns:
  /// - `true` if the value associated with the `useBackwardCompatibility` key
  ///   is not `'false'`.
  /// - `false` otherwise.
  bool get useBackwardCompatibility =>
      this['useBackwardCompatibility'] != 'false';
}

/// Serialises async critical sections without external dependencies.
///
/// Each [run] call waits for the previous one to finish (including error cases)
/// before starting the next, preventing concurrent read-modify-write races.
class _AsyncLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() fn) {
    final next = _last.then((_) => fn());
    // Swallow errors so a failed operation does not poison future callers.
    _last = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}

/// The `FlutterSecureStorageWindows` class provides a Windows-specific
/// implementation of the `FlutterSecureStoragePlatform` interface.
///
/// This implementation uses a combination of a backward-compatible storage
/// mechanism and a platform-specific storage backend.
class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  /// Creates an instance of `FlutterSecureStorageWindows` with default
  /// configurations for both backward compatibility and platform-specific
  /// storage.
  FlutterSecureStorageWindows()
      : this._(
          MethodChannelFlutterSecureStorage(),
          DpapiJsonFileMapStorage(),
        );

  /// Internal constructor to initialize `FlutterSecureStorageWindows` with
  /// custom implementations for backward compatibility and platform-specific
  /// storage.
  ///
  /// Parameters:
  /// - [_backwardCompatible]: The storage mechanism used for backward
  ///   compatibility.
  /// - [_storage]: The platform-specific storage backend for Windows.
  FlutterSecureStorageWindows._(
    this._backwardCompatible,
    this._storage,
  );

  /// The storage implementation used for backward compatibility.
  final FlutterSecureStoragePlatform _backwardCompatible;

  /// The platform-specific storage implementation for Windows, using DPAPI.
  final MapStorage _storage;

  // More Better Gakujo patch: instances share one file (and one .tmp path), so
  // serialize the complete read-modify-write cycle across this isolate.
  static final _lock = _AsyncLock();

  /// Registers this plugin.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        if (map.containsKey(key)) {
          return true;
        }

        if (options.useBackwardCompatibility) {
          return _backwardCompatible.containsKey(key: key, options: options);
        }

        return false;
      });

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        final initialSize = map.length;
        map.remove(key);
        if (map.length != initialSize) {
          await _storage.save(map, options);
        }

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.delete(key: key, options: options);
        }
      });

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _lock.run(() async {
        await _storage.clear(options);

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.deleteAll(options: options);
        }
      });

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);

        var result = map[key];
        if (options.useBackwardCompatibility) {
          if (result == null) {
            final compatible =
                await _backwardCompatible.read(key: key, options: options);
            if (compatible != null) {
              // Write back now, so the value should be retrieved from JSON file
              // next.
              result = map[key] = compatible;
              await _storage.save(map, options);
            }
          }

          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }

        return result;
      });

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        if (!options.useBackwardCompatibility) {
          // Just return a map.
          return map;
        }

        final compatible = await _backwardCompatible.readAll(options: options);

        if (compatible.isEmpty) {
          return map;
        }

        for (final entry in compatible.entries) {
          map.putIfAbsent(entry.key, () => entry.value);
        }

        // Write back now, so the value should be retrieved from JSON file next.
        await _storage.save(map, options);

        // Clear old entries.
        await _backwardCompatible.deleteAll(options: options);

        return map;
      });

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) =>
      _lock.run(() async {
        final map = await _storage.load(options);
        map[key] = value;
        await _storage.save(map, options);

        if (options.useBackwardCompatibility) {
          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }
      });
}

/// Creates a custom instance of `FlutterSecureStorageWindows` for testing.
///
/// This factory function is annotated with `@visibleForTesting` to indicate
/// its intended use in testing scenarios. It allows specifying custom
/// implementations for backward compatibility and platform-specific storage.
///
/// Parameters:
/// - [backwardCompatible]: A custom implementation of
///   `FlutterSecureStoragePlatform` for backward-compatible storage behavior.
/// - [mapStorage]: A custom implementation of `MapStorage` for Windows secure
///   storage functionality.
///
/// Returns:
/// - An instance of `FlutterSecureStorageWindows` configured with the given
///   `backwardCompatible` and `mapStorage` implementations.
@visibleForTesting
FlutterSecureStorageWindows createFlutterSecureStorageWindows(
  FlutterSecureStoragePlatform backwardCompatible,
  MapStorage mapStorage,
) =>
    FlutterSecureStorageWindows._(backwardCompatible, mapStorage);

@visibleForTesting

/// An abstract class that defines the interface for map-based storage
/// implementations.
abstract class MapStorage {
  /// Loads a map of key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the load operation.
  FutureOr<Map<String, String>> load(Map<String, String> options);

  /// Saves a map of key-value pairs to the storage medium.
  ///
  /// Parameters:
  /// - [data]: A map containing the data to save.
  /// - [options]: A map of options to customize the save operation.
  FutureOr<void> save(Map<String, String> data, Map<String, String> options);

  /// Clears all key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the clear operation.
  FutureOr<void> clear(Map<String, String> options);
}

/// The file name used to store encrypted JSON data.
///
/// This constant is exposed for testing purposes.
@visibleForTesting
const String encryptedJsonFileName = 'flutter_secure_storage.dat';

/// A `MapStorage` implementation that uses DPAPI (Data Protection API) for
/// encryption and stores data in a JSON file on disk.
///
/// This implementation is specific to Windows platforms.
@visibleForTesting
class DpapiJsonFileMapStorage extends MapStorage {
  /// Creates an instance of `DpapiJsonFileMapStorage`.
  DpapiJsonFileMapStorage()
      : _fileFactory = File.new,
        _getFilePathForTesting = null;

  // More Better Gakujo patch: exercise actual DPAPI/file handling in a temporary
  // directory and inject I/O failures without touching application storage.
  /// Creates storage with an isolated path and optional file-operation faults.
  @visibleForTesting
  DpapiJsonFileMapStorage.forTesting({
    required FutureOr<String> Function() getFilePath,
    File Function(String) fileFactory = File.new,
  })  : _fileFactory = fileFactory,
        _getFilePathForTesting = getFilePath;

  final File Function(String) _fileFactory;
  final FutureOr<String> Function()? _getFilePathForTesting;

  /// Retrieves the canonical path to the encrypted JSON file used for storage.
  ///
  /// This method constructs the file path based on the application's support
  /// directory.
  ///
  /// Returns:
  /// - A [FutureOr] resolving to the canonical file path as a string.
  FutureOr<String> _getJsonFilePath() async {
    final getFilePath = _getFilePathForTesting;
    if (getFilePath != null) {
      return getFilePath();
    }
    final appDataDirectory = await getApplicationSupportDirectory();

    return path.canonicalize(
      path.join(
        appDataDirectory.path,
        encryptedJsonFileName,
      ),
    );
  }

  // More Better Gakujo patch: exists() can conceal access errors. Attempt the
  // operation directly and only accept the two Windows not-found error codes.
  static bool _isMissingFile(FileSystemException error) =>
      error.osError?.errorCode == ERROR_FILE_NOT_FOUND ||
      error.osError?.errorCode == ERROR_PATH_NOT_FOUND;

  // More Better Gakujo patch: preserve the original encrypted bytes for manual
  // recovery. If renaming fails, do not allow a caller to overwrite the file.
  Future<Map<String, String>> _preserveCorruptFile(File file) async {
    var timestamp = DateTime.now().microsecondsSinceEpoch;
    var preservedPath = '${file.path}.corrupt-$timestamp';
    while (await _fileFactory(preservedPath).exists()) {
      preservedPath = '${file.path}.corrupt-${++timestamp}';
    }
    await file.rename(preservedPath);
    // Do not log the exception: FormatException can include decrypted contents.
    debugPrint('Preserved unreadable secure storage file: $preservedPath');
    return {};
  }

  @override
  FutureOr<Map<String, String>> load(Map<String, String> options) async {
    final file = _fileFactory(await _getJsonFilePath());

    late final Uint8List encryptedText;
    // More Better Gakujo patch: sharing violations (antivirus, backup or sync
    // tools) are usually brief, so retry before failing the operation.
    for (var attempt = 1;; attempt += 1) {
      try {
        encryptedText = await file.readAsBytes();
        break;
      } on FileSystemException catch (e) {
        if (_isMissingFile(e)) {
          return {};
        }
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 100 * attempt));
          continue;
        }
        // More Better Gakujo patch: a failed read must abort any pending
        // mutation instead of being mistaken for an empty store.
        throw PlatformException(
          code: 'read_failed',
          message: 'Failed to read encrypted secure storage.',
          details: e.osError?.errorCode,
        );
      }
    }

    // More Better Gakujo patch: an empty existing file is corrupt, not missing.
    if (encryptedText.isEmpty) {
      return _preserveCorruptFile(file);
    }

    late final String plainText;
    try {
      plainText = using((alloc) {
        final pEncryptedText = alloc<Uint8>(encryptedText.length);
        pEncryptedText
            .asTypedList(encryptedText.length)
            .setAll(0, encryptedText);

        // Specify size of the struct explicitly.
        final encryptedTextBlob =
            alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
        encryptedTextBlob.ref.cbData = encryptedText.length;
        encryptedTextBlob.ref.pbData = pEncryptedText;

        // Specify size of the struct explicitly.
        final plainTextBlob =
            alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
        final Win32Result(value: isUnprotected, error: unprotectError) =
            CryptUnprotectData(
          encryptedTextBlob,
          null,
          null,
          null,
          0,
          plainTextBlob,
        );
        if (!isUnprotected) {
          throw WindowsException(
            unprotectError.toHRESULT(),
            message: 'Failure on CryptUnprotectData()',
          );
        }

        if (plainTextBlob.ref.pbData.address == NULL) {
          throw WindowsException(
            ERROR_OUTOFMEMORY.toHRESULT(),
            message: 'Failure on CryptUnprotectData()',
          );
        }

        try {
          return utf8.decoder.convert(
            plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
          );
        } finally {
          if (plainTextBlob.ref.pbData.address != NULL) {
            final Win32Result(value: localFreeResult, error: localFreeError) =
                LocalFree(HLOCAL(plainTextBlob.ref.pbData.cast()));
            if (!localFreeResult.isNull) {
              debugPrint(
                'load: Failed to LocalFree with: '
                '${localFreeError.toHRESULT().toHexString()}',
              );
            }
          }
        }
      });
    } on FormatException {
      return _preserveCorruptFile(file);
    } on WindowsException {
      return _preserveCorruptFile(file);
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(plainText);
    } on FormatException {
      return _preserveCorruptFile(file);
    }

    if (decoded is! Map) {
      return _preserveCorruptFile(file);
    }

    return {
      for (final e
          in decoded.entries.where((x) => x.key is String && x.value is String))
        e.key as String: e.value as String,
    };
  }

  @override
  FutureOr<void> save(
    Map<String, String> data,
    Map<String, String> options,
  ) async {
    final file = _fileFactory(await _getJsonFilePath());
    final json = jsonEncode(data);
    final plainText = utf8.encode(json);

    await using<FutureOr<void>>((alloc) async {
      final pPlainText = alloc<Uint8>(plainText.length);
      pPlainText.asTypedList(plainText.length).setAll(0, plainText);

      // Specify size of the struct explicitly.
      final plainTextBlob =
          alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      plainTextBlob.ref.cbData = plainText.length;
      plainTextBlob.ref.pbData = pPlainText;

      // Specify size of the struct explicitly.
      final encryptedTextBlob =
          alloc.allocate<CRYPT_INTEGER_BLOB>(sizeOf<CRYPT_INTEGER_BLOB>());
      final Win32Result(value: isProtected, error: protectError) =
          CryptProtectData(
        plainTextBlob,
        null,
        null,
        null,
        0,
        encryptedTextBlob,
      );
      if (!isProtected) {
        throw WindowsException(
          protectError.toHRESULT(),
          message: 'Failure on CryptProtectData()',
        );
      }

      if (encryptedTextBlob.ref.pbData.address == NULL) {
        throw WindowsException(
          ERROR_OUTOFMEMORY.toHRESULT(),
          message: 'Failure on CryptProtectData()',
        );
      }

      try {
        final encryptedText = encryptedTextBlob.ref.pbData
            .asTypedList(encryptedTextBlob.ref.cbData);

        // More Better Gakujo patch: never truncate the only good copy. A failed
        // write/rename propagates, leaving the old file intact; the next write
        // removes any temporary file left by an interrupted attempt.
        final temporaryFile = _fileFactory('${file.path}.tmp');
        try {
          await temporaryFile.delete();
        } on FileSystemException catch (e) {
          if (!_isMissingFile(e)) {
            rethrow;
          }
        }
        await temporaryFile.create(recursive: true);
        await temporaryFile.writeAsBytes(encryptedText, flush: true);
        await temporaryFile.rename(file.path);
      } finally {
        if (encryptedTextBlob.ref.pbData.address != NULL) {
          final Win32Result(value: localFreeResult, error: localFreeError) =
              LocalFree(HLOCAL(encryptedTextBlob.ref.pbData.cast()));
          if (!localFreeResult.isNull) {
            debugPrint(
              'save: Failed to LocalFree with: '
              '${localFreeError.toHRESULT().toHexString()}',
            );
          }
        }
      }
    });
  }

  @override
  FutureOr<void> clear(Map<String, String> options) async {
    final file = _fileFactory(await _getJsonFilePath());
    final parent = Directory(path.dirname(file.path));
    final baseName = path.basename(file.path);
    final recoveryName = RegExp('^${RegExp.escape(baseName)}\\.corrupt-[0-9]+\$');
    final residuals = <String>[];
    try {
      await for (final entry in parent.list(followLinks: false)) {
        final name = path.basename(entry.path);
        if (name != '$baseName.tmp' && !recoveryName.hasMatch(name)) continue;
        if (entry is! File) {
          throw FileSystemException('Unexpected secure storage recovery entry', entry.path);
        }
        residuals.add(entry.path);
      }
    } on FileSystemException catch (error) {
      if (!_isMissingFile(error)) rethrow;
    }
    for (final candidate in [file.path, ...residuals]) {
      try {
        await _fileFactory(candidate).delete();
      } on FileSystemException catch (error) {
        if (!_isMissingFile(error)) rethrow;
      }
    }
  }
}
