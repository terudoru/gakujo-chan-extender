import 'dart:convert';

import 'package:flutter/services.dart';

class DownloadResponsePolicy {
  const DownloadResponsePolicy._();

  static const pageReturnedMessage =
      'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください';

  static void validate({
    required String fileName,
    String? contentDispositionFileName,
    String? mimeType,
    required List<int> prefix,
  }) {
    final htmlName = RegExp(r'\.html?$', caseSensitive: false);
    if (htmlName.hasMatch(fileName.trim()) ||
        htmlName.hasMatch(contentDispositionFileName?.trim() ?? '')) {
      return;
    }
    final type = mimeType?.split(';').first.trim().toLowerCase() ?? '';
    final isHtml = const {
          '',
          'text/html',
          'application/xhtml+xml',
          'application/octet-stream',
        }.contains(type) &&
        RegExp(
          r'^(?:\xEF\xBB\xBF)?[\x09-\x0D\x20]*(?:<!doctype html|<html)[\x09-\x0D\x20/>]',
          caseSensitive: false,
        ).hasMatch(latin1.decode(prefix));
    if (isHtml) {
      throw PlatformException(
        code: 'download_failed',
        message: pageReturnedMessage,
      );
    }
  }
}
