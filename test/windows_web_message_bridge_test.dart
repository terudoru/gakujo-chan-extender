import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

void main() {
  test('decodes map messages from webview_windows', () {
    final message = WindowsWebMessageBridge.decode({
      'channel': 'MoreBetterGakujoDownloads',
      'message': '{"url":"https://example.test/file.pdf"}',
    });

    expect(message?.channel, 'MoreBetterGakujoDownloads');
    expect(message?.message, '{"url":"https://example.test/file.pdf"}');
  });

  test('decodes string messages defensively', () {
    final message = WindowsWebMessageBridge.decode(
      '{"channel":"MoreBetterGakujoDownloads","message":"payload"}',
    );

    expect(message?.channel, 'MoreBetterGakujoDownloads');
    expect(message?.message, 'payload');
  });

  test('ignores malformed messages', () {
    expect(WindowsWebMessageBridge.decode('not json'), isNull);
    expect(WindowsWebMessageBridge.decode(42), isNull);
  });
}
