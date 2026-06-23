import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'allowed_web_origins.dart';
import 'download_destination_settings.dart';
import 'download_file_name_policy.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_request.dart';
import 'gakujo_download_service.dart';
import 'secure_storage_factory.dart';

class FileSystemGakujoDownloadService extends GakujoDownloadService {
  FileSystemGakujoDownloadService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageFactory.create();

  static const _downloadRootPathKey = 'more_better_gakujo_download_root_path';
  static const _nativeDownloadsChannel = MethodChannel(
    'net.yoshida.morebettergakujo/downloads',
  );

  final FlutterSecureStorage _secureStorage;

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
    try {
      if (!AllowedWebOrigins.canLoad(request.url, debugAllowed: false)) {
        throw PlatformException(
          code: 'blocked_url',
          message: 'Gakujo以外のダウンロードをブロックしました',
        );
      }

      final downloaded = await _downloadBytes(
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
      final courseFolderName = DownloadFileNamePolicy.courseFolderName(
        requestedCourseName: request.courseName,
        fileName: fileName,
      );

      if (saveMode == DownloadSaveMode.flatWithPickerEachTime) {
        if (Platform.isIOS) {
          return _exportToNativePicker(
            bytes: downloaded.bytes,
            fileName: fileName,
            mimeType: downloaded.mimeType,
          );
        }

        return _saveToPickedFlutterFile(
          bytes: downloaded.bytes,
          fileName: fileName,
        );
      }

      if (_usesNativeDownloadRoot) {
        return _saveToNativeConfiguredFolder(
          bytes: downloaded.bytes,
          fileName: fileName,
          courseFolderName: courseFolderName,
          mimeType: downloaded.mimeType,
          autoSortByCourse: saveMode.autoSortByCourse,
        );
      }

      return _saveToConfiguredFlutterFolder(
        bytes: downloaded.bytes,
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
    required Uint8List bytes,
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
    await File(location.path).writeAsBytes(bytes);
    return GakujoDownloadResult(
      fileName: _baseName(location.path),
      courseName: '',
    );
  }

  Future<GakujoDownloadResult> _saveToConfiguredFlutterFolder({
    required Uint8List bytes,
    required String fileName,
    required String courseFolderName,
    required bool autoSortByCourse,
  }) async {
    final root = await _configuredRootDirectory();
    final parent = autoSortByCourse
        ? await _ensureChildDirectory(root, courseFolderName)
        : root;
    final finalName = await _uniqueFileName(parent, fileName);
    await _writeFile(parent, finalName, bytes);
    return GakujoDownloadResult(
      fileName: finalName,
      courseName: autoSortByCourse ? _baseName(parent.path) : '',
    );
  }

  Future<_DownloadedFile> _downloadBytes(
    GakujoDownloadRequest request, {
    String? userAgent,
    String? cookieHeader,
  }) async {
    final method = request.method.toUpperCase() == 'POST' ? 'POST' : 'GET';
    final uri = method == 'GET' && request.formFields.isNotEmpty
        ? Uri.parse(request.url).replace(
            queryParameters: {
              ...Uri.parse(request.url).queryParameters,
              ...request.formFields,
            },
          )
        : Uri.parse(request.url);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final httpRequest = await client.openUrl(method, uri);
      httpRequest.followRedirects = true;
      httpRequest.headers.set(HttpHeaders.acceptHeader, '*/*');
      final normalizedUserAgent = userAgent?.trim();
      if (normalizedUserAgent != null && normalizedUserAgent.isNotEmpty) {
        httpRequest.headers
            .set(HttpHeaders.userAgentHeader, normalizedUserAgent);
      }
      final normalizedCookieHeader = cookieHeader?.trim();
      if (normalizedCookieHeader != null && normalizedCookieHeader.isNotEmpty) {
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

      final response = await httpRequest.close().timeout(
            const Duration(seconds: 30),
          );
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw PlatformException(
          code: 'download_failed',
          message: 'ダウンロードに失敗しました HTTP ${response.statusCode}',
        );
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(
        const Duration(seconds: 60),
      )) {
        builder.add(chunk);
      }
      final disposition =
          response.headers.value(HttpHeaders.contentDisposition);
      return _DownloadedFile(
        bytes: builder.takeBytes(),
        finalUrl: response.redirects.isEmpty
            ? uri.toString()
            : response.redirects.last.location.toString(),
        mimeType: response.headers.contentType?.mimeType,
        contentDispositionFileName:
            DownloadFileNamePolicy.fileNameFromContentDisposition(disposition),
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

  bool get _usesNativeDownloadRoot => Platform.isIOS || Platform.isMacOS;

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

  Future<File> _writeFile(
    Directory directory,
    String fileName,
    Uint8List bytes,
  ) async {
    return File(_join(directory.path, fileName)).writeAsBytes(bytes);
  }

  Future<String> _uniqueFileName(
      Directory directory, String desiredName) async {
    final existing =
        await directory.list().map((entity) => _baseName(entity.path)).toSet();
    return DownloadFileNamePolicy.uniqueName(desiredName, existing);
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

class _DownloadedFile {
  const _DownloadedFile({
    required this.bytes,
    required this.finalUrl,
    required this.mimeType,
    required this.contentDispositionFileName,
  });

  final Uint8List bytes;
  final String finalUrl;
  final String? mimeType;
  final String? contentDispositionFileName;
}
