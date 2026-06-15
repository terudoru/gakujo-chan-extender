import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'download_destination_settings.dart';
import 'download_file_name_policy.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_request.dart';
import 'gakujo_download_service.dart';

class FileSystemGakujoDownloadService extends GakujoDownloadService {
  FileSystemGakujoDownloadService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _downloadRootPathKey =
      'more_better_gakujo_download_root_path';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<DownloadDestinationSettings> getDownloadRoot() async {
    final path = await _secureStorage.read(key: _downloadRootPathKey);
    return _settingsFromPath(path);
  }

  @override
  Future<DownloadDestinationSettings> pickDownloadRoot() async {
    final current = await getDownloadRoot();
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
    await _secureStorage.delete(key: _downloadRootPathKey);
    return const DownloadDestinationSettings(isConfigured: false);
  }

  @override
  Future<GakujoDownloadResult> download(
    GakujoDownloadRequest request, {
    String? userAgent,
    String? cookieHeader,
    required DownloadSaveMode saveMode,
  }) async {
    try {
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

      if (saveMode == DownloadSaveMode.flatWithPickerEachTime) {
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
        await File(location.path).writeAsBytes(downloaded.bytes);
        return GakujoDownloadResult(
          fileName: _baseName(location.path),
          courseName: '',
        );
      }

      final root = await _configuredRootDirectory();
      final parent = saveMode.autoSortByCourse
          ? await _ensureChildDirectory(
              root,
              DownloadFileNamePolicy.safeFolderName(request.courseName),
            )
          : root;
      final finalName = await _uniqueFileName(parent, fileName);
      await File(_join(parent.path, finalName)).writeAsBytes(downloaded.bytes);
      return GakujoDownloadResult(
        fileName: finalName,
        courseName: saveMode.autoSortByCourse ? _baseName(parent.path) : '',
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
    try {
      final httpRequest = await client.openUrl(method, uri);
      httpRequest.followRedirects = true;
      final normalizedUserAgent = userAgent?.trim();
      if (normalizedUserAgent != null && normalizedUserAgent.isNotEmpty) {
        httpRequest.headers.set(HttpHeaders.userAgentHeader, normalizedUserAgent);
      }
      final normalizedCookieHeader = cookieHeader?.trim();
      if (normalizedCookieHeader != null && normalizedCookieHeader.isNotEmpty) {
        httpRequest.headers.set(HttpHeaders.cookieHeader, normalizedCookieHeader);
      }

      if (method == 'POST') {
        final body = _encodeForm(request.formFields);
        httpRequest.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        httpRequest.add(utf8.encode(body));
      }

      final response = await httpRequest.close();
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw PlatformException(
          code: 'download_failed',
          message: 'ダウンロードに失敗しました HTTP ${response.statusCode}',
        );
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final disposition = response.headers.value(HttpHeaders.contentDisposition);
      return _DownloadedFile(
        bytes: builder.takeBytes(),
        finalUrl: response.redirects.isEmpty
            ? uri.toString()
            : response.redirects.last.location.toString(),
        mimeType: response.headers.contentType?.mimeType,
        contentDispositionFileName: _fileNameFromContentDisposition(disposition),
      );
    } finally {
      client.close(force: true);
    }
  }

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
    return getApplicationDocumentsDirectory().then((directory) => directory.path);
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

  Future<String> _uniqueFileName(Directory directory, String desiredName) async {
    final existing = await directory
        .list()
        .map((entity) => _baseName(entity.path))
        .toSet();
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

  static String? _fileNameFromContentDisposition(String? header) {
    if (header == null || header.trim().isEmpty) {
      return null;
    }

    final encodedMatch = RegExp(
      r'''filename\*=UTF-8''([^;]+)''',
      caseSensitive: false,
    ).firstMatch(header);
    if (encodedMatch != null) {
      return Uri.decodeComponent(encodedMatch.group(1) ?? '');
    }

    final quotedMatch = RegExp(
      r'''filename="?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(header);
    return quotedMatch?.group(1);
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
