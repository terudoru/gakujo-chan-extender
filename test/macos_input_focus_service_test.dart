import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/macos_input_focus_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'net.yoshida.morebettergakujo/input_focus.test',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('asks macOS to restore Flutter as the native first responder', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return true;
    });

    final restored = await const MacosInputFocusService(channel: channel)
        .restoreFlutterFirstResponder();

    expect(restored, isTrue);
    expect(receivedCall?.method, 'restoreFlutterFirstResponder');
  });

  test('reports a missing native bridge without blocking the dialog', () async {
    final restored = await const MacosInputFocusService(channel: channel)
        .restoreFlutterFirstResponder();

    expect(restored, isFalse);
  });

  test('does not call the native bridge on another platform', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      callCount += 1;
      return true;
    });

    final restored = await const MacosInputFocusService(channel: channel)
        .restoreFlutterFirstResponder();

    expect(restored, isTrue);
    expect(callCount, 0);
  });
}
