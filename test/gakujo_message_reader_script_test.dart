import 'package:morebettergakujo_flutter/src/gakujo_message_reader_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds bulk message read controls', () {
    final script = GakujoMessageReaderScript.build();

    expect(script, contains('__MBG_MESSAGE_READER_VERSION'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script, contains('|| document'));
    expect(script, contains("doc.querySelector('table.normal:nth-child(9)')"));
    expect(script, contains('指定した個数を既読にする'));
    expect(script, contains('既読にする数(半角数字)'));
    expect(script, contains("fetch(url, { credentials: 'include' })"));
    expect(script, contains('markReadWithFrame(url)'));
    expect(script, contains('location.reload()'));
  });

  test('matches original extension by reading the first requested rows', () {
    final script = GakujoMessageReaderScript.build();

    expect(
      script,
      contains('for (var i = 1; i < table.rows.length && urls.length < limit'),
    );
    expect(
      script,
      contains("var link = table.rows[i].querySelector('a[href]')"),
    );
    expect(script, isNot(contains('classList')));
    expect(script, isNot(contains('fontWeight')));
  });
}
