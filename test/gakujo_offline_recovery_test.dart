import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

class _TestPrefs extends Fake implements GakujoLocalPrefsStore {
  @override
  Future<GakujoLocalPrefs?> load() async => null;

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pageA = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/offline-a';
  const pageB = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/offline-b';
  const automatic = 'オフラインのようです。接続が戻ると自動で再読み込みします';
  const manual = '読み込めませんでした。接続を確認して再読み込みを押してください';
  const offline = windows.WebErrorStatus.disconnected;
  const invalid = windows.WebErrorStatus.errorHttpInvalidServerResponse;
  const tick = Duration(seconds: 5);

  const plugin = MethodChannel('io.jns.webview.win');
  const view = MethodChannel('io.jns.webview.win/73');
  const events = EventChannel('io.jns.webview.win/73/events');
  const notifications = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );
  const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
  const window = MethodChannel('net.yoshida.morebettergakujo/window');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MockStreamHandlerEventSink sink;
  late List<String> commands;
  late bool online;
  late int probes;
  Completer<bool>? pending;

  setUp(() {
    commands = [];
    online = false;
    probes = 0;
    pending = null;
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_setup_completed': 'true',
      'more_better_gakujo_disabled_feature_flags': 'update_notice',
    });
    messenger.setMockMethodCallHandler(
      plugin,
      (call) async => call.method == 'initialize' ? {'textureId': 73} : null,
    );
    messenger.setMockMethodCallHandler(notifications, (_) async => null);
    messenger.setMockMethodCallHandler(
      downloads,
      (_) async => {'isConfigured': false},
    );
    messenger.setMockMethodCallHandler(window, (_) async => null);
    messenger.setMockMethodCallHandler(
      paths,
      (_) async => throw MissingPluginException(),
    );
    messenger.setMockMethodCallHandler(view, (call) async {
      if (call.method == 'loadUrl') commands.add('loadUrl ${call.arguments}');
      if (call.method == 'reload') commands.add('reload');
      if (call.method == 'addScriptToExecuteOnDocumentCreated') return 'id';
      return call.method == 'executeScript' ? '{}' : null;
    });
  });
  tearDown(() {
    for (final channel in [
      plugin,
      view,
      downloads,
      notifications,
      window,
      paths,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockStreamHandler(events, null);
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> mount(WidgetTester tester) async {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, eventSink) {
          sink = eventSink;
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GakujoWebApp(
          localPrefsStore: _TestPrefs(),
          gakujoReachable: () async {
            probes++;
            return pending?.future ?? Future.value(online);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Texture), findsOneWidget);
    expect(commands, hasLength(1)); // The initial page load.
    commands.clear();
  }

  void event(String type, Object value) =>
      sink.success({'type': type, 'value': value});
  Future<void> navigate(WidgetTester tester, String url) async {
    event('navigationStarting', url);
    await tester.idle();
    event('urlChanged', url);
    await tester.idle();
    event('loadingStateChanged', windows.LoadingState.loading.index);
    await tester.idle();
    await tester.pump();
  }

  Future<void> finish(
    WidgetTester tester, [
    windows.WebErrorStatus? error,
  ]) async {
    if (error != null) event('onLoadError', error.index);
    event(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
    await tester.idle();
    await tester.pump();
  }

  Future<void> failPageA(WidgetTester tester) async {
    await mount(tester);
    await navigate(tester, pageA);
    await finish(tester, offline);
    expect(find.text(automatic), findsOneWidget);
  }

  void hide(WidgetTester tester, {bool pause = false}) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    if (pause) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    }
  }

  void resume(WidgetTester tester) {
    final binding = tester.binding;
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  void recoveryTest(String name, WidgetTesterCallback body) {
    testWidgets(
      name,
      (tester) async {
        try {
          await body(tester);
        } finally {
          resume(tester);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 4));
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      skip: !Platform.isWindows,
    );
  }

  for (final pause in [false, true]) {
    for (final failFirst in [false, true]) {
      final background = pause ? 'pause' : 'hide';
      recoveryTest(
        'offline failure ${failFirst ? "before" : "after"} $background waits for resume',
        (tester) async {
          await mount(tester);
          await navigate(tester, pageA);
          if (failFirst) await finish(tester, offline);
          hide(tester, pause: pause);
          if (!failFirst) await finish(tester, offline);
          final observer =
              tester.state(find.byType(GakujoWebApp)) as WidgetsBindingObserver;
          online = true;
          await tester.pump(tick);
          expect(probes, 0);
          expect(commands, isEmpty);
          observer.didChangeAppLifecycleState(tester.binding.lifecycleState!);
          resume(tester);
          observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump(tick);
          await tester.pump(tick);
          expect(probes, 1);
          expect(commands, ['loadUrl $pageA']);
        },
      );
    }
  }

  recoveryTest(
    'a probe finishing after hide cannot load until a fresh probe on resume',
    (tester) async {
      await failPageA(tester);
      pending = Completer<bool>();
      await tester.pump(tick);
      expect(probes, 1);
      hide(tester);
      pending!.complete(true);
      pending = null;
      await tester.pump(tick);
      expect(commands, isEmpty);
      expect(probes, 1);
      online = true;
      resume(tester);
      await tester.pump(tick);
      expect(probes, 2);
      expect(commands, ['loadUrl $pageA']);
    },
  );

  recoveryTest('a visible unfocused app still recovers', (tester) async {
    await failPageA(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    online = true;
    await tester.pump(tick);
    expect(commands, ['loadUrl $pageA']);
    expect(probes, 1);
  });

  for (final failedBeforeHide in [true, false]) {
    final failure = failedBeforeHide ? 'before hiding' : 'after restoration';
    recoveryTest('Windows recovers without focus (failure $failure)', (
      tester,
    ) async {
      await mount(tester);
      await navigate(tester, pageA);
      if (failedBeforeHide) await finish(tester, offline);
      hide(tester);
      online = true;
      await tester.pump(tick * 2);
      expect(probes, 0);
      expect(commands, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      if (!failedBeforeHide) await finish(tester, offline);
      await tester.pump(tick * 2);
      expect(probes, 1);
      expect(commands, ['loadUrl $pageA']);
      expect(find.text(automatic), findsNothing);

      resume(tester);
      await tester.pump(tick * 2);
      expect(probes, 1);
      expect(commands, ['loadUrl $pageA']);
    });
  }

  for (final replacement in ['navigation', 'success']) {
    recoveryTest('$replacement while hidden clears the deferred retry', (
      tester,
    ) async {
      await failPageA(tester);
      hide(tester);
      if (replacement == 'navigation') {
        // An allowed new request can precede its first URL change.
        event('navigationStarting', pageB);
        await tester.idle();
      } else {
        await finish(tester);
      }
      resume(tester);
      online = true;
      await tester.pump(tick);
      expect(probes, 0);
      expect(commands, isEmpty);
    });
  }

  for (final outcome in [offline, invalid, null]) {
    recoveryTest(
      'automatic reload budget after ${outcome?.name ?? "success"}',
      (tester) async {
        await mount(tester);
        await navigate(tester, pageA);
        online = true;
        for (var attempt = 1; attempt <= 3; attempt++) {
          await finish(tester, offline);
          await tester.pump(tick);
          expect(commands, List.filled(attempt, 'loadUrl $pageA'));
          event('loadingStateChanged', windows.LoadingState.loading.index);
          await tester.idle();
        }
        await finish(tester, outcome);
        await tester.tap(find.byTooltip('再読み込み'));
        await tester.pump();
        expect(commands.last, 'reload');
        event('loadingStateChanged', windows.LoadingState.loading.index);
        await tester.idle();
        await finish(tester, offline);
        final renewed = outcome == null;
        expect(find.text(renewed ? automatic : manual), findsOneWidget);
        await tester.pump(tick);
        expect(
          commands.where((c) => c == 'loadUrl $pageA'),
          hasLength(renewed ? 4 : 3),
        );
      },
    );
  }

  recoveryTest(
    'expiry replaces the pending promise with manual reload guidance',
    (tester) async {
      await failPageA(tester);
      await tester.pump(const Duration(minutes: 9, seconds: 55));
      expect(find.text(automatic), findsOneWidget);
      expect(probes, greaterThan(0));
      await tester.pump(tick);
      final stopped = probes;
      online = true;
      await tester.pump(tick * 2);
      expect(probes, stopped);
      expect(commands, isEmpty);
      expect(find.text(manual), findsOneWidget);
      expect(find.text(automatic), findsNothing);
    },
  );

  recoveryTest('expiry preserves an intervening error status', (tester) async {
    await failPageA(tester);
    await finish(tester, invalid);
    final error = find.text('読み込みエラー: ${invalid.name}');
    expect(error, findsOneWidget);
    await tester.pump(const Duration(minutes: 11));
    expect(error, findsOneWidget);
    expect(commands, isEmpty);
  });

  recoveryTest('navigation before expiry keeps the new page status', (
    tester,
  ) async {
    await failPageA(tester);
    await tester.pump(const Duration(minutes: 9, seconds: 50));
    await navigate(tester, pageB);
    await finish(tester);
    await tester.pump(const Duration(seconds: 15));
    expect(find.textContaining('表示中:'), findsOneWidget);
    expect(find.text(manual), findsNothing);
    expect(commands, isEmpty);
  });

  recoveryTest('disposal cancels a pending probe and its deadline', (
    tester,
  ) async {
    await failPageA(tester);
    pending = Completer<bool>();
    await tester.pump(tick);
    expect(probes, 1);
    await tester.pumpWidget(const SizedBox());
    pending!.complete(true);
    await tester.pump(const Duration(minutes: 11));
    expect(probes, 1);
    expect(commands, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
