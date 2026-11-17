import 'package:flutter/foundation.dart';

// フォームの公開・動作確認後に https://gakujo-report.terudoru.com/ を設定（report_form/README.md）。
const String? reportFormBaseUrl = null;

Uri? get reportFormBaseUri {
  final url = reportFormBaseUrl;
  return url == null ? null : Uri.parse(url);
}

enum ReportType { bug, request }

Uri buildReportFormUri({
  required Uri baseUri,
  required ReportType type,
  required String version,
  required TargetPlatform platform,
}) => baseUri.replace(
  queryParameters: {
    'type': type.name,
    'version': version,
    'platform': switch (platform) {
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.fuchsia => 'other',
    },
  },
  fragment: '',
);
