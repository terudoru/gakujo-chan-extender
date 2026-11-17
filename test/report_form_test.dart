import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/report_form.dart';

void main() {
  test('release default keeps the report form disabled', () {
    expect(reportFormBaseUrl, isNull);
    expect(reportFormBaseUri, isNull);
  });

  test('builds bug and request URLs with only the three allowed parameters', () {
    for (final type in ReportType.values) {
      final uri = buildReportFormUri(
        baseUri: Uri.parse(
          'https://gakujo-report.terudoru.com/?token=private&user=123#private',
        ),
        type: type,
        version: '1.2.3+4 & preview',
        platform: TargetPlatform.windows,
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'gakujo-report.terudoru.com');
      expect(uri.path, '/');
      expect(uri.queryParameters, {
        'type': type.name,
        'version': '1.2.3+4 & preview',
        'platform': 'windows',
      });
      expect(uri.fragment, isEmpty);
      expect(uri.toString(), isNot(contains('private')));
    }
  });

  test('maps each running platform to a value accepted by the form', () {
    const platforms = {
      TargetPlatform.windows: 'windows',
      TargetPlatform.macOS: 'macos',
      TargetPlatform.linux: 'linux',
      TargetPlatform.android: 'android',
      TargetPlatform.iOS: 'ios',
      TargetPlatform.fuchsia: 'other',
    };
    for (final entry in platforms.entries) {
      final uri = buildReportFormUri(
        baseUri: Uri.https('gakujo-report.terudoru.com', '/'),
        type: ReportType.bug,
        version: '1.0.0',
        platform: entry.key,
      );
      expect(uri.queryParameters['platform'], entry.value);
    }
  });
}
