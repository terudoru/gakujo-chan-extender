import 'package:morebettergakujo_flutter/src/gakujo_download_url_policy.dart';
import 'package:test/test.dart';

void main() {
  test('ignores undecodable event query values without throwing', () {
    for (final query in ['_eventId=%FF', '_eventId=%E3%81', '%FF=value']) {
      expect(
        GakujoDownloadUrlPolicy.shouldDownload(
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/page?$query',
        ),
        isFalse,
        reason: query,
      );
    }
  });

  test('detects Gakujo info download event urls', () {
    expect(
      GakujoDownloadUrlPolicy.shouldDownload(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
        '?_eventId=infoDownLoad&questionSort=0&tempNo=2',
      ),
      isTrue,
    );
  });

  test('does not treat normal campussquare pages as downloads', () {
    expect(
      GakujoDownloadUrlPolicy.shouldDownload(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
        '?_eventId=reportList',
      ),
      isFalse,
    );
  });

  test('detects direct file urls', () {
    expect(
      GakujoDownloadUrlPolicy.shouldDownload(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/files/report.pdf',
      ),
      isTrue,
    );
  });
}
