import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

class _StartupLocalPrefsStore extends GakujoLocalPrefsStore {
  // Recovery must use the secure store's setup flag, not this startup mirror.
  @override
  Future<GakujoLocalPrefs?> load() async => const GakujoLocalPrefs(
    appSettings: GakujoAppSettings(setupCompleted: true),
  );

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const window = MethodChannel('net.yoshida.morebettergakujo/window');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const windowsPlugin = MethodChannel('io.jns.webview.win');
  const windowsView = MethodChannel('io.jns.webview.win/73');
  const windowsEvents = EventChannel('io.jns.webview.win/73/events');
  const linuxView = MethodChannel('com.abandoft.webview_all_linux/91');
  const linuxEvents = EventChannel('com.abandoft.webview_all_linux/91/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Completer<void> unlock;
  late int settingsReads;
  final eventSinks = <String, MockStreamHandlerEventSink>{};
  var retrying = false;
  var setupCompleted = false;

  setUp(() {
    LinuxWebViewPlatform.registerWith();
    unlock = Completer<void>();
    settingsReads = 0;
    eventSinks.clear();
    retrying = false;
    setupCompleted = false;
    messenger.setMockMethodCallHandler(storage, (call) async {
      if (call.method == 'containsKey') return false;
      if (call.method == 'readAll' ||
          (call.method == 'read' &&
              (call.arguments as Map)['key'] ==
                  'more_better_gakujo_setup_completed')) {
        settingsReads++;
        if (!retrying) {
          throw PlatformException(code: 'KeyringLocked');
        }
        await unlock.future;
        if (call.method == 'readAll') {
          return <String, String>{
            if (setupCompleted) 'more_better_gakujo_setup_completed': 'true',
          };
        }
        return setupCompleted ? 'true' : null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(window, (call) async {
      if (call.method == 'secretServiceStatus') return 'running';
      return null;
    });
    messenger.setMockMethodCallHandler(paths, (call) async {
      throw MissingPluginException('No local preferences in this test');
    });
    messenger.setMockMethodCallHandler(windowsPlugin, (call) async {
      if (call.method == 'initialize') return {'textureId': 73};
      return null;
    });
    messenger.setMockMethodCallHandler(windowsView, (call) async {
      if (call.method == 'executeScript' &&
          call.arguments == gakujoPortalAuthStateProbeScript) {
        return '"login"';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(LinuxWebViewController.rootChannel, (
      call,
    ) async {
      if (call.method == 'createWebView') return 91;
      return null;
    });
    messenger.setMockMethodCallHandler(linuxView, (call) async {
      if (call.method == 'runJavaScriptReturningResult') {
        final script = (call.arguments as Map)['script'];
        return script == gakujoPortalAuthStateProbeScript ? 'login' : '';
      }
      return null;
    });
    for (final channel in [windowsEvents, linuxEvents]) {
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            eventSinks[channel.name] = sink;
          },
        ),
      );
    }
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [
      storage,
      window,
      paths,
      windowsPlugin,
      windowsView,
      LinuxWebViewController.rootChannel,
      linuxView,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    for (final channel in [windowsEvents, linuxEvents]) {
      messenger.setMockStreamHandler(channel, null);
    }
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    for (final completed in [false, true]) {
      testWidgets(
        '$platform storage retry opens setup only when incomplete ($completed)',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          setupCompleted = completed;
          await tester.pumpWidget(
            MaterialApp(
              home: GakujoWebApp(localPrefsStore: _StartupLocalPrefsStore()),
            ),
          );
          await tester.pumpAndSettle();
          if (Platform.isMacOS) {
            // macOS starts from the local mirror without touching Keychain.
            expect(settingsReads, 0);
            expect(find.text('初回セットアップ'), findsNothing);
            expect(
              find.widgetWithText(AlertDialog, '保存データにアクセスできません'),
              findsNothing,
            );
          } else {
            expect(settingsReads, greaterThan(0));
          }
          // A loaded login page requests secure settings on macOS. Other hosts
          // have already reached the same recovery dialog during startup.
          const url =
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
          if (Platform.isWindows) {
            final sink = eventSinks[windowsEvents.name]!;
            sink.success({'type': 'urlChanged', 'value': url});
            sink.success({
              'type': 'loadingStateChanged',
              'value': windows.LoadingState.navigationCompleted.index,
            });
          } else {
            final sink = eventSinks[linuxEvents.name]!;
            sink.success({'type': 'pageStarted', 'url': url});
            sink.success({'type': 'pageFinished', 'url': url});
          }
          await tester.pumpAndSettle();
          expect(settingsReads, greaterThan(0));
          final initialReads = settingsReads;
          final recovery = find.widgetWithText(AlertDialog, '保存データにアクセスできません');
          expect(recovery, findsOneWidget);
          expect(find.text('初回セットアップ'), findsNothing);
          final route = ModalRoute.of(tester.element(recovery))!;
          var recoveryDismissed = false;
          unawaited(route.completed.then((_) => recoveryDismissed = true));

          retrying = true;
          await tester.tap(find.text('再試行'));
          await tester.pump();
          expect(settingsReads, greaterThan(initialReads));
          expect(find.text('初回セットアップ'), findsNothing);
          expect(recoveryDismissed, isFalse);

          await tester.runAsync(() async {
            unlock.complete();
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
          expect(find.text('初回セットアップ'), findsNothing);
          await tester.pumpAndSettle();
          expect(recoveryDismissed, isTrue);
          expect(recovery, findsNothing);
          expect(
            find.text('初回セットアップ'),
            completed ? findsNothing : findsOneWidget,
          );
          if (!completed) {
            Navigator.of(tester.element(find.text('初回セットアップ'))).pop();
            await tester.pumpAndSettle();
            expect(find.text('初回セットアップ'), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
