import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('io.jns.webview.win');
  const view = MethodChannel('io.jns.webview.win/73');
  const events = EventChannel('io.jns.webview.win/73/events');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const window = MethodChannel('net.yoshida.morebettergakujo/window');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late MockStreamHandlerEventSink sink;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    FlutterSecureStorage.setMockInitialValues({'more_better_gakujo_setup_completed':'true'});
    calls.clear();
    messenger.setMockMethodCallHandler(plugin, (call) async => call.method == 'initialize' ? {'textureId':73} : null);
    messenger.setMockMethodCallHandler(view, (call) async {
      calls.add(call);
      if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'synthetic-script';
      return call.method == 'executeScript' ? '{}' : null;
    });
    messenger.setMockMethodCallHandler(paths, (_) async => throw MissingPluginException());
    messenger.setMockMethodCallHandler(window, (_) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [plugin, view, paths, window]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockStreamHandler(events, null);
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> showApp(WidgetTester tester) async {
    // Create the stream in this widget test's fake-clock zone.
    messenger.setMockStreamHandler(events, MockStreamHandler.inline(onListen: (_, value) { sink = value; }));
    await tester.pumpWidget(const MaterialApp(home: GakujoWebApp()));
    await tester.pumpAndSettle();
    expect(find.byType(Texture), findsOneWidget,
      reason:'WebView must initialize before testing gestures; calls: ${calls.map((call) => call.method).toList()}');
    expect(find.byType(AlertDialog), findsNothing,
      reason:'The preview must not be obscured by a startup dialog: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}');
    expect(tester.getSize(find.byType(Texture)).height, greaterThan(100));
    expect(find.byType(Texture).hitTestable(), findsOneWidget,
      reason:'texture rect: ${tester.getRect(find.byType(Texture))}');
    expect(calls.where((call) => call.method == 'addScriptToExecuteOnDocumentCreated' && (call.arguments as String).contains('MbgPreviewNavigation')), isNotEmpty,
      reason:'Preview bridge must be configured; methods: ${calls.map((call) => call.method).toList()}');
    sink.success({'type':'urlChanged','value':'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'});
    await tester.pumpAndSettle();
    sink.success({'type':'historyChanged','value':{'canGoBack':true,'canGoForward':true}});
    await tester.pump();
    calls.clear();
  }
  Future<void> preview(WidgetTester tester, String state) async {
    sink.success({'type':'webMessageReceived','value':jsonEncode({'channel':'MbgPreviewNavigation','message':state})});
    await tester.pump();
  }
  List<String> scripts() => calls.where((call) => call.method == 'executeScript').map((call) => call.arguments as String).toList();
  List<String> previewZooms() => scripts().where((script) => script.startsWith('window.__MBG_PREVIEW_ZOOM &&')).toList();
  List<String> hostZooms() => scripts().where((script) => script.contains('// web_scripts/src/desktop_page_zoom/main.ts')).toList();
  List<MethodCall> history() => calls.where((call) => call.method == 'goBack' || call.method == 'goForward').toList();
  Future<void> scroll(WidgetTester tester, Offset delta) async {
    await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(find.byType(Texture)), scrollDelta: delta));
    await tester.pump();
  }

  testWidgets('preview scroll and pinch belong to the viewer, including closing tails', (tester) async {
    await showApp(tester);
    await preview(tester, 'visible');
    for (final delta in [const Offset(160,0), const Offset(5,100), const Offset(-200,30)]) {
      await scroll(tester, delta);
    }
    expect(history(), isEmpty);
    expect(scripts().where((script) => script.contains('// web_scripts/src/preview_navigate/main.ts')), isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    calls.clear();
    await scroll(tester, const Offset(0,-100));
    expect(previewZooms(), hasLength(1));
    expect(hostZooms(), isEmpty);
    expect(calls.where((call) => call.method == 'setScrollDelta'), isEmpty,
      reason:'WebView2 must not receive the same modified wheel again');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    final trackpad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    final centre = tester.getCenter(find.byType(Texture));
    await trackpad.panZoomStart(centre);
    calls.clear();
    await trackpad.panZoomUpdate(centre, pan: const Offset(4,1), scale: 1.1);
    await tester.pump();
    expect(previewZooms(), hasLength(1));
    expect(hostZooms(), isEmpty);
    await preview(tester, 'hidden');
    calls.clear();
    await trackpad.panZoomUpdate(centre, pan: const Offset(180,1), scale: 1.2);
    await tester.pump();
    expect(previewZooms(), isEmpty);
    expect(hostZooms(), isEmpty);
    expect(history(), isEmpty);
    await preview(tester, 'visible');
    calls.clear();
    await trackpad.panZoomUpdate(centre, pan: const Offset(200,1), scale: 1.3);
    await tester.pump();
    expect(previewZooms(), isEmpty, reason:'reopening cannot revive an interrupted pinch');
    await trackpad.panZoomEnd();

    await preview(tester, 'visible');
    await scroll(tester, const Offset(-70,0));
    await preview(tester, 'none');
    calls.clear();
    for (var i=0;i<4;i++) {
      await tester.pump(const Duration(milliseconds:150));
      await scroll(tester, const Offset(-130,0));
    }
    expect(history(), isEmpty, reason:'momentum cannot close or navigate past the preview');
    await tester.pump(const Duration(milliseconds:251));
    await scroll(tester, const Offset(-140,0));
    await tester.pumpAndSettle();
    expect(history().map((call) => call.method), ['goBack'], reason:'fresh intentional navigation still works outside previews');
    await tester.pump(const Duration(seconds:2));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  }, skip: !Platform.isWindows);

  testWidgets('modified-wheel ownership survives hide/reopen until the stream is idle', (tester) async {
    await showApp(tester);
    await preview(tester,'visible');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await scroll(tester,const Offset(0,-50));
    expect(previewZooms(), hasLength(1));
    await preview(tester,'hidden');
    calls.clear();
    await scroll(tester,const Offset(0,-50));
    expect(previewZooms(), isEmpty);
    expect(hostZooms(), isEmpty);
    await preview(tester,'visible');
    await scroll(tester,const Offset(0,-50));
    expect(previewZooms(), isEmpty);
    await tester.pump(const Duration(milliseconds:251));
    await scroll(tester,const Offset(0,-50));
    expect(previewZooms(), hasLength(1));
    await preview(tester,'none');
    calls.clear();
    await scroll(tester,const Offset(0,-50));
    expect(hostZooms(), isEmpty);
    await tester.pump(const Duration(milliseconds:251));
    await scroll(tester,const Offset(0,-50));
    await tester.pump(const Duration(milliseconds:100));
    expect(hostZooms(), isNotEmpty, reason:'a fresh wheel zoom outside previews still zooms the page');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds:2));
    debugDefaultTargetPlatformOverride = null;
  }, skip: !Platform.isWindows);

  testWidgets('explicit mouse back still navigates an open preview', (tester) async {
    await showApp(tester);
    await preview(tester,'visible');
    calls.clear();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons:kBackMouseButton);
    await mouse.down(tester.getCenter(find.byType(Texture)));
    await mouse.up();
    await tester.pump();
    expect(scripts().where((script) => script.contains('// web_scripts/src/preview_navigate/main.ts')), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  }, skip: !Platform.isWindows);
}
