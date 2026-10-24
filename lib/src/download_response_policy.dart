import 'dart:convert';

import 'package:flutter/services.dart';

class DownloadResponsePolicy {
  const DownloadResponsePolicy._();

  static const pageReturnedMessage =
      'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください';

  static void validate({
    required String fileName,
    String? mimeType,
    required List<int> prefix,
  }) {
    if (RegExp(r'\.html?$', caseSensitive: false).hasMatch(fileName.trim())) {
      return;
    }
    final isHtml = mimeType?.split(';').first.trim().toLowerCase() ==
            'text/html' ||
        RegExp(r'^[\s\uFEFF]*(?:<!doctype html|<html)', caseSensitive: false)
            .hasMatch(utf8.decode(prefix, allowMalformed: true));
    if (isHtml) {
      throw PlatformException(
        code: 'download_failed',
        message: pageReturnedMessage,
      );
    }
  }
}
