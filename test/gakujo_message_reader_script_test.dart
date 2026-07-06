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
}
