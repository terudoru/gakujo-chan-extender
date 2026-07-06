import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:test/test.dart';

void main() {
  test('resolves relative redirect locations against the current url', () {
    final finalUrl = resolveRedirectedDownloadUrl(
      Uri.parse('https://gakujo.iess.niigata-u.ac.jp/campusweb/start'),
      [Uri.parse('/campusweb/download/file.pdf')],
    );

    expect(
      finalUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/download/file.pdf',
    );
  });

  test('resolves chained relative redirects in order', () {
    final finalUrl = resolveRedirectedDownloadUrl(
      Uri.parse('https://gakujo.iess.niigata-u.ac.jp/campusweb/start'),
      [
        Uri.parse('step1'),
        Uri.parse('download/file.pdf'),
      ],
    );

    expect(
      finalUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/download/file.pdf',
    );
  });

  test('keeps the initial url when there are no redirects', () {
    final finalUrl = resolveRedirectedDownloadUrl(
      Uri.parse('https://gakujo.iess.niigata-u.ac.jp/campusweb/file.pdf'),
      const [],
    );

    expect(
      finalUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/file.pdf',
    );
  });
}
