import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('macos/Runner/AppDelegate.swift').readAsStringSync();
  });

  test('registers the macOS input focus bridge', () {
    expect(
      source,
      contains('net.yoshida.morebettergakujo/input_focus'),
    );
    expect(source, contains('inputFocusBridge.register('));
    expect(
      source,
      contains('guard call.method == "restoreFlutterFirstResponder"'),
    );
  });

  test('releases a stale platform-view responder before focusing Flutter', () {
    final release = source.indexOf('window.makeFirstResponder(nil)');
    final restore = source.indexOf(
      'window.makeFirstResponder(controller.view)',
      release,
    );

    expect(release, greaterThanOrEqualTo(0));
    expect(restore, greaterThan(release));
  });
}
