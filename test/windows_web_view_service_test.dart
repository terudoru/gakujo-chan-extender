import 'dart:async';

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

  Future<void> flushEvents() async {
    // URL delegates intentionally remain pending in the race tests. Only
    // drain a bounded number of turns; never wait for their callbacks.
    for (var turn = 0; turn < 3; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> emit(String type, Object value) async {
    eventSink!.success({'type': type, 'value': value});
    await flushEvents();
  }

  testWidgets('forwards cancelled native downloads with suggested metadata', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final native = windows.WebviewController();
      await native.initialize();
      final controller = WindowsGakujoWebViewController(native);
      final downloads = <GakujoWebViewDownload>[];
      await controller.setNavigationDelegate(
        GakujoNavigationDelegate(onDownloadStarting: downloads.add),
      );
      for (final kind in windows.WebviewDownloadEventKind.values) {
        await emit('downloadEvent', {
          'kind': kind.index,
          'url': 'https://gakujo.iess.niigata-u.ac.jp/file',
          'resultFilePath': r'C:\Users\student\Downloads\lecture.pdf',
          'mimeType': 'application/pdf',
          'bytesReceived': 0,
          'totalBytesToReceive': 1024,
        });
      }
      expect(downloads, hasLength(1));
      expect(downloads.single.url, 'https://gakujo.iess.niigata-u.ac.jp/file');
      expect(downloads.single.resultFilePath,
          r'C:\Users\student\Downloads\lecture.pdf');
      expect(downloads.single.mimeType, 'application/pdf');
      await emit('downloadEvent', {
        'kind': windows.WebviewDownloadEventKind.downloadStarted.index,
        'url': 'blob:https://gakujo.iess.niigata-u.ac.jp/id',
        'resultFilePath': '',
        'bytesReceived': 0,
        'totalBytesToReceive': 0,
      });
      expect(downloads.last.url, startsWith('blob:'));
      expect(downloads.last.mimeType, isEmpty);
      expect(calls, isEmpty);
      await controller.dispose();
    });
  });

  const pageA = 'https://gakujo.iess.niigata-u.ac.jp/a';
  const pageB = 'https://gakujo.iess.niigata-u.ac.jp/b';

  testWidgets('loadUrl supersedes A before B emits urlChanged', (tester) async {
    await tester.runAsync(() async {
      final native = windows.WebviewController();
      await native.initialize();
      final controller = WindowsGakujoWebViewController(native);
      final decisionA = Completer<GakujoNavigationDecision>();
      final requested = <String>[];
      final started = <String>[];
      await controller.setNavigationDelegate(GakujoNavigationDelegate(
        onNavigationRequest: (request) {
          requested.add(request.url);
          if (request.url == pageA) {
            return decisionA.future;
          }
          return GakujoNavigationDecision.navigate;
        },
        onPageStarted: started.add,
      ));

      await emit('urlChanged', pageA);
      expect(requested, [pageA]);
      // The method-channel mock completes immediately, independently of A.
      await controller.loadUrl(pageB);
      decisionA.complete(GakujoNavigationDecision.prevent);
      await flushEvents();
      expect(started, isEmpty);
      expect(await controller.currentUrl(), isNull);
      expect(calls.map((call) => call.method), ['loadUrl']);
      expect(calls.single.arguments, pageB);

      await emit('urlChanged', pageB);
      expect(started, [pageB]);
      expect(await controller.currentUrl(), pageB);
      expect(calls.map((call) => call.method), ['loadUrl']);
      await controller.dispose();
    });
  });

  for (final staleDecision in GakujoNavigationDecision.values) {
    testWidgets('B urlChanged supersedes A with ${staleDecision.name}',
        (tester) async {
      await tester.runAsync(() async {
        final native = windows.WebviewController();
        await native.initialize();
        final controller = WindowsGakujoWebViewController(native);
        final decisionA = Completer<GakujoNavigationDecision>();
        final requested = <String>[];
        final started = <String>[];
        await controller.setNavigationDelegate(GakujoNavigationDelegate(
          onNavigationRequest: (request) {
            requested.add(request.url);
            if (request.url == pageA) {
              return decisionA.future;
            }
            return GakujoNavigationDecision.navigate;
          },
          onPageStarted: started.add,
        ));

        await emit('urlChanged', pageA);
        await emit('urlChanged', pageB);
        expect(requested, [pageA, pageB]);
        expect(started, [pageB]);
        decisionA.complete(staleDecision);
        await flushEvents();
        expect(started, [pageB]);
        expect(await controller.currentUrl(), pageB);
        expect(calls, isEmpty);
        await controller.dispose();
      });
    });
  }

  for (final action in ['reload', 'goBack', 'goForward', 'dispose']) {
    testWidgets('$action invalidates a pending URL decision', (tester) async {
      await tester.runAsync(() async {
        final native = windows.WebviewController();
        await native.initialize();
        final controller = WindowsGakujoWebViewController(native);
        final decisionA = Completer<GakujoNavigationDecision>();
        final started = <String>[];
        await controller.setNavigationDelegate(GakujoNavigationDelegate(
          onNavigationRequest: (_) => decisionA.future,
          onPageStarted: started.add,
        ));
        await emit('historyChanged', {'canGoBack': true, 'canGoForward': true});
        await emit('urlChanged', pageA);
        switch (action) {
          case 'reload':
            await controller.reload();
          case 'goBack':
            await controller.goBack();
          case 'goForward':
            await controller.goForward();
          case 'dispose':
            await controller.dispose();
        }
        decisionA.complete(GakujoNavigationDecision.prevent);
        await flushEvents();
        expect(started, isEmpty);
        if (action == 'dispose') {
          expect(calls, isEmpty);
        } else {
          expect(calls.map((call) => call.method), [action]);
          expect(await controller.currentUrl(), isNull);
          await controller.dispose();
        }
      });
    });
  }

  for (final disposeDuringStop in [false, true]) {
    testWidgets(
        'skips rollback after stop when superseded '
        '(dispose: $disposeDuringStop)', (tester) async {
      await tester.runAsync(() async {
        final stop = Completer<void>();
        messenger.setMockMethodCallHandler(instance, (call) async {
          calls.add(call);
          if (call.method == 'stop') await stop.future;
          return null;
        });
        final native = windows.WebviewController();
        await native.initialize();
        final controller = WindowsGakujoWebViewController(native);
        final started = <String>[];
        await controller.setNavigationDelegate(GakujoNavigationDelegate(
          onNavigationRequest: (request) => request.url == pageA
              ? GakujoNavigationDecision.prevent
              : GakujoNavigationDecision.navigate,
          onPageStarted: started.add,
        ));
        await emit(
            'historyChanged', {'canGoBack': true, 'canGoForward': false});
        await emit('urlChanged', pageA);
        expect(calls.map((call) => call.method), ['stop']);
        if (disposeDuringStop) {
          await controller.dispose();
        } else {
          await controller.loadUrl(pageB);
          await emit('urlChanged', pageB);
        }
        stop.complete();
        await flushEvents();
        expect(calls.map((call) => call.method),
            disposeDuringStop ? ['stop'] : ['stop', 'loadUrl']);
        expect(started, disposeDuringStop ? isEmpty : [pageB]);
        if (!disposeDuringStop) {
          expect(await controller.currentUrl(), pageB);
          await controller.dispose();
        }
      });
    });
  }

  testWidgets('renderer recovery stops after three attempts and reports status',
      (tester) async {
    await tester.runAsync(() async {
      final native = windows.WebviewController();
      await native.initialize();
      final controller = WindowsGakujoWebViewController(native);
      final errors = <GakujoWebResourceError>[];
      final finished = <String>[];
      await controller.setNavigationDelegate(GakujoNavigationDelegate(
        onWebResourceError: errors.add,
        onPageFinished: finished.add,
      ));
      await emit('urlChanged', pageB);
      for (var attempt = 0; attempt < 3; attempt++) {
        await emit('processFailed', 1);
      }
      expect(errors, isEmpty);
      await emit('processFailed', 1);
      await emit('processFailed', 1);
      expect(calls.where((call) => call.method == 'loadUrl'), hasLength(3));
      expect(errors.single.description, '表示が繰り返し停止したため再読み込みを止めました。再読込を押してください');
      expect(errors.single.isConnectivityError, isFalse);
      await emit('loadingStateChanged', windows.LoadingState.loading.index);
      await emit('loadingStateChanged',
          windows.LoadingState.navigationCompleted.index);
      expect(finished, isEmpty);

      // Manual reload remains usable and can report a completed page again.
      await controller.reload();
      await emit('loadingStateChanged',
          windows.LoadingState.navigationCompleted.index);
      expect(calls.where((call) => call.method == 'reload'), hasLength(1));
      expect(finished, [pageB]);
      await controller.dispose();
    });
  });

  testWidgets('renderer recovery budget uses a rolling sixty-second window',
      (tester) async {
    await tester.runAsync(() async {
      var elapsed = Duration.zero;
      final native = windows.WebviewController();
      await native.initialize();
      final controller = WindowsGakujoWebViewController(
        native,
        recoveryElapsed: () => elapsed,
      );
      for (final (seconds, recoveries) in [
        (0, 1),
        (20, 2),
        (40, 3),
        (59, 3),
        (60, 4),
        (61, 4),
        (80, 5),
      ]) {
        elapsed = Duration(seconds: seconds);
        await emit('processFailed', 1);
        expect(
          calls.where((call) => call.method == 'loadUrl'),
          hasLength(recoveries),
          reason: 'at $seconds seconds',
        );
      }
      await controller.dispose();
    });
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

  for (final initiallyEnabled in [false, true]) {
    testWidgets('native download interception follows flag $initiallyEnabled',
        (tester) async {
      await tester.runAsync(() async {
        final native = windows.WebviewController();
        await native.initialize();
        final controller = WindowsGakujoWebViewController(native);
        const service = WindowsGakujoWebViewService();
        await service.configureController(
          controller,
          debugAllowed: false,
          downloadInterceptionEnabled: initiallyEnabled,
        );
        await controller.setDownloadInterceptionEnabled(!initiallyEnabled);
        await controller.setDownloadInterceptionEnabled(initiallyEnabled);
        expect(
          calls
              .where((call) => call.method == 'setDownloadInterceptionEnabled')
              .map((call) => call.arguments),
          [initiallyEnabled, !initiallyEnabled, initiallyEnabled],
        );
        await controller.dispose();
      });
    });
  }

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
      // Recovery goes through loadUrl's navigation bookkeeping first.
      for (var turn = 0;
          turn < 20 && !calls.any((call) => call.method == 'loadUrl');
          turn += 1) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    expect(
      calls.lastWhere((call) => call.method == 'loadUrl').arguments,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    );
    await tester.runAsync(controller.dispose);
  });
}
