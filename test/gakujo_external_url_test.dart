import 'package:morebettergakujo_flutter/src/gakujo_external_url.dart';
import 'package:test/test.dart';

void main() {
  for (final url in [
    'https://www.youtube.com/watch?v=90EsN7f8x8A',
    'https://docs.google.com/forms/d/e/form-id/viewform'
        '?usp=pp_url&entry.123=first%20answer&entry.123=second&embedded=true',
  ]) {
    test('Copy URL preserves the full external query: $url', () {
      expect(sanitizeGakujoCopyUrl(url), url);
      expect(Uri.parse(sanitizeGakujoExternalUrl(url)).query, isEmpty);
      expect(
        sanitizeGakujoExternalEntry({'url': url})['url'],
        sanitizeGakujoExternalUrl(url),
      );
      expect(
        sanitizeGakujoNotificationKey('deadline|$url|due'),
        'deadline|${sanitizeGakujoExternalUrl(url)}|due',
      );
    });
  }

  for (final tabId in ['en', 'sch', 'kj', 'si', 'sd', 'sy']) {
    test('Copy URL and exports preserve portal tab $tabId', () {
      final url =
          'https://gakujo.iess.niigata-u.ac.jp/'
          'campusweb/campusportal.do?page=main&tabId=$tabId';
      expect(sanitizeGakujoCopyUrl(url), url);
      expect(sanitizeGakujoExternalUrl(url), url);
    });
  }

  test('Copy URL still removes Gakujo session data', () {
    const url =
        'https://gakujo.iess.niigata-u.ac.jp/'
        'campusweb%3BJSESSIONID%3Dsecret-path/campussquare.do'
        '?_flowId=KJW0001100-flow&seqNo=42&_flowExecutionKey=e1s1'
        '&jsessionid=secret-query&token=secret-token';
    expect(
      sanitizeGakujoCopyUrl(url),
      'https://gakujo.iess.niigata-u.ac.jp/'
      'campusweb/campussquare.do?_flowId=KJW0001100-flow&seqNo=42',
    );
  });

  test('Copy URL strips session path parameters on external pages', () {
    for (final session in [';jsessionid=secret', '%3BJSESSIONID%3Dsecret']) {
      expect(
        sanitizeGakujoCopyUrl(
          'https://www.youtube.com/watch$session?v=90EsN7f8x8A',
        ),
        'https://www.youtube.com/watch?v=90EsN7f8x8A',
      );
    }
  });

  test('Gakujo host stays sanitized with a nonstandard authority', () {
    expect(
      sanitizeGakujoCopyUrl(
        'https://user:password@gakujo.iess.niigata-u.ac.jp:8443/'
        'campusweb/campusportal.do?page=main&tabId=sd&token=secret',
      ),
      'https://gakujo.iess.niigata-u.ac.jp:8443/'
      'campusweb/campusportal.do?page=main&tabId=sd',
    );
  });

  test('Copy URL only preserves queries for allowed external pages', () {
    expect(
      sanitizeGakujoCopyUrl('https://example.test/watch?token=secret'),
      'https://example.test/watch',
    );
  });
}
