import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('void commands forward immediately and stop after disposal', () async {
    const plugin = MethodChannel('io.jns.webview.win');
    const instance = MethodChannel('io.jns.webview.win/73');
    const events = EventChannel('io.jns.webview.win/73/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final nativeReply = Completer<void>();
    final calls = <(String, Object?)>[];
    messenger.setMockMethodCallHandler(plugin, (call) async {
      return call.method == 'initialize' ? {'textureId': 73} : null;
    });
    messenger.setMockMethodCallHandler(instance, (call) async {
      calls.add((call.method, call.arguments));
      if (call.method == 'loadStringContent') await nativeReply.future;
      if (call.method == 'moveFocus') throw PlatformException(code: 'focus');
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(() {
      messenger.setMockStreamHandler(events, null);
      messenger.setMockMethodCallHandler(instance, null);
      messenger.setMockMethodCallHandler(plugin, null);
    });

    final controller = WebviewController();
    await expectLater(controller.reload(), throwsStateError);
    await controller.initialize();

    final load = controller.loadStringContent('<p>日本語</p>');
    expect(calls, [('loadStringContent', '<p>日本語</p>')]);
    await controller.reload();
    await controller.setFpsLimit();
    await controller.setFpsLimit(null);
    await controller.removeVirtualHostNameMapping('fixture.test');
    await expectLater(
      controller.focus(),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'focus')),
    );
    expect(calls, [
      ('loadStringContent', '<p>日本語</p>'),
      ('reload', null),
      ('setFpsLimit', 0),
      ('setFpsLimit', null),
      ('clearVirtualHostNameMapping', 'fixture.test'),
      ('moveFocus', null),
    ]);
    nativeReply.complete();
    await load;

    calls.clear();
    final disposal = controller.dispose();
    await controller.loadStringContent('<p>ignored</p>');
    await controller.reload();
    await controller.focus();
    await disposal;
    expect(calls, isEmpty);
  });
}
