import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const instance = MethodChannel('com.abandoft.webview_all_linux/91');
  const events = EventChannel('com.abandoft.webview_all_linux/91/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late int attempts;
  var failCreation = true;
  var failSettings = false;
  var failureMessage = 'raw details';
  Completer<int>? pendingCreation;

  setUp(() {
    calls = [];
    attempts = 0;
    failCreation = true;
    failSettings = false;
    failureMessage = 'raw details';
    pendingCreation = null;
    messenger.setMockMethodCallHandler(LinuxWebViewController.rootChannel, (
      call,
    ) async {
      if (call.method != 'createWebView') return null;
      attempts++;
      if (failCreation) {
        throw PlatformException(
          code: 'creation_failed',
          message: failureMessage,
        );
      }
      return pendingCreation == null ? 91 : await pendingCreation!.future;
    });
    messenger.setMockMethodCallHandler(instance, (call) async {
      calls.add(call);
      if (call.method == 'applySettings' && failSettings) {
        throw PlatformException(code: 'settings_failed');
      }
      return null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      LinuxWebViewController.rootChannel,
      null,
    );
    messenger.setMockMethodCallHandler(instance, null);
    messenger.setMockStreamHandler(events, null);
  });

  Widget page(LinuxWebViewController controller) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => LinuxWebViewWidget(
          PlatformWebViewWidgetCreationParams(controller: controller),
        ).build(context),
      ),
    ),
  );

  Future<void> disposeFailed(LinuxWebViewController controller) async {
    try {
      await controller.dispose();
    } on PlatformException {
      // A failed initialization is also returned by the plugin's disposal.
    }
  }

  testWidgets(
    'Linux start failures show Japanese recovery and distro packages',
    (tester) async {
      final controller = LinuxWebViewController(
        const LinuxWebViewControllerCreationParams(),
      );
      await tester.pumpWidget(page(controller));
      await tester.pump();

      expect(find.textContaining('Webページの表示を開始できませんでした'), findsOneWidget);
      for (final package in [
        'libwebkit2gtk-4.1-0',
        'webkit2gtk4.1',
        'webkit2gtk-4.1',
      ]) {
        expect(find.textContaining(package), findsOneWidget);
      }
      expect(find.text('再試行'), findsOneWidget);
      expect(find.textContaining('creation_failed'), findsNothing);
      expect(find.text('詳細: raw details'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await disposeFailed(controller);
    },
  );

  testWidgets('read-only WebKit directories show the native reason and path', (
    tester,
  ) async {
    const path = '/home/test/.local/share/net.yoshida.morebettergakujo/cookies';
    failureMessage =
        "Unable to protect WebKit cookie directory '$path': Read-only file system";
    final controller = LinuxWebViewController(
      const LinuxWebViewControllerCreationParams(),
    );

    await tester.pumpWidget(page(controller));
    await tester.pump();

    expect(find.text('詳細: $failureMessage'), findsOneWidget);
    expect(find.textContaining(path), findsOneWidget);
    expect(find.textContaining('アプリのデータフォルダに書き込めるか'), findsOneWidget);
    expect(find.textContaining('ライブラリが入っているか'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await disposeFailed(controller);
  });

  testWidgets(
    'failed retries stay recoverable and a successful retry shows the page',
    (tester) async {
      final controller = LinuxWebViewController(
        const LinuxWebViewControllerCreationParams(),
      );
      await tester.pumpWidget(page(controller));
      await tester.pump();

      await tester.tap(find.text('再試行'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('再試行'), findsOneWidget);
      expect(tester.takeException(), isNull);

      failCreation = false;
      final pending = Completer<int>();
      pendingCreation = pending;
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(find.text('再試行'), findsNothing);
      await controller.retryInitialization();
      expect(attempts, 3);
      pending.complete(91);
      await tester.pump();
      await tester.pump();
      expect(controller.initializationError.value, isNull);
      expect(find.textContaining('Webページの表示を開始できませんでした'), findsNothing);
      expect(calls.any((call) => call.method == 'setFrame'), isTrue);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.dispose);
    },
  );

  test(
    'startup settings, JavaScript channels and URL resume after retry',
    () async {
      final controller = LinuxWebViewController(
        const LinuxWebViewControllerCreationParams(),
      );
      final appController = WebViewController.fromPlatform(controller);
      final startup = () async {
        await appController.setJavaScriptMode(JavaScriptMode.unrestricted);
        await appController.addJavaScriptChannel(
          'AppChannel',
          onMessageReceived: (_) {},
        );
        await appController.loadRequest(
          Uri.parse('https://gakujo.iess.niigata-u.ac.jp/'),
        );
      }();
      await expectLater(controller.ready, throwsA(isA<PlatformException>()));
      expect(calls, isEmpty);

      failCreation = false;
      await controller.retryInitialization();
      await startup.timeout(const Duration(seconds: 1));

      expect(calls.map((call) => call.method), [
        'setJavaScriptMode',
        'addJavaScriptChannel',
        'loadRequest',
      ]);
      expect(
        calls.last.arguments['url'],
        'https://gakujo.iess.niigata-u.ac.jp/',
      );
      await controller.dispose();
    },
  );

  test(
    'WebView retry keeps the startup keyring and setup flow once per run',
    () async {
      final startupFlow = GakujoStartupFlow();
      var storageReads = 0;
      var recoveryDialogs = 0;
      var setupWizards = 0;
      Future<bool> loadSettings() => startupFlow.loadSettings(() async {
        storageReads++;
        if (startupFlow.claimStorageRecovery()) recoveryDialogs++;
        startupFlow.continuedWithoutStorage = true;
        if (startupFlow.claimSetup()) setupWizards++;
        return false;
      });
      await loadSettings();
      final controller = LinuxWebViewController(
        const LinuxWebViewControllerCreationParams(),
      );
      final resumedStartup = () async {
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await loadSettings();
        if (startupFlow.claimStorageRecovery()) recoveryDialogs++;
        if (startupFlow.claimSetup()) setupWizards++;
      }();
      await expectLater(controller.ready, throwsA(isA<PlatformException>()));

      failCreation = false;
      await controller.retryInitialization();
      await resumedStartup.timeout(const Duration(seconds: 1));

      expect(storageReads, 1);
      expect(recoveryDialogs, 1);
      expect(setupWizards, 1);
      expect(startupFlow.continuedWithoutStorage, isTrue);
      await controller.dispose();
    },
  );

  test(
    'overlapping startup settings loads retain the same pending result',
    () async {
      final flow = GakujoStartupFlow();
      final pending = Completer<bool>();
      var reads = 0;
      Future<bool> load() => flow.loadSettings(() {
        reads++;
        return pending.future;
      });

      final first = load();
      final second = load();
      expect(second, same(first));
      pending.complete(false);
      expect(await first, isFalse);
      expect(await load(), isFalse);
      expect(reads, 1);
    },
  );

  test('explicit storage retries remain available after automatic startup', () {
    final flow = GakujoStartupFlow();
    expect(flow.claimStorageRecovery(), isTrue);
    expect(flow.claimStorageRecovery(), isFalse);
    expect(flow.claimStorageRecovery(automatic: false), isTrue);
    expect(flow.claimStorageRecovery(), isFalse);
    expect(flow.claimSetup(), isTrue);
    expect(flow.claimSetup(), isFalse);
  });

  test(
    'failure applying creation settings disposes its native view before retry',
    () async {
      failCreation = false;
      failSettings = true;
      final controller = LinuxWebViewController(
        const LinuxWebViewControllerCreationParams(
          developerExtrasEnabled: false,
        ),
      );
      await expectLater(controller.ready, throwsA(isA<PlatformException>()));
      expect(calls.map((call) => call.method), ['applySettings', 'dispose']);

      failSettings = false;
      await controller.retryInitialization();

      expect(controller.initializationError.value, isNull);
      expect(calls.map((call) => call.method), [
        'applySettings',
        'dispose',
        'applySettings',
      ]);
      await controller.dispose();
    },
  );

  test(
    'disposing a failed view releases startup operations waiting for retry',
    () async {
      final controller = LinuxWebViewController(
        const LinuxWebViewControllerCreationParams(),
      );
      final startup = controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      final checked = expectLater(startup, throwsStateError);
      await expectLater(controller.ready, throwsA(isA<PlatformException>()));

      await disposeFailed(controller);
      await checked.timeout(const Duration(seconds: 1));
      expect(attempts, 1);
    },
  );
}
