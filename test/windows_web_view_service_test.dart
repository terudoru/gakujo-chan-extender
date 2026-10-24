import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('io.jns.webview.win');
  const instance = MethodChannel('io.jns.webview.win/73');
  const events = EventChannel('io.jns.webview.win/73/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late MockStreamHandlerEventSink? eventSink;

  setUp(() {
    calls = [];
    eventSink = null;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      if (call.method == 'initialize') return {'textureId': 73};
      return null;
    });
    messenger.setMockMethodCallHandler(instance, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (arguments, sink) {
        eventSink = sink;
      }),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(instance, null);
    messenger.setMockStreamHandler(events, null);
  });

  group('Windows resource errors', () {
    const connectivityStatuses = {
      windows.WebErrorStatus.disconnected,
      windows.WebErrorStatus.hostNameNotResolved,
      windows.WebErrorStatus.cannotConnect,
      windows.WebErrorStatus.connectionAborted,
      windows.WebErrorStatus.connectionReset,
      windows.WebErrorStatus.timeout,
      windows.WebErrorStatus.serverUnreachable,
    };

    for (final status in windows.WebErrorStatus.values) {
      test('maps ${status.name} as a main-frame navigation error', () {
        final mapped = GakujoWebResourceError.fromWindows(status);
        expect(mapped.description, status.name);
        expect(mapped.isForMainFrame, isTrue);
        expect(
            mapped.isConnectivityError, connectivityStatuses.contains(status));
      });
    }
  });

  testWidgets('an offline error page does not finish a successful navigation', (
    tester,
  ) async {
    const url = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
    final native = windows.WebviewController();
    await tester.runAsync(native.initialize);
    final controller = WindowsGakujoWebViewController(native);
    final errors = <GakujoWebResourceError>[];
    final finished = <String>[];
    await tester.runAsync(
      () => controller.setNavigationDelegate(
        GakujoNavigationDelegate(
          onWebResourceError: errors.add,
          onPageFinished: finished.add,
        ),
      ),
    );
    Future<void> emit(String type, Object value) async {
      await tester.runAsync(() async {
        eventSink!.success({'type': type, 'value': value});
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      });
    }

    await emit('urlChanged', url);
    await emit('loadingStateChanged', windows.LoadingState.loading.index);
    await emit('onLoadError', windows.WebErrorStatus.disconnected.index);
    await emit(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
    expect(errors.single.description, 'disconnected');
    expect(errors.single.isForMainFrame, isTrue);
    expect(errors.single.isConnectivityError, isTrue);
    expect(finished, isEmpty);

    // A later reload of the same URL can complete without urlChanged.
    await tester.runAsync(controller.reload);
    await emit('loadingStateChanged', windows.LoadingState.loading.index);
    await emit(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
    expect(finished, [url]);
    expect(calls.where((call) => call.method == 'reload'), hasLength(1));
    await tester.runAsync(controller.dispose);
  });

  testWidgets('Windows service anchors page popups below app controls', (
    tester,
  ) async {
    final native = windows.WebviewController();
    await tester.runAsync(native.initialize);
    final controller = WindowsGakujoWebViewController(native);
    const service = WindowsGakujoWebViewService();
    await tester.runAsync(controller.setJavaScriptModeUnrestricted);

    Widget page(double top) => Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned(
                left: 24,
                top: top,
                width: 600,
                height: 400,
                child: service.buildWidget(controller),
              ),
            ],
          ),
        );
    await tester.pumpWidget(page(112));
    await tester.pump();
    List<dynamic> geometry() =>
        calls.lastWhere((call) => call.method == 'setSize').arguments
            as List<dynamic>;
    expect(geometry(), [600, 400, tester.view.devicePixelRatio, 24, 112]);

    // Showing another toolbar must move popup anchors even if size is unchanged.
    await tester.pumpWidget(page(160));
    await tester.pump();
    expect(geometry(), [600, 400, tester.view.devicePixelRatio, 24, 160]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('Windows service enables the right-click context menu', (
    tester,
  ) async {
    final native = windows.WebviewController();
    await tester.runAsync(native.initialize);
    final controller = WindowsGakujoWebViewController(native);
    const service = WindowsGakujoWebViewService();

    await tester.runAsync(
      () => service.configureController(controller, debugAllowed: false),
    );

    final call = calls.lastWhere(
      (call) => call.method == 'setDefaultContextMenusEnabled',
    );
    expect(call.arguments, isTrue);
    final devTools = calls.lastWhere(
      (call) => call.method == 'setDevToolsEnabled',
    );
    expect(devTools.arguments, isFalse);
    await tester.runAsync(controller.dispose);
  });

  testWidgets('Windows service blocks disallowed sites before navigation', (
    tester,
  ) async {
    final native = windows.WebviewController();
    await tester.runAsync(native.initialize);
    final controller = WindowsGakujoWebViewController(native);
    const service = WindowsGakujoWebViewService();
    final requested = <String>[];
    await tester.runAsync(
      () => controller.setNavigationDelegate(
        GakujoNavigationDelegate(
          onNavigationRequest: (request) {
            requested.add(request.url);
            return GakujoNavigationDecision.prevent;
          },
        ),
      ),
    );

    await tester.runAsync(
      () => service.configureController(controller, debugAllowed: false),
    );

    final call = calls.lastWhere(
      (call) => call.method == 'setNavigationAllowlist',
    );
    final arguments = call.arguments as Map<Object?, Object?>;
    expect(arguments['hosts'], contains('gakujo.iess.niigata-u.ac.jp'));
    expect(arguments['hostSuffixes'], contains('.niigata-u.ac.jp'));

    await tester.runAsync(() async {
      eventSink!.success({
        'type': 'navigationBlocked',
        'value': 'https://example.com/',
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });
    expect(requested, ['https://example.com/']);
    await tester.runAsync(controller.dispose);
  });

  testWidgets('Windows service explains a WebView2 startup failure', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(plugin, (call) async {
      if (call.method == 'initialize') {
        throw PlatformException(code: 'environment_creation_failed');
      }
      return null;
    });
    final controller =
        WindowsGakujoWebViewController(windows.WebviewController());
    const service = WindowsGakujoWebViewService();

    await tester.pumpWidget(
      MaterialApp(home: service.buildWidget(controller)),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.textContaining('WebView2 Runtime'), findsOneWidget);
  });

  testWidgets('Windows service reloads after the renderer exits', (
    tester,
  ) async {
    final native = windows.WebviewController();
    await tester.runAsync(native.initialize);
    final controller = WindowsGakujoWebViewController(native);
    await tester.runAsync(controller.setJavaScriptModeUnrestricted);

    await tester.runAsync(() async {
      eventSink!.success({'type': 'processFailed', 'value': 2});
      await Future<void>.delayed(Duration.zero);
    });
    expect(calls.where((call) => call.method == 'loadUrl'), isEmpty);

    await tester.runAsync(() async {
      eventSink!.success({'type': 'processFailed', 'value': 1});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });
    expect(
      calls.lastWhere((call) => call.method == 'loadUrl').arguments,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    );
    await tester.runAsync(controller.dispose);
  });
}
