import 'package:morebettergakujo_flutter/src/gakujo_message_filter_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds keyword-based message row filter', () {
    final script = GakujoMessageFilterScript.build(
      keywords: ['アンケート', ' 集中  講義 ', 'アンケート'],
    );

    expect(script, contains('__MBG_MESSAGE_FILTER_VERSION'));
    expect(script, contains('__MBG_MESSAGE_FILTER_SIGNATURE'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script, contains("doc.querySelector('table.normal:nth-child(9)')"));
    expect(script, contains('"アンケート"'));
    expect(script, contains('"集中 講義"'));
    expect(script, contains('data-mbg-message-filtered'));
    expect(script, contains("row.style.display = hide ? 'none' : ''"));
    expect(script, contains('除外中: '));
  });
}
