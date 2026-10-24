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
    String? requestUrl,
    required List<int> prefix,
  }) {
    final htmlName = RegExp(r'\.html?$', caseSensitive: false);
    if (htmlName.hasMatch(fileName.trim()) ||
        htmlName.hasMatch(contentDispositionFileName?.trim() ?? '') ||
        htmlName.hasMatch(Uri.tryParse(requestUrl ?? '')?.path ?? '')) {
      return;
    }
    final type = mimeType?.split(';').first.trim().toLowerCase() ?? '';
    if (type.startsWith('text/') && type != 'text/html') return;
    final isHtml = RegExp(
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
