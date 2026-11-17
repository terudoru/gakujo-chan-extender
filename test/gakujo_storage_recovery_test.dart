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

class _StartupLocalPrefsStore extends GakujoLocalPrefsStore {
  _StartupLocalPrefsStore({required this.onObservation});

  final void Function(String) onObservation;

  // Recovery must use the secure store's setup flag, not this startup mirror.
  @override
  Future<GakujoLocalPrefs?> load() async {
    onObservation('localPrefs.load.called:setupCompleted=true');
    onObservation('localPrefs.load.completed:setupCompleted=true');
    return const GakujoLocalPrefs(
      appSettings: GakujoAppSettings(setupCompleted: true),
    );
  }

  @override
  Future<void> saveAppSettings(GakujoAppSettings settings) async {
    onObservation(
      'localPrefs.saveAppSettings.called:setupCompleted=${settings.setupCompleted}',
    );
    onObservation(
      'localPrefs.saveAppSettings.completed:setupCompleted=${settings.setupCompleted}',
    );
  }
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
  const loginProbeResult = <String, bool>{
    'hasLoginFields': true,
    'hasTwoFactorField': false,
    'hasAuthenticatedMarker': false,
  };
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Completer<void> unlock;
  late int settingsReads;
  late int loginProbes;
  final eventSinks = <String, MockStreamHandlerEventSink>{};
  final methodCalls = <String>[];
  var channelGuardScripts = 0;
  var retrying = false;
  var setupCompleted = false;

  setUp(() {
    LinuxWebViewPlatform.registerWith();
    unlock = Completer<void>();
    settingsReads = 0;
    loginProbes = 0;
    eventSinks.clear();
    methodCalls.clear();
    channelGuardScripts = 0;
    retrying = false;
    setupCompleted = false;
    messenger.setMockMethodCallHandler(storage, (call) async {
      methodCalls.add('storage.${call.method}');
      if (call.method == 'containsKey') return false;
      if (call.method == 'readAll' ||
          (call.method == 'read' &&
              (call.arguments as Map)['key'] ==
                  'more_better_gakujo_setup_completed')) {
        settingsReads++;
        if (!retrying) {
          throw PlatformException(code: 'KeyringLocked');
        }
        methodCalls.add(
          'storage.${call.method}.unlockWaiting:setupCompleted=$setupCompleted',
        );
        await unlock.future;
        methodCalls.add(
          'storage.${call.method}.unlockCompleted:setupCompleted=$setupCompleted',
        );
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
      methodCalls.add('window.${call.method}');
      if (call.method == 'secretServiceStatus') return 'running';
      return null;
    });
    messenger.setMockMethodCallHandler(paths, (call) async {
      methodCalls.add('paths.${call.method}');
      throw MissingPluginException('No local preferences in this test');
    });
    messenger.setMockMethodCallHandler(windowsPlugin, (call) async {
      methodCalls.add('windowsPlugin.${call.method}');
      if (call.method == 'initialize') return {'textureId': 73};
      return null;
    });
    messenger.setMockMethodCallHandler(windowsView, (call) async {
      methodCalls.add('windowsView.${call.method}');
      return null;
    });
    messenger.setMockMethodCallHandler(LinuxWebViewController.rootChannel, (
      call,
    ) async {
      methodCalls.add('linuxRoot.${call.method}');
      if (call.method == 'createWebView') return 91;
      return null;
    });
    messenger.setMockMethodCallHandler(linuxView, (call) async {
      methodCalls.add('linuxView.${call.method}');
      if (call.method == 'runJavaScript' &&
          ((call.arguments as Map)['script'] as String).contains(
            '// web_scripts/src/channel_guard/main.ts',
          )) {
        // Classify the install call without retaining its script/capability.
        channelGuardScripts++;
        methodCalls.add('channelGuardInstallObserved');
      }
      if (call.method == 'runJavaScriptReturningResult') {
        final script = (call.arguments as Map)['script'];
        if (script == gakujoPortalAuthStateProbeScript) {
          loginProbes++;
          return loginProbeResult;
        }
        return '';
      }
      return null;
    });
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
          final uiSnapshots = <String>[];
          int countCalls(String method) =>
              methodCalls.where((call) => call == method).length;
          void recordUi(String stage) {
            final texts = tester
                .widgetList<Text>(find.byType(Text, skipOffstage: false))
                .map((text) => text.data)
                .whereType<String>();
            final ui = <String, bool>{
              'preparing': texts.contains('準備中'),
              'loadingPortal': texts.any(
                (text) =>
                    text.startsWith('読み込み中:') &&
                    text.contains('campusportal.do'),
              ),
              'displayingPortal': texts.any(
                (text) =>
                    text.startsWith('表示中:') && text.contains('campusportal.do'),
              ),
              'recovery': texts.contains('保存データにアクセスできません'),
              'setup': texts.contains('初回セットアップ'),
            };
            uiSnapshots.add(
              '$stage: createWebView=${countCalls('linuxRoot.createWebView')}, '
              'loadRequest=${countCalls('linuxView.loadRequest')}, '
              'channelGuardScripts=$channelGuardScripts, '
              'loginProbes=$loginProbes, sinks=${eventSinks.keys.toList()}, '
              'ui=$ui',
            );
          }

          String diagnostics() =>
              'Storage recovery diagnostics (method names/counts and synthetic UI only):\n'
              '${uiSnapshots.join('\n')}\n'
              'methodCalls=${methodCalls.asMap().entries.map((entry) => '${entry.key}:${entry.value}').join(', ')}';

          expect(
            gakujoPortalAuthStateFromJavaScriptResult(loginProbeResult),
            GakujoPortalAuthState.login,
          );
          debugDefaultTargetPlatformOverride = platform;
          setupCompleted = completed;
          // Create the event streams in this widget test's FakeAsync zone.
          for (final channel in [windowsEvents, linuxEvents]) {
            messenger.setMockStreamHandler(
              channel,
              MockStreamHandler.inline(
                onListen: (arguments, sink) {
                  eventSinks[channel.name] = sink;
                  methodCalls.add('listen:${channel.name}');
                },
              ),
            );
          }
          await tester.pumpWidget(
            MaterialApp(
              home: GakujoWebApp(
                localPrefsStore: _StartupLocalPrefsStore(
                  onObservation: methodCalls.add,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          recordUi('initial pumpAndSettle completed');
          if (Platform.isMacOS) {
            // macOS starts from the local mirror without touching Keychain.
            expect(settingsReads, 0, reason: diagnostics());
            expect(find.text('初回セットアップ'), findsNothing);
            expect(
              find.widgetWithText(AlertDialog, '保存データにアクセスできません'),
              findsNothing,
            );
            // Only macOS needs a login page to begin the secure-settings read.
            const url =
                'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
            final sink = eventSinks[linuxEvents.name]!;
            methodCalls.add('send:pageStarted');
            sink.success({'type': 'pageStarted', 'url': url});
            recordUi('after pageStarted queued');
            methodCalls.add('send:pageFinished');
            sink.success({'type': 'pageFinished', 'url': url});
            recordUi('after pageFinished queued');
            // Preserve the failing event/pump order; queued UI can predate
            // delivery, while the settled snapshot shows rendered effects.
            await tester.pumpAndSettle();
            recordUi('after events pumpAndSettle completed');
            expect(loginProbes, greaterThan(0), reason: diagnostics());
          } else {
            expect(settingsReads, greaterThan(0), reason: diagnostics());
          }
          expect(settingsReads, greaterThan(0), reason: diagnostics());
          final initialReads = settingsReads;
          final recovery = find.widgetWithText(AlertDialog, '保存データにアクセスできません');
          expect(recovery, findsOneWidget, reason: diagnostics());
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
          recordUi('after retry pumpAndSettle completed');
          expect(recoveryDismissed, isTrue);
          expect(recovery, findsNothing);
          expect(
            find.text('初回セットアップ'),
            completed ? findsNothing : findsOneWidget,
            reason: diagnostics(),
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
