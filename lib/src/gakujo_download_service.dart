import 'package:flutter/services.dart';

import 'download_destination_settings.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_request.dart';

class GakujoDownloadResult {
  const GakujoDownloadResult({
    required this.fileName,
    required this.courseName,
  });

  final String fileName;
  final String courseName;

  factory GakujoDownloadResult.fromMap(Map<dynamic, dynamic>? raw) {
    return GakujoDownloadResult(
      fileName: raw?['fileName']?.toString() ?? '',
      courseName: raw?['courseName']?.toString() ?? '',
    );
  }
}

class GakujoDownloadService {
  const GakujoDownloadService();

  static const _channel = MethodChannel(
    'net.yoshida.morebettergakujo/downloads',
  );

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

  Future<DownloadDestinationSettings> pickDownloadRoot() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'pickDownloadRoot',
    );
    return DownloadDestinationSettings.fromMap(raw);
  }

  Future<DownloadDestinationSettings> clearDownloadRoot() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'clearDownloadRoot',
    );
    return DownloadDestinationSettings.fromMap(raw);
  }

  Future<GakujoDownloadResult> download(
    GakujoDownloadRequest request, {
    String? userAgent,
    required DownloadSaveMode saveMode,
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
    return GakujoDownloadResult.fromMap(raw);
  }
}
