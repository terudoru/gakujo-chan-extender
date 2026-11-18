import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/history_marker.g.dart';
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
  const portal =
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
  const report = '$portal?page=main&tabId=en';
  const schedule = '$portal?page=main&tabId=sch';
  const notices = '$portal?page=main&tabId=si';
  const message =
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
      'campussquare.do?_flowId=KJW0001100-flow&keijitype=1&genrecd=2&seqNo=3';
  final openMessage = GakujoMessageStarScript.buildOpen(
    keijitype: '1',
    genrecd: '2',
    seqNo: '3',
  );
  const plugin = MethodChannel('io.jns.webview.win');
  const view = MethodChannel('io.jns.webview.win/73');
  const events = EventChannel('io.jns.webview.win/73/events');
  const notifications = MethodChannel(
    'net.yoshida.morebettergakujo/notifications',
  );
  const downloads = MethodChannel('net.yoshida.morebettergakujo/downloads');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final loads = <String>[];
  late MockStreamHandlerEventSink webView;
  Completer<void>? reportLoad;
  var loginVisible = false;
  var authProbes = 0;
  var reachabilityProbes = 0;
  var historyReads = 0;
  final readHistory = gakujoHistoryMarkerJs({'action': 'read'});
  var messageOpens = 0;
  Completer<String>? pendingAuthProbe;

  setUp(() {
    loads.clear();
    reportLoad = null;
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
    messenger.setMockMethodCallHandler(view, (call) async {
      switch (call.method) {
        case 'loadUrl':
          final url = call.arguments as String;
          loads.add(url);
          if (url == report) await reportLoad?.future;
          return null;
        case 'addScriptToExecuteOnDocumentCreated':
          return 'id';
        case 'executeScript':
          if (call.arguments == readHistory) historyReads++;
          if (call.arguments == openMessage) {
            messageOpens++;
            // WebView2 JSON-encodes the script's returned JSON string.
            return jsonEncode(jsonEncode({'status': 'ok', 'url': notices}));
          }
          if (call.arguments == gakujoPortalAuthStateProbeScript) {
            authProbes++;
            if (pendingAuthProbe != null) return pendingAuthProbe!.future;
            return loginVisible
                ? '{"hasLoginFields":true}'
                : '{"hasAuthenticatedMarker":true}';
          }
          return '{}';
      }
      return null;
    });
  });

  tearDown(() {
    for (final channel in [plugin, view, downloads, notifications]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockStreamHandler(events, null);
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> tapNotification(String url) async {
    const codec = StandardMethodCodec();
    final reply = await messenger.handlePlatformMessage(
      notifications.name,
      codec.encodeMethodCall(
        MethodCall('deadlineNotificationTapped', {'url': url}),
      ),
      null,
    );
    expect(codec.decodeEnvelope(reply!), isTrue);
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> openCalendar(WidgetTester tester) async {
    await tapText(tester, 'スケジュール連携');
    expect(find.text('Googleスケジュール連携'), findsOneWidget);
  }

  Future<void> closeCalendar(WidgetTester tester) async {
    final dialog = find.ancestor(
      of: find.text('Googleスケジュール連携'),
      matching: find.byType(AlertDialog),
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('閉じる')));
    await tester.pumpAndSettle();
  }

  void event(String type, Object value) =>
      webView.success({'type': type, 'value': value});

  Future<void> startPage(
    WidgetTester tester,
    String url, {
    bool sourceChanged = true,
  }) async {
    event('navigationStarting', url);
    await tester.idle();
    if (sourceChanged) {
      event('urlChanged', url);
      await tester.idle();
    }
    event('loadingStateChanged', windows.LoadingState.loading.index);
    await tester.pump();
  }

  Future<void> finishPage(WidgetTester tester) async {
    event(
      'loadingStateChanged',
      windows.LoadingState.navigationCompleted.index,
    );
    await tester.idle();
    await tester.pumpAndSettle();
  }

  bool gateReleased(WidgetTester tester) {
    final home = find.widgetWithIcon(
      IconButton,
      Icons.home_outlined,
      skipOffstage: false,
    );
    return tester.widget<IconButton>(home).onPressed != null;
  }

  Future<void> waitForProcessing(
    WidgetTester tester,
    bool Function() done,
  ) async {
    // Page-finished processing reads script assets asynchronously. Keep the
    // fake clock well short of the deferred navigation's eight-second timeout.
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  Future<void> deferNotification(WidgetTester tester, String url) async {
    await openCalendar(tester);
    await tapNotification(url);
    await closeCalendar(tester);
  }

  Future<void> revisitSettledReport(WidgetTester tester) async {
    await deferNotification(tester, report);
    await startPage(tester, report);
    await finishPage(tester);
    await waitForProcessing(tester, () => gateReleased(tester));

    final probesBeforeRepeat = authProbes;
    await deferNotification(tester, report);
    await startPage(tester, report, sourceChanged: false);
    await finishPage(tester);
    await waitForProcessing(tester, () => gateReleased(tester));
    expect(authProbes, greaterThan(probesBeforeRepeat));

    await startPage(tester, schedule); // Follow an ordinary link.
    await finishPage(tester);
    expect(loads, [report, report]);
  }

  Future<void> repeatMessageDuringDrain(WidgetTester tester) async {
    await deferNotification(tester, message);
    await startPage(tester, message);
    await tapNotification(message);
    await finishPage(tester);
    await waitForProcessing(tester, () => loads.length == 2);
    expect(loads, [message, message]);
    expect(messageOpens, 0);
    expect(gateReleased(tester), isFalse);

    await startPage(tester, message, sourceChanged: false);
    await finishPage(tester);
    await waitForProcessing(tester, () => loads.length == 3);
    expect(loads, [message, message, notices]);
    expect(messageOpens, 1);
    expect(gateReleased(tester), isTrue);
  }

  Future<void> retryDisconnectedSchedule(WidgetTester tester) async {
    await deferNotification(tester, schedule);
    await startPage(tester, schedule);
    final probesBeforeError = authProbes;
    final reachabilityBeforeError = reachabilityProbes;
    event('onLoadError', windows.WebErrorStatus.disconnected.index);
    await finishPage(tester); // The native bridge pairs an error and completion.
    expect(authProbes, probesBeforeError);
    expect(loads, [schedule]);
    await tester.pump(const Duration(seconds: 5));
    expect(reachabilityProbes, reachabilityBeforeError + 1);
    expect(loads, [schedule, schedule]);
    expect(gateReleased(tester), isFalse);
  }

  Future<void> followLinkAfterRecovery(
    WidgetTester tester, {
    required bool sourceChanged,
  }) async {
    await retryDisconnectedSchedule(tester);
    final probesBeforeRetry = authProbes;
    await startPage(tester, schedule, sourceChanged: sourceChanged);
    await finishPage(tester);
    final probesAfterRetry = authProbes;
    await tester.pump(const Duration(seconds: 8));
    await waitForProcessing(tester, () => gateReleased(tester));

    await startPage(tester, notices); // Ordinary link after the calendar deadline.
    final historyBeforeLink = historyReads;
    await finishPage(tester);
    // History markers run after login restoration has considered the link.
    await waitForProcessing(
      tester,
      () => historyReads > historyBeforeLink || loads.length > 2,
    );
    expect(loads, [schedule, schedule]);
    expect(probesAfterRetry, probesBeforeRetry + 1);
  }

  testWidgets(
    'calendar drains the latest navigation until release or disposal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The reachability timer started by a WebView event uses the test clock.
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            webView = sink;
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GakujoWebApp(
            localPrefsStore: _TestPrefs(),
            gakujoReachable: () async {
              reachabilityProbes++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsOneWidget);
      expect(loads, hasLength(1));
      loads.clear();
      await tester.tap(find.byTooltip('設定'));
      await tester.pump();
      await tester.pumpAndSettle();
      await tapText(tester, '外部連携');
      await openCalendar(tester);
      await tapNotification(report);
      expect(loads, isEmpty);
      await closeCalendar(tester);
      await startPage(tester, report);
      await tapText(tester, '学務情報システムの画面');
      await tapText(tester, 'モバイル版');
      await tapNotification(notices);
      await tapNotification(schedule);
      expect(loads, [report]);
      await tester.pump(const Duration(seconds: 8));
      expect(loads, [report, schedule]);

      await tapNotification(notices);
      final probesBeforeLateFinish = authProbes;
      await finishPage(tester); // A late completion for the timed-out report.
      expect(authProbes, probesBeforeLateFinish);
      expect(loads, [report, schedule]);
      await startPage(tester, schedule);
      await finishPage(tester);
      await waitForProcessing(tester, () => loads.length == 3);
      expect(loads, [report, schedule, notices]);
      // The last notification is redirected to login. Authentication should
      // restore that target, even though the calendar gate has since released.
      loginVisible = true;
      await startPage(tester, Uri.parse(portal).resolve('login.do').toString());
      await finishPage(tester);
      await waitForProcessing(tester, () => gateReleased(tester));
      loginVisible = false;
      await startPage(tester, portal);
      await finishPage(tester);
      await waitForProcessing(tester, () => loads.length == 4);
      expect(loads, [report, schedule, notices, notices]);
      await tapNotification(report);
      expect(loads, [report, schedule, notices, notices, report]);

      loads.clear();
      await openCalendar(tester);
      await closeCalendar(tester);
      expect(loads, isEmpty);

      await revisitSettledReport(tester);
      loads.clear();
      await repeatMessageDuringDrain(tester);
      loads.clear();

      for (final sourceChanged in [true, false]) {
        await followLinkAfterRecovery(tester, sourceChanged: sourceChanged);
        loads.clear();
      }

      await retryDisconnectedSchedule(tester);
      await tapNotification(notices);
      await tester.pump(const Duration(seconds: 3));
      // The retry keeps the first request's deadline and queued successor.
      expect(loads, [schedule, schedule, notices]);
      await startPage(tester, notices);
      await finishPage(tester);
      await waitForProcessing(tester, () => gateReleased(tester));
      loads.clear();

      // A settings navigation replaces the queued schedule while the report
      // command is still awaiting a platform reply.
      await openCalendar(tester);
      reportLoad = Completer<void>();
      await tapNotification(report);
      await closeCalendar(tester);
      await tapNotification(schedule);
      await tapText(tester, 'デスクトップ版');
      expect(loads, [report]);
      reportLoad!.completeError(PlatformException(code: 'load_failed'));
      await tester.pump();
      final desktop = GakujoPageMode.desktop.startUrl;
      expect(loads, [report, desktop]);
      await startPage(tester, desktop);
      await finishPage(tester);
      await waitForProcessing(tester, () => gateReleased(tester));
      expect(loads, [report, desktop]);

      // Hold the actual settings control's operation Future so we can observe
      // its completion even after the widget and its toolbar are gone.
      final section = tester.widget<AppIntegrationSection>(
        find.byType(AppIntegrationSection),
      );
      var finished = false;
      final operation = section.onScheduleIntegration().then(
        (_) => finished = true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Googleスケジュール連携'), findsOneWidget);
      await tapNotification(schedule);
      await closeCalendar(tester);
      expect(loads, [report, desktop, schedule]);
      pendingAuthProbe = Completer<String>();
      final probesBeforeDisposal = authProbes;
      await startPage(tester, schedule);
      await finishPage(tester);
      await waitForProcessing(
        tester,
        () => authProbes == probesBeforeDisposal + 1,
      );
      await tapNotification(notices);
      expect(finished, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.idle();
      expect(finished, isTrue);
      pendingAuthProbe!.complete('{}');
      await operation;
      await tester.pump();
      expect(loads, [report, desktop, schedule]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    skip: !Platform.isWindows,
  );
}
