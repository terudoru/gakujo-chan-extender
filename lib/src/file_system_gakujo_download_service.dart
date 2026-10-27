import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
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
    final file = _file;
    if (file != null) {
      await file.copy(path);
    } else {
      await File(path).writeAsBytes(_bytes!);
    }
  }

  Future<void> dispose() async => _cleanup?.call();
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

  @override
  Future<DownloadDestinationSettings> getDownloadRoot() async {
    if (_usesNativeDownloadRoot) {
      return _getNativeDownloadRoot();
    }

    final path = await _secureStorage.read(key: _downloadRootPathKey);
    return _settingsFromPath(path);
  }

  @override
  Future<DownloadDestinationSettings> pickDownloadRoot() async {
    final current = await getDownloadRoot();
    if (_usesNativeDownloadRoot) {
      final raw =
          await _nativeDownloadsChannel.invokeMethod<Map<dynamic, dynamic>>(
        'pickDownloadRoot',
      );
      return DownloadDestinationSettings.fromMap(raw);
    }

    final selected = await getDirectoryPath(
      initialDirectory: current.path ?? await _defaultDirectoryPath(),
      confirmButtonText: '保存先にする',
      canCreateDirectories: true,
    );
    if (selected == null || selected.trim().isEmpty) {
      return current;
    }

    await _secureStorage.write(
      key: _downloadRootPathKey,
      value: selected,
    );
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

    await _secureStorage.delete(key: _downloadRootPathKey);
    return const DownloadDestinationSettings(isConfigured: false);
  }

  @override
  Future<GakujoDownloadResult> download(
    GakujoDownloadRequest request, {
    String? userAgent,
    String? cookieHeader,
    Rect? sharePositionOrigin,
    required DownloadSaveMode saveMode,
  }) async {
    AuthenticatedDownloadedFile? downloaded;
    try {
      if (!AllowedWebOrigins.canLoad(request.url, debugAllowed: false)) {
        throw PlatformException(
          code: 'blocked_url',
          message: 'Gakujo以外のダウンロードをブロックしました',
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
      final courseFolderName = DownloadFileNamePolicy.courseFolderName(
        requestedCourseName: request.courseName,
        fileName: fileName,
      );

      if (saveMode == DownloadSaveMode.flatWithPickerEachTime) {
        if (Platform.isIOS) {
          return await _exportToNativePicker(
            bytes: await downloaded.readBytes(),
            fileName: fileName,
            mimeType: downloaded.mimeType,
          );
        }

        return await _saveToPickedFlutterFile(
          downloaded: downloaded,
          fileName: fileName,
        );
      }

      if (_usesNativeDownloadRoot) {
        return await _saveToNativeConfiguredFolder(
          bytes: await downloaded.readBytes(),
          fileName: fileName,
          courseFolderName: courseFolderName,
          mimeType: downloaded.mimeType,
          autoSortByCourse: saveMode.autoSortByCourse,
        );
      }

      return await _saveToConfiguredFlutterFolder(
        downloaded: downloaded,
        fileName: fileName,
        courseFolderName: courseFolderName,
        autoSortByCourse: saveMode.autoSortByCourse,
      );
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
    return GakujoDownloadResult.fromMap(raw);
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
    return GakujoDownloadResult.fromMap(raw);
  }

  Future<GakujoDownloadResult> _saveToPickedFlutterFile({
    required AuthenticatedDownloadedFile downloaded,
    required String fileName,
  }) async {
    final location = await getSaveLocation(
      initialDirectory: await _defaultDirectoryPath(),
      suggestedName: fileName,
      confirmButtonText: '保存',
      canCreateDirectories: true,
    );
    if (location == null) {
      throw PlatformException(
        code: 'cancelled',
        message: '保存をキャンセルしました',
      );
    }
    await downloaded.saveTo(location.path);
    return GakujoDownloadResult(
      fileName: _baseName(location.path),
      courseName: '',
      location: location.path,
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
    var uri = method == 'GET' && request.formFields.isNotEmpty
        ? Uri.parse(request.url).replace(
            queryParameters: {
              ...Uri.parse(request.url).queryParameters,
              ...request.formFields,
            },
          )
        : Uri.parse(request.url);

    final client = _httpClientFactory();
    client.connectionTimeout = _requestTimeout;
    try {
      for (var redirectCount = 0; redirectCount <= 10; redirectCount += 1) {
        if (!AllowedWebOrigins.canLoad(uri.toString(), debugAllowed: false)) {
          throw PlatformException(
            code: 'blocked_url',
            message: 'Gakujo以外へのリダイレクトをブロックしました',
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
          final body = _encodeForm(request.formFields);
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
              message: 'Gakujo以外へのリダイレクトをブロックしました',
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
            message: 'ダウンロードに失敗しました HTTP ${response.statusCode}',
          );
        }

        final finalUrl = resolveRedirectedDownloadUrl(
          uri,
          response.redirects.map((redirect) => redirect.location),
        );
        if (!AllowedWebOrigins.canLoad(finalUrl, debugAllowed: false)) {
          throw PlatformException(
            code: 'blocked_url',
            message: 'Gakujo以外へのリダイレクトをブロックしました',
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
          await sink.close();
          await directory.delete(recursive: true);
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
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return downloads.path;
    }
    return getApplicationDocumentsDirectory()
        .then((directory) => directory.path);
  }

  DownloadDestinationSettings _settingsFromPath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return const DownloadDestinationSettings(isConfigured: false);
    }
    final directory = Directory(path);
    return DownloadDestinationSettings(
      isConfigured: directory.existsSync(),
      displayName: _baseName(path),
      path: path,
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

  static String _encodeForm(Map<String, String> fields) {
    return fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
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
