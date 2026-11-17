import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'allowed_web_origins.dart';
import 'download_destination_settings.dart';
import 'download_file_name_policy.dart';
import 'download_response_policy.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_history_store.dart';
import 'gakujo_download_request.dart';
import 'gakujo_download_service.dart';
import 'secure_storage_factory.dart';

typedef AuthenticatedDownloadBytesLoader = Future<AuthenticatedDownloadedFile>
    Function(
  GakujoDownloadRequest request, {
  String? userAgent,
});

class AuthenticatedDownloadedFile {
  const AuthenticatedDownloadedFile({
    required Uint8List this._bytes,
    required this.finalUrl,
    this.mimeType,
    this.contentDispositionFileName,
  })  : _file = null,
        _cleanup = null;

  /// Transfers ownership of a completed temporary file to the save operation.
  const AuthenticatedDownloadedFile.fromFile({
    required File this._file,
    required Future<void> Function() this._cleanup,
    required this.finalUrl,
    this.mimeType,
    this.contentDispositionFileName,
  })  : _bytes = null;

  final Uint8List? _bytes;
  final File? _file;
  final Future<void> Function()? _cleanup;
  final String finalUrl;
  final String? mimeType;
  final String? contentDispositionFileName;

  Future<Uint8List> readBytes() async => _bytes ?? await _file!.readAsBytes();

  Future<void> validateResponse(String fileName,
      {required String requestUrl}) async {
    Stream<List<int>> chunks() async* {
      final bytes = _bytes;
      if (bytes == null) {
        yield* _file!.openRead();
      } else {
        for (var start = 0; start < bytes.length; start += 1024) {
          final end = start + 1024 < bytes.length ? start + 1024 : bytes.length;
          yield Uint8List.sublistView(bytes, start, end);
        }
      }
    }

    final prefix = BytesBuilder(copy: false);
    await for (final chunk in chunks()) {
      final remaining = 1024 - prefix.length;
      prefix
          .add(chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
      if (prefix.length == 1024) break;
    }
    DownloadResponsePolicy.validate(
      fileName: fileName,
      contentDispositionFileName: contentDispositionFileName,
      mimeType: mimeType,
      requestUrl: requestUrl,
      prefix: prefix.takeBytes(),
    );
  }

  Future<void> saveTo(String path) async {
    await writeDownloadFileAtomically(path, openRead());
  }

  Stream<List<int>> openRead() => _file?.openRead() ?? Stream.value(_bytes!);

  Future<void> dispose() async => _cleanup?.call();
}

@visibleForTesting
Future<void> writeDownloadFileAtomically(
  String path,
  Stream<List<int>> bytes,
) async {
  final parent = File(path).parent;
  final random = Random.secure();
  final suffix = List.generate(4, (_) => random.nextInt(1 << 32).toRadixString(16))
      .join();
  final temporary = File('${parent.path}/.mbg-download-$suffix.tmp');
  await temporary.create(exclusive: true);
  try {
    final output = await temporary.open(mode: FileMode.writeOnly);
    try {
      await for (final chunk in bytes) {
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    // Dart uses a replacing rename on Windows as well as Unix.
    await temporary.rename(path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

@visibleForTesting
Future<String?> linuxDownloadInitialDirectory({
  required Future<Directory?> Function() downloadsDirectory,
  required String? homeDirectory,
}) async {
  try {
    final downloads = await downloadsDirectory();
    if (downloads != null) return downloads.path;
  } on Object {
    // An optional initial folder must not prevent the chooser from opening.
  }
  if (homeDirectory != null &&
      homeDirectory.isNotEmpty &&
      Directory(homeDirectory).existsSync()) {
    return homeDirectory;
  }
  return null;
}

class FileSystemGakujoDownloadService extends GakujoDownloadService {
  FileSystemGakujoDownloadService({
    FlutterSecureStorage? secureStorage,
    this._authenticatedBytesLoader,
    HttpClient Function()? httpClientFactory,
    @visibleForTesting this._requestTimeout = const Duration(seconds: 30),
    @visibleForTesting bool? usesNativeDownloadRoot,
  })  : _secureStorage = secureStorage ?? SecureStorageFactory.create(),
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _usesNativeDownloadRootOverride = usesNativeDownloadRoot;

  static const _downloadRootPathKey = 'more_better_gakujo_download_root_path';
  static const _nativeDownloadsChannel = MethodChannel(
    'net.yoshida.morebettergakujo/downloads',
  );

  final FlutterSecureStorage _secureStorage;
  final AuthenticatedDownloadBytesLoader? _authenticatedBytesLoader;
  final HttpClient Function() _httpClientFactory;
  final Duration _requestTimeout;
  final bool? _usesNativeDownloadRootOverride;
  Future<void> _pendingConfiguredFolderSave = Future<void>.value();
  bool _linuxRootSessionOnly = false;
  String? _linuxSessionRootPath;
  int _linuxRootRevision = 0;
  static const _linuxRootReadTimeout = Duration(seconds: 3);

  @override
  Future<DownloadDestinationSettings> getDownloadRoot() async {
    if (_usesNativeDownloadRoot) {
      return _getNativeDownloadRoot();
    }

    if (_linuxRootSessionOnly) {
      return _settingsFromPath(_linuxSessionRootPath);
    }
    final revision = _linuxRootRevision;
    final path = await _secureStorage.read(key: _downloadRootPathKey);
    // A late read must not replace a folder already chosen for this session.
    if (!_linuxRootSessionOnly && revision == _linuxRootRevision) {
      _linuxSessionRootPath = path;
    }
    return _settingsFromPath(_linuxSessionRootPath);
  }

  @override
  Future<DownloadDestinationSettings> pickDownloadRoot() async {
    if (_usesNativeDownloadRoot) {
      await getDownloadRoot();
      final raw =
          await _nativeDownloadsChannel.invokeMethod<Map<dynamic, dynamic>>(
        'pickDownloadRoot',
      );
      return DownloadDestinationSettings.fromMap(raw);
    }

    DownloadDestinationSettings current;
    if (defaultTargetPlatform == TargetPlatform.linux) {
      try {
        // Reopening the gate can wait forever without an unlock prompter.
        current = await getDownloadRoot().timeout(_linuxRootReadTimeout);
      } on PlatformException catch (error) {
        if (error.code != 'KeyringLocked') rethrow;
        _linuxRootSessionOnly = true;
        current = _settingsFromPath(_linuxSessionRootPath);
      } on TimeoutException {
        current = _settingsFromPath(_linuxSessionRootPath);
      }
    } else {
      current = await getDownloadRoot();
    }
    final initialDirectory = current.path ?? await _defaultDirectoryPath();
    final selected = defaultTargetPlatform == TargetPlatform.linux
        ? await const MethodChannel('net.yoshida.morebettergakujo/window')
              .invokeMethod<String>('pickDownloadDirectory', {
                'initialDirectory': initialDirectory,
              })
        : await getDirectoryPath(
            initialDirectory: initialDirectory,
            confirmButtonText: '保存先にする',
            canCreateDirectories: true,
          );
    if (selected == null || selected.trim().isEmpty) {
      return current;
    }

    await _saveDownloadRoot(selected);
    return _settingsFromPath(selected);
  }

  @override
  Future<DownloadDestinationSettings> clearDownloadRoot() async {
    if (_usesNativeDownloadRoot) {
      final raw =
          await _nativeDownloadsChannel.invokeMethod<Map<dynamic, dynamic>>(
        'clearDownloadRoot',
      );
      return DownloadDestinationSettings.fromMap(raw);
    }

    await _saveDownloadRoot(null);
    return _settingsFromPath(null);
  }

  Future<void> _saveDownloadRoot(String? path) async {
    Future<void> save() => path == null
        ? _secureStorage.delete(key: _downloadRootPathKey)
        : _secureStorage.write(key: _downloadRootPathKey, value: path);
    if (defaultTargetPlatform != TargetPlatform.linux) {
      await save();
      return;
    }
    _linuxRootRevision++;
    _linuxSessionRootPath = path;
    if (_linuxRootSessionOnly) return;
    try {
      await save();
    } on PlatformException catch (error) {
      if (error.code != 'KeyringLocked') rethrow;
      _linuxRootSessionOnly = true;
    }
  }

  @override
  Future<GakujoDownloadResult> download(
    GakujoDownloadRequest request, {
    String? userAgent,
    String? cookieHeader,
    Rect? sharePositionOrigin,
    required DownloadSaveMode saveMode,
    bool retainUploadSnapshot = false,
  }) async {
    AuthenticatedDownloadedFile? downloaded;
    try {
      if (!AllowedWebOrigins.canLoad(request.url, debugAllowed: false)) {
        throw PlatformException(
          code: 'blocked_url',
          message: '学務情報システム以外のダウンロードをブロックしました',
        );
      }

      downloaded = await _downloadBytes(
        request,
        userAgent: userAgent,
        cookieHeader: cookieHeader,
      );
      final fileName = DownloadFileNamePolicy.safeFileName(
        preferredName: request.fileName,
        contentDispositionName: downloaded.contentDispositionFileName,
        url: downloaded.finalUrl,
        mimeType: downloaded.mimeType,
      );
      // Judge by the name the student asked for: the derived name can take
      // .html from the page's own Content-Type and slip past the check.
      await downloaded.validateResponse(request.fileName,
          requestUrl: request.url);
      // Prefer a page course, then history matches, then filename heuristics.
      var courseFolderName = DownloadFileNamePolicy.courseFolderName(
        requestedCourseName: request.courseName,
        fileName: '',
        courseNameAmbiguous: request.courseNameAmbiguous,
      );
      if (!request.courseNameAmbiguous &&
          courseFolderName == DownloadFileNamePolicy.unknownCourseFolderName) {
        var knownCourseNames = <String>[];
        if (saveMode.autoSortByCourse) {
          try {
            final history = await GakujoDownloadHistoryStore(
              secureStorage: _secureStorage,
            ).load().timeout(const Duration(seconds: 3));
            knownCourseNames = history.map((entry) => entry.courseName).toList();
          } on Object {
            // Optional course hints must not stop a save when storage is unavailable.
          }
        }
        courseFolderName = DownloadFileNamePolicy.courseFolderName(
          requestedCourseName: request.courseName,
          fileName: fileName,
          knownCourseNames: knownCourseNames,
        );
      }

      final GakujoDownloadResult result;
      if (saveMode == DownloadSaveMode.flatWithPickerEachTime) {
        if (Platform.isIOS) {
          result = await _exportToNativePicker(
            bytes: await downloaded.readBytes(),
            fileName: fileName,
            mimeType: downloaded.mimeType,
          );
        } else {
          result = await _saveToPickedFlutterFile(
            downloaded: downloaded,
            fileName: fileName,
          );
        }
      } else if (_usesNativeDownloadRoot) {
        result = await _saveToNativeConfiguredFolder(
          bytes: await downloaded.readBytes(),
          fileName: fileName,
          courseFolderName: courseFolderName,
          mimeType: downloaded.mimeType,
          autoSortByCourse: saveMode.autoSortByCourse,
        );
      } else {
        result = await _saveToConfiguredFlutterFolder(
          downloaded: downloaded,
          fileName: fileName,
          courseFolderName: courseFolderName,
          autoSortByCourse: saveMode.autoSortByCourse,
        );
      }
      if (!retainUploadSnapshot || result.uploadBytes != null) return result;
      return await result.retainUpload(downloaded.openRead());
    } on PlatformException {
      rethrow;
    } on Object catch (error) {
      throw PlatformException(
        code: 'download_failed',
        message: '保存できませんでした: $error',
      );
    } finally {
      try {
        await downloaded?.dispose();
      } on Object catch (error, stackTrace) {
        developer.log('Failed to remove a temporary download',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
    }
  }

  Future<GakujoDownloadResult> _exportToNativePicker({
    required Uint8List bytes,
    required String fileName,
    required String? mimeType,
  }) async {
    final raw =
        await _nativeDownloadsChannel.invokeMethod<Map<dynamic, dynamic>>(
      'exportDownloadedFile',
      {
        'bytes': bytes,
        'fileName': fileName,
        'mimeType': mimeType ?? 'application/octet-stream',
      },
    );
    return GakujoDownloadResult.fromMap(raw).withUploadBytes(bytes);
  }

  Future<GakujoDownloadResult> _saveToNativeConfiguredFolder({
    required Uint8List bytes,
    required String fileName,
    required String courseFolderName,
    required String? mimeType,
    required bool autoSortByCourse,
  }) async {
    final raw =
        await _nativeDownloadsChannel.invokeMethod<Map<dynamic, dynamic>>(
      'saveDownloadedFileToConfiguredFolder',
      {
        'bytes': bytes,
        'fileName': fileName,
        'courseName': courseFolderName,
        'mimeType': mimeType ?? 'application/octet-stream',
        'autoSortByCourse': autoSortByCourse,
      },
    );
    return GakujoDownloadResult.fromMap(raw).withUploadBytes(bytes);
  }

  Future<GakujoDownloadResult> _saveToPickedFlutterFile({
    required AuthenticatedDownloadedFile downloaded,
    required String fileName,
  }) async {
    final initialDirectory = await _defaultDirectoryPath();
    final path = defaultTargetPlatform == TargetPlatform.linux
        ? await const MethodChannel('net.yoshida.morebettergakujo/window')
              .invokeMethod<String>('pickSaveFile', {
                'initialDirectory': initialDirectory,
                'suggestedName': fileName,
              })
        : (await getSaveLocation(
            initialDirectory: initialDirectory,
            suggestedName: fileName,
            confirmButtonText: '保存',
            canCreateDirectories: true,
          ))?.path;
    if (path == null) {
      throw PlatformException(
        code: 'cancelled',
        message: '保存をキャンセルしました',
      );
    }
    await downloaded.saveTo(path);
    return GakujoDownloadResult(
      fileName: _baseName(path),
      courseName: '',
      location: path,
    );
  }

  Future<GakujoDownloadResult> _saveToConfiguredFlutterFolder({
    required AuthenticatedDownloadedFile downloaded,
    required String fileName,
    required String courseFolderName,
    required bool autoSortByCourse,
  }) {
    return _enqueueConfiguredFolderSave(() async {
      final root = await _configuredRootDirectory();
      final parent = autoSortByCourse
          ? await _ensureChildDirectory(root, courseFolderName)
          : root;
      final reservedFile = await _reserveUniqueFile(parent, fileName);
      try {
        await downloaded.saveTo(reservedFile.path);
      } on Object {
        try {
          await reservedFile.delete();
        } on Object catch (error, stackTrace) {
          developer.log(
            'Failed to remove a reserved download file',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
        }
        rethrow;
      }
      final existingFile = await _findIdenticalDownload(
        parent,
        fileName,
        reservedFile,
      );
      if (existingFile != null) {
        await reservedFile.delete();
      }
      final savedFile = existingFile ?? reservedFile;
      final finalName = _baseName(savedFile.path);
      return GakujoDownloadResult(
        fileName: finalName,
        courseName: autoSortByCourse ? _baseName(parent.path) : '',
        location: savedFile.path,
        alreadySaved: existingFile != null,
      );
    });
  }

  Future<T> _enqueueConfiguredFolderSave<T>(Future<T> Function() operation) {
    final next = _pendingConfiguredFolderSave.then((_) => operation());
    _pendingConfiguredFolderSave = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<AuthenticatedDownloadedFile> _downloadBytes(
    GakujoDownloadRequest request, {
    String? userAgent,
    String? cookieHeader,
  }) async {
    final normalizedCookieHeader = cookieHeader?.trim();
    final authenticatedBytesLoader = _authenticatedBytesLoader;
    // A JavaScript cookie header can omit HttpOnly session cookies. When an
    // authenticated WebView loader is available, it is the authoritative path.
    if (authenticatedBytesLoader != null) {
      return authenticatedBytesLoader(
        request,
        userAgent: userAgent,
      );
    }

    var method = request.method.toUpperCase() == 'POST' ? 'POST' : 'GET';
    var uri = Uri.parse(request.url);
    final fields = request.orderedFormFields;
    if (method == 'GET' && fields.isNotEmpty) {
      final names = fields.map((field) => field[0]).toSet();
      uri = uri.replace(query: _encodeForm([
        for (final entry in uri.queryParametersAll.entries)
          if (!names.contains(entry.key))
            for (final value in entry.value) [entry.key, value],
        ...fields,
      ]));
    }

    final client = _httpClientFactory();
    client.connectionTimeout = _requestTimeout;
    try {
      for (var redirectCount = 0; redirectCount <= 10; redirectCount += 1) {
        if (!AllowedWebOrigins.canLoad(uri.toString(), debugAllowed: false)) {
          throw PlatformException(
            code: 'blocked_url',
            message: '学務情報システム以外へのリダイレクトをブロックしました',
          );
        }

        final httpRequest =
            await client.openUrl(method, uri).timeout(_requestTimeout);
        httpRequest.followRedirects = false;
        httpRequest.headers.set(HttpHeaders.acceptHeader, '*/*');
        final normalizedUserAgent = userAgent?.trim();
        if (normalizedUserAgent != null && normalizedUserAgent.isNotEmpty) {
          httpRequest.headers
              .set(HttpHeaders.userAgentHeader, normalizedUserAgent);
        }
        if (normalizedCookieHeader != null &&
            normalizedCookieHeader.isNotEmpty) {
          httpRequest.headers
              .set(HttpHeaders.cookieHeader, normalizedCookieHeader);
        }

        if (method == 'POST') {
          final body = _encodeForm(fields);
          final encodedBody = utf8.encode(body);
          httpRequest.headers
              .set(HttpHeaders.contentLengthHeader, encodedBody.length);
          httpRequest.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
            charset: 'utf-8',
          );
          httpRequest.add(encodedBody);
        }

        final response = await httpRequest.close().timeout(_requestTimeout);
        final redirectLocation =
            response.headers.value(HttpHeaders.locationHeader);
        if (_isRedirectStatus(response.statusCode) &&
            redirectLocation != null &&
            redirectLocation.trim().isNotEmpty) {
          final nextUri = uri.resolve(redirectLocation);
          if (!AllowedWebOrigins.canLoad(
            nextUri.toString(),
            debugAllowed: false,
          )) {
            throw PlatformException(
              code: 'blocked_url',
              message: '学務情報システム以外へのリダイレクトをブロックしました',
            );
          }
          await response.drain<void>().timeout(_requestTimeout);
          uri = nextUri;
          if (response.statusCode == 303 ||
              ((response.statusCode == 301 || response.statusCode == 302) &&
                  method == 'POST')) {
            method = 'GET';
          }
          continue;
        }
        if (response.statusCode < 200 || response.statusCode > 299) {
          throw PlatformException(
            code: 'download_failed',
            message: 'ダウンロードに失敗しました（HTTP ${response.statusCode}）',
          );
        }

        final finalUrl = resolveRedirectedDownloadUrl(
          uri,
          response.redirects.map((redirect) => redirect.location),
        );
        if (!AllowedWebOrigins.canLoad(finalUrl, debugAllowed: false)) {
          throw PlatformException(
            code: 'blocked_url',
            message: '学務情報システム以外へのリダイレクトをブロックしました',
          );
        }

        if (response.contentLength > maxGakujoDownloadBytes) {
          throw PlatformException(code: 'download_too_large', message: 'ダウンロードが大きすぎます');
        }
        final directory = await Directory.systemTemp.createTemp('mbg_download_');
        final file = File('${directory.path}${Platform.pathSeparator}download');
        final sink = file.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.timeout(const Duration(seconds: 60))) {
            received += chunk.length;
            if (received > maxGakujoDownloadBytes) {
              throw PlatformException(code: 'download_too_large', message: 'ダウンロードが大きすぎます');
            }
            sink.add(chunk);
            await sink.flush();
          }
          await sink.close();
        } on Object {
          try {
            await sink.close();
          } on Object {
            // The write has already failed.
          }
          try {
            await directory.delete(recursive: true);
          } on Object {
            // Preserve the original failure if cleanup also fails.
          }
          rethrow;
        }
        final disposition =
            response.headers.value(HttpHeaders.contentDisposition);
        return AuthenticatedDownloadedFile.fromFile(
          file: file,
          cleanup: () => directory.delete(recursive: true),
          finalUrl: finalUrl,
          mimeType: response.headers.contentType?.mimeType,
          contentDispositionFileName:
              DownloadFileNamePolicy.fileNameFromContentDisposition(
                  disposition),
        );
      }
      throw PlatformException(
        code: 'download_failed',
        message: 'リダイレクトが多すぎます',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<DownloadDestinationSettings> _getNativeDownloadRoot() async {
    try {
      final raw =
          await _nativeDownloadsChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getDownloadRoot',
      );
      return DownloadDestinationSettings.fromMap(raw);
    } on MissingPluginException {
      return const DownloadDestinationSettings(isConfigured: false);
    }
  }

  bool get _usesNativeDownloadRoot =>
      _usesNativeDownloadRootOverride ?? (Platform.isIOS || Platform.isMacOS);

  Future<Directory> _configuredRootDirectory() async {
    final settings = await getDownloadRoot();
    final path = settings.path;
    if (!settings.isConfigured || path == null || path.isEmpty) {
      throw PlatformException(
        code: 'missing_root',
        message: 'ダウンロード保存先が未設定です',
      );
    }
    return Directory(path)..createSync(recursive: true);
  }

  Future<String?> _defaultDirectoryPath() async {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return linuxDownloadInitialDirectory(
        downloadsDirectory: getDownloadsDirectory,
        homeDirectory: Platform.environment['HOME'],
      );
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return downloads.path;
    }
    return getApplicationDocumentsDirectory()
        .then((directory) => directory.path);
  }

  DownloadDestinationSettings _settingsFromPath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return DownloadDestinationSettings(
        isConfigured: false,
        isSessionOnly: _linuxRootSessionOnly,
      );
    }
    final directory = Directory(path);
    return DownloadDestinationSettings(
      isConfigured: directory.existsSync(),
      displayName: _baseName(path),
      path: path,
      isSessionOnly: _linuxRootSessionOnly,
    );
  }

  Future<Directory> _ensureChildDirectory(Directory root, String name) async {
    final directory = Directory(_join(root.path, name));
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _reserveUniqueFile(
      Directory directory, String desiredName) async {
    final listedNames =
        await directory.list().map((entity) => _baseName(entity.path)).toSet();
    final namesAlreadyTried = <String>{};
    for (var attempt = 0; attempt < 1000; attempt += 1) {
      final candidateName = DownloadFileNamePolicy.uniqueName(
        desiredName,
        {...listedNames, ...namesAlreadyTried},
      );
      final candidate = File(_join(directory.path, candidateName));
      try {
        await candidate.create(exclusive: true);
        return candidate;
      } on PathExistsException {
        namesAlreadyTried.add(candidateName);
      }
    }
    throw FileSystemException(
      'Could not reserve a unique download file after 1000 attempts',
      directory.path,
    );
  }

  Future<File?> _findIdenticalDownload(
    Directory directory,
    String desiredName,
    File newFile,
  ) async {
    final candidateNames = {
      desiredName.toLowerCase(),
      for (var index = 1; index <= 999; index += 1)
        DownloadFileNamePolicy.numberedName(desiredName, index).toLowerCase(),
    };
    final size = await newFile.length();
    await for (final entity in directory.list(followLinks: false)) {
      final existingName = _baseName(entity.path);
      // Files saved before names were bounded keep their longer name.
      if (entity is! File ||
          entity.path == newFile.path ||
          !(candidateNames.contains(existingName.toLowerCase()) ||
              candidateNames.contains(DownloadFileNamePolicy.boundedName(
                existingName,
              ).toLowerCase()))) {
        continue;
      }
      try {
        if (await entity.length() == size &&
            await _filesHaveSameContent(newFile, entity)) {
          return entity;
        }
      } on FileSystemException catch (error, stackTrace) {
        // An unreadable or disappearing candidate cannot prove a duplicate.
        developer.log('Failed to compare a saved download',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
    }
    return null;
  }

  Future<bool> _filesHaveSameContent(File firstFile, File secondFile) async {
    final first = await firstFile.open();
    try {
      final second = await secondFile.open();
      try {
        final buffer = Uint8List(64 * 1024);
        while (true) {
          final chunk = await first.read(buffer.length);
          if (chunk.isEmpty) {
            return await second.readByte() == -1;
          }
          var offset = 0;
          while (offset < chunk.length) {
            final count = await second.readInto(buffer, offset, chunk.length);
            if (count == 0) {
              return false;
            }
            offset += count;
          }
          for (var index = 0; index < chunk.length; index += 1) {
            if (chunk[index] != buffer[index]) {
              return false;
            }
          }
        }
      } finally {
        await second.close();
      }
    } finally {
      await first.close();
    }
  }

  static String _encodeForm(List<List<String>> fields) {
    return fields
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry[0])}=${Uri.encodeQueryComponent(entry[1])}',
        )
        .join('&');
  }

  static String _join(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final index = trimmed.lastIndexOf('/');
    return index < 0 ? trimmed : trimmed.substring(index + 1);
  }
}

@visibleForTesting
String resolveRedirectedDownloadUrl(Uri initialUri, Iterable<Uri> redirects) {
  var current = initialUri;
  for (final redirect in redirects) {
    current = current.resolveUri(redirect);
  }
  return current.toString();
}

bool _isRedirectStatus(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}
