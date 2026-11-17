import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

import 'download_destination_settings.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_request.dart';

class GakujoDownloadResult {
  const GakujoDownloadResult({
    required this.fileName,
    required this.courseName,
    this.location,
    this.alreadySaved = false,
    this.uploadBytes,
    this.uploadSnapshot,
  });

  final String fileName;
  final String courseName;
  final String? location;
  final bool alreadySaved;
  final Uint8List? uploadBytes;
  final GakujoDownloadSnapshot? uploadSnapshot;

  GakujoDownloadResult withUploadBytes(Uint8List bytes) => GakujoDownloadResult(
    fileName: fileName,
    courseName: courseName,
    location: location,
    alreadySaved: alreadySaved,
    uploadBytes: bytes,
  );

  GakujoDownloadResult withUploadSnapshot(GakujoDownloadSnapshot snapshot) =>
      GakujoDownloadResult(
        fileName: fileName,
        courseName: courseName,
        location: location,
        alreadySaved: alreadySaved,
        uploadBytes: uploadBytes,
        uploadSnapshot: snapshot,
      );

  Future<GakujoDownloadResult> retainUpload(Stream<List<int>> bytes) async {
    try {
      return withUploadSnapshot(await GakujoDownloadSnapshot.capture(bytes));
    } on Object catch (error, stackTrace) {
      // The local file has already been saved; only the Drive copy failed.
      developer.log('Failed to keep a Google Drive upload snapshot',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      return this;
    }
  }

  factory GakujoDownloadResult.fromMap(Map<dynamic, dynamic>? raw) {
    final fileName = raw?['fileName']?.toString().trim() ?? '';
    if (raw == null || fileName.isEmpty) {
      throw PlatformException(
        code: 'cancelled',
        message: '保存をキャンセルしました',
      );
    }
    return GakujoDownloadResult(
      fileName: fileName,
      courseName: raw['courseName']?.toString() ?? '',
      location: raw['location']?.toString(),
      alreadySaved: raw['alreadySaved'] == true,
    );
  }
}

class GakujoDownloadSnapshot {
  GakujoDownloadSnapshot._(this._directory, this._file, this.length);

  final Directory _directory;
  final File _file;
  final int length;

  static Future<GakujoDownloadSnapshot> capture(Stream<List<int>> bytes) async {
    final directory = await Directory.systemTemp.createTemp('mbg-drive-');
    try {
      final file = File('${directory.path}/download');
      final output = await file.open(mode: FileMode.writeOnly);
      try {
        await for (final chunk in bytes) {
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      return GakujoDownloadSnapshot._(directory, file, await file.length());
    } on Object {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Stream<List<int>> openRead() => _file.openRead();

  Future<void> dispose() async {
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}

abstract class GakujoDownloadService {
  const GakujoDownloadService();

  Future<DownloadDestinationSettings> getDownloadRoot();

  Future<DownloadDestinationSettings> pickDownloadRoot();

  Future<DownloadDestinationSettings> clearDownloadRoot();

  Future<GakujoDownloadResult> download(
    GakujoDownloadRequest request, {
    String? userAgent,
    String? cookieHeader,
    Rect? sharePositionOrigin,
    required DownloadSaveMode saveMode,
    bool retainUploadSnapshot = false,
  });
}

class MethodChannelGakujoDownloadService extends GakujoDownloadService {
  const MethodChannelGakujoDownloadService();

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/downloads',
  );

  Future<int> contentUriSize(String uri) async {
    final size = await _channel.invokeMethod<int>('contentUriSize', {'uri': uri});
    if (size == null || size < 0) throw StateError('Content URI size unavailable');
    return size;
  }

  Stream<List<int>> openContentUri(String uri, int size) async* {
    const chunkSize = 8 * 1024 * 1024;
    var offset = 0;
    while (offset < size) {
      final length = size - offset < chunkSize ? size - offset : chunkSize;
      final bytes = await _channel.invokeMethod<Uint8List>(
        'readContentUriChunk',
        {'uri': uri, 'offset': offset, 'length': length},
      );
      if (bytes == null || bytes.length != length) {
        throw StateError('Content URI changed or returned incomplete data');
      }
      offset += bytes.length;
      yield bytes;
    }
  }

  @override
  Future<DownloadDestinationSettings> getDownloadRoot() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDownloadRoot',
      );
      return DownloadDestinationSettings.fromMap(raw);
    } on MissingPluginException {
      return const DownloadDestinationSettings(isConfigured: false);
    }
  }

  @override
  Future<DownloadDestinationSettings> pickDownloadRoot() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'pickDownloadRoot',
    );
    return DownloadDestinationSettings.fromMap(raw);
  }

  @override
  Future<DownloadDestinationSettings> clearDownloadRoot() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'clearDownloadRoot',
    );
    return DownloadDestinationSettings.fromMap(raw);
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
    final method = saveMode == DownloadSaveMode.flatWithPickerEachTime
        ? 'downloadToPickedFile'
        : 'downloadToConfiguredFolder';
    final arguments = request.toMethodChannelArguments(userAgent: userAgent)
      ..['autoSortByCourse'] = saveMode.autoSortByCourse;
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      method,
      arguments,
    );
    final result = GakujoDownloadResult.fromMap(raw);
    if (!retainUploadSnapshot) return result;
    Stream<List<int>> source() async* {
      final location = result.location!;
      final uri = Uri.tryParse(location);
      if (uri?.scheme == 'content') {
        yield* openContentUri(location, await contentUriSize(location));
      } else {
        yield* (uri?.scheme == 'file' ? File.fromUri(uri!) : File(location))
            .openRead();
      }
    }
    return result.retainUpload(source());
  }
}

class UnsupportedGakujoDownloadService extends GakujoDownloadService {
  const UnsupportedGakujoDownloadService(this.message);

  final String message;

  @override
  Future<DownloadDestinationSettings> getDownloadRoot() async {
    return const DownloadDestinationSettings(isConfigured: false);
  }

  @override
  Future<DownloadDestinationSettings> pickDownloadRoot() {
    throw PlatformException(
      code: 'unsupported_platform',
      message: message,
    );
  }

  @override
  Future<DownloadDestinationSettings> clearDownloadRoot() async {
    return const DownloadDestinationSettings(isConfigured: false);
  }

  @override
  Future<GakujoDownloadResult> download(
    GakujoDownloadRequest request, {
    String? userAgent,
    String? cookieHeader,
    Rect? sharePositionOrigin,
    required DownloadSaveMode saveMode,
    bool retainUploadSnapshot = false,
  }) {
    throw PlatformException(
      code: 'unsupported_platform',
      message: message,
    );
  }
}
